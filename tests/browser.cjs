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
    await output.waitForTimeout(2250);
    assert.equal(await output.locator('.lh-line1').textContent(), 'Timothy Butler');
    assert.equal(await output.locator('.lh-line2').textContent(), 'Pastor');
    assert(await output.evaluate(() => document.fonts.check('400 48px "LH Quicksand"')));
    assert(await output.locator('.lh-logo').evaluate(el => el.complete && el.naturalWidth > 0));
    const animation = await output.evaluate(async () => {
      const baseUrl = '/themes/little-hills/';
      const {mount} = await import(baseUrl + 'theme.js');
      const template = await (await fetch(baseUrl + 'template.html')).text();
      const root = document.createElement('div');
      root.style.cssText = 'position:fixed;left:-10000px'; document.body.append(root);
      const instance = await mount(root, {baseUrl, template, cue: {variant: 'regular', font: 'quicksand', line1: 'Test', line2: 'Test'}});
      const pose = () => [...root.querySelectorAll('[style]')].map(el => el.getAttribute('style'));
      const samples = [.25, .5, .75].map(progress => {
        instance.render({phase: 'entering', progress, width: 1920, height: 1080});
        const entry = pose();
        const positions = [...root.querySelectorAll('.lh-band')].map(el => parseFloat(el.style.transform.slice(11)));
        instance.render({phase: 'exiting', progress: 1 - progress, exitFrom: 1, width: 1920, height: 1080});
        return {entry, exit: pose(), positions};
      });
      instance.unmount(); root.remove(); return samples;
    });
    for (const sample of animation) {
      assert.deepEqual(sample.exit, sample.entry, 'Regular build-out exactly reverses build-in');
      assert(sample.positions.every(x => x < 0), 'Regular bars grow from the left');
      assert.equal(new Set(sample.positions).size, 3, 'Bars advance at different rates');
    }
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
    const progress = tablet.locator('.cue[data-id="timothy"] progress');
    await progress.waitFor({state: 'visible'});
    const firstProgress = await progress.evaluate(el => el.value);
    await tablet.waitForTimeout(2250);
    assert(await progress.evaluate(el => el.value) > firstProgress, 'Cue progress advances');
    assert.match(await tablet.locator('.cue[data-id="timothy"] .cue-remaining').textContent(), /^\d+s$/);
    await tablet.screenshot({path: path.join(repo, 'test-results/ipad-control.png')});
    await command('trigger', 'timothy');
    await tablet.waitForFunction(() => Number(document.querySelector('.cue[data-id="timothy"] .cue-remaining').textContent.replace('s', '')) <= 2);
    await command('clear');
    await progress.waitFor({state: 'hidden'});
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
    await output.waitForFunction(() => getComputedStyle(document.querySelector('#graphic')).visibility === 'hidden', null, {timeout: 6500});
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

    // A failed first asset load must be retried when the stream reconnects,
    // even though the active cue and its start timestamp have not changed.
    const recovery = await browser.newPage();
    await recovery.route('**/themes/little-hills/template.html', route => route.abort());
    await recovery.goto(`${base}/output/lower-third`);
    await command('show', 'timothy');
    const recoveryStart = (await state()).run.startedAt;
    await recovery.waitForTimeout(600);
    assert.equal(await recovery.locator('#graphic').evaluate(el => getComputedStyle(el).visibility), 'hidden');
    await recovery.unroute('**/themes/little-hills/template.html');
    await recovery.context().setOffline(true);
    await recovery.waitForTimeout(200);
    await recovery.context().setOffline(false);
    await recovery.locator('.lh-logo').waitFor({state: 'visible', timeout: 10000});
    assert.equal((await state()).run.startedAt, recoveryStart, 'Asset recovery does not restart the cue');
    await command('clear');
    await recovery.close();

    // Simulate a silent network black hole: TCP remains open, but the server
    // stops processing. Browser online/offline events cannot detect this.
    server.kill('SIGSTOP');
    await tablet.locator('#connection[data-online="false"]').waitFor({timeout: 10000});
    assert(await tablet.getByRole('button', {name: 'Timothy Butler', exact: true}).isDisabled());
    server.kill('SIGCONT');
    await tablet.locator('#connection[data-online="true"]').waitFor({timeout: 12000});
    await tablet.getByRole('button', {name: 'Timothy Butler', exact: true}).click();
    await output.waitForFunction(() => document.querySelector('.lh-line1')?.textContent === 'Timothy Butler');
    await command('clear');
    console.log('Browser checks passed, including reverse animation, cue progress, failed-asset recovery, and silent-connection timeout/recovery.');
  } finally {
    await browser?.close();
    server.kill('SIGCONT');
    server.kill('SIGTERM');
    await rm(temp, {recursive: true, force: true});
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
