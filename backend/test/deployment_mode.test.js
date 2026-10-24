const test = require('node:test');
const assert = require('node:assert/strict');
const { IncomingMessage, ServerResponse } = require('node:http');
const { Duplex } = require('node:stream');
const { randomBytes } = require('node:crypto');
const { createApp } = require('../server');
const { createGenerationCapacity } = require('../generation_capacity');
const testAccessKey = randomBytes(32).toString('hex'); // Yalnız testte üretilir; gerçek anahtar değildir.

// Express'in gerçek middleware/route zinciri; socket bağlantısı veya listen yok.
function request(app, method, url, body = '', contentType = 'application/json', observe = () => {},
  headers = { authorization: `Bearer ${testAccessKey}` }) {
  return new Promise((resolve, reject) => {
    const bytes = Buffer.from(body, 'utf8');
    const socket = new Duplex({ read() {}, write(chunk, encoding, callback) { callback(); } });
    const req = new IncomingMessage(socket);
    req.method = method; req.url = url; req.httpVersion = '1.1';
    req.headers = { 'content-type': contentType, 'content-length': String(bytes.length), ...headers };
    const res = new ServerResponse(req);
    req.on('error', reject); res.on('error', reject);
    res.end = function (chunk) {
      const text = chunk == null ? '' : chunk.toString();
      resolve({ status: res.statusCode, body: text ? JSON.parse(text) : null });
      socket.destroy();
      return res;
    };
    observe(res);
    req.push(bytes); req.push(null);
    app.handle(req, res, reject);
  });
}

const input = { behaviorId: 'D01', cardVersion: '0.2', ageMonths: 30, sceneContext: 'Evde oyun.' };
const graph = { schemaVersion: '1.0', scenarioId: 'story', title: 'Taslak', language: 'tr',
  behaviorId: 'D01', cardVersion: '0.2', ageMonths: 30, startSceneId: 'start',
  scenes: [{ id: 'start', description: 'Başlangıç' }, { id: 'end', description: 'Bitiş' }],
  transitions: [{ fromSceneId: 'start', toSceneId: 'end', description: 'Devam' }], endSceneIds: ['end'] };
const planInput = { request: input, graph, planId: 'generated-deployment-test' };
function controlled({ env = {}, beforeGenerate, timers } = {}) {
  let calls = 0;
  const app = createApp({ env: { BACKEND_MODE: 'deployment', SCENARIO_INPUT_MODEL: 'controlled-model',
    TEAM_ACCESS_KEY: testAccessKey, ...env },
    generationTimers: timers,
    genAI: { getGenerativeModel() { throw new Error('Eski sağlayıcı yolu çağrılmamalı.'); } },
    generate: async (_, model, prompts) => {
      calls++;
      if (beforeGenerate) await beforeGenerate(prompts, calls);
      assert.equal(model, 'controlled-model');
      const sent = JSON.parse(prompts.user);
      if (prompts.system.includes('Bu yalnız doğrusal 26 sahnelik deneydir')) return JSON.stringify({
        title: 'Deney', summary: 'İncelenmemiş taslak.', scenes: Array.from({ length: 26 }, (_, i) => ({
          phase: i < 6 ? 'TABAN' : i < 17 ? 'UYARAN' : 'KAPANIS',
          videoPrompt: 'Same room and child.', startState: `state-${i}`, endState: `state-${i + 1}`,
        })),
      });
      if (!sent.graph) return JSON.stringify({ commonStart: 'Oyun.', alternatives: [
        { title: 'Devam', continuation: 'Yönelir.', ending: 'Biter.' }] });
      return JSON.stringify({ schemaVersion: '1.0', scenarioId: graph.scenarioId,
        planId: sent.planId, authoringNote: 'İncelenmedi.', continuityNotes: 'Aynı ortam.',
        visualSuggestions: 'Üretilmiş öneri.', d01CallTiming: [{ clipId: 'clip-start', callEndS: 3 }],
        clips: graph.scenes.map(scene => ({ id: `clip-${scene.id}`, sceneId: scene.id,
          orderInScene: 1, targetDurationS: 8, plannedAction: 'Oyun.', initialState: 'Önce.',
          finalState: 'Sonra.', productionPrompt: 'Sabit kamera.', voiceoverInstructions: 'Ses yönergesi.' })) });
    } });
  return { app, calls: () => calls };
}

test('Deployment: yalnız sağlık ve iki güncel üretim yolu; eski/diğer yollar ayrıştırıcıya ulaşmaz', async () => {
  const fake = controlled();
  for (const [method, url] of [['POST', '/api/analyze-video'], ['POST', '/api/generate-scenario'],
    ['POST', '/other'], ['GET', '/api/generate-clip-plan'], ['POST', '/health']]) {
    const response = await request(fake.app, method, url, '{bozuk');
    assert.equal(response.status, 404);
    assert.equal(response.body.success, false);
  }
  assert.equal(fake.calls(), 0);
  const health = await request(fake.app, 'GET', '/health');
  assert.equal(health.status, 200);
  assert.deepEqual(Object.keys(health.body).sort(), ['service', 'status', 'timestamp']);
  assert.equal(health.body.status, 'online');
  assert.equal((await request(fake.app, 'POST', '/api/generate-scenario-input', JSON.stringify(input))).status, 200);
  assert.equal((await request(fake.app, 'POST', '/api/generate-clip-plan', JSON.stringify(planInput))).status, 200);
  assert.equal(fake.calls(), 2);
  assert.equal((await request(fake.app, 'OPTIONS', '/api/generate-clip-plan')).status, 204);
});

test('Deployment: 1 MiB UTF-8 gövde kabul edilir; bir bayt fazlası ve Türkçe bayt aşımı 413 verir', async () => {
  const fake = controlled();
  const limit = 1024 * 1024;
  const empty = JSON.stringify({ ...input, sceneContext: '' });
  const exact = JSON.stringify({ ...input, sceneContext: 'x'.repeat(limit - Buffer.byteLength(empty)) });
  assert.equal(Buffer.byteLength(exact), limit);
  assert.equal((await request(fake.app, 'POST', '/api/generate-scenario-input', exact)).status, 200);
  for (const url of ['/api/generate-scenario-input', '/api/generate-clip-plan', '/api/compare-scenario']) {
    for (const body of [exact + ' ', JSON.stringify({ ...input, sceneContext: 'ş'.repeat(limit / 2) })]) {
      const response = await request(fake.app, 'POST', url, body);
      assert.equal(response.status, 413);
      assert.equal(response.body.success, false);
      assert.match(response.body.error, /boyut sınırını/);
    }
    const malformed = await request(fake.app, 'POST', url, '{bozuk');
    assert.equal(malformed.status, 400);
    assert.equal(malformed.body.success, false);
  }
  assert.equal(fake.calls(), 1);
});

test('Varsayılan geliştirme modu eski yolları korur; geçersiz mod sessizce açılmaz', async () => {
  const app = createApp({ env: {} });
  for (const url of ['/api/generate-scenario', '/api/analyze-video']) {
    const response = await request(app, 'POST', url, '{}', 'application/json', () => {}, {});
    assert.equal(response.status, 400); // Route var; anahtar/video olmadığından sağlayıcı çağrısı yok.
  }
  const larger = JSON.stringify({ ...input, sceneContext: 'x'.repeat(1024 * 1024) });
  const result = await request(app, 'POST', '/api/generate-scenario-input', larger);
  assert.equal(result.status, 503); // Geliştirme 50 MB sınırı korundu; model yapılandırılmamış.
  assert.throws(() => createApp({ env: { BACKEND_MODE: 'deploymnt' } }), /BACKEND_MODE/);
});

test('Deployment ekip anahtarı zorunludur; iki endpoint auth kontrolü gövdeden önce çalışır', async () => {
  for (const value of [undefined, '', ' ', 'a b']) {
    assert.throws(() => createApp({ env: { BACKEND_MODE: 'deployment', TEAM_ACCESS_KEY: value } }), /TEAM_ACCESS_KEY/);
  }
  const fake = controlled();
  for (const url of ['/api/generate-scenario-input', '/api/generate-clip-plan', '/api/compare-scenario']) {
    for (const authorization of [undefined, '', `Bearer ${randomBytes(32).toString('hex')}`, 'Basic invalid']) {
      const headers = authorization === undefined ? {} : { authorization };
      const response = await request(fake.app, 'POST', url, '{bozuk', 'application/json', () => {}, headers);
      assert.equal(response.status, 401);
      assert.equal(response.body.code, 'team_access_required');
      assert.ok(!JSON.stringify(response.body).includes(testAccessKey));
    }
  }
  const oversized = await request(fake.app, 'POST', '/api/generate-clip-plan', 'x'.repeat(1024 * 1024 + 1),
    'application/json', () => {}, {});
  assert.equal(oversized.status, 401);
  assert.equal(fake.calls(), 0);
  assert.equal((await request(fake.app, 'GET', '/health', '', 'application/json', () => {}, {})).status, 200);
  assert.equal((await request(fake.app, 'OPTIONS', '/api/generate-clip-plan', '', 'application/json', () => {}, {})).status, 204);
  assert.equal(fake.calls(), 0);
  assert.equal((await postScenario(fake.app)).status, 200);
  assert.equal((await postPlan(fake.app)).status, 200);
  assert.equal(fake.calls(), 2);
});

function deferred() {
  let resolve, reject;
  const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
}
const postScenario = app => request(app, 'POST', '/api/generate-scenario-input', JSON.stringify(input));
const postPlan = app => request(app, 'POST', '/api/generate-clip-plan', JSON.stringify(planInput));
function assertBusy(response) {
  assert.equal(response.status, 429);
  assert.equal(response.body.code, 'local_capacity_exceeded');
  assert.equal(response.body.success, false);
  assert.equal(response.body.providerError, undefined);
}

test('Ortak kapasite varsayılan 1: iki endpoint paylaşır; health/OPTIONS tüketmez; başarı serbest bırakır', async () => {
  const gate = deferred(), started = deferred();
  const fake = controlled({ beforeGenerate: async (_, n) => {
    if (n === 1) { started.resolve(); await gate.promise; }
  } });
  const first = postScenario(fake.app);
  try {
    await started.promise;
    const unauthorized = await request(fake.app, 'POST', '/api/generate-clip-plan', JSON.stringify(planInput),
      'application/json', () => {}, {});
    assert.equal(unauthorized.status, 401); // Dolu kapasiteye ulaşmadan auth reddi.
    const preview = await request(fake.app, 'POST', '/api/compare-scenario',
      JSON.stringify({ request: input, arm: 'A', action: 'preview' }));
    assert.equal(preview.status, 200); // Preview dolu kapasitede de sağlayıcı çağırmaz.
    const comparison = await request(fake.app, 'POST', '/api/compare-scenario',
      JSON.stringify({ request: input, arm: 'A', action: 'generate', protocolId: preview.body.preview.protocolId }));
    assertBusy(comparison);
    assertBusy(await postPlan(fake.app));
    assertBusy(await postScenario(fake.app));
    assert.equal(fake.calls(), 1);
    assert.equal((await request(fake.app, 'GET', '/health')).status, 200);
    assert.equal((await request(fake.app, 'OPTIONS', '/api/generate-clip-plan')).status, 204);
  } finally { gate.resolve(); }
  assert.equal((await first).status, 200);
  assert.equal((await postPlan(fake.app)).status, 200);
  assert.equal(fake.calls(), 2);
});

test('Kapasite 2: sağlayıcı hatası yalnız kendi slotunu bırakır; tek kapatma ikinci işi etkilemez', async () => {
  const gates = [deferred(), deferred(), deferred()];
  const starts = [deferred(), deferred(), deferred()];
  const fake = controlled({ env: { GENERATION_MAX_CONCURRENT: '2' }, beforeGenerate: async (_, n) => {
    if (n <= 3) { starts[n - 1].resolve(); await gates[n - 1].promise; }
  } });
  const first = postScenario(fake.app);
  let second, third;
  try {
    await starts[0].promise;
    second = postPlan(fake.app); await starts[1].promise;
    assertBusy(await postScenario(fake.app));
    gates[0].reject(new Error('Kontrollü sağlayıcı hatası'));
    assert.equal((await first).status, 502);
    third = postScenario(fake.app); await starts[2].promise;
    assertBusy(await postPlan(fake.app));
    assert.equal(fake.calls(), 3);
  } finally { for (const gate of gates) gate.resolve(); }
  assert.equal((await second).status, 200);
  assert.equal((await third).status, 200);
  assert.equal((await postPlan(fake.app)).status, 200);
});

for (const outcome of ['timeout', 'disconnect']) {
  for (const lateError of [false, true]) {
    test(`${outcome}: HTTP bittiğinde slot tutulur; geç sağlayıcı ${lateError ? 'hatası' : 'başarısı'} bırakır`, async () => {
      const callbacks = new Set();
      const timers = { setTimeout(callback) { callbacks.add(callback); return callback; },
        clearTimeout(callback) { callbacks.delete(callback); } };
      const gate = deferred(), started = deferred();
      let firstResponse, ends = 0;
      const fake = controlled({ timers, beforeGenerate: async (_, n) => {
        if (n === 1) { started.resolve(); await gate.promise; }
      } });
      const pending = request(fake.app, 'POST', '/api/generate-scenario-input', JSON.stringify(input),
        'application/json', res => {
          firstResponse = res;
          const original = res.end;
          res.end = function (...args) { ends++; return original.apply(this, args); };
        });
      // Disconnect yanıt üretmez; o Promise bilinçli olarak beklenmez.
      try {
        await started.promise;
        if (outcome === 'timeout') {
          callbacks.values().next().value();
          assert.equal((await pending).status, 504);
        } else {
          firstResponse.emit('close');
        }
        assertBusy(await postPlan(fake.app));
        assert.equal(fake.calls(), 1);
      } finally {
        if (lateError) gate.reject(new Error('Geç kontrollü hata'));
        else gate.resolve();
      }
      assert.equal((await postPlan(fake.app)).status, 200);
      assert.equal(fake.calls(), 2);
      assert.equal(ends, outcome === 'timeout' ? 1 : 0);
      assert.equal(firstResponse.listenerCount('close'), 0);
      assert.equal(callbacks.size, 0);
    });
  }
}

test('Kapasite ayarı pozitif güvenli tam sayıdır; release tekrarı kapasiteyi artırmaz; development sınırlanmaz', async () => {
  for (const value of ['', '0', '-1', '1.5', 'abc', ' 1', '1e2', '9007199254740992']) {
    assert.throws(() => createApp({ env: { BACKEND_MODE: 'deployment', GENERATION_MAX_CONCURRENT: value } }),
      /GENERATION_MAX_CONCURRENT/);
  }
  const pool = createGenerationCapacity();
  const release = pool.tryAcquire();
  assert.equal(pool.tryAcquire(), null);
  release(); release();
  const secondRelease = pool.tryAcquire();
  assert.equal(typeof secondRelease, 'function');
  assert.equal(pool.tryAcquire(), null);
  secondRelease();
  const gates = [deferred(), deferred()], started = [deferred(), deferred()];
  const fake = controlled({ env: { BACKEND_MODE: 'development', GENERATION_MAX_CONCURRENT: 'invalid' },
    beforeGenerate: async (_, n) => { started[n - 1].resolve(); await gates[n - 1].promise; } });
  const first = postScenario(fake.app); let second;
  try {
    await started[0].promise;
    second = postPlan(fake.app); await started[1].promise;
    assert.equal(fake.calls(), 2);
  } finally { for (const gate of gates) gate.resolve(); }
  assert.equal((await first).status, 200);
  assert.equal((await second).status, 200);
});
