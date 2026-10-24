const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { generateText, generateTextWithUsage } = require('../gemini_text');
const { createScenarioInputHandler, loadCard } = require('../scenario_input_generation');
const { createGenerationCapacity } = require('../generation_capacity');
const { createGenerationMeasurement } = require('../generation_measurement');

const request = { behaviorId: 'D01', cardVersion: '0.2', ageMonths: 31,
  sceneContext: 'NEVER_LOG_CONTEXT_CHILD_NAME', additionalInstructions: 'NEVER_LOG_INSTRUCTION' };
const narrative = ' \n' + JSON.stringify({ commonStart: 'NEVER_LOG_RAW', alternatives: [
  { title: 'Devam', continuation: 'Yönelme.', ending: 'Bitiş.' }] }) + '\n ';
const graph = { schemaVersion: '1.0', scenarioId: 'measure-story', title: 'Taslak', language: 'tr',
  ageMonths: 31, behaviorId: 'D01', cardVersion: '0.2', startSceneId: 'start',
  scenes: [{ id: 'start', description: 'Başlangıç' }, { id: 'end', description: 'Bitiş' }],
  transitions: [{ fromSceneId: 'start', toSceneId: 'end', description: 'Devam' }], endSceneIds: ['end'] };
const planInput = { request, graph, planId: 'generated-measurement' };
const plan = ' \n' + JSON.stringify({ schemaVersion: '1.0', scenarioId: graph.scenarioId,
  planId: planInput.planId, authoringNote: 'İncelenmedi', continuityNotes: 'Aynı ortam', visualSuggestions: 'Öneri',
  d01CallTiming: [{ clipId: 'start-clip', callEndS: 3 }],
  clips: graph.scenes.map(scene => ({ id: `${scene.id}-clip`, sceneId: scene.id, orderInScene: 1,
    targetDurationS: 8, plannedAction: 'Oyun', initialState: 'Önce', finalState: 'Sonra',
    productionPrompt: 'NEVER_LOG_PROMPT', voiceoverInstructions: 'NEVER_LOG_AUDIO' })) }) + '\n ';
function deferred() {
  let resolve, reject;
  const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
}
class Response extends EventEmitter {
  constructor() { super(); this.statusCode = 200; this.bodies = []; }
  status(code) { this.statusCode = code; return this; }
  json(body) { this.bodies.push(body); return this; }
}
function call(handler, body) {
  const res = new Response();
  return { res, done: handler({ body }, res) };
}
function assertSafe(record) {
  const serialized = JSON.stringify(record);
  for (const forbidden of ['NEVER_LOG', 'Authorization', 'Bearer', 'TEAM_ACCESS_KEY', 'sceneContext', 'rawResponse', 'C:\\']) {
    assert.ok(!serialized.includes(forbidden));
  }
  assert.match(record.requestId, /^[0-9a-f-]{36}$/);
  assert.equal(record.behaviorSource.sourceId, 'Davranis_Kartlari_v02.md');
  assert.equal(record.behaviorSource.cardVersion, '0.2');
  assert.equal(record.behaviorSource.behaviorId, 'D01');
  assert.equal(record.behaviorSource.sha256.length, 64);
}

test('SDK usage mevcutsa gerçek sayaç; yoksa/geçersizse null; ham metin ve eski metin arayüzü korunur', async () => {
  for (const [usage, expected] of [[undefined, { promptTokens: null, outputTokens: null }],
    [{ promptTokenCount: 0, candidatesTokenCount: 7 }, { promptTokens: 0, outputTokens: 7 }],
    [{ promptTokenCount: -1, candidatesTokenCount: '7' }, { promptTokens: null, outputTokens: null }]]) {
    let calls = 0;
    const sdk = { getGenerativeModel() { return { async generateContent() {
      calls++; return { response: { text: () => narrative, usageMetadata: usage } };
    } }; } };
    const result = await generateTextWithUsage(sdk, 'controlled', { system: '', user: '' }, { schema: {}, maxOutputTokens: 5 });
    assert.equal(result.text, narrative); assert.deepEqual(result.usage, expected); assert.equal(calls, 1);
    assert.equal(await generateText(sdk, 'controlled', { system: '', user: '' }, { schema: {}, maxOutputTokens: 5 }), narrative);
    assert.equal(calls, 2); // İki açık çağrı; çağrı başına otomatik tekrar yok.
  }
  const sdk = { getGenerativeModel() { return { async generateContent() {
    return { response: { text: () => narrative, get usageMetadata() { throw Error('Ölçüm okunamadı'); } } };
  } }; } };
  assert.equal((await generateTextWithUsage(sdk, '', { system: '', user: '' }, {})).text, narrative);
});

for (const clipPlan of [false, true]) {
  for (const mode of ['success', 'validation_error', 'provider_error']) {
    test(`${clipPlan ? 'plan' : 'senaryo'} ${mode}: tek kaynak/seçim, ayrı süreler, tek güvenli ölçüm`, async () => {
      const records = [];
      let time = 0, calls = 0;
      const expected = clipPlan ? plan : narrative;
      const card = await loadCard(request);
      const run = call(createScenarioInputHandler({ clipPlan, modelName: 'controlled', now: () => ++time,
        reportProviderError: () => {}, reportMeasurement: record => records.push(record),
        generate: async (_, prompts) => {
          calls++;
          assert.equal(prompts.system.split(card.section).length - 1, 1);
          assert.equal(prompts.system.split(card.commonRules).length - 1, 1);
          assert.deepEqual(JSON.parse(prompts.user), clipPlan ? planInput : request);
          if (mode === 'provider_error') throw Error('NEVER_LOG_PROVIDER_DETAILS');
          return { text: mode === 'validation_error' ? '{bozuk' : expected,
            usage: { promptTokens: 12, outputTokens: 0 } };
        } }), clipPlan ? planInput : request);
      await run.done;
      assert.equal(calls, 1); assert.equal(records.length, 1);
      const record = records[0];
      assert.equal(record.outcome, mode);
      assert.equal(record.endpoint, clipPlan ? 'generate-clip-plan' : 'generate-scenario-input');
      assert.equal(record.retrievalDurationMs, 1);
      assert.equal(record.providerDurationMs, 1);
      assert.equal(record.endpointDurationMs, 5);
      assert.equal(record.providerStarted, true); assert.equal(record.providerFinished, true);
      assert.equal(record.promptTokens, mode === 'provider_error' ? null : 12);
      assert.equal(record.outputTokens, mode === 'provider_error' ? null : 0);
      assertSafe(record);
      assert.deepEqual(run.res.bodies[0].measurement, record);
      assert.equal(run.res.statusCode, mode === 'success' ? 200 : 502);
      if (mode === 'success') {
        assert.equal(run.res.bodies[0].rawResponse, expected);
        assert.equal(run.res.bodies[0].behaviorSource.sourceId, card.sourceId);
      } else if (mode === 'validation_error') assert.equal(run.res.bodies[0].rawResponse, '{bozuk');
    });
  }
}

for (const clipPlan of [false, true]) {
  for (const reason of ['timeout', 'disconnected']) {
    for (const lateError of [false, true]) {
      test(`${clipPlan ? 'plan' : 'senaryo'} ${reason}: geç ${lateError ? 'hata' : 'başarı'} çift sayılmaz; slot erken bırakılmaz`, async () => {
        const started = deferred(), answer = deferred(), released = deferred();
        const pool = createGenerationCapacity();
        const records = [];
        let deadline, releases = 0;
        const run = call(createScenarioInputHandler({ clipPlan, modelName: 'controlled',
          reportMeasurement: record => records.push(record), reportProviderError: () => {},
          capacity: { tryAcquire() { const release = pool.tryAcquire(); return release ? () => {
            releases++; release(); released.resolve();
          } : null; } },
          timers: { setTimeout(callback) { deadline = callback; return 1; }, clearTimeout() {} },
          generate: async () => { started.resolve(); return answer.promise; },
        }), clipPlan ? planInput : request);
        await started.promise;
        if (reason === 'timeout') deadline(); else run.res.emit('close');
        await run.done;
        assert.equal(records.length, 1);
        const original = JSON.stringify(records[0]);
        assert.equal(records[0].outcome, reason);
        assert.equal(records[0].providerStarted, true);
        assert.equal(records[0].providerFinished, false);
        assert.equal(records[0].providerDurationMs, null);
        assert.equal(records[0].promptTokens, null);
        assert.equal(pool.tryAcquire(), null);
        if (lateError) answer.reject(Error('Geç sağlayıcı hatası'));
        else answer.resolve({ text: clipPlan ? plan : narrative, usage: { promptTokens: 99 } });
        await released.promise;
        assert.equal(releases, 1);
        assert.equal(records.length, 1);
        assert.equal(JSON.stringify(records[0]), original);
        assert.equal(run.res.bodies.length, reason === 'timeout' ? 1 : 0);
        const release = pool.tryAcquire(); assert.equal(typeof release, 'function'); release();
        assertSafe(records[0]);
      });
    }
  }
}

test('Ölçüm saati/alıcı hatası üretimi değiştirmez; terminal requestId tek kalır', async () => {
  for (const reportMeasurement of [() => { throw Error('Kayıt hatası'); }, async () => { throw Error('Async kayıt hatası'); }]) {
    const run = call(createScenarioInputHandler({ modelName: 'controlled', now: () => { throw Error('Saat hatası'); },
      reportMeasurement, generate: async () => narrative }), request);
    await run.done;
    assert.equal(run.res.statusCode, 200); assert.equal(run.res.bodies[0].rawResponse, narrative);
    assert.equal(run.res.bodies[0].measurement.endpointDurationMs, null);
    assert.equal(run.res.bodies[0].measurement.providerDurationMs, null);
    assert.equal(run.res.bodies[0].measurement.outputTokens, null);
  }
  const records = [];
  const measure = createGenerationMeasurement({ endpoint: 'generate-scenario-input', report: x => records.push(x) });
  const first = measure.finish('timeout');
  assert.equal(measure.finish('success'), first); assert.equal(records.length, 1);
  assert.ok(Object.isFrozen(first));
});

test('Başarıyla sınırlı örnekleme yok: geçersiz istek/kapasite/yapılandırma da ayrı kayıt verir', async () => {
  const records = [];
  for (const mode of ['invalid_request', 'capacity_rejected', 'configuration_error']) {
    const run = call(createScenarioInputHandler({ modelName: mode === 'configuration_error' ? '' : 'controlled',
      capacity: mode === 'capacity_rejected' ? { tryAcquire: () => null } : null,
      reportMeasurement: record => records.push(record),
      generate: async () => { throw Error('Sağlayıcıya ulaşılmamalı'); },
    }), mode === 'invalid_request' ? { ...request, ageMonths: 11 } : request);
    await run.done;
    assert.equal(records.at(-1).outcome, mode);
    assert.equal(records.at(-1).providerStarted, false);
  }
  assert.equal(records.length, 3);
  assert.equal(new Set(records.map(x => x.requestId)).size, 3);
});
