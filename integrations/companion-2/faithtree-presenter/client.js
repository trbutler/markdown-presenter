const {EventEmitter} = require('events');
const http = require('http');
const https = require('https');
const {performance} = require('perf_hooks');

// Node 14-compatible client; Companion 2.4.2 needs no additional packages.
class PresenterClient extends EventEmitter {
  constructor(baseUrl, options = {}) {
    super();
    this.base = new URL(baseUrl);
    if (!['http:', 'https:'].includes(this.base.protocol) || this.base.username || this.base.password) {
      throw new Error('Use an HTTP or HTTPS server URL without credentials');
    }
    this.staleMs = options.staleMs || 6500;
    this.retryMs = options.retryMs || 1000;
    this.requestMs = options.requestMs || 3000;
    this.connected = false;
    this.running = false;
    this.snapshot = null;
    this.commands = new Set();
    this.generation = 0;
  }
  start() {
    if (this.running) return;
    this.running = true;
    this.lastActivity = performance.now();
    this.timer = setInterval(() => {
      if (this.stream && performance.now() - this.lastActivity > this.staleMs) {
        this.disconnect('No heartbeat from Presenter');
      }
      const view = JSON.stringify(this.view());
      if (view !== this.lastView) { this.lastView = view; this.emit('change', this.view()); }
    }, Math.min(100, this.staleMs / 3));
    this.connect();
  }
  stop() {
    this.running = false;
    clearInterval(this.timer);
    clearTimeout(this.retry);
    this.generation++;
    this.stream?.destroy(); this.stream = null;
    this.response?.destroy(); this.response = null;
    for (const request of this.commands) request.destroy(new Error('Presenter connection stopped'));
    this.commands.clear();
    this.connected = false;
    this.snapshot = null;
  }
  disconnect(reason) {
    if (!this.running) return;
    this.generation++;
    const stream = this.stream; this.stream = null;
    const response = this.response; this.response = null;
    stream?.destroy(); response?.destroy();
    const changed = this.connected;
    this.connected = false;
    this.snapshot = null;
    this.emit('connection', false, reason);
    if (changed) this.emit('change', this.view());
    clearTimeout(this.retry);
    this.retry = setTimeout(() => this.connect(), this.retryMs);
  }
  connect() {
    if (!this.running) return;
    clearTimeout(this.retry);
    const generation = ++this.generation;
    const url = new URL('/api/v1/outputs/lower-third/events', this.base);
    this.lastActivity = performance.now();
    const transport = url.protocol === 'https:' ? https : http;
    const request = transport.get(url, {headers: {Accept: 'text/event-stream'}}, response => {
      if (generation !== this.generation) { response.destroy(); return; }
      if (response.statusCode !== 200) {
        response.resume(); this.disconnect(`Presenter HTTP ${response.statusCode}`); return;
      }
      this.response = response;
      response.setEncoding('utf8');
      let buffer = '';
      response.on('data', chunk => {
        if (generation !== this.generation) return;
        this.lastActivity = performance.now();
        buffer += chunk;
        if (buffer.length > 262144) { this.disconnect('Presenter stream is too large'); return; }
        let boundary;
        while ((boundary = /\r?\n\r?\n/.exec(buffer))) {
          const frame = buffer.slice(0, boundary.index);
          buffer = buffer.slice(boundary.index + boundary[0].length);
          const lines = frame.split(/\r?\n/);
          const event = lines.find(line => line.startsWith('event:'));
          if (event && event.slice(6).trim() !== 'message') continue;
          const data = lines.filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
          if (!data) continue;
          try { this.accept(JSON.parse(data)); }
          catch { this.disconnect('Invalid Presenter state'); return; }
        }
      });
      response.on('end', () => { if (generation === this.generation) this.disconnect('Presenter stream closed'); });
      response.on('error', error => { if (generation === this.generation) this.disconnect(error.message); });
      response.on('close', () => { if (generation === this.generation) this.disconnect('Presenter stream closed'); });
    });
    this.stream = request;
    request.on('error', error => { if (generation === this.generation) this.disconnect(error.message); });
  }
  accept(snapshot) {
    if (!Number.isFinite(snapshot.serverNow) || !Number.isFinite(snapshot.revision)
      || !['hidden', 'entering', 'holding', 'exiting'].includes(snapshot.phase)) throw new Error('Invalid state');
    if (snapshot.run && (!snapshot.run.cue || typeof snapshot.run.cue.id !== 'string'
      || !['startedAt', 'enterMs', 'exitAt', 'exitMs'].every(key => Number.isFinite(snapshot.run[key])))) {
      throw new Error('Invalid run');
    }
    // Disconnection clears the snapshot, allowing a restarted server's revision 0.
    if (this.snapshot && snapshot.revision < this.snapshot.revision) return;
    this.snapshot = snapshot;
    this.receivedAt = performance.now();
    const wasConnected = this.connected;
    this.connected = true;
    if (!wasConnected) this.emit('connection', true);
    this.emit('change', this.view());
  }
  view() {
    const run = this.snapshot?.run;
    const now = this.snapshot ? this.snapshot.serverNow + performance.now() - this.receivedAt : 0;
    const phase = !run || now >= run.exitAt + run.exitMs ? 'hidden'
      : now >= run.exitAt ? 'exiting' : now >= run.startedAt + run.enterMs ? 'holding' : 'entering';
    return {connected: this.connected, phase, cueId: phase === 'hidden' ? '' : run.cue.id,
      remaining: phase === 'hidden' ? 0 : Math.max(0, Math.ceil((run.exitAt + run.exitMs - now) / 1000))};
  }
  isActive(cueId, includeExit = false) {
    const view = this.view();
    return view.connected && view.cueId === cueId
      && (view.phase === 'entering' || view.phase === 'holding' || (includeExit && view.phase === 'exiting'));
  }
  request(path, body) {
    if (!this.running) return Promise.reject(new Error('Presenter connection is stopped'));
    const url = new URL(path, this.base);
    const transport = url.protocol === 'https:' ? https : http;
    return new Promise((resolve, reject) => {
      const payload = body === undefined ? null : JSON.stringify(body);
      const request = transport.request(url, {method: payload ? 'POST' : 'GET', headers: payload
        ? {'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload)} : {}}, response => {
        response.setEncoding('utf8');
        let result = '';
        response.on('data', chunk => {
          result += chunk;
          if (result.length > 262144) request.destroy(new Error('Presenter response is too large'));
        });
        response.on('error', finishError);
        response.on('aborted', () => finishError(new Error('Presenter response was interrupted')));
        response.on('end', () => {
          cleanup();
          try {
            const data = JSON.parse(result);
            if (response.statusCode < 200 || response.statusCode >= 300) throw new Error(data.error || `HTTP ${response.statusCode}`);
            resolve(data);
          } catch (error) { reject(error); }
        });
      });
      const timeout = setTimeout(() => request.destroy(new Error('Presenter request timed out')), this.requestMs);
      const cleanup = () => { clearTimeout(timeout); this.commands.delete(request); };
      const finishError = error => { cleanup(); reject(error); };
      this.commands.add(request);
      request.on('error', finishError);
      request.end(payload);
    });
  }
  async command(action, cueId) {
    const generation = this.generation;
    try {
      const snapshot = await this.request('/api/v1/outputs/lower-third/commands', {action, cueId});
      if (generation === this.generation) this.accept(snapshot);
      return snapshot;
    } catch (error) {
      // Never replay a toggle command after an uncertain HTTP response.
      if (generation === this.generation) this.disconnect(error.message);
      throw error;
    }
  }
}

module.exports = PresenterClient;
