function positive(value, fallback, name) {
  const text = value === undefined ? String(fallback) : value;
  if (typeof text !== 'string' || !/^[1-9]\d*$/.test(text) || !Number.isSafeInteger(Number(text)) || Number(text) > 3600000) throw new Error(`Invalid ${name}`);
  return Number(text);
}
// Analiz zaman aşımı varsayılanı 15 dk: 3,5 dk'lık (5040 kare) videolar için pay bırakır.
// Gerekirse PILOT_D01_TIMEOUT_MS ile değiştirilir (üst sınır 60 dk).
const DEFAULT_ANALYSIS_TIMEOUT_MS = 900000;
function backendTiming(env) {
  return { timeoutMs: positive(env.PILOT_D01_TIMEOUT_MS, DEFAULT_ANALYSIS_TIMEOUT_MS, 'PILOT_D01_TIMEOUT_MS'),
    killGraceMs: positive(env.PILOT_D01_KILL_GRACE_MS, 10000, 'PILOT_D01_KILL_GRACE_MS') };
}
function checkTiming(env) {
  const backend = backendTiming(env);
  // İstemci gözlem penceresi varsayılan olarak sunucu zaman aşımını kapsar (sözleşme aşağıda denetlenir).
  const waitMs = positive(env.PILOT_CHECK_WAIT_MS, Math.min(3600000, backend.timeoutMs), 'PILOT_CHECK_WAIT_MS');
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
module.exports = { backendTiming, checkTiming, pollTerminal, DEFAULT_ANALYSIS_TIMEOUT_MS };
