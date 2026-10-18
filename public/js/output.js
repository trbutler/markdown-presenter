import {subscribe, playback} from './state.js';

const root = document.querySelector('#graphic');
const output = location.pathname.split('/').pop();
let mounted = null;
let mountedKey = '';
let wantedKey = '';
let generation = 0;
let failedKey = '';
const loadedThemes = new Map();

async function loadTheme(id) {
  if (!loadedThemes.has(id)) loadedThemes.set(id, (async () => {
    const baseUrl = `/themes/${encodeURIComponent(id)}/`;
    const response = await fetch(`${baseUrl}template.html`);
    if (!response.ok) throw new Error('Theme template unavailable');
    const template = await response.text();
    const style = document.createElement('link');
    style.dataset.theme = id;
    style.rel = 'stylesheet'; style.href = `${baseUrl}style.css`;
    const ready = new Promise((resolve, reject) => { style.onload = resolve; style.onerror = reject; });
    document.head.append(style);
    try {
      await ready;
      return {baseUrl, template, module: await import(`${baseUrl}theme.js?load=${Date.now()}`)};
    } catch (error) { style.remove(); throw error; }
  })().catch(error => { loadedThemes.delete(id); throw error; }));
  return loadedThemes.get(id);
}

async function changeTheme(run, key) {
  const version = ++generation;
  wantedKey = key;
  failedKey = '';
  root.style.visibility = 'hidden';
  mounted?.unmount(); mounted = null; mountedKey = '';
  if (!run) return;
  let staging;
  try {
    const theme = await loadTheme(run.cue.theme);
    if (version !== generation) return;
    // Stage offscreen to prevent an obsolete async mount from overwriting a new cue.
    staging = document.createElement('div');
    staging.style.cssText = 'position:absolute;inset:0;visibility:hidden';
    root.append(staging);
    const instance = await theme.module.mount(staging, {...theme, cue: run.cue});
    if (version !== generation) { instance.unmount(); staging.remove(); return; }
    staging.style.visibility = '';
    mounted = {render: state => instance.render(state), unmount() { instance.unmount(); staging.remove(); }};
    mountedKey = key;
  } catch (error) {
    staging?.remove();
    if (version === generation) {
      failedKey = key;
      loadedThemes.delete(run.cue.theme);
      document.querySelector(`link[data-theme="${run.cue.theme}"]`)?.remove();
    }
    console.error('Output theme failed to load', error);
    // A failed theme stays transparent; diagnostic information stays in console.
  }
}

const connection = subscribe(output, snapshot => {
  const run = snapshot.run;
  const key = run ? JSON.stringify([run.startedAt, run.cue]) : '';
  if (key !== wantedKey || (key && key === failedKey)) changeTheme(run, key);
});

function frame() {
  const run = connection.state()?.run;
  const phase = playback(run, connection.now());
  const visible = phase.phase !== 'hidden' && mounted && mountedKey === wantedKey && wantedKey !== failedKey;
  root.style.visibility = visible ? 'visible' : 'hidden';
  if (visible) mounted.render({...phase, width: innerWidth, height: innerHeight});
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
