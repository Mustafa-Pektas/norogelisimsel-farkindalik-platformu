/**
 * Otomatik ve Deterministik Senaryo & FSM Doğrulayıcısı
 * LLM kullanmaz; saf kural ve mantık denetimi yapar.
 */

function validateFSMContinuity(scenes) {
  if (!Array.isArray(scenes) || scenes.length < 2) {
    return { matchRate: 0, matchedCount: 0, totalTransitions: 25, details: [] };
  }

  const totalTransitions = scenes.length - 1;
  let matchedCount = 0;
  const details = [];

  for (let i = 0; i < totalTransitions; i++) {
    const end = (scenes[i].endState || '').trim().toLowerCase();
    const start = (scenes[i + 1].startState || '').trim().toLowerCase();

    // Tam eşitlik veya yüksek kelime benzerliği
    const isExact = end === start && end.length > 0;
    const isClose = !isExact && (end.includes(start) || start.includes(end) || hasTokenOverlap(end, start));
    const passed = isExact || isClose;

    if (passed) matchedCount++;

    details.push({
      transition: `${i + 1} -> ${i + 2}`,
      endState: scenes[i].endState,
      startState: scenes[i + 1].startState,
      passed,
      isExact,
    });
  }

  const matchRate = totalTransitions > 0 ? Number((matchedCount / totalTransitions).toFixed(4)) : 0;

  return {
    matchRate,
    matchedCount,
    totalTransitions,
    passed: matchRate >= 0.8, // %80 ve üzeri süreklilik kabul edilir
    details,
  };
}

function hasTokenOverlap(s1, s2) {
  const t1 = new Set(s1.split(/\s+/).filter((w) => w.length > 3));
  const t2 = new Set(s2.split(/\s+/).filter((w) => w.length > 3));
  let common = 0;
  for (const w of t1) {
    if (t2.has(w)) common++;
  }
  return common >= 3;
}

function validateDeltaTCompliance({ scenes, riskProfile, expectedAtypicalMin = 2.5, expectedTypicalMax = 2.0 }) {
  if (!Array.isArray(scenes)) return { compliant: false, reasons: ['scenes dizisi yok'] };

  const normRisk = (riskProfile || '').replace(/İ/g, 'I').replace(/ı/g, 'i').toUpperCase();
  const isAtypical = normRisk.includes('ATIPIK') || normRisk.includes('ATYPICAL') || normRisk.includes('RISK');
  const stimulusScenes = scenes.filter((s) => s.phase === 'UYARAN');
  const reasons = [];
  let evaluated = 0;
  let compliantCount = 0;

  stimulusScenes.forEach((s, idx) => {
    if (s.clinical && s.clinical.latencySeconds !== undefined && s.clinical.latencySeconds !== null) {
      evaluated++;
      const lat = Number(s.clinical.latencySeconds);
      if (isAtypical) {
        if (lat >= expectedAtypicalMin) {
          compliantCount++;
        } else {
          reasons.push(`Uyaran Sahne ${idx + 1}: Atipik gecikme (${lat}s) beklenen ${expectedAtypicalMin}s eşiğinden küçük.`);
        }
      } else {
        if (lat <= expectedTypicalMax) {
          compliantCount++;
        } else {
          reasons.push(`Uyaran Sahne ${idx + 1}: Tipik gecikme (${lat}s) beklenen ${expectedTypicalMax}s eşiğinden büyük.`);
        }
      }
    }
  });

  // Atipik vakalarda hiç tepki verilmemesi (latencySeconds: null veya hiç olmaması) da ADOS-2 kuralı gereği geçerli atipikliktir
  const compliant = isAtypical ? (evaluated === 0 || compliantCount > 0) : compliantCount > 0;

  return {
    compliant,
    evaluated,
    compliantCount,
    isAtypical,
    reasons,
  };
}

function validateEnvironmentKeywords(scenes) {
  if (!Array.isArray(scenes)) return { pass: false, passRate: 0 };

  const keys = ['car', 'sweater', 'rug'];
  let passCount = 0;

  scenes.forEach((s) => {
    const text = (s.videoPrompt || '').toLowerCase();
    const hits = keys.filter((k) => text.includes(k));
    if (hits.length >= 2) passCount++;
  });

  const passRate = Number((passCount / scenes.length).toFixed(4));
  return {
    pass: passRate >= 0.75,
    passRate,
    passCount,
    totalScenes: scenes.length,
  };
}

function validateFullScenario(scenarioJson, { riskProfile, expectedAtypicalMin, expectedTypicalMax }) {
  const scenes = scenarioJson?.scenes || [];
  const sceneCountValid = scenes.length === 26;

  const fsm = validateFSMContinuity(scenes);
  const deltaT = validateDeltaTCompliance({
    scenes,
    riskProfile,
    expectedAtypicalMin,
    expectedTypicalMax,
  });
  const env = validateEnvironmentKeywords(scenes);

  return {
    schemaValid: sceneCountValid && Boolean(scenarioJson?.summary) && Boolean(scenarioJson?.title),
    sceneCount: scenes.length,
    fsmMatchRate: fsm.matchRate,
    fsmPassed: fsm.passed,
    deltaTCompliant: deltaT.compliant,
    envKeywordPass: env.pass,
    envPassRate: env.passRate,
    reasons: [...deltaT.reasons],
  };
}

module.exports = {
  validateFSMContinuity,
  validateDeltaTCompliance,
  validateEnvironmentKeywords,
  validateFullScenario,
};
