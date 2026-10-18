const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const {spawn} = require('node:child_process');
const {mkdtemp, rm, readFile} = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const {createRequire} = require('node:module');
const Client = require('../integrations/companion-2/faithtree-presenter/client');
const base = 'http://127.0.0.1:3221';
let server, temp;
async function waitFor(predicate, timeout = 5000) {
  const until = Date.now() + timeout;
  while (Date.now() < until) { if (await predicate()) return; await new Promise(resolve => setTimeout(resolve, 20)); }
  throw new Error('Timed out waiting for Presenter feedback');
}
before(async () => {
  temp = await mkdtemp(path.join(os.tmpdir(), 'presenter-companion-'));
  let logs = '';
  server = spawn('perl', ['script/display-server', 'daemon', '-l', base], {
    cwd: path.resolve(__dirname, '..'), env: {...process.env, PRESENTER_CUES: path.join(temp, 'cues.json')},
  });
  server.stdout.on('data', b => { logs += b; }); server.stderr.on('data', b => { logs += b; });
  await waitFor(async () => { try { return (await fetch(`${base}/api/v1/cues`)).ok; } catch { return false; } });
});
after(async () => { server?.kill('SIGCONT'); server?.kill('SIGTERM'); await rm(temp, {recursive: true, force: true}); });

test('live feedback follows web actions, second press, replacement, and automatic out', async () => {
  const client = new Client(base);
  client.start();
  try {
    await waitFor(() => client.connected);
    await client.command('clear');
    // Send a web/API command outside this client; the stream supplies feedback.
    await fetch(`${base}/api/v1/outputs/lower-third/commands`, {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({action: 'show', cueId: 'timothy'})});
    await waitFor(() => client.isActive('timothy'));
    assert.equal(client.isActive('prayer'), false);
    await client.command('trigger', 'timothy');
    assert.equal(client.isActive('timothy'), false, 'second press turns light off at exit start');
    assert.equal(client.isActive('timothy', true), true, 'optional feedback includes build-out');
    await client.command('show', 'prayer');
    assert.equal(client.isActive('prayer'), false, 'pending cue is not yet on air');
    await waitFor(() => client.isActive('prayer'));
    assert.equal(client.isActive('timothy', true), false);
    await client.command('clear');
    const cue = {id: 'automatic', label: 'Automatic', theme: 'little-hills', variant: 'regular', font: 'quicksand', line1: 'Auto', line2: '', holdMs: 200};
    await client.request('/api/v1/cues', cue);
    await client.command('show', 'automatic');
    assert(client.isActive('automatic'));
    await waitFor(() => client.view().phase === 'exiting');
    assert.equal(client.isActive('automatic'), false, 'automatic exit turns light off');
    assert.equal(client.isActive('automatic', true), true);
    await client.command('clear');
    assert.equal(client.isActive('automatic', true), false);
  } finally { client.stop(); }
});

test('Companion 2.4.2 action/feedback contract and generated presets', async () => {
  const filename = path.resolve(__dirname, '../integrations/companion-2/faithtree-presenter/index.js');
  class Skeleton {
    constructor(system, id, config) { this.config = config; this.STATUS_OK = 0; this.STATUS_WARNING = 1; this.STATUS_ERROR = 2; }
    rgb(r,g,b) { return (r << 16) | (g << 8) | b; }
    setActions(value) { this.actions = value; }
    setFeedbackDefinitions(value) { this.feedbacks = value; }
    setPresetDefinitions(value) { this.presets = value; }
    setVariableDefinitions(value) { this.definitions = value; }
    setVariables(value) { this.variables = value; }
    checkFeedbacks() { this.feedbackChecks = (this.feedbackChecks || 0) + 1; }
    status(level, message) { this.health = {level, message}; }
    log() {}
  }
  const moduleObject = {exports: {}};
  const requireFromModule = createRequire(filename);
  const wrapper = vm.runInThisContext(`(function(require, module, exports) {${await readFile(filename, 'utf8')}\n})`, {filename});
  wrapper(name => name === '../../instance_skel' ? Skeleton : requireFromModule(name), moduleObject, moduleObject.exports);
  const instance = new moduleObject.exports(null, 'test', {url: base});
  instance.init();
  try {
    await waitFor(() => instance.presets?.some(preset => preset.actions[0].options.cueId === 'timothy'));
    await instance.action({action: 'clear', options: {}});
    const feedback = {options: {cueId: 'timothy', includeExit: false}};
    assert.equal(instance.feedbacks.on_air.callback(feedback), false);
    await instance.action({action: 'trigger', options: {cueId: 'timothy'}});
    assert.equal(instance.feedbacks.on_air.callback(feedback), true);
    assert.equal(instance.variables.cue_id, 'timothy');
    assert.equal(instance.variables.connected, 1);
    await instance.action({action: 'trigger', options: {cueId: 'timothy'}});
    assert.equal(instance.feedbacks.on_air.callback(feedback), false);
    assert(instance.feedbackChecks > 2);
    const preset = instance.presets.find(p => p.actions[0].options.cueId === 'timothy');
    assert.equal(preset.feedbacks[0].type, 'on_air');
    assert.equal(preset.release_actions.length, 0, 'no double trigger on release');
    await instance.action({action: 'clear', options: {}});
  } finally { instance.destroy(); }
  assert.equal(instance.client, null);
});

test('silent stream failure clears lights and reconnects to a restarted timeline', async () => {
  let paused = false, revision = 9, posts = 0;
  const peers = new Set();
  const snapshot = () => {
    const now = Date.now();
    return {revision, serverNow: now, phase: 'holding', run: {cue: {id: 'timothy'}, startedAt: now - 3000,
      enterMs: 2000, exitAt: now + 10000, exitMs: 2000}};
  };
  const fake = http.createServer((req, res) => {
    if (req.url.endsWith('/events')) {
      res.writeHead(200, {'Content-Type': 'text/event-stream'});
      peers.add(res);
      if (!paused) res.write(`data: ${JSON.stringify(snapshot())}\n\n`);
      req.on('close', () => peers.delete(res));
    } else { posts++; /* Deliberately never answer a command. */ }
  });
  await new Promise(resolve => fake.listen(0, '127.0.0.1', resolve));
  const pulse = setInterval(() => { if (!paused) for (const peer of peers) peer.write('event: heartbeat\ndata: {}\n\n'); }, 30);
  const client = new Client(`http://127.0.0.1:${fake.address().port}`, {staleMs: 180, retryMs: 40, requestMs: 80});
  client.start();
  try {
    await waitFor(() => client.isActive('timothy'));
    paused = true;
    await waitFor(() => !client.connected);
    assert.equal(client.isActive('timothy'), false, 'a stale stream cannot leave the button lit');
    revision = 0; paused = false;
    await waitFor(() => client.isActive('timothy'));
    assert.equal(client.snapshot.revision, 0, 'restart accepts the new revision sequence');
    await assert.rejects(client.command('trigger', 'timothy'), /timed out/);
    await new Promise(resolve => setTimeout(resolve, 200));
    assert.equal(posts, 1, 'uncertain toggle is never replayed after reconnect');
  } finally {
    client.stop(); clearInterval(pulse);
    for (const peer of peers) peer.destroy();
    fake.closeAllConnections();
    await new Promise(resolve => fake.close(resolve));
  }
});
