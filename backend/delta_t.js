'use strict';
// UYARAN sahnelerindeki tepki gecikmelerinin (latencySeconds) istenen risk profiline uyumu.
// Eşikler bilgi tabanından gelir (retriever.getSelectiveRuleContext); simülasyon tasarım parametresidir.

// Tek gecikmeyi sınıflar: ≤ tipik üst sınır → TIPIK, ≥ atipik alt sınır → ATIPIK, arası → SINIRDA.
function classifyLatency(latency, typicalMax, atypicalMin) {
  if (typeof latency !== 'number' || !Number.isFinite(latency)) return null;
  if (latency <= typicalMax) return 'TIPIK';
  if (latency >= atypicalMin) return 'ATIPIK';
  return 'SINIRDA';
}

// Senaryonun gerçekleşen sınıfı: herhangi bir gecikme atipik ise ATIPIK; hepsi tipik ise TIPIK; aksi SINIRDA.
// Gecikme yoksa null (sınıflanamadı).
function classifyScenario(latencies, typicalMax, atypicalMin) {
  const classes = latencies.map(l => classifyLatency(l, typicalMax, atypicalMin)).filter(Boolean);
  if (!classes.length) return null;
  if (classes.includes('ATIPIK')) return 'ATIPIK';
  if (classes.every(c => c === 'TIPIK')) return 'TIPIK';
  return 'SINIRDA';
}

function uyaranLatencies(scenes) {
  return (scenes || []).filter(s => s && s.phase === 'UYARAN')
    .map(s => s.clinical?.latencySeconds).filter(l => typeof l === 'number' && Number.isFinite(l));
}

// selective: getSelectiveRuleContext çıktısı. Gecikme eşiği olmayan kartlarda veya gecikme yoksa null döner
// (eskiden "uyumlu" sayılıyordu; ölçülemeyen uyum değildir).
function deltaTCompliance(scenes, selective) {
  if (!selective || !selective.hasLatencyThreshold) return { compliant: null, reason: 'no_latency_threshold' };
  const latencies = uyaranLatencies(scenes);
  if (!latencies.length) return { compliant: null, reason: 'no_latency_values', latencies };
  const actual = classifyScenario(latencies, selective.expectedTypicalDelayMax, selective.expectedAtypicalDelayMin);
  return { compliant: actual === selective.riskCategory, expected: selective.riskCategory, actual, latencies };
}

module.exports = { classifyLatency, classifyScenario, uyaranLatencies, deltaTCompliance };
