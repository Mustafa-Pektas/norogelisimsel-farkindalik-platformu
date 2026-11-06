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
branched.stages = refs.map((ref, i) => ({stageIndex:i+1, behaviorId:ref.behaviorId,
  title:`Stage ${i+1}`, prompt:`Prompt ${ref.behaviorId}`,
  branches:['typical','atypical'].map(branchType => ({branchType,title:branchType,continuation:`Continue ${branchType}`}))}));
branched.alternatives = ['+D01+D02','+D01-D02','-D01+D02','-D01-D02'].map(outcomeKey => ({
  outcomeKey,title:outcomeKey,continuation:`Continue ${outcomeKey}`,ending:`End ${outcomeKey}`,behaviorIds:['D01','D02']}));
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
  const reversed = structuredClone(branched);
  reversed.alternatives.reverse();
  assert.deepEqual(validateNarrative(JSON.stringify(reversed), request), reversed);
  for (const mutate of [
    v => { delete v.stages; },
    v => { v.stages[1] = structuredClone(v.stages[0]); },
    v => { v.stages.reverse(); },
    v => { v.stages[0].stageIndex = 2; },
    v => { delete v.stages[0].stageIndex; },
    v => { v.stages[0].branches[1].branchType = 'typical'; },
    v => { v.stages[0].branches.pop(); },
    v => { v.stages[1].behaviorId = 'D10'; },
    v => { v.alternatives.pop(); },
    v => { v.alternatives[1].outcomeKey = v.alternatives[0].outcomeKey; },
    v => { delete v.alternatives[0].outcomeKey; },
    v => { v.alternatives[0].outcomeKey = '+D02+D01'; },
  ]) {
    const invalid = structuredClone(branched); mutate(invalid);
    assert.throws(() => validateNarrative(JSON.stringify(invalid), request));
  }
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

test('Çoklu davranış aşamalı çıktı (stages) başarıyla doğrulanır; eksik dal veya geçersiz tip reddedilir', () => {
  const multiStage = {
    structure: 'branched',
    commonStart: 'Kum havuzunda oyun.',
    commonBehaviorIds: ['D01', 'D02'],
    stages: [
      {
        stageIndex: 1,
        behaviorId: 'D01',
        title: 'Aşama 1: İsme Tepki Gözlemi',
        prompt: 'Yetişkin doğal sesle "Ali" der.',
        branches: [
          { branchType: 'typical', title: 'İsme Tepki Gözlendi', continuation: 'Ali başını çevirir.' },
          { branchType: 'atypical', title: 'İsme Tepki Gözlenmedi', continuation: 'Ali kumla oynamaya devam eder.' },
        ],
      },
      {
        stageIndex: 2,
        behaviorId: 'D02',
        title: 'Aşama 2: İşarete Yönelme Gözlemi',
        prompt: 'Yetişkin kovayı işaret eder.',
        branches: [
          { branchType: 'typical', title: 'İşarete Yönelme Gözlendi', continuation: 'Ali kovaya bakar.', ending: 'İşarete yönelme tamamlandı.' },
          { branchType: 'atypical', title: 'İşme Yönelme Gözlenmedi', continuation: 'Ali kovaya bakmaz.', ending: 'İşarete yönelme gerçekleşmedi.' },
        ],
      },
    ],
    alternatives: [
      { outcomeKey: '+D01+D02', title: 'D01+ / D02+', continuation: 'İkisi de olumlu.', ending: 'Her iki davranış da gözlendi.', behaviorIds: ['D01', 'D02'] },
      { outcomeKey: '+D01-D02', title: 'D01+ / D02-', continuation: 'D01 olumlu, D02 olumsuz.', ending: 'İsme tepki var, işarete yönelme yok.', behaviorIds: ['D01', 'D02'] },
      { outcomeKey: '-D01+D02', title: 'D01- / D02+', continuation: 'D01 olumsuz, D02 olumlu.', ending: 'İsme tepki yok, işarete yönelme var.', behaviorIds: ['D01', 'D02'] },
      { outcomeKey: '-D01-D02', title: 'D01- / D02-', continuation: 'İkisi de olumsuz.', ending: 'Ne isme tepki ne de işarete yönelme gözlendi.', behaviorIds: ['D01', 'D02'] },
    ],
  };

  const validated = validateNarrative(JSON.stringify(multiStage), request);
  assert.deepEqual(validated, multiStage);

  // Schema validates stages presence
  const schema = narrativeSchemaFor(request);
  assert.ok(schema.required.includes('stages'));
  assert.ok(schema.properties.stages);

  // Invalid branchType rejected
  const invalidType = structuredClone(multiStage);
  invalidType.stages[0].branches[0].branchType = 'invalid_type';
  assert.throws(() => validateNarrative(JSON.stringify(invalidType), request));

  // Incomplete stages list rejected
  const missingStage = structuredClone(multiStage);
  missingStage.stages = [missingStage.stages[0]];
  assert.throws(() => validateNarrative(JSON.stringify(missingStage), request));
});
