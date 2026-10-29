const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { validatePlanRequest, validatePlan, buildPlanPrompts, validateD01Observation, requiredD01ObservationSeconds } = require('../scenario_clip_generation');
const { createScenarioInputHandler, loadCard } = require('../scenario_input_generation');
const request = { behaviorId: 'D01', cardVersion: '0.2', ageMonths: 31,
  sceneContext: 'Deniz evde küplerle oynuyor.', additionalInstructions: null };
const graph = { schemaVersion: '1.0', scenarioId: 'server-story', title: 'Taslak', language: 'tr',
  behaviorId: 'D01', cardVersion: '0.2', ageMonths: 31, startSceneId: 'start',
  scenes: ['start', 'a', 'b'].map(id => ({ id, description: `Sahne ${id}` })),
  transitions: ['a', 'b'].map(id => ({ fromSceneId: 'start', toSceneId: id, description: id })),
  endSceneIds: ['a', 'b'] };
const input = { request, graph, planId: 'generated-controlled-1' };
let sourceCard;
test.before(async () => { sourceCard = await loadCard(request); });
function plan() { return { schemaVersion: '1.0', planId: input.planId, scenarioId: graph.scenarioId,
  authoringNote: 'İncelenmemiş üretim taslağı.', continuityNotes: 'Aynı Deniz ve ev.',
  visualSuggestions: 'Üretilmiş görsel öneri: krem kıyafet.',
  d01CallTiming: [{ clipId: 'start-1', callEndS: 3 }],
  clips: graph.scenes.flatMap(s => [1, 2].map(orderInScene => ({ id: `${s.id}-${orderInScene}`,
    sceneId: s.id, orderInScene, targetDurationS: 6, plannedAction: s.description,
    initialState: ' Önce ', finalState: ' Sonra ', productionPrompt: ' Tam görsel metin ',
    voiceoverInstructions: ' Ayrı seslendirme; henüz ses üretilmedi. ' }))) }; }
class Response extends EventEmitter {
  constructor() { super(); this.statusCode = 200; this.bodies = []; }
  status(code) { this.statusCode = code; return this; }
  json(body) { this.bodies.push(body); }
}
function shortObservationPlan(endingDuration = 3) {
  const value = plan();
  value.authoringNote = 'Gözlem penceresi tamamlandı.'; // Bu serbest iddia doğrulama yerine geçmez.
  value.clips = value.clips.filter(c => c.sceneId !== 'start' || c.orderInScene === 1);
  for (const c of value.clips) {
    c.targetDurationS = c.sceneId === 'start' ? 4 : c.orderInScene === 1 ? 5 : endingDuration;
  }
  return value;
}
test('Gerçek örneğin kontrollü karşılığı: 4−3+5+3=9 sn reddedilir; ham yanıt onarılmaz', async () => {
  const value = shortObservationPlan();
  assert.throws(() => validatePlan(JSON.stringify(value), input, sourceCard), /9 sn, gerekli 10 sn/);
  const raw = ` \n${JSON.stringify(value)}\n `;
  const res = new Response();
  await createScenarioInputHandler({ clipPlan: true, modelName: 'controlled', generate: async () => raw })({ body: input }, res);
  assert.equal(res.statusCode, 502);
  assert.equal(res.bodies[0].success, false);
  assert.equal(res.bodies[0].rawResponse, raw);
  assert.equal(res.bodies[0].plan, undefined);
  assert.deepEqual(value, shortObservationPlan());
});
test('Sınırda 10 sn her dal için ayrı kabul edilir; yalnız bir dal 9 sn ise plan reddedilir', () => {
  const value = shortObservationPlan(4);
  validatePlan(JSON.stringify(value), input, sourceCard);
  assert.deepEqual(validateD01Observation(value, input, sourceCard).map(p => p.postCallDurationS), [10, 10]);
  value.clips.find(c => c.id === 'b-2').targetDurationS = 3;
  assert.throws(() => validatePlan(JSON.stringify(value), input, sourceCard), /start → b; 9 sn/);
});
test('Çağrı zamanlaması eksik, tekrarlı, metinsel veya klip dışında olamaz', () => {
  for (const timing of [undefined, null, [], [{ clipId: 'missing', callEndS: 3 }],
    ...[0, -1, 4.01, '3', null].map(callEndS => [{ clipId: 'start-1', callEndS }]),
    [{ clipId: 'start-1', callEndS: 3 }, { clipId: 'start-1', callEndS: 3 }],
    [{ clipId: 'a-1', callEndS: 1 }], // Diğer yolda çağrı yok.
    [{ clipId: 'start-1', callEndS: 3 }, { clipId: 'a-1', callEndS: 1 }]]) {
    const value = shortObservationPlan(4); value.d01CallTiming = timing;
    assert.throws(() => validatePlan(JSON.stringify(value), input, sourceCard));
  }
});
test('Gerekli süre güvenilir kart kaynağından gelir; kaynak eksikse varsayılan 10 atanmaz', () => {
  const revised = { ...sourceCard, commonRules: sourceCard.commonRules.replaceAll('10 saniye', '13 saniye') };
  assert.equal(requiredD01ObservationSeconds(revised), 13);
  assert.throws(() => validatePlan(JSON.stringify(shortObservationPlan(4)), input, revised), /gerekli 13 sn/);
  assert.throws(() => requiredD01ObservationSeconds({ commonRules: '' }), /okunamadı/);
});
test('Ayrı dallarda birer çağrı olabilir; ortak çağrı eklenirse aynı yoldaki ikinci çağrı reddedilir', () => {
  const value = plan();
  value.d01CallTiming = [{ clipId: 'a-1', callEndS: 2 }, { clipId: 'b-1', callEndS: 2 }];
  assert.deepEqual(validateD01Observation(value, input, sourceCard).map(p => p.postCallDurationS), [10, 10]);
  value.d01CallTiming.push({ clipId: 'start-1', callEndS: 3 });
  assert.throws(() => validatePlan(JSON.stringify(value), input, sourceCard), /birden fazla çağrı/);
});
test('Ortak çağrı klibi d01CallTiming içinde bir kez listelenir; şema ve istem aynı tekil kayıt kuralını açıklar', async () => {
  const value = shortObservationPlan(4);
  value.d01CallTiming = [{ clipId: 'start-1', callEndS: 3 }];
  assert.deepEqual(validateD01Observation(value, input, sourceCard).map(path => path.postCallDurationS), [10, 10]);
  const schema = require('../scenario_clip_generation').planSchemaFor(input);
  assert.equal(schema.required.filter(field => field === 'd01CallTiming').length, 1);
  assert.equal(Object.keys(schema.properties).filter(field => field === 'd01CallTiming').length, 1);
  assert.match(schema.properties.d01CallTiming.description, /tek kayıt/);
  const prompt = buildPlanPrompts(input, sourceCard).system;
  assert.match(prompt, /HER BENZERSİZ KLİP için yalnız bir kayıt/);
  assert.match(prompt, /clipId kaydını dallar için TEKRARLAMA/);
});
test('D01 zamanı başka davranışa genellenmez; kamera koşulu istemde insan incelemesi olarak kalır', async () => {
  const value = plan(); delete value.d01CallTiming;
  const other = { ...input, request: { ...request, behaviorId: 'D02' }, graph: { ...graph, behaviorId: 'D02' } };
  validatePlan(JSON.stringify(value), other);
  const prompt = buildPlanPrompts(input, sourceCard).system;
  assert.ok(prompt.includes('başlangıç görüş alanı dışında, fakat kamera kadrajında görünür'));
  assert.ok(prompt.includes('Bu kamera/yerleşim koşulu insan incelemesindedir'));
});
test('Graf/istek referansları, erişim ve bitiş kuralları doğrulanır; dallar korunur', () => {
  assert.deepEqual(validatePlanRequest(input), input);
  for (const mutate of [x => x.graph.ageMonths = 24, x => x.graph.startSceneId = 'missing',
    x => x.graph.scenes.push(x.graph.scenes[0]), x => x.graph.transitions.pop(),
    x => x.graph.endSceneIds = ['start'], x => x.planId = 'd01-elle-hazirlanmis-klip-plani-001',
    x => delete x.request.sceneContext]) {
    const value = structuredClone(input); mutate(value); assert.throws(() => validatePlanRequest(value));
  }
});
test('Sürümlü yaş grubu graf ve klip planında tam eşleşir; eski ay şeması değişmeden kalır', async () => {
  for (const id of ['12_18', '18_24', '24_36']) {
    const ageGroup = { contractVersion: '1.0', id };
    const ageRequest = { requestVersion: '3.0', behaviors: [{ behaviorId: 'D01', cardVersion: '0.2' }],
      ageGroup, sceneContext: request.sceneContext, additionalInstructions: request.additionalInstructions };
    const ageGraph = structuredClone(graph);
    ageGraph.schemaVersion = '1.2'; delete ageGraph.ageMonths; ageGraph.ageGroup = ageGroup;
    ageGraph.behaviors = ageRequest.behaviors;
    for (const scene of ageGraph.scenes) scene.behaviorIds = ['D01'];
    const ageInput = validatePlanRequest({ request: ageRequest, graph: ageGraph, planId: input.planId });
    const result = plan(); result.schemaVersion = '1.1'; result.ageGroup = ageGroup;
    assert.deepEqual(validatePlan(JSON.stringify(result), ageInput, sourceCard), result);
    const prompt = buildPlanPrompts(ageInput, sourceCard);
    assert.match(prompt.system, new RegExp(`Age-group contract metadata must match the graph exactly:.*${id}`));
    assert.ok(prompt.system.includes('Do not invent a representative month'));
    const wrong = structuredClone(result); wrong.ageGroup = { contractVersion: '1.0', id: '12_18' === id ? '18_24' : '12_18' };
    assert.throws(() => validatePlan(JSON.stringify(wrong), ageInput, sourceCard));
  }
});
test('Klipler tüm sahneleri kesintisiz sırayla kapsar; süre, kimlik ve ses alanı zorunlu', () => {
  assert.deepEqual(validatePlan(JSON.stringify(plan()), input, sourceCard), plan());
  for (const mutate of [p => p.clips = p.clips.filter(c => c.sceneId !== 'b'),
    p => p.clips[0].targetDurationS = 8.1, p => p.clips[0].targetDurationS = 0,
    p => p.clips[0].orderInScene = 3, p => p.clips[0].sceneId = 'missing',
    p => p.clips[0].id = p.clips[1].id, p => p.scenarioId = 'd01',
    p => delete p.clips[0].voiceoverInstructions, p => delete p.visualSuggestions]) {
    const value = plan(); mutate(value); assert.throws(() => validatePlan(JSON.stringify(value), input, sourceCard));
  }
});
test('Aynı güncel kart kaynağı; yaş/bağlam ve tam dallı graf modele gider', async () => {
  const card = await loadCard(request);
  const prompts = buildPlanPrompts(input, card);
  assert.deepEqual(JSON.parse(prompts.user), input);
  assert.ok(prompts.system.includes(card.section));
  assert.ok(prompts.system.includes(card.commonRules));
  assert.match(prompts.system, /voiceoverInstructions/);
  assert.match(prompts.system, /Üretilmiş görsel öneri/);
});
test('Alternatif sayısı sabit değildir; ortak başlangıç tek sahne olarak kalır', () => {
  const value = structuredClone(input);
  value.graph.scenes.push({ id: 'third', description: 'Üçüncü bitiş' });
  value.graph.endSceneIds.push('third');
  value.graph.transitions.push({ fromSceneId: 'start', toSceneId: 'third', description: 'Üçüncü alternatif' });
  const before = JSON.stringify(value.graph);
  validatePlanRequest(value);
  const result = plan();
  result.clips.push({ ...result.clips[0], id: 'third-1', sceneId: 'third' });
  validatePlan(JSON.stringify(result), value, sourceCard);
  assert.equal(JSON.stringify(value.graph), before);
  assert.equal(value.graph.scenes.filter(s => s.id === 'start').length, 1);
});

test('D01 plan istemi tek çağrıyı, alan uyumunu ve bağımsız klip sürekliliğini ister; grafı değiştirmez', async () => {
  const value = structuredClone(input);
  value.graph.scenes[0].description = 'Deniz evde oynar. Annesi bir kez adını söyler.';
  const before = JSON.stringify(value);
  const prompts = buildPlanPrompts(value, await loadCard(request));
  assert.equal(prompts.user, before);
  assert.equal(JSON.stringify(value), before);
  for (const rule of ['D01 ÇAĞRI VE GÖZLEM PLANI', 'tek çağrıyı çoğaltma',
    'Yalnız çağrı klibinin plannedAction', 'initialState ve finalState',
    'voiceoverInstructions', 'çağrı bitiminden itibaren planla',
    'çağrı öncesi süreyi pencereye dahil etme', 'her alternatif yol için ayrı hesapla',
    'birbirini dışlayan dalların sürelerini toplayarak', 'devam kliplerinde çağrı tekrarlanmaz',
    'Her klip dış araçta bağımsız üretilir', 'kamera/kadraj',
    'Kaynakta verilen yetişkin konumu/duruşu', 'plannedAction,', 'initialState, finalState, productionPrompt ve continuityNotes',
    'ilgili klip alanlarında aynı öneriyi tutarlı taşı', 'baş/bakış yönünün çağıran kişiye dönmesidir',
    'göz teması veya tüm bedenin dönmesi gerekmez', 'Sesli/sözel yanıt varsa bunu yönelmeden ayrı olay olarak belirt',
    'yalnız yapısaldır', 'kesintisiz D01 denemesi ve zaman kanıtı henüz doğrulanmadı']) {
    assert.ok(prompts.system.includes(rule), rule);
  }
});

test('Klip istemi açık kamera tercihini korur; D02 nesne/konum/hedef eksiklerini öneri diye ayırır', async () => {
  const cameraRequest = { ...request, additionalInstructions: 'Sabit kamera, geniş açı.' };
  const cameraPrompts = buildPlanPrompts({ ...input, request: cameraRequest }, sourceCard);
  assert.ok(cameraPrompts.system.includes('İstek, ek yönerge veya graf sabit kamera açısı/kadrajı açıkça belirtiyorsa'));
  assert.ok(cameraPrompts.system.includes('gerekçesiz yakın plan, zoom veya yeniden kadraj ekleme'));
  assert.ok(cameraPrompts.system.includes('Sabit açı/kadraj belirtilmemişse bunu kullanıcı tercihi gibi varsayma'));

  const d02Request = { ...request, behaviorId: 'D02', additionalInstructions: 'Sabit kamera.' };
  const d02Input = { ...input, request: d02Request, graph: { ...graph, behaviorId: 'D02' } };
  const d02Card = await loadCard(d02Request);
  const d02Prompts = buildPlanPrompts(d02Input, d02Card);
  assert.ok(d02Prompts.system.includes('D02 NESNE VE HEDEF SÜREKLİLİĞİ'));
  assert.ok(d02Prompts.system.includes('iki sabit nesneyi birbirinden ayırt edilebilir kimlik ve görünür konumlarıyla belirt'));
  assert.ok(d02Prompts.system.includes('hangi nesnenin işaret edilen hedef olduğunu açıkça yaz'));
  assert.ok(d02Prompts.system.includes('Üretilmiş görsel öneri'));
  assert.ok(d02Prompts.system.includes('anlamsal olarak doğrulamaz ve içerik onayı değildir'));
  assert.deepEqual(JSON.parse(d02Prompts.user), d02Input);

  const d01Prompts = buildPlanPrompts(input, sourceCard);
  assert.ok(!d01Prompts.system.includes('D02 NESNE VE HEDEF SÜREKLİLİĞİ'));
});

test('Pilot pencere güncel kart metninden gelir; istemde bağımsız sabit süre veya klinik eşik yoktur', async () => {
  const card = await loadCard(request);
  assert.ok(card.commonRules.includes('10 saniyelik kesintisiz gözlem'));
  const original = buildPlanPrompts(input, card);
  assert.ok(original.system.includes(card.commonRules));
  // Yalnız testteki kaynak girdisi değiştirilir; gerçek kart dosyası değiştirilmez.
  const revised = { ...card, commonRules: card.commonRules.replaceAll('10 saniye', '13 saniye') };
  const modified = buildPlanPrompts(input, revised);
  assert.ok(modified.system.includes(revised.commonRules));
  assert.ok(modified.system.includes('13 saniyelik kesintisiz gözlem'));
  assert.ok(!modified.system.includes('10 saniye'));
  assert.ok(modified.system.includes('klinik tepki eşiği veya yanıt için son tarih değildir'));
});

test('D01 plan ayrıntıları başka kartın görev kurallarının yerine geçmez', async () => {
  const req = { ...request, behaviorId: 'D02' };
  const value = { ...input, request: req, graph: { ...graph, behaviorId: req.behaviorId } };
  const prompts = buildPlanPrompts(value, await loadCard(req));
  assert.ok(!prompts.system.includes('D01 ÇAĞRI VE GÖZLEM PLANI'));
  assert.deepEqual(JSON.parse(prompts.user), value);
});
test('Uyuşmayan graf isteği Gemini çağrılmadan reddedilir', async () => {
  let calls = 0;
  const value = structuredClone(input); value.graph.cardVersion = '0.1';
  const res = new Response();
  await createScenarioInputHandler({ clipPlan: true, modelName: 'controlled',
    generate: async () => { ++calls; return JSON.stringify(plan()); } })({ body: value }, res);
  assert.equal(res.statusCode, 400); assert.equal(calls, 0);
});
test('Endpoint: tek gerçek sağlayıcı çağrısının ham metni korunur; eksik plan başarı olmaz', async () => {
  for (const invalid of [false, true]) {
    const value = plan();
    if (invalid) value.clips = value.clips.filter(c => c.sceneId !== 'b');
    const raw = ` \n${JSON.stringify(value)}\n `;
    let calls = 0;
    const handler = createScenarioInputHandler({ clipPlan: true, modelName: 'controlled',
      generate: async (_, prompts) => { ++calls; assert.deepEqual(JSON.parse(prompts.user), input); return raw; } });
    const res = new Response(); await handler({ body: input }, res);
    assert.equal(calls, 1); assert.equal(res.statusCode, invalid ? 502 : 200);
    assert.equal(res.bodies[0].rawResponse, raw);
    assert.equal(res.bodies[0].success, !invalid);
    if (!invalid) {
      assert.deepEqual(res.bodies[0].input, input);
      assert.equal(res.bodies[0].validation, 'structure_only'); // Anlamsal onay değildir.
    }
  }
});
test('Timeout, bağlantı kapanışı ve sağlayıcı hatası örnek plan üretmez', async () => {
  for (const mode of ['timeout', 'disconnect', 'provider']) {
    let signalStarted, finish, timeout;
    const started = new Promise(r => { signalStarted = r; });
    const gate = new Promise(r => { finish = r; });
    const res = new Response();
    const handler = createScenarioInputHandler({ clipPlan: true, modelName: 'controlled',
      reportProviderError: () => {},
      timers: { setTimeout: fn => { timeout = fn; return 1; }, clearTimeout: () => {} },
      generate: async () => { signalStarted(); if (mode === 'provider') throw new Error('secret-not-logged'); return gate; } });
    const done = handler({ body: input }, res);
    await started;
    if (mode === 'timeout') timeout();
    if (mode === 'disconnect') res.emit('close');
    await done;
    finish(JSON.stringify(plan()));
    if (mode === 'disconnect') assert.equal(res.bodies.length, 0);
    else { assert.equal(res.bodies[0].success, false); assert.equal(res.statusCode, mode === 'timeout' ? 504 : 502); }
    assert.equal(res.listenerCount('close'), 0);
  }
});
