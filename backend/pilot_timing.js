function positive(value, fallback, name) {
  const text = value === undefined ? String(fallback) : value;
  if (typeof text !== 'string' || !/^[1-9]\d*$/.test(text) || !Number.isSafeInteger(Number(text)) || Number(text) > 3600000) throw new Error(`Invalid ${name}`);
  return Number(text);
}
function backendTiming(env) {
  return { timeoutMs: positive(env.PILOT_D01_TIMEOUT_MS, 600000, 'PILOT_D01_TIMEOUT_MS'),
    killGraceMs: positive(env.PILOT_D01_KILL_GRACE_MS, 10000, 'PILOT_D01_KILL_GRACE_MS') };
}
function checkTiming(env) {
  const backend = backendTiming(env);
  const waitMs = positive(env.PILOT_CHECK_WAIT_MS, 600000, 'PILOT_CHECK_WAIT_MS');
  const closingGraceMs = positive(env.PILOT_CHECK_CLOSE_GRACE_MS, 45000, 'PILOT_CHECK_CLOSE_GRACE_MS');
  if (waitMs + closingGraceMs < backend.timeoutMs + backend.killGraceMs + 35000) throw new Error('Client observation window must include backend termination, polling and HTTP margin');
  return { ...backend, waitMs, closingGraceMs, totalObservationMs: waitMs + closingGraceMs, pollMs: 5000 };
}
async function pollTerminal({ read, sleep, now, timing, observe = () => {} }) {
  const start = now(); const observations = []; let status;
  const terminal = s => ['completed', 'failed', 'interrupted'].includes(s?.status);
  async function sample() { status = await read(); observations.push(status); observe(status); }
  await sample();
  while (!terminal(status) && now() - start < timing.waitMs) {
    await sleep(Math.min(timing.pollMs, timing.waitMs - (now() - start))); await sample();
  }
  // Mandatory boundary GET; never classify using the last snapshot before sleep.
  await sample();
  while (!terminal(status) && now() - start < timing.totalObservationMs) {
    await sleep(Math.min(timing.pollMs, timing.totalObservationMs - (now() - start))); await sample();
  }
  await sample(); // Final GET also after the bounded closing window.
  return { finalStatus: status, terminal: terminal(status), finalGetPerformed: true, observations,
    code: status?.code || (terminal(status) ? (status.status === 'completed' ? null : `backend_${status.status}`) : 'client_observation_expired') };
}
module.exports = { backendTiming, checkTiming, pollTerminal };
