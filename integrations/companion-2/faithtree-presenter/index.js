const Instance = require('../../instance_skel');
const PresenterClient = require('./client');

class Presenter extends Instance {
  init() { this.updateConfig(this.config); }
  config_fields() {
    return [{type: 'textinput', id: 'url', label: 'Presenter server URL', width: 12,
      default: 'http://100.68.136.48:3210'}];
  }
  updateConfig(config) {
    this.destroy();
    this.config = config;
    this.cues = [];
    this.defineControls();
    this.setVariableDefinitions([
      {name: 'connected', label: 'Presenter connection (1/0)'},
      {name: 'cue_id', label: 'Current cue ID'},
      {name: 'phase', label: 'Playback phase'},
      {name: 'remaining', label: 'Seconds remaining, including build-out'},
    ]);
    try {
      const client = new PresenterClient(config.url || 'http://100.68.136.48:3210');
      this.client = client;
      client.on('connection', (connected, reason) => {
        this.status(connected ? this.STATUS_OK : this.STATUS_WARNING, connected ? 'Connected' : reason || 'Disconnected');
        this.updateFeedback();
        if (connected) this.loadCues();
      });
      client.on('change', () => this.updateFeedback());
      client.start();
      this.refreshTimer = setInterval(() => { if (client.connected) this.loadCues(); }, 15000);
      this.status(this.STATUS_WARNING, 'Connecting');
      this.updateFeedback();
    } catch (error) { this.status(this.STATUS_ERROR, error.message); this.updateFeedback(); }
  }
  async loadCues() {
    const client = this.client;
    if (!client || this.loading === client) return;
    this.loading = client;
    try {
      const cues = await client.request('/api/v1/cues');
      if (this.client !== client) return;
      if (!Array.isArray(cues) || cues.some(cue => typeof cue.id !== 'string' || typeof cue.label !== 'string')) throw new Error('Invalid cue list');
      if (JSON.stringify(cues) !== JSON.stringify(this.cues)) { this.cues = cues; this.defineControls(); }
    } catch (error) { if (this.client === client) this.log('warn', `Could not refresh cues: ${error.message}`); }
    finally { if (this.loading === client) this.loading = null; }
  }
  defineControls() {
    const cueOption = () => ({type: 'dropdown', id: 'cueId', label: 'Cue',
      choices: this.cues.map(cue => ({id: cue.id, label: cue.label})), default: this.cues[0]?.id || ''});
    this.setActions({
      trigger: {label: 'Trigger / take out cue', options: [cueOption()]},
      show: {label: 'Show cue', options: [cueOption()]},
      hide: {label: 'Animated take-out', options: []},
      clear: {label: 'Immediately clear output', options: []},
      refresh: {label: 'Refresh cue list', options: []},
    });
    const activeStyle = {bgcolor: this.rgb(90, 130, 30), color: this.rgb(255, 255, 255)};
    const offlineStyle = {bgcolor: this.rgb(230, 155, 35), color: this.rgb(0, 0, 0)};
    this.setFeedbackDefinitions({
      on_air: {type: 'boolean', label: 'Cue is on air', description: 'Light the button using the server playback state.',
        style: activeStyle, options: [cueOption(), {type: 'checkbox', id: 'includeExit', label: 'Keep lit during build-out', default: false}],
        callback: feedback => Boolean(this.client?.isActive(feedback.options.cueId, feedback.options.includeExit))},
      disconnected: {type: 'boolean', label: 'Presenter is disconnected', style: offlineStyle, options: [],
        callback: () => !this.client?.connected},
    });
    this.setPresetDefinitions(this.cues.map(cue => ({category: 'Lower thirds', label: cue.label,
      bank: {style: 'text', text: cue.label, size: 'auto', color: this.rgb(255, 255, 255), bgcolor: this.rgb(30, 40, 25)},
      actions: [{action: 'trigger', options: {cueId: cue.id}}], release_actions: [],
      feedbacks: [
        {type: 'on_air', options: {cueId: cue.id, includeExit: false}, style: activeStyle},
        {type: 'disconnected', options: {}, style: offlineStyle},
      ]})));
    this.checkFeedbacks();
  }
  updateFeedback() {
    const view = this.client?.view() || {connected: false, cueId: '', phase: 'hidden', remaining: 0};
    this.setVariables({connected: view.connected ? 1 : 0, cue_id: view.cueId, phase: view.phase, remaining: view.remaining});
    this.checkFeedbacks('on_air', 'disconnected');
  }
  async action({action, options}) {
    if (action === 'refresh') return this.loadCues();
    if (!['trigger', 'show', 'hide', 'clear'].includes(action)) return;
    try {
      if (!this.client) throw new Error('Configure the Presenter server URL first');
      await this.client.command(action, options?.cueId);
    } catch (error) { this.log('error', `Presenter command failed: ${error.message}`); }
  }
  destroy() {
    clearInterval(this.refreshTimer);
    this.client?.stop();
    this.client = null;
  }
}

module.exports = Presenter;
