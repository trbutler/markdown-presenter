// Anchor each server timestamp to a monotonic local clock. Browser wall clocks
// need not agree with the server, including when the service moves to NetBird.
export function subscribe(output, onState, onConnection = () => {}) {
  let snapshot = null;
  let receivedAt = 0;
  let currentServerTime = 0;
  const events = new EventSource(`/api/v1/outputs/${encodeURIComponent(output)}/events`);
  events.onopen = () => onConnection(true);
  events.onerror = () => onConnection(false);
  events.onmessage = event => {
    snapshot = JSON.parse(event.data);
    receivedAt = performance.now();
    currentServerTime = snapshot.serverNow;
    onState(snapshot);
  };
  return {
    now: () => currentServerTime + performance.now() - receivedAt,
    state: () => snapshot,
    close: () => events.close(),
  };
}

export function playback(run, now) {
  if (!run || now >= run.exitAt + run.exitMs) return {phase: 'hidden', progress: 1};
  if (now >= run.exitAt) return {phase: 'exiting', progress: Math.max(0, (now - run.exitAt) / run.exitMs), exitFrom: run.exitFrom};
  if (now < run.startedAt + run.enterMs) return {phase: 'entering', progress: Math.max(0, (now - run.startedAt) / run.enterMs)};
  return {phase: 'holding', progress: 1};
}
