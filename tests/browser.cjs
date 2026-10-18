const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {mkdtemp, mkdir, rm} = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');

(async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'presenter-browser-'));
  const repo = path.resolve(__dirname, '..');
  const base = 'http://127.0.0.1:3220';
  let logs = '';
  const server = spawn('perl', ['script/display-server', 'daemon', '-l', base], {
    cwd: repo, env: {...process.env, PRESENTER_CUES: path.join(temp, 'cues.json')},
  });
  server.stdout.on('data', b => { logs += b; }); server.stderr.on('data', b => { logs += b; });
  let browser;
  try {
    let ready = false;
    for (let i = 0; i < 100; i++) {
      try { if ((await fetch(`${base}/api/v1/cues`)).ok) { ready = true; break; } } catch {}
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert(ready, `Server did not start: ${logs}`);
    async function api(url, body, method = 'POST') {
      const response = await fetch(`${base}/api/v1/${url}`, {method, headers: {'content-type': 'application/json'}, body: JSON.stringify(body)});
      assert(response.ok, await response.clone().text()); return response.json();
    }
    const command = (action, cueId) => api('outputs/lower-third/commands', {action, cueId});
    const state = async () => (await fetch(`${base}/api/v1/outputs/lower-third/state`)).json();
    browser = await chromium.launch({headless: true, args: ['--no-sandbox']});
    const context = await browser.newContext({viewport: {width: 1920, height: 1080}});
    const output = await context.newPage();
    const mirror = await context.newPage();
    const errors = [];
    for (const page of [output, mirror]) page.on('pageerror', error => errors.push(error.message));
    await Promise.all([output.goto(`${base}/output/lower-third`), mirror.goto(`${base}/output/lower-third`)]);
    assert.equal(await output.locator('#graphic').evaluate(el => getComputedStyle(el).visibility), 'hidden');
    assert.equal(await output.locator('body').evaluate(el => getComputedStyle(el).backgroundColor), 'rgba(0, 0, 0, 0)');
    await command('trigger', 'timothy');
    await Promise.all([output.locator('.lh-logo').waitFor({state: 'visible'}), mirror.locator('.lh-logo').waitFor({state: 'visible'})]);
    await output.waitForTimeout(1450);
    assert.equal(await output.locator('.lh-line1').textContent(), 'Timothy Butler');
    assert.equal(await output.locator('.lh-line2').textContent(), 'Pastor');
    assert(await output.evaluate(() => document.fonts.check('400 48px "LH Quicksand"')));
    assert(await output.locator('.lh-logo').evaluate(el => el.complete && el.naturalWidth > 0));
    await mkdir(path.join(repo, 'test-results'), {recursive: true});
    await output.screenshot({path: path.join(repo, 'test-results/little-hills-regular.png'), omitBackground: true});
    const started = (await state()).run.startedAt;
    await mirror.reload(); await mirror.locator('.lh-logo').waitFor({state: 'visible'});
    assert.equal((await state()).run.startedAt, started, 'Reload must not restart playback');
    const transforms = await Promise.all([output, mirror].map(page => page.locator('.lh-main').evaluate(el => el.style.transform)));
    assert.equal(transforms[0], transforms[1], 'Both clients join the same holding state');
    await command('trigger', 'prayer');
    await output.waitForFunction(() => document.querySelector('.lh-line1')?.textContent === 'Need Prayer?');
    await output.waitForTimeout(1400);
    assert(await output.locator('.lh-stage').evaluate(el => el.classList.contains('full-width')));
    await output.screenshot({path: path.join(repo, 'test-results/little-hills-full-width.png'), omitBackground: true});
    await command('clear');
    await output.waitForFunction(() => getComputedStyle(document.querySelector('#graphic')).visibility === 'hidden');

    const tablet = await browser.newPage({viewport: {width: 1024, height: 900}, hasTouch: true});
    tablet.on('pageerror', error => errors.push(error.message));
    await tablet.goto(base);
    await tablet.getByText('Connected', {exact: true}).waitFor();
    await command('show', 'timothy');
    await tablet.waitForTimeout(1500);
    await tablet.screenshot({path: path.join(repo, 'test-results/ipad-control.png')});
    await command('clear');
    await tablet.getByRole('button', {name: 'New cue', exact: true}).click();
    await tablet.getByLabel('Button label', {exact: true}).fill('Browser test');
    await tablet.getByLabel('Top line', {exact: true}).fill('<img src=x onerror=alert(1)>');
    await tablet.getByLabel('Second line', {exact: true}).fill('555-123-4567 · tim@littlehills.church');
    await tablet.getByLabel('Hold after build-in (seconds)', {exact: true}).fill('0.5');
    await tablet.getByRole('button', {name: 'Save cue', exact: true}).click();
    await tablet.getByRole('button', {name: 'Browser test', exact: true}).waitFor();
    await tablet.getByRole('button', {name: 'Browser test', exact: true}).click();
    await output.waitForFunction(() => document.querySelector('.lh-line1')?.textContent.includes('<img'));
    assert.equal(await output.locator('.lh-line1 img').count(), 0, 'Content is literal text');
    await output.waitForTimeout(1400);

    // Disconnected output still completes the authoritative lifecycle locally.
    await context.setOffline(true);
    await output.waitForTimeout(2200);
    assert.equal(await output.locator('#graphic').evaluate(el => getComputedStyle(el).visibility), 'hidden');
    await context.setOffline(false);
    await command('show', 'timothy');
    await output.locator('.lh-logo').waitFor({state: 'visible', timeout: 10000});
    await command('clear');

    // Theme font selection and unusually long contact information.
    const longCue = {id: 'long', label: 'Long line', theme: 'little-hills', variant: 'full-width', font: 'serene-sands',
      line1: 'Little Hills Church', line2: '555-123-4567 · a-very-long-contact-address@littlehills.church', holdMs: 10000};
    await api('cues', longCue);
    await command('show', 'long');
    await output.locator('.lh-stage.serene-sands').waitFor({state: 'visible'});
    assert(await output.evaluate(() => document.fonts.check('400 48px "LH Serene Sands"')));
    assert(await output.locator('.lh-line2').evaluate(el => el.scrollWidth <= el.clientWidth));
    assert.equal(await tablet.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'Tablet has no horizontal overflow');
    assert.deepEqual(errors, [], 'No browser exceptions');
    await command('clear');
    console.log('Browser checks passed: transparency, fonts, two-client playback, refresh, replacement, cue editing, escaping, offline completion, reconnect, long text, tablet layout.');
  } finally {
    await browser?.close();
    server.kill('SIGTERM');
    await rm(temp, {recursive: true, force: true});
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
