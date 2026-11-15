const test = require('node:test');
const assert = require('node:assert/strict');
const { classifyLatency, classifyScenario, deltaTCompliance } = require('../delta_t');
const retriever = require('../rag/retriever');

const scenes = latencies => latencies.map(l => ({ phase: 'UYARAN', clinical: { latencySeconds: l } }))
  .concat([{ phase: 'TABAN', clinical: { latencySeconds: 9 } }]);

test('Gecikme sınıfı eşiklere göre (18-24 ay: 1,8 / 2,5 sn)', () => {
  assert.equal(classifyLatency(1.8, 1.8, 2.5), 'TIPIK');
  assert.equal(classifyLatency(2.0, 1.8, 2.5), 'SINIRDA');
  assert.equal(classifyLatency(2.5, 1.8, 2.5), 'ATIPIK');
  assert.equal(classifyLatency(null, 1.8, 2.5), null);
  assert.equal(classifyScenario([1.0, 3.0], 1.8, 2.5), 'ATIPIK');
  assert.equal(classifyScenario([1.0, 1.2], 1.8, 2.5), 'TIPIK');
  assert.equal(classifyScenario([1.0, 2.0], 1.8, 2.5), 'SINIRDA');
  assert.equal(classifyScenario([], 1.8, 2.5), null);
});

test('Gerçek retriever çıktısıyla uyum: eskiden hata yutulup her zaman true dönüyordu', () => {
  const sel = p => retriever.getSelectiveRuleContext({ behaviorCode: 'D01', ageMonths: 21, riskProfile: p });
  assert.equal(deltaTCompliance(scenes([1.2]), sel('TİPİK')).compliant, true);
  assert.equal(deltaTCompliance(scenes([3.1]), sel('TİPİK')).compliant, false);
  assert.equal(deltaTCompliance(scenes([3.1]), sel('ATİPİK')).compliant, true);
  assert.equal(deltaTCompliance(scenes([2.1]), sel('SINIRDA')).compliant, true);
  const r = deltaTCompliance(scenes([2.1]), sel('ATİPİK'));
  assert.deepEqual([r.compliant, r.expected, r.actual], [false, 'ATIPIK', 'SINIRDA']);
  assert.equal(deltaTCompliance([{ phase: 'UYARAN', clinical: {} }], sel('TİPİK')).compliant, null);
  const noLatencyCard = retriever.getSelectiveRuleContext({ behaviorCode: 'D04', ageMonths: 30, riskProfile: 'TİPİK' });
  assert.equal(deltaTCompliance(scenes([5]), noLatencyCard).compliant, null);
});
