const { randomUUID } = require('node:crypto');
const { performance } = require('node:perf_hooks');

// Yalnız güvenli metadata. Kalıcı kayıt, tampon veya istatistik endpoint'i yoktur.
function createGenerationMeasurement({ endpoint, now = () => performance.now(), report } = {}) {
  function stamp() {
    try { const value = now(); return Number.isFinite(value) ? value : null; } catch (_) { return null; }
  }
  function duration(start) {
    const end = stamp();
    return start !== null && end !== null && end >= start ? Number((end - start).toFixed(3)) : null;
  }
  const started = stamp();
  let retrievalStart = null, providerStart = null, terminal;
  const state = { requestId: randomUUID(), endpoint, retrievalDurationMs: null,
    providerDurationMs: null, providerStarted: false, providerFinished: false,
    promptTokens: null, outputTokens: null, behaviorSource: null };
  return {
    startRetrieval() { retrievalStart = stamp(); },
    finishRetrieval(card) {
      state.retrievalDurationMs = duration(retrievalStart);
      if (card) state.behaviorSource = Object.freeze({ sourceId: card.sourceId,
        behaviorId: card.behaviorId, cardVersion: card.version, sha256: card.sha256,
        behaviors: card.selectedCards?.map(ref => ({ behaviorId: ref.behaviorId, cardVersion: ref.cardVersion })) ?? null });
    },
    startProvider() { state.providerStarted = true; providerStart = stamp(); },
    finishProvider() { state.providerDurationMs = duration(providerStart); state.providerFinished = true; },
    captureUsage(usage) {
      try {
        for (const key of ['promptTokens', 'outputTokens']) {
          if (Number.isSafeInteger(usage?.[key]) && usage[key] >= 0) state[key] = usage[key];
        }
      } catch (_) { /* Eksik/okunamayan sayaç null kalır; içerik sonucu değişmez. */ }
    },
    finish(outcome) {
      if (!terminal) {
        terminal = Object.freeze({ ...state, outcome, endpointDurationMs: duration(started) });
        try {
          if (typeof report === 'function') Promise.resolve(report(terminal)).catch(() => {});
        } catch (_) { /* Ölçüm alıcısı üretim yanıtını bozamaz. */ }
      }
      return terminal;
    },
  };
}
module.exports = { createGenerationMeasurement };
