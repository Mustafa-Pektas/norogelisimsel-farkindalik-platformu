const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { validateRequest, requestBehaviors, loadCard, narrativeSchemaFor, validateNarrative,
  createScenarioInputHandler, narrativeContract, narrativeSettings } = require('../scenario_input_generation');
const { prepareComparison } = require('../scenario_comparison');
const { validatePlanRequest, validatePlan, buildPlanPrompts } = require('../scenario_clip_generation');

const refs = ['D01','D02'].map(behaviorId => ({ behaviorId, cardVersion: '0.2' }));
const request = { requestVersion: '2.0', behaviors: refs, ageMonths: 31,
  sceneContext: '  Evde oyuncaklarla oyun.  ', additionalInstructions: 'Sabit kamera.' };
const branched = { structure: 'branched', commonStart: '  Ortak başlangıç.  ', commonBehaviorIds: ['D01','D02'],
  alternatives: [
    { title: 'Birinci devam', continuation: '  Birinci devam metni.  ', ending: 'Birinci bitiş.', behaviorIds: ['D01'] },
    { title: 'İkinci devam', continuation: 'İkinci devam metni.', ending: 'İkinci bitiş.', behaviorIds: ['D02'] },
  ] };
const linearRequest = { ...request, production: { structure: 'linear26', targetSceneCount: 26,
  targetDurationS: 210, maxClipDurationS: 8 } };
const linear = { structure: 'linear26', commonStart: '  Genel anlatı.  ', alternatives: [],
  linearScenes: Array.from({ length: 26 }, (_, i) => ({ title: `Sahne ${i + 1}`,
    description: `  Anlatı ${i + 1}.  `, behaviorIds: [i % 2 ? 'D02' : 'D01'] })) };
class Reply extends EventEmitter {
  constructor() { super(); this.statusCode = 200; }
  status(value) { this.statusCode = value; return this; }
  json(body) { this.body = body; return this; }
}
async function call(handler, body) { const res = new Reply(); await handler({ body }, res); return res; }

test('V2 bütün kimlik/sürümleri korur; v1 tek davranış aynı biçimde kalır', () => {
  assert.deepEqual(validateRequest(request), request);
  const legacy = { behaviorId: 'D01', cardVersion: '0.2', ageMonths: 31,
    sceneContext: request.sceneContext, additionalInstructions: null };
  assert.deepEqual(validateRequest(legacy), legacy);
  assert.deepEqual(requestBehaviors(legacy), [refs[0]]);
  for (const body of [{ ...request, behaviors: [] }, { ...request, behaviors: [refs[0],refs[0]] },
    { ...request, behaviors: [{ behaviorId: 'ONT-01', cardVersion: '0.2' }] },
    { ...request, ageMonths: 11 }, { ...request, ageMonths: 37 }, { ...linearRequest,
      production: { ...linearRequest.production, maxClipDurationS: 9 } }]) {
    assert.throws(() => validateRequest(body));
  }
});
test('Tek kaynak tüm seçili kartları bir kez içerir; ilk kartla yetinmez ve sürüm hatası fallback yapmaz', async () => {
  const card = await loadCard(request);
  assert.deepEqual(card.selectedCards.map(c => ({ behaviorId: c.behaviorId, cardVersion: c.cardVersion })), refs);
  for (const selected of card.selectedCards) assert.equal(card.section.split(selected.section).length - 1, 1);
  await assert.rejects(loadCard({ ...request, behaviors: [refs[0], { ...refs[1], cardVersion: '0.1' }] }), /sürüm/);
  const previews = ['A','B','C'].map(arm => prepareComparison({ request, arm, action: 'preview' }, card, 'controlled'));
  assert.equal(new Set(previews.map(p => p.protocolId)).size, 1);
  assert.equal(new Set(previews.map(p => p.system.split('KAYNAK BAĞLAMI:')[0])).size, 1);
  for (const preview of previews) {
    assert.deepEqual(JSON.parse(preview.user), request);
    assert.deepEqual(preview.source.behaviors, refs);
    assert.deepEqual(preview.settings, narrativeSettings);
    assert.equal(preview.outputContract, narrativeContract);
  }
  for (const selected of card.selectedCards) {
    assert.equal(previews[1].system.split(selected.section).length - 1, 1);
    assert.ok(!previews[0].system.includes(selected.section));
  }
});
test('Dallı çıktı seçilen davranışları sahnelere bağlar; eksik ilişki veya kayıp kart reddedilir', () => {
  const raw = ' \n' + JSON.stringify(branched) + '\n ';
  assert.deepEqual(validateNarrative(raw, request), branched);
  for (const change of [value => { delete value.commonBehaviorIds; }, value => { value.alternatives[0].behaviorIds = ['D10']; },
    value => { value.commonBehaviorIds = ['D01']; value.alternatives[1].behaviorIds = ['D01']; }]) {
    const value = structuredClone(branched); change(value);
    assert.throws(() => validateNarrative(JSON.stringify(value), request));
  }
  assert.equal(raw, ' \n' + JSON.stringify(branched) + '\n ');
});
test('26 sahne isteği model anlatısını korur; eski doğrusal çıktı veya uydurulmuş dal kabul edilmez', async () => {
  assert.deepEqual(validateNarrative(JSON.stringify(linear), linearRequest), linear);
  for (const value of [{ ...linear, linearScenes: linear.linearScenes.slice(1) },
    { ...linear, alternatives: branched.alternatives }, { title: 'Eski', scenes: linear.linearScenes }]) {
    assert.throws(() => validateNarrative(JSON.stringify(value), linearRequest));
  }
  const card = await loadCard(request);
  const oldPreview = prepareComparison({ request, arm: 'A', action: 'preview' }, card, 'controlled');
  assert.throws(() => prepareComparison({ request: linearRequest, arm: 'A', action: 'generate', protocolId: oldPreview.protocolId },
    card, 'controlled'), /değişti/);
});
test('Normal ve A/B/C aynı çoklu istek/şema/ayarları kullanır; seçim için ek sağlayıcı çağrısı yoktur', async () => {
  for (const input of [request, linearRequest]) {
    const output = input.production ? linear : branched;
    const raw = ' \n' + JSON.stringify(output) + '\n ';
    const calls = [];
    const generate = async (model, prompts, settings) => { calls.push({ model, prompts, settings }); return raw; };
    const normal = await call(createScenarioInputHandler({ generate, modelName: 'controlled' }), input);
    assert.equal(normal.statusCode, 200); assert.equal(normal.body.rawResponse, raw);
    assert.deepEqual(normal.body.behaviorSource.behaviors, refs);
    const comparison = createScenarioInputHandler({ generate, modelName: 'controlled', comparison: true });
    for (const arm of ['A','B','C']) {
      const preview = await call(comparison, { request: input, arm, action: 'preview' });
      const result = await call(comparison, { request: input, arm, action: 'generate', protocolId: preview.body.preview.protocolId });
      assert.equal(result.statusCode, 200); assert.equal(result.body.rawResponse, raw);
    }
    assert.equal(calls.length, 4);
    for (const actual of calls) {
      assert.deepEqual(JSON.parse(actual.prompts.user), input);
      assert.deepEqual(actual.settings, { schema: narrativeSchemaFor(input), ...narrativeSettings });
    }
  }
});
test('Çoklu graf/plan kimliği ve sahne ilişkileri doğrulanır; süre hedefi ölçüm değildir', async () => {
  const graph = { schemaVersion: '1.1', scenarioId: 'multi', title: 'Taslak', language: 'tr', ageMonths: 31,
    behaviorId: 'D01', cardVersion: '0.2', behaviors: refs, startSceneId: 'start',
    scenes: ['start','end'].map(id => ({ id, description: id, behaviorIds: ['D01','D02'] })),
    transitions: [{ fromSceneId: 'start', toSceneId: 'end', description: 'Devam' }], endSceneIds: ['end'] };
  const input = validatePlanRequest({ request, graph, planId: 'generated-multi' });
  const plan = { schemaVersion: '1.0', scenarioId: 'multi', planId: input.planId, authoringNote: 'İncelenmedi',
    continuityNotes: 'Aynı ortam', visualSuggestions: 'Üretilmiş öneri', d01CallTiming: [{ clipId: 'start-clip', callEndS: 3 }],
    clips: graph.scenes.map(scene => ({ id: scene.id + '-clip', sceneId: scene.id, orderInScene: 1, targetDurationS: 8,
      plannedAction: 'Eylem', initialState: 'Önce', finalState: 'Sonra', productionPrompt: 'Görsel prompt', voiceoverInstructions: 'Ayrı ses' })) };
  const card = await loadCard(request);
  assert.equal(validatePlan(JSON.stringify(plan), input, card).clips.length, 2); // 8-3+8 = 13 sn
  assert.deepEqual(JSON.parse(buildPlanPrompts(input, card).user).request.behaviors, refs);
  assert.throws(() => validatePlanRequest({ ...input, graph: { ...graph, behaviors: [refs[0]] } }), /uyuşmuyor/);
  assert.throws(() => validatePlanRequest({ ...input, graph: { ...graph,
    scenes: graph.scenes.map(s => ({ ...s, behaviorIds: ['D01'] })) } }), /kapsamıyor/);
});
