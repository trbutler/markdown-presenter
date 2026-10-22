#!/usr/bin/env node
// Headless check of the 1214 view variants of a generated deck.
// Usage: PLAYWRIGHT=/path/to/node_modules/playwright node check-views.js deck.html [baseline.html] [chromium|webkit]
// baseline.html: the same markdown built with the 1213 template (before the
// 1214 port); the audience view must render pixel-identically to it.
// The template's own names are used: ?view=confidence is the notes view and
// ?view=control is the service view (hub 1213 + 1214 combined).
'use strict';
const path = require('path');
const { chromium, webkit } = require(process.env.PLAYWRIGHT || 'playwright');

const deck = 'file://' + path.resolve(process.argv[2]);
const baseline = process.argv[3] && process.argv[3] !== '-' ? 'file://' + path.resolve(process.argv[3]) : null;
const engineName = process.argv[4] || 'chromium';
const engine = engineName === 'webkit' ? webkit : chromium;

let failures = 0;
function check(name, ok, detail) {
  console.log((ok ? 'PASS ' : 'FAIL ') + name + (detail !== undefined ? '  [' + detail + ']' : ''));
  if (!ok) failures++;
}

const activeIndex = page => page.evaluate(() => Array.from(document.querySelectorAll('body > .slide')).findIndex(s => s.classList.contains('active')));

(async () => {
  const browser = await engine.launch();
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });

  // Audience: keys, black, Home/End
  const aud = await ctx.newPage();
  await aud.goto(deck + '?view=audience');
  check('audience: html class', await aud.evaluate(() => document.documentElement.className.includes('view-audience')));
  check('audience: starts on slide 0', (await activeIndex(aud)) === 0);
  await aud.keyboard.press('ArrowRight');
  check('audience: Right -> 1', (await activeIndex(aud)) === 1);
  await aud.keyboard.press('ArrowDown');
  check('audience: Down -> 2', (await activeIndex(aud)) === 2);
  await aud.keyboard.press('ArrowUp');
  check('audience: Up -> 1', (await activeIndex(aud)) === 1);
  await aud.keyboard.press('PageUp');
  await aud.keyboard.press('PageDown');
  await aud.keyboard.press('Space');
  check('audience: PageUp, PageDown, Space -> 2', (await activeIndex(aud)) === 2);
  await aud.keyboard.press('b');
  await aud.waitForTimeout(500);
  check('audience: B blacks', await aud.evaluate(() => document.documentElement.classList.contains('blacked') && getComputedStyle(document.querySelector('body > .slide.active')).visibility === 'hidden'));
  await aud.keyboard.press('ArrowLeft');
  check('audience: Left while black only un-blacks', (await activeIndex(aud)) === 2 && !(await aud.evaluate(() => document.documentElement.classList.contains('blacked'))));
  await aud.keyboard.press('Home');
  check('audience: Home -> 0', (await activeIndex(aud)) === 0);
  await aud.keyboard.press('End');
  check('audience: End -> last', (await activeIndex(aud)) === (await aud.evaluate(() => document.querySelectorAll('.slide').length - 1)));
  check('audience: notes hidden', await aud.evaluate(() => Array.from(document.querySelectorAll('.notes')).every(n => getComputedStyle(n).display === 'none')));

  // Browser sync: a confidence tab follows the audience tab over BroadcastChannel
  const conf = await ctx.newPage();
  await conf.goto(deck + '?view=confidence');
  await conf.waitForTimeout(300);
  check('sync: new confidence tab picks up audience state (last slide)', (await activeIndex(conf)) === 2, await activeIndex(conf));
  await aud.keyboard.press('Home');
  await conf.waitForTimeout(300);
  check('sync: Home in audience moves confidence to 0', (await activeIndex(conf)) === 0);

  // Confidence content
  const cm = await conf.evaluate(() => ({
    notes: document.getElementById('notesBody').textContent,
    nextTitle: Array.from(document.querySelectorAll('#nextPreview .slide.active h1'), h => h.textContent),
    clock: document.querySelector('#statusBar [data-clock]').textContent,
    timer: document.querySelector('#statusBar [data-timer]').textContent,
    pos: document.querySelector('#statusBar .pos').textContent,
    scale: getComputedStyle(document.querySelector('body > .slide.active')).transform,
    curBox: document.querySelector('body > .slide.active').getBoundingClientRect().width
  }));
  check('confidence: notes of current slide, escaped', cm.notes.includes('Mention the prayer walk') && cm.notes.includes('<angle brackets> & ampersands'), cm.notes.slice(0, 60));
  check('confidence: next slide shown', cm.nextTitle.length === 1 && cm.nextTitle[0] === 'What We Do', JSON.stringify(cm.nextTitle));
  check('confidence: clock and timer', /\d/.test(cm.clock) && /^\d\d:\d\d$/.test(cm.timer), cm.clock + ' ' + cm.timer);
  check('confidence: position label', cm.pos === 'Slide 1 / 3', cm.pos);
  check('confidence: stage scaled', /^matrix\(0\.\d+, 0, 0, 0\.\d+, 0, 0\)$/.test(cm.scale) && cm.curBox > 300 && cm.curBox < 1280, cm.scale + ' w=' + Math.round(cm.curBox));
  await conf.keyboard.press('End');
  await aud.waitForTimeout(300);
  check('confidence: End shows End card and propagates to audience',
    await conf.evaluate(() => getComputedStyle(document.getElementById('nextEnd')).display === 'flex') && (await activeIndex(aud)) === 2);
  check('confidence: notes on last slide', (await conf.evaluate(() => document.getElementById('notesBody').textContent)) === 'Close in prayer.');
  await conf.keyboard.press('ArrowLeft');
  await conf.waitForTimeout(2500); // let the slide fade and content fade-in finish
  await conf.screenshot({ path: path.join(process.cwd(), 'view-confidence-' + engineName + '.png') });

  // Control view
  const ctl = await ctx.newPage();
  await ctl.goto(deck + '?view=control');
  await ctl.waitForTimeout(300);
  check('control: one card per slide', (await ctl.locator('#servicePanel button[data-index]').count()) === 3);
  await ctl.locator('#servicePanel button[data-index]').nth(0).click();
  await aud.waitForTimeout(300);
  check('control: card click drives audience', (await activeIndex(aud)) === 0);
  await ctl.locator('[data-act=black]').click();
  await aud.waitForTimeout(300);
  check('control: Black button drives audience', await aud.evaluate(() => document.documentElement.classList.contains('blacked')));
  await ctl.locator('[data-act=black]').click();
  await ctl.screenshot({ path: path.join(process.cwd(), 'view-control-' + engineName + '.png') });

  // Overlay: transparent background, foreground only
  const ovCtx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const ov = await ovCtx.newPage();
  await ov.goto(deck + '?view=overlay');
  await ov.waitForTimeout(2500); // let the content fade-in finish
  const ovs = await ov.evaluate(() => ({
    html: getComputedStyle(document.documentElement).backgroundColor,
    body: getComputedStyle(document.body).backgroundColor,
    slideBg: getComputedStyle(document.querySelector('.slide.active')).backgroundImage,
    bug: getComputedStyle(document.querySelector('.bug')).display,
    grad: getComputedStyle(document.querySelector('.gradient-top')).display
  }));
  check('overlay: html/body transparent', ovs.html === 'rgba(0, 0, 0, 0)' && ovs.body === 'rgba(0, 0, 0, 0)', ovs.html + ' / ' + ovs.body);
  check('overlay: no photo, bug or gradients', ovs.slideBg === 'none' && ovs.bug === 'none' && ovs.grad === 'none');
  const png = await ov.screenshot({ omitBackground: true, path: path.join(process.cwd(), 'view-overlay-' + engineName + '.png') });
  // PNG colour type byte 25: 6 = RGBA
  check('overlay: screenshot keeps an alpha channel', png[25] === 6, 'colorType=' + png[25]);

  // Native bridge: fake window.webkit.messageHandlers.presenter as WKWebView provides it
  const natCtx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  await natCtx.addInitScript(() => {
    window.__sent = [];
    window.webkit = { messageHandlers: { presenter: { postMessage: m => window.__sent.push(JSON.parse(JSON.stringify(m))) } } };
    window.__presenterView = 'control';
  });
  const nat = await natCtx.newPage();
  await nat.goto(deck);
  let sent = await nat.evaluate(() => window.__sent);
  check('bridge: ready message with view/count/titles', sent[0] && sent[0].type === 'ready' && sent[0].view === 'control' && sent[0].count === 3 && sent[0].titles[2] === 'Join Us', JSON.stringify(sent[0]));
  await nat.keyboard.press('ArrowRight');
  sent = await nat.evaluate(() => window.__sent);
  check('bridge: JS ignores keys in-app (native routes them)', sent.length === 1 && (await nat.evaluate(() => window.presenter.state().index)) === 0);
  await nat.locator('#servicePanel button[data-index]').nth(2).click();
  sent = await nat.evaluate(() => window.__sent);
  check('bridge: card click posts a request, does not self-apply', sent[1] && sent[1].type === 'request' && sent[1].index === 2 && (await nat.evaluate(() => window.presenter.state().index)) === 0, JSON.stringify(sent[1]));
  // Read in the same task as apply(): the timer must show the native origin
  // at once, then keep counting from it.
  const ns = await nat.evaluate(() => {
    window.presenter.apply({ index: 2, black: true, timerStart: Date.now() - 65000 });
    return { st: window.presenter.state(), cur: document.querySelector('#servicePanel button.current .num').textContent, timer: document.querySelector('[data-timer]').textContent };
  });
  check('bridge: presenter.apply renders native state', ns.st.index === 2 && ns.st.black === true && ns.cur === '3' && ns.timer === '01:05', JSON.stringify(ns));
  await nat.waitForTimeout(1400);
  const later = await nat.evaluate(() => document.querySelector('[data-timer]').textContent);
  check('bridge: timer keeps counting from the native origin', later === '01:06', later);

  // Audience regression against the pre-1214 template
  if (baseline) {
    const shots = [];
    for (const url of [baseline, deck]) {
      const p = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
      await p.goto(url);
      await p.waitForTimeout(2500);
      await p.keyboard.press('ArrowRight');
      await p.waitForTimeout(2500);
      shots.push(await p.screenshot({ animations: 'disabled', mask: [p.locator('.bug')] }));
    }
    check('audience: pixel-identical to the 1213 template (bug masked)', Buffer.compare(shots[0], shots[1]) === 0, shots[0].length + ' vs ' + shots[1].length);
  }

  await browser.close();
  console.log(failures ? failures + ' FAILED' : 'ALL PASS');
  process.exit(failures ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
