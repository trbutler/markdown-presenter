import {subscribe, playback} from './state.js';

const $ = selector => document.querySelector(selector);
const form = $('#cue-form');
let cues = [];
let themes = [];
let editing = null;
let connected = false;
let state = null;
const message = text => { $('#message').textContent = text; $('#message').hidden = !text; };
async function api(url, method = 'GET', body) {
  const response = await fetch(`/api/v1/${url}`, {method, headers: {'Content-Type': 'application/json'}, body: body === undefined ? undefined : JSON.stringify(body)});
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`);
  return data;
}
async function act(action, cueId) {
  try { await api('outputs/lower-third/commands', 'POST', {action, cueId}); message(''); }
  catch (error) { message(error.message); }
}
function renderCues() {
  $('#cues').replaceChildren(...cues.map(cue => {
    const tile = document.createElement('article'); tile.className = 'cue'; tile.dataset.id = cue.id;
    const trigger = document.createElement('button'); trigger.className = 'cue-trigger';
    trigger.textContent = cue.label; trigger.disabled = !connected; trigger.onclick = () => act('trigger', cue.id);
    const detail = document.createElement('div'); detail.className = 'cue-detail';
    const label = document.createElement('span'); label.textContent = `${cue.variant} · ${cue.holdMs / 1000}s`;
    const edit = document.createElement('button'); edit.textContent = 'Edit'; edit.setAttribute('aria-label', `Edit ${cue.label}`); edit.onclick = () => openEditor(cue);
    detail.append(label, edit); tile.append(trigger, detail); return tile;
  }));
  markActive();
}
function markActive() {
  for (const tile of document.querySelectorAll('.cue')) {
    const active = tile.dataset.id === state?.run?.cue.id;
    tile.dataset.active = String(active);
    tile.dataset.pending = String(tile.dataset.id === state?.pending?.id);
    tile.querySelector('.cue-trigger').setAttribute('aria-pressed', String(active));
    tile.querySelector('.cue-trigger').disabled = !connected;
  }
}
function options(select, values, selected) {
  select.replaceChildren(...values.map(value => {
    const option = document.createElement('option');
    option.value = typeof value === 'string' ? value : value.id;
    option.textContent = typeof value === 'string' ? value : value.name;
    return option;
  }));
  if (selected !== undefined) select.value = selected;
}
function themeFields(cue = {}) {
  const theme = themes.find(t => t.id === form.elements.theme.value);
  if (!theme) return;
  options(form.elements.variant, theme.variants, cue.variant || theme.defaults.variant);
  options(form.elements.font, theme.fonts, cue.font || theme.defaults.font);
  $('#content-fields').replaceChildren(...theme.fields.map(field => {
    const label = document.createElement('label'); label.textContent = field.label;
    const input = document.createElement('input'); input.name = field.id; input.maxLength = 200; input.value = cue[field.id] || '';
    label.append(input); return label;
  }));
}
function openEditor(cue = null) {
  editing = cue?.id || null;
  $('#editor-heading').textContent = cue ? 'Edit cue' : 'New cue';
  form.elements.label.value = cue?.label || '';
  options(form.elements.theme, themes, cue?.theme || themes[0]?.id);
  themeFields(cue || {});
  form.elements.holdSeconds.value = (cue?.holdMs ?? 10000) / 1000;
  $('#delete').hidden = !cue;
  $('#editor').hidden = false;
  form.elements.label.focus();
}
form.elements.theme.onchange = () => themeFields();
$('#new').onclick = () => openEditor();
$('#cancel').onclick = () => { $('#editor').hidden = true; };
$('#clear').onclick = () => act('clear');
form.onsubmit = async event => {
  event.preventDefault();
  const button = form.querySelector('[type=submit]'); button.disabled = true;
  try {
    const cue = Object.fromEntries(new FormData(form));
    cue.holdMs = Math.round(Number(cue.holdSeconds) * 1000); delete cue.holdSeconds;
    cue.id = editing || `cue-${Date.now().toString(36)}-${Math.random().toString(36).slice(2,8)}`;
    await api(editing ? `cues/${encodeURIComponent(editing)}` : 'cues', editing ? 'PUT' : 'POST', cue);
    cues = await api('cues'); renderCues(); $('#editor').hidden = true; message('');
  } catch (error) { message(error.message); }
  finally { button.disabled = false; }
};
$('#delete').onclick = async () => {
  if (!editing || !confirm('Delete this saved cue? An active copy will finish playing.')) return;
  try {
    await api(`cues/${encodeURIComponent(editing)}`, 'DELETE');
    cues = await api('cues'); renderCues(); $('#editor').hidden = true; message('');
  } catch (error) { message(error.message); }
};
let connection;
async function init() {
  [themes, cues] = await Promise.all([api('themes'), api('cues')]);
  renderCues();
  connection = subscribe('lower-third', snapshot => { state = snapshot; markActive(); }, online => {
    connected = online;
    $('#connection').textContent = online ? 'Connected' : 'Disconnected · reconnecting';
    $('#connection').dataset.online = String(online);
    $('#clear').disabled = !online;
    markActive();
    if (online) api('cues').then(next => { cues = next; renderCues(); }).catch(error => message(error.message));
  });
}
setInterval(() => {
  if (!connection) return;
  const current = playback(state?.run, connection.now());
  $('#playback').textContent = current.phase === 'hidden' ? 'Hidden' : `${state.run.cue.label} · ${current.phase}`;
}, 100);
init().catch(error => message(`Could not load controls: ${error.message}. Reload to retry.`));
