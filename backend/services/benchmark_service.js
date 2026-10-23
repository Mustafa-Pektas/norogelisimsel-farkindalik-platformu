const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const logFilePath = path.join(__dirname, '..', 'logs', 'model_benchmarks.jsonl');

function ensureLogDir() {
  const dir = path.dirname(logFilePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function recordBenchmarkEntry(entry) {
  ensureLogDir();

  const record = {
    runId: entry.runId || `run_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`,
    timestamp: new Date().toISOString(),
    arm: entry.arm || 'B', // 'A' (Baseline), 'B' (Kural Enj.), 'C' (Full-Context)
    caseId: entry.caseId || 'custom',
    behaviorCode: entry.behaviorCode || 'D01',
    ageMonths: entry.ageMonths || 18,
    riskProfile: entry.riskProfile || 'ATİPİK',
    modelVersion: entry.modelVersion || 'gemini-flash',
    promptTokens: entry.promptTokens || 0,
    outputTokens: entry.outputTokens || 0,
    latencyApiMs: Math.round(entry.latencyApiMs || 0),
    retrievalMs: Number(entry.retrievalMs || 0),
    retryCount: entry.retryCount || 0,
    schemaValid: Boolean(entry.schemaValid),
    fsmMatchRate: Number(entry.fsmMatchRate || 0),
    deltaTCompliant: Boolean(entry.deltaTCompliant),
    envKeywordPass: Boolean(entry.envKeywordPass),
  };

  const line = JSON.stringify(record) + '\n';
  fs.appendFileSync(logFilePath, line, 'utf8');

  return record;
}

function getBenchmarkStats() {
  ensureLogDir();
  if (!fs.existsSync(logFilePath)) {
    return { totalRuns: 0, arms: {} };
  }

  const raw = fs.readFileSync(logFilePath, 'utf8');
  const lines = raw.split('\n').filter((l) => l.trim().length > 0);
  const entries = [];

  for (const l of lines) {
    try {
      entries.push(JSON.parse(l));
    } catch (_) {}
  }

  const arms = {
    A: { count: 0, latencies: [], fsmRates: [], deltaTPass: 0, schemaPass: 0, tokensIn: [], tokensOut: [] },
    B: { count: 0, latencies: [], fsmRates: [], deltaTPass: 0, schemaPass: 0, tokensIn: [], tokensOut: [] },
    C: { count: 0, latencies: [], fsmRates: [], deltaTPass: 0, schemaPass: 0, tokensIn: [], tokensOut: [] },
  };

  entries.forEach((e) => {
    const a = arms[e.arm] || arms.B;
    a.count++;
    if (e.latencyApiMs > 0) a.latencies.push(e.latencyApiMs);
    if (typeof e.fsmMatchRate === 'number') a.fsmRates.push(e.fsmMatchRate);
    if (e.deltaTCompliant) a.deltaTPass++;
    if (e.schemaValid) a.schemaPass++;
    if (e.promptTokens) a.tokensIn.push(e.promptTokens);
    if (e.outputTokens) a.tokensOut.push(e.outputTokens);
  });

  const summarize = (data) => {
    if (data.count === 0) return { count: 0 };
    const sortedLat = [...data.latencies].sort((x, y) => x - y);
    const medLat = sortedLat.length > 0 ? sortedLat[Math.floor(sortedLat.length / 2)] : 0;
    const p95Lat = sortedLat.length > 0 ? sortedLat[Math.floor(sortedLat.length * 0.95)] : 0;
    const avgFsm = data.fsmRates.length > 0 ? data.fsmRates.reduce((s, v) => s + v, 0) / data.fsmRates.length : 0;
    const avgTokensIn = data.tokensIn.length > 0 ? Math.round(data.tokensIn.reduce((s, v) => s + v, 0) / data.tokensIn.length) : 0;

    return {
      count: data.count,
      medianLatencyMs: medLat,
      p95LatencyMs: p95Lat,
      avgFsmMatchRate: Number(avgFsm.toFixed(4)),
      deltaTComplianceRate: Number((data.deltaTPass / data.count).toFixed(4)),
      schemaSuccessRate: Number((data.schemaPass / data.count).toFixed(4)),
      avgPromptTokens: avgTokensIn,
    };
  };

  return {
    totalRuns: entries.length,
    arms: {
      A_Baseline: summarize(arms.A),
      B_RuleInjection: summarize(arms.B),
      C_FullContext: summarize(arms.C),
    },
  };
}

module.exports = {
  recordBenchmarkEntry,
  getBenchmarkStats,
};
