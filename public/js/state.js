// Anchor each server timestamp to a monotonic local clock. Browser wall clocks
// need not agree with the server, including when the service moves to NetBird.
export function subscribe(output, onState, onConnection = () => {}) {
  let snapshot = null;
  let receivedAt = 0;
  let currentServerTime = 0;
  let events = null;
  let retry = null;
  let closed = false;
  let online = null;
  let lastActivity = performance.now();
  const staleMs = 6500; // Three missed 2-second heartbeats, with some margin.
  function status(value) {
    if (online !== value) { online = value; onConnection(value); }
  }
  function disconnect() {
    events?.close(); events = null;
    clearTimeout(retry); retry = null;
    status(false);
  }
  function reconnect() {
    disconnect();
    if (!closed) retry = setTimeout(connect, 1000);
  }
  function connect() {
    clearTimeout(retry); retry = null;
    if (closed || navigator.onLine === false) return;
    events?.close();
    lastActivity = performance.now();
    const stream = new EventSource(`/api/v1/outputs/${encodeURIComponent(output)}/events`);
    events = stream;
    stream.onerror = () => { if (events === stream) reconnect(); };
    // A socket opening is insufficient: only a fresh snapshot confirms health.
    stream.onmessage = event => {
      if (events !== stream) return;
      try {
        const next = JSON.parse(event.data);
        if (!Number.isFinite(next.serverNow)) throw new Error('Invalid snapshot');
        snapshot = next;
        lastActivity = receivedAt = performance.now();
        currentServerTime = snapshot.serverNow;
        onState(snapshot);
        status(true);
      } catch { reconnect(); }
    };
    stream.addEventListener('heartbeat', () => {
      if (events === stream) lastActivity = performance.now();
    });
  }
  function resume() {
    if (closed) return;
    if (!events || performance.now() - lastActivity > staleMs) { disconnect(); connect(); }
  }
  function offline() { disconnect(); }
  function visibility() { if (document.visibilityState === 'visible') resume(); }
  const watchdog = setInterval(() => {
    if (events && performance.now() - lastActivity > staleMs) reconnect();
    else if (!events && !retry && navigator.onLine !== false) connect();
  }, 1000);
  window.addEventListener('online', resume);
  window.addEventListener('offline', offline);
  window.addEventListener('pageshow', resume);
  document.addEventListener('visibilitychange', visibility);
  status(false);
  connect();
  return {
    now: () => currentServerTime + performance.now() - receivedAt,
    state: () => snapshot,
    reconnect,
    close() {
      closed = true;
      disconnect();
      clearInterval(watchdog);
      window.removeEventListener('online', resume);
      window.removeEventListener('offline', offline);
      window.removeEventListener('pageshow', resume);
      document.removeEventListener('visibilitychange', visibility);
    },
  };
}

export function playback(run, now) {
  if (!run || now >= run.exitAt + run.exitMs) return {phase: 'hidden', progress: 1};
  if (now >= run.exitAt) return {phase: 'exiting', progress: Math.max(0, (now - run.exitAt) / run.exitMs), exitFrom: run.exitFrom};
  if (now < run.startedAt + run.enterMs) return {phase: 'entering', progress: Math.max(0, (now - run.startedAt) / run.enterMs)};
  return {phase: 'holding', progress: 1};
}
