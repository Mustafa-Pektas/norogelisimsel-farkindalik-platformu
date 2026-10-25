const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { validateRequest, loadCard, buildNarrativePrompts, validateNarrative,
  createScenarioInputHandler, safeProviderDiagnostic, defaultCardsPath } = require('../scenario_input_generation');
const { generateText } = require('../gemini_text');
const request = { behaviorId: 'D01', cardVersion: '0.2', ageMonths: 30,
  sceneContext: ' Evde oyuncakla oyun ', additionalInstructions: null };
const content = { commonStart: '  Ortak başlangıç  ', alternatives: [
  { title: 'Yönelme', continuation: ' Annesine döner ', ending: ' İlk bitiş ' },
  { title: 'Oyun', continuation: ' Oynar ', ending: ' İkinci bitiş ' },
] };
const raw = ` \n${JSON.stringify(content)}\n `;
function deferred() {
  let resolve, reject;
  const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
}
class Response extends EventEmitter {
  constructor() { super(); this.statusCode = 200; this.bodies = []; }
  status(value) { this.statusCode = value; return this; }
  json(value) { this.bodies.push(value); return this; }
}
function call(handler, body = request) {
  const res = new Response();
  return { res, done: handler({ body }, res) };
}
test('İstek alanları zorunlu; yaş, eski kimlik, sürüm ve ek alan sessizce tamamlanmaz', () => {
  for (const patch of [{ ageMonths: undefined }, { ageMonths: 11 }, { ageMonths: 37 },
    { ageMonths: 24.5 }, { behaviorId: 'ONT-01' }, { cardVersion: '' },
    { sceneContext: ' ' }, { additionalInstructions: 3 }, { riskProfile: 'tipik' }]) {
    assert.throws(() => validateRequest({ ...request, ...patch }));
  }
  for (const ageMonths of [12, 36]) assert.equal(validateRequest({ ...request, ageMonths }).ageMonths, ageMonths);
  assert.equal(validateRequest(request).sceneContext, request.sceneContext);
});
test('Tek güncel Markdown kaynağı: tüm kartların işlem ve gözlem kuralları okunur', async () => {
  for (let i = 1; i <= 10; i++) {
    const req = { ...request, behaviorId: `D${String(i).padStart(2, '0')}` };
    const card = await loadCard(req);
    assert.match(card.section, /\| Senaryo \|/);
    assert.match(card.section, /\| Değerlendirilemedi \|/);
    assert.equal(card.sha256.length, 64);
    const prompts = buildNarrativePrompts(req, card);
    assert.ok(prompts.system.includes(card.section));
    assert.ok(prompts.system.includes(card.commonRules));
    assert.deepEqual(JSON.parse(prompts.user), req);
  }
  await assert.rejects(loadCard({ ...request, cardVersion: '0.1' }), /uyuşmuyor/);
  await assert.rejects(loadCard(request, '/missing/current/cards.md'), /okunamadı/);
});
test('Paket kart kaynağı farklı çalışma dizininde okunur; hatalı açık yol varsayılana dönmez', async () => {
  const originalDirectory = process.cwd();
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'scenario-card-path-'));
  try {
    process.chdir(directory);
    assert.equal(defaultCardsPath, path.resolve(__dirname, '../resources/Davranis_Kartlari_v02.md'));
    const card = await loadCard(request);
    assert.equal(card.version, request.cardVersion);
    assert.match(card.section, /D01/);
    await assert.rejects(loadCard(request, path.join(directory, 'missing.md')),
      error => error.status === 503 && /okunamadı/.test(error.message));
    // Mevcut paket kartı açık yolun hatasını gizleyerek başarı üretmemeli.
    let providerCalls = 0;
    const handler = createScenarioInputHandler({ cardsPath: path.join(directory, 'missing.md'),
      modelName: 'controlled-model', generate: async () => { providerCalls++; return raw; } });
    const { res, done } = call(handler);
    await done;
    assert.equal(res.statusCode, 503);
    assert.equal(res.bodies[0].success, false);
    assert.equal(providerCalls, 0);
  } finally {
    process.chdir(originalDirectory);
    await fs.rm(directory, { recursive: true, force: true });
  }
});
test('Dar normalizasyon anlatıları korur; bozuk/eksik/metadata uyuşmayan çıktı reddedilir', () => {
  for (const text of [raw, '```json\n' + JSON.stringify(content) + '\n```',
    JSON.stringify({ scenarioInput: content })]) {
    assert.deepEqual(validateNarrative(text, request), content);
  }
  for (const value of ['{bozuk', JSON.stringify({ commonStart: 'Eksik' }),
    JSON.stringify({ ...content, ageMonths: 24 }), JSON.stringify({ ...content, behaviorId: 'D02' }),
    JSON.stringify({ ...content, cardVersion: '0.1' }), JSON.stringify({ ...content, risk: 'red' }),
    JSON.stringify({ ...content, alternatives: [] }), JSON.stringify({ scenarioInput: content, extra: true })]) {
    assert.throws(() => validateNarrative(value, request));
  }
});

test('D01 istemi bağlamı aynen taşır; ad/yerleşim önerisini ve ek hareket sınırını açıklar', async () => {
  // Kontrollü örnek; kullanıcıdan alınmış gerçek çıktı değildir.
  const req = { ...request, ageMonths: 32,
    sceneContext: ' Ece salonda oyuncak arabayla oynar; babası çocuğun solunda oturur. ',
    additionalInstructions: ' Verilen isim ve yerleşimi koru. ' };
  const before = JSON.stringify(req);
  const card = await loadCard(req);
  const prompts = buildNarrativePrompts(req, card);
  assert.equal(prompts.user, before);
  assert.equal(JSON.stringify(req), before);
  for (const rule of ['D01 ANLATI AYRINTILARI', 'aynı adı ve yazımı kullan',
    "'taslak önerisi'", 'Başlangıç bakış hedefini', 'her izlenen yolda tek çağrı',
    'baş/bakış yönünün çağıran kişiye dönmesidir', 'göz teması veya tüm bedenin dönmesi gerekmez',
    'Sesli/sözel yanıt planlanıyorsa', 'ayrı olay olarak anlat', "'Hızla'",
    'baş yönelme koşulları değildir; bunları yeni başarı ölçütü olarak ekleme',
    'Yetişkin çocuğa dokunmaz']) {
    assert.ok(prompts.system.includes(rule), rule);
  }
  assert.ok(prompts.system.includes(card.section));
  assert.ok(prompts.system.includes(card.commonRules));
});

test('D01 çağrı ayrıntıları farklı davranışın istemine zorlanmaz', async () => {
  const req = { ...request, behaviorId: 'D02' };
  const prompts = buildNarrativePrompts(req, await loadCard(req));
  assert.ok(!prompts.system.includes('D01 ANLATI AYRINTILARI'));
  assert.deepEqual(JSON.parse(prompts.user), req);
});
test('Gemini metin çağrısı paylaşılır; ham metin değişmez, tekrar yoktur', async () => {
  let calls = 0;
  const sdk = { getGenerativeModel(options) {
    assert.equal(options.model, 'controlled-model');
    assert.equal(options.generationConfig.maxOutputTokens, 4096);
    return { async generateContent(input) {
      ++calls; assert.equal(input, 'İstek'); return { response: { text: () => raw } };
    } };
  } };
  assert.equal(await generateText(sdk, 'controlled-model', { system: 'Kurallar', user: 'İstek' },
    { schema: {}, maxOutputTokens: 4096 }), raw);
  assert.equal(calls, 1);
});
test('Endpoint başarı: tam ham cevap/istek döner; graf veya onay üretmez', async () => {
  let calls = 0;
  const run = call(createScenarioInputHandler({ modelName: 'controlled-model', generate: async () => { ++calls; return raw; } }));
  await run.done;
  assert.equal(run.res.statusCode, 200);
  assert.equal(calls, 1);
  assert.equal(run.res.bodies[0].rawResponse, raw);
  assert.deepEqual(run.res.bodies[0].request, request);
  assert.equal(run.res.bodies[0].validation, 'structure_only');
  assert.equal(run.res.bodies[0].graph, undefined);
  assert.equal(run.res.listenerCount('close'), 0);
});
for (const mode of ['malformed', 'metadata', 'provider', 'config', 'version']) {
  test(`Endpoint ${mode}: hata açık, örnek sonuç/tekrar yok`, async () => {
    let calls = 0;
    const reports = [];
    const invalid = mode === 'metadata' ? JSON.stringify({ ...content, ageMonths: 24 }) : '{bozuk';
    const run = call(createScenarioInputHandler({ modelName: mode === 'config' ? '' : 'controlled-model',
      reportProviderError: diagnostic => reports.push(diagnostic),
      generate: async () => { ++calls; if (mode === 'provider') throw Error('Gizli sağlayıcı ayrıntısı'); return invalid; },
    }), mode === 'version' ? { ...request, cardVersion: '0.1' } : request);
    await run.done;
    assert.equal(run.res.statusCode, mode === 'config' ? 503 : mode === 'version' ? 409 : 502);
    assert.equal(run.res.bodies[0].success, false);
    assert.equal(calls, ['config', 'version'].includes(mode) ? 0 : 1);
    assert.equal(run.res.bodies[0].scenario, undefined);
    if (['metadata', 'malformed'].includes(mode)) assert.equal(run.res.bodies[0].rawResponse, invalid);
    assert.ok(!run.res.bodies[0].error.includes('Gizli'));
    assert.equal(reports.length, mode === 'provider' ? 1 : 0);
  });
}
for (const reason of ['timeout', 'disconnect']) {
  test(`${reason}: bekleme sonlanır, geç cevap yazılmaz; sağlayıcı iptali iddia edilmez`, async () => {
    const started = deferred(), answer = deferred();
    const reports = [];
    let deadline;
    let cleared = false;
    const run = call(createScenarioInputHandler({ modelName: 'controlled-model',
      reportProviderError: diagnostic => reports.push(diagnostic),
      generate: async () => { started.resolve(); return answer.promise; },
      timers: { setTimeout(callback) { deadline = callback; return 1; }, clearTimeout() { cleared = true; } },
    }));
    await started.promise;
    if (reason === 'timeout') deadline(); else run.res.emit('close');
    await run.done;
    assert.equal(run.res.bodies.length, reason === 'timeout' ? 1 : 0);
    if (reason === 'timeout') assert.equal(run.res.statusCode, 504);
    answer.resolve(raw);
    await answer.promise;
    assert.equal(run.res.bodies.length, reason === 'timeout' ? 1 : 0);
    assert.ok(cleared);
    assert.equal(run.res.listenerCount('close'), 0);
    assert.equal(reports.length, 0);
  });
}

// SDK kaynaklarında doğrulanan alan biçimi; gerçek SDK/API çağrısı yoktur.
class GoogleGenerativeAIFetchError extends Error {
  constructor(status, reason) {
    super('SENTINEL_CONTENT https://invalid.test/path?key=SENTINEL_SECRET');
    this.status = status;
    this.statusText = 'SENTINEL_HEADER';
    this.errorDetails = [{ reason, metadata: { key: 'SENTINEL_SECRET', prompt: 'SENTINEL_CONTENT' } }];
    this.stack = 'SENTINEL_STACK';
  }
}
for (const [status, reason, category] of [
  [400, 'API_KEY_INVALID', 'credentials_or_permission'],
  [401, undefined, 'credentials_or_permission'],
  [403, 'SERVICE_DISABLED', 'credentials_or_permission'],
  [404, undefined, 'model_or_operation_not_found'],
  [429, 'RESOURCE_EXHAUSTED', 'quota_or_rate_limit'],
  [400, 'INVALID_ARGUMENT', 'invalid_provider_request'],
  [503, undefined, 'provider_unavailable'],
]) {
  test(`Güvenli sağlayıcı tanılaması ${status}/${reason}: neden korunur, sır/içerik taşınmaz`, async () => {
    const reports = [];
    let calls = 0;
    const run = call(createScenarioInputHandler({ modelName: 'controlled-model',
      generate: async () => { ++calls; throw new GoogleGenerativeAIFetchError(status, reason); },
      reportProviderError: diagnostic => reports.push(diagnostic),
    }));
    await run.done;
    assert.equal(run.res.statusCode, 502); // Backend hata sözleşmesi aynı.
    assert.equal(run.res.bodies[0].success, false);
    assert.equal(calls, 1);
    assert.equal(reports.length, 1);
    const diagnostic = reports[0];
    assert.equal(diagnostic.httpStatus, status);
    assert.equal(diagnostic.type, 'GoogleGenerativeAIFetchError');
    assert.equal(diagnostic.category, category);
    assert.deepEqual(run.res.bodies[0].providerError, diagnostic);
    assert.match(run.res.bodies[0].error, new RegExp(`HTTP ${status}`));
    assert.ok(!JSON.stringify([reports, run.res.bodies]).includes('SENTINEL'));
    assert.ok(!JSON.stringify([reports, run.res.bodies]).includes('invalid.test'));
    assert.equal(run.res.listenerCount('close'), 0);
  });
}
test('Serbest hata türü/kodu/mesajı ve iç içe metadata loga kopyalanmaz; bilinmeyen bilinmeyen kalır', () => {
  const error = new Error('SENTINEL_CONTENT');
  error.name = 'SENTINEL_NAME';
  error.code = 'SENTINEL_CODE';
  error.status = 'SENTINEL_STATUS';
  error.errorDetails = [{ reason: 'SENTINEL_REASON', metadata: { secret: 'SENTINEL_SECRET' } }];
  const diagnostic = safeProviderDiagnostic(error);
  assert.equal(diagnostic.httpStatus, null);
  assert.equal(diagnostic.type, 'UnknownError');
  assert.equal(diagnostic.code, 'UNKNOWN');
  assert.equal(diagnostic.category, 'unknown_provider_error');
  assert.ok(!JSON.stringify(diagnostic).includes('SENTINEL'));
});
test('Yalnız bilinen ağ kodu korunur; iç hata sağlayıcı reddi diye sunulmaz', () => {
  const error = new TypeError('SENTINEL_URL');
  error.cause = { code: 'ENOTFOUND', headers: 'SENTINEL_HEADER' };
  assert.equal(safeProviderDiagnostic(error).code, 'ENOTFOUND');
  assert.equal(safeProviderDiagnostic(error).category, 'transport_error');
  assert.equal(safeProviderDiagnostic(error, 'prepare').category, 'internal_error');
  assert.ok(!JSON.stringify(safeProviderDiagnostic(error)).includes('SENTINEL'));
});
test('Tanılama callback hatası yanıtı veya temizliği kesmez', async () => {
  const run = call(createScenarioInputHandler({ modelName: 'controlled-model',
    generate: async () => { throw new GoogleGenerativeAIFetchError(403); },
    reportProviderError: () => { throw Error('SENTINEL_LOGGER'); },
  }));
  await run.done;
  assert.equal(run.res.statusCode, 502);
  assert.equal(run.res.bodies[0].providerError.httpStatus, 403);
  assert.equal(run.res.listenerCount('close'), 0);
});

test('QuotaFailure yalnız kota kategorisine çevrilir; ayrıntıları dışarı verilmez', () => {
  const error = new GoogleGenerativeAIFetchError(429);
  error.errorDetails = [{ '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
    violations: [{ subject: 'SENTINEL_PROJECT', description: 'SENTINEL_CONTENT' }] }];
  const diagnostic = safeProviderDiagnostic(error);
  assert.equal(diagnostic.code, 'QUOTA_EXCEEDED');
  assert.equal(diagnostic.category, 'quota_or_rate_limit');
  assert.ok(!JSON.stringify(diagnostic).includes('SENTINEL'));
});
class GoogleGenerativeAIResponseError extends Error {}
test('Engellenen/geçersiz SDK yanıtı kendi kategorisindedir; yanıt metni loglanmaz', () => {
  const error = new GoogleGenerativeAIResponseError('SENTINEL_CONTENT');
  error.response = { candidates: [{ text: 'SENTINEL_CONTENT' }] };
  const diagnostic = safeProviderDiagnostic(error);
  assert.equal(diagnostic.category, 'provider_response_error');
  assert.equal(diagnostic.httpStatus, null);
  assert.ok(!JSON.stringify(diagnostic).includes('SENTINEL'));
});
