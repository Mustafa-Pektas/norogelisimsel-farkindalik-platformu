const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { createGenerationCapacity } = require('../generation_capacity');
const { loadCard, createScenarioInputHandler } = require('../scenario_input_generation');
const { validateComparisonRequest, prepareComparison, validateComparisonOutput, finalizeLegacyComparisonOutput, validateLegacyComparisonOutput, validateFSMContinuity,
  settings } = require('../scenario_comparison');
const request = { behaviorId: 'D01', cardVersion: '0.2', ageMonths: 31,
  sceneContext: 'Deniz evde bloklarla oynar.', additionalInstructions: 'Sabit kamera.' };
const legacyRaw = ' \n' + JSON.stringify({ title: 'Deney', summary: 'Üretilmiş görsel öneri: açık renk kıyafet.',
  scenes: Array.from({ length: 26 }, (_, i) => ({ phase: i < 6 ? 'TABAN' : i < 17 ? 'UYARAN' : 'KAPANIS',
    videoPrompt: 'Same child, blocks, room and stationary camera.', startState: `state-${i}`, endState: `state-${i + 1}` })) }) + '\n ';
const raw = ' \n' + JSON.stringify({ commonStart: 'Deniz bloklarla oynar; anne bir kez Deniz der.',
  alternatives: [{ title: 'Yönelme', continuation: 'Deniz annesine başını çevirir.', ending: 'Çağrı tekrarlanmadan biter.' },
    { title: 'Oyun', continuation: 'Deniz oyuna devam eder.', ending: 'Çağrı tekrarlanmadan biter.' }] }) + '\n ';
class Response extends EventEmitter {
  constructor() { super(); this.statusCode = 200; this.bodies = []; }
  status(code) { this.statusCode = code; return this; }
  json(body) { this.bodies.push(body); return this; }
}
async function call(handler, body) {
  const res = new Response(); await handler({ body }, res); return res;
}

test('223bc7d A/B/C uyarlaması: aynı temel/girdi, tek kanonik kaynak, kaynak miktarı farklı', async () => {
  const card = await loadCard(request);
  const previews = ['A', 'B', 'C'].map(arm => prepareComparison({ request, arm, action: 'preview' }, card, 'controlled'));
  assert.equal(new Set(previews.map(p => p.protocolId)).size, 1);
  assert.equal(new Set(previews.map(p => p.user)).size, 1);
  assert.equal(new Set(previews.map(p => p.system.split('KAYNAK BAĞLAMI:')[0])).size, 1);
  assert.ok(!previews[0].system.includes(card.section));
  assert.equal(previews[1].system.split(card.section).length - 1, 1);
  assert.equal(previews[1].system.split(card.commonRules).length - 1, 1);
  assert.equal(previews[2].system.split(card.fullText).length - 1, 1);
  for (const preview of previews) {
    assert.ok(preview.system.includes(card.title));
    assert.equal(preview.outputContract, 'scenario-input-narrative-v3');
    assert.deepEqual(preview.settings, settings);
    assert.deepEqual(JSON.parse(preview.user), request);
    assert.equal(preview.source.sha256, card.sha256);
    assert.ok(!preview.system.includes('Klinik Tepki Eşiği'));
  }
  assert.throws(() => prepareComparison({ request, arm: 'A', action: 'generate', protocolId: previews[0].protocolId },
    { ...card, sha256: 'changed' }, 'controlled'), /değişti/);
  assert.throws(() => prepareComparison({ request, arm: 'A', action: 'generate', protocolId: previews[0].protocolId },
    card, 'other-model'), /değişti/);
  assert.throws(() => prepareComparison({ request, arm: 'A', action: 'generate', protocolId: '0'.repeat(64) },
    card, 'controlled'), /değişti/);
});

test('Normal üretim ve A/B/C aynı görev, ayar ve anlatı şemasını kullanır; kaynak dışında kol farkı yoktur', async () => {
  const { narrativeSchema, narrativeSettings } = require('../scenario_input_generation');
  const card = await loadCard(request);
  let normal;
  const handler = createScenarioInputHandler({ modelName: 'controlled', generate: async (model, prompts, options) => {
    normal = { model, prompts, options }; return raw;
  } });
  const response = await call(handler, request);
  assert.equal(response.statusCode, 200);
  for (const arm of ['A', 'B', 'C']) {
    const preview = prepareComparison({ request, arm, action: 'preview' }, card, 'controlled');
    assert.equal(preview.system.split('KAYNAK BAĞLAMI:')[0], normal.prompts.system.split('KAYNAK BAĞLAMI:')[0]);
    assert.equal(preview.user, normal.prompts.user);
    assert.deepEqual(preview.settings, narrativeSettings);
  }
  assert.deepEqual(normal.options, { schema: narrativeSchema, ...narrativeSettings });
  assert.equal(response.bodies[0].rawResponse, raw);
});

test('Önizleme sağlayıcı/kapasite tüketmez; kullanıcı protokolü olmadan üretim yok', async () => {
  let calls = 0;
  const handler = createScenarioInputHandler({ comparison: true, modelName: 'controlled',
    capacity: { tryAcquire() { throw Error('Önizleme slot tüketmemeli'); } },
    generate: async () => { calls++; return raw; } });
  for (const arm of ['A', 'B', 'C']) {
    const response = await call(handler, { request, arm, action: 'preview' });
    assert.equal(response.statusCode, 200); assert.equal(response.bodies[0].measurement.outcome, 'preview');
    assert.equal(response.bodies[0].measurement.providerStarted, false);
    assert.equal(response.bodies[0].preview.arm, arm);
  }
  assert.equal((await call(handler, { request, arm: 'A', action: 'generate' })).statusCode, 400);
  assert.equal(calls, 0);
  for (const patch of [{ arm: 'X' }, { request: { ...request, ageMonths: 11 } },
    { request: { ...request, behaviorId: 'ONT-01' } }, { riskProfile: 'typical' }]) {
    assert.throws(() => validateComparisonRequest({ request, arm: 'A', action: 'preview', ...patch }));
  }
});

test('Üç ayrı açık başlatma aynı ayarlarla üç çağrı yapar; ham cevap ve her kolun ölçümü korunur', async () => {
  const calls = [];
  const handler = createScenarioInputHandler({ comparison: true, modelName: 'controlled',
    generate: async (model, prompts, options) => {
      calls.push({ model, prompts, options }); return { text: raw, usage: { promptTokens: 10, outputTokens: 0 } };
    } });
  const records = [];
  for (const arm of ['A', 'B', 'C']) {
    const preview = (await call(handler, { request, arm, action: 'preview' })).bodies[0].preview;
    const response = await call(handler, { request, arm, action: 'generate', protocolId: preview.protocolId });
    assert.equal(response.statusCode, 200);
    const body = response.bodies[0];
    assert.equal(body.rawResponse, raw); assert.equal(body.comparison.arm, arm);
    assert.deepEqual(body.scenarioInput, JSON.parse(raw));
    assert.equal(body.comparison.outputContract, 'scenario-input-narrative-v3');
    assert.equal(body.scenario, undefined);
    assert.equal(body.textualContinuity, undefined);
    assert.equal(body.measurement.outputTokens, 0); assert.equal(body.measurement.endpoint, 'compare-scenario');
    records.push(body.measurement);
  }
  assert.equal(calls.length, 3);
  for (const call of calls) {
    assert.equal(call.model, 'controlled');
    assert.equal(call.options.temperature, 0.2); assert.equal(call.options.topP, 0.95);
    assert.equal(call.options.maxOutputTokens, 16384); assert.deepEqual(JSON.parse(call.prompts.user), request);
  }
  assert.equal(new Set(records.map(r => r.requestId)).size, 3);
  assert.equal(records.length, 3);
});

test('26 sahne mobil alanları ham cevap değiştirilmeden plan metaverisiyle tamamlanır', () => {
  const parsed = validateLegacyComparisonOutput(legacyRaw);
  const finalized = finalizeLegacyComparisonOutput(parsed);
  assert.equal(legacyRaw.startsWith(' \n'), true);
  assert.equal(legacyRaw.endsWith('\n '), true);
  assert.equal(finalized.scenes.length, 26);
  assert.equal(finalized.scenes[0].durationSec, 8);
  assert.equal(finalized.scenes[1].time, '00:08');
  assert.equal(finalized.scenes[25].time, '03:20');
  assert.equal(parsed.scenes[0].id, undefined);
});

test('Boş durum FSM eşleşmesi değildir; klinik alan ve eksik sahne reddedilir; hatada ham metin kaybolmaz', async () => {
  assert.equal(validateFSMContinuity([{ endState: '' }, { startState: '' }]).matchedCount, 0);
  assert.equal(validateFSMContinuity([]).matchRate, null);
  const invalid = JSON.parse(raw); invalid.clinical = { latencySeconds: 2 };
  assert.throws(() => validateComparisonOutput(JSON.stringify(invalid), request), /geçersiz/);
  delete invalid.clinical;
  delete invalid.alternatives[0].ending;
  assert.throws(() => validateComparisonOutput(JSON.stringify(invalid), request), /eksik/);
  assert.throws(() => validateComparisonOutput(legacyRaw, request), /geçersiz/);
  for (const kind of ['validation', 'provider']) {
    let calls = 0;
    const handler = createScenarioInputHandler({ comparison: true, modelName: 'controlled', reportProviderError: () => {},
      generate: async () => { calls++; if (kind === 'provider') throw Error('Kontrollü hata'); return ' bozuk ham '; } });
    const preview = (await call(handler, { request, arm: 'B', action: 'preview' })).bodies[0].preview;
    const response = await call(handler, { request, arm: 'B', action: 'generate', protocolId: preview.protocolId });
    assert.equal(response.statusCode, 502); assert.equal(calls, 1);
    assert.equal(response.bodies[0].measurement.outcome, kind === 'provider' ? 'provider_error' : 'validation_error');
    if (kind === 'validation') assert.equal(response.bodies[0].rawResponse, ' bozuk ham ');
  }
});

test('Karşılaştırma timeout geç cevabı uygulamaz; ortak slot sağlayıcı bitene kadar tutulur', async () => {
  let start, finish, releaseObserved;
  const started = new Promise(resolve => { start = resolve; });
  const gate = new Promise(resolve => { finish = resolve; });
  const released = new Promise(resolve => { releaseObserved = resolve; });
  const pool = createGenerationCapacity();
  let deadline, calls = 0;
  const records = [];
  const handler = createScenarioInputHandler({ comparison: true, modelName: 'controlled',
    capacity: { tryAcquire() { const release = pool.tryAcquire(); return release ? () => {
      release(); releaseObserved();
    } : null; } }, reportMeasurement: record => records.push(record),
    timers: { setTimeout(callback) { deadline = callback; return 1; }, clearTimeout() {} },
    generate: async () => { calls++; start(); await gate; return raw; },
  });
  const card = await loadCard(request);
  const preview = prepareComparison({ request, arm: 'A', action: 'preview' }, card, 'controlled');
  const body = { request, arm: 'A', action: 'generate', protocolId: preview.protocolId };
  const res = new Response(); const pending = handler({ body }, res);
  await started; deadline(); await pending;
  assert.equal(res.statusCode, 504); assert.equal(records[0].outcome, 'timeout');
  assert.equal(pool.tryAcquire(), null); assert.equal(calls, 1);
  finish(); await released;
  assert.equal(res.bodies.length, 1); assert.equal(records.length, 1);
  assert.equal((await call(handler, body)).statusCode, 200); assert.equal(calls, 2);
});
