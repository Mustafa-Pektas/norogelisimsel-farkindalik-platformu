'use strict';
/*
 * RAG / senaryo üretimi stres testi.
 *
 * Ölçtüğü: güncel üretim yollarının (/api/generate-scenario-input ve /api/compare-scenario A/B/C/D)
 * eşzamanlı yük altında yanıt süreleri (istemci, uç nokta, arama/retrieval, sağlayıcı) ve hata oranları
 * (yerel kapasite reddi, sağlayıcı hatası, zaman aşımı, doğrulama hatası, bağlantı hatası).
 *
 * Kipler:
 *   --mode local  (varsayılan, ÜCRETSİZ): Gerçek createApp (deployment kipi, gerçek Express zinciri, gerçek
 *                 kart/JSON RAG okuma ve doğrulama) 127.0.0.1'de açılır; yalnız Gemini çağrısı kontrollü bir
 *                 sahte sağlayıcıyla (ayarlanabilir gecikme + hata enjeksiyonu) değiştirilir. Ağ/para yok.
 *   --mode remote (ÜCRETLİ): Gerçek sunucuya gerçek istek. Anahtar yalnız stdin'den tek JSON satırı
 *                 olarak okunur ({"accessKey":"..."}); argv/dosya/loga yazılmaz. --max-requests zorunlu üst
 *                 sınırdır; ilk sağlayıcı kota reddinde (429) durulur.
 *
 * Örnek:
 *   node rag_stress_test.js --mode local --requests 40 --concurrency 4 --capacity 1
 *   node rag_stress_test.js --mode local --requests 40 --concurrency 4 --capacity 4 --fail-rate 0.1
 *   echo {"accessKey":"..."} | node rag_stress_test.js --mode remote --server https://... --requests 8 --concurrency 1 --max-requests 8
 */
const fs = require('node:fs');
const path = require('node:path');
const { performance } = require('node:perf_hooks');
const { randomBytes } = require('node:crypto');

const DEFAULT_INPUTS = require('./experiments/comparison_24.json').inputs;
const ENDPOINTS = ['input', 'compare'];

function parseArgs(argv) {
  const opts = { mode: 'local', requests: 40, concurrency: 4, capacity: '1', latencyMs: [800, 2500],
    failRate: 0, endpoints: ENDPOINTS, output: null, server: null, maxRequests: null, seed: 1,
    queueMax: '0', queueWaitMs: '60000', continueOnQuota: false };
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i], value = argv[i + 1];
    const need = () => { if (value === undefined) throw Error(`${key} değeri eksik`); i++; return value; };
    if (key === '--mode') opts.mode = need();
    else if (key === '--requests') opts.requests = Number(need());
    else if (key === '--concurrency') opts.concurrency = Number(need());
    else if (key === '--capacity') opts.capacity = need();
    else if (key === '--latency-ms') opts.latencyMs = need().split('-').map(Number);
    else if (key === '--fail-rate') opts.failRate = Number(need());
    else if (key === '--endpoints') opts.endpoints = need().split(',');
    else if (key === '--output') opts.output = need();
    else if (key === '--server') opts.server = need();
    else if (key === '--max-requests') opts.maxRequests = Number(need());
    else if (key === '--seed') opts.seed = Number(need());
    else if (key === '--queue-max') opts.queueMax = need();
    else if (key === '--queue-wait-ms') opts.queueWaitMs = need();
    else if (key === '--continue-on-quota') opts.continueOnQuota = true;
    else if (key === '--save-outputs') opts.saveOutputs = true;
    else throw Error(`Bilinmeyen argüman: ${key}`);
  }
  if (!['local', 'remote'].includes(opts.mode)) throw Error('--mode local veya remote olmalı');
  if (!Number.isInteger(opts.requests) || opts.requests < 1) throw Error('--requests pozitif tam sayı olmalı');
  if (!Number.isInteger(opts.concurrency) || opts.concurrency < 1) throw Error('--concurrency pozitif tam sayı olmalı');
  if (opts.endpoints.some(e => !ENDPOINTS.includes(e))) throw Error(`--endpoints yalnız ${ENDPOINTS.join(',')}`);
  if (opts.latencyMs.length === 1) opts.latencyMs = [opts.latencyMs[0], opts.latencyMs[0]];
  if (opts.latencyMs.some(v => !Number.isFinite(v) || v < 0) || opts.latencyMs[0] > opts.latencyMs[1]) throw Error('--latency-ms min-max biçiminde olmalı');
  if (!(opts.failRate >= 0 && opts.failRate <= 1)) throw Error('--fail-rate 0..1 olmalı');
  if (opts.mode === 'remote') {
    if (!opts.server) throw Error('remote kipte --server zorunlu');
    if (!Number.isInteger(opts.maxRequests) || opts.maxRequests < 1) throw Error('remote kipte --max-requests (ücret üst sınırı) zorunlu');
    if (opts.requests > opts.maxRequests) throw Error(`--requests (${opts.requests}) --max-requests (${opts.maxRequests}) sınırını aşıyor`);
  }
  return opts;
}

// Belirlenimci küçük PRNG (tekrarlanabilir gecikme/hata dizisi)
function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) % 1e9) / 1e9; };
}

function plan(opts) {
  const jobs = [];
  for (let i = 0; i < opts.requests; i++) {
    const input = DEFAULT_INPUTS[i % DEFAULT_INPUTS.length];
    const endpoint = opts.endpoints[i % opts.endpoints.length];
    const arm = endpoint === 'compare' ? ['A', 'B', 'C', 'D'][Math.floor(i / opts.endpoints.length) % 4] : null;
    jobs.push({ index: i, endpoint, arm, inputId: input.id, request: input.request });
  }
  return jobs;
}

// --- Sahte sağlayıcı (yalnız local kip) ---------------------------------------------------------
class FakeProviderError extends Error {
  constructor(status) { super(`Simulated provider HTTP ${status}`); this.status = status; }
}
function fakeOutput(request) {
  const ids = (request.behaviors || [{ behaviorId: request.behaviorId }]).map(b => b.behaviorId);
  if (ids.length !== 1) throw Error('Sahte sağlayıcı yalnız tek davranışlı girdileri destekler');
  return JSON.stringify({ commonStart: 'Çocuk evde oyuncaklarla oynar; yetişkin yakındadır.', structure: 'branched',
    commonBehaviorIds: ids, alternatives: [
      { title: 'Yönelme', continuation: 'Çocuk yetişkine döner.', ending: 'Oyun sürer.', behaviorIds: ids },
      { title: 'Yönelmeme', continuation: 'Çocuk oyuna devam eder.', ending: 'Sahne biter.', behaviorIds: ids }] });
}
function createFakeGenerate(opts) {
  const random = rng(opts.seed);
  const stats = { calls: 0, active: 0, peakActive: 0 };
  const generate = async (_genAI, _model, prompts) => {
    stats.calls++; stats.active++; stats.peakActive = Math.max(stats.peakActive, stats.active);
    try {
      const [lo, hi] = opts.latencyMs;
      await new Promise(resolve => setTimeout(resolve, lo + random() * (hi - lo)));
      if (random() < opts.failRate) throw new FakeProviderError(random() < 0.5 ? 503 : 429);
      const request = JSON.parse(prompts.user);
      const body = request.request ?? request;
      return { text: fakeOutput(body), usage: { promptTokens: Math.round(prompts.system.length / 4), outputTokens: 180 } };
    } finally { stats.active--; }
  };
  return { generate, stats };
}

// --- HTTP ---------------------------------------------------------------------------------------
async function post(base, route, body, key, timeoutMs) {
  const started = performance.now();
  try {
    const response = await fetch(new URL(route, base), {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(timeoutMs),
      headers: { 'Content-Type': 'application/json', ...(key ? { Authorization: `Bearer ${key}` } : {}) },
      body: JSON.stringify(body) });
    let json = null;
    try { json = await response.json(); } catch (_) { /* gövde JSON değil */ }
    return { status: response.status, body: json, clientMs: performance.now() - started };
  } catch (error) {
    return { status: null, body: null, clientMs: performance.now() - started,
      transportError: error?.name === 'TimeoutError' ? 'client_timeout' : 'transport_error' };
  }
}

function classify(res) {
  if (res.transportError) return res.transportError;
  if (res.status === 200 && res.body?.success) return 'success';
  const outcome = res.body?.measurement?.outcome;
  if (res.body?.code === 'local_capacity_exceeded') return 'capacity_rejected';
  if (res.status === 401) return 'unauthorized';
  if (outcome === 'timeout' || res.status === 504) return 'server_timeout';
  if (res.body?.providerError?.httpStatus === 429 || res.body?.providerError?.category === 'quota_or_rate_limit') return 'provider_quota';
  if (outcome === 'provider_error' || res.status === 502 && res.body?.providerError) return 'provider_error';
  if (outcome === 'validation_error') return 'validation_error';
  if (outcome) return outcome;
  return `http_${res.status}`;
}

// --save-outputs: içerik kalite denetimi için modelin ham cevabı (ve hata mesajı) kayda eklenir.
function attachOutput(record, res, save) {
  if (!save) return record;
  if (typeof res.body?.rawResponse === 'string') record.rawResponse = res.body.rawResponse;
  if (res.body && !res.body.success && typeof res.body.error === 'string') record.error = res.body.error.slice(0, 300);
  return record;
}

async function runJob(job, base, key, save = false) {
  const record = { index: job.index, endpoint: job.endpoint, arm: job.arm, inputId: job.inputId };
  if (job.endpoint === 'input') {
    const res = await post(base, '/api/generate-scenario-input', job.request, key, 150000);
    Object.assign(record, { status: res.status, outcome: classify(res), clientMs: res.clientMs,
      measurement: res.body?.measurement ?? null });
    return attachOutput(record, res, save);
  }
  // compare: önce önizleme (sağlayıcı çağrısı yok), sonra üretim
  const preview = await post(base, '/api/compare-scenario', { request: job.request, arm: job.arm, action: 'preview' }, key, 30000);
  record.previewMs = preview.clientMs;
  if (preview.status !== 200 || !preview.body?.preview?.protocolId) {
    Object.assign(record, { status: preview.status, outcome: `preview_${classify(preview)}`, clientMs: preview.clientMs,
      measurement: preview.body?.measurement ?? null });
    return record;
  }
  const res = await post(base, '/api/compare-scenario', { request: job.request, arm: job.arm, action: 'generate',
    protocolId: preview.body.preview.protocolId }, key, 150000);
  Object.assign(record, { status: res.status, outcome: classify(res), clientMs: res.clientMs,
    measurement: res.body?.measurement ?? null });
  return attachOutput(record, res, save);
}

async function runPool(jobs, concurrency, worker, onRecord) {
  const results = new Array(jobs.length);
  let next = 0, stop = false;
  async function lane() {
    while (!stop && next < jobs.length) {
      const job = jobs[next++];
      const record = await worker(job);
      results[job.index] = record;
      if (onRecord(record) === 'stop') stop = true;
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, jobs.length) }, lane));
  return results.filter(Boolean);
}

// --- Özet ---------------------------------------------------------------------------------------
function pct(values, p) {
  const v = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!v.length) return null;
  return v[Math.min(v.length - 1, Math.ceil((p / 100) * v.length) - 1)];
}
function stat(values) {
  const v = values.filter(Number.isFinite);
  return v.length ? { n: v.length, p50: pct(v, 50), p95: pct(v, 95), p99: pct(v, 99), max: Math.max(...v),
    mean: v.reduce((a, b) => a + b, 0) / v.length } : { n: 0 };
}
function summarize(records, wallMs) {
  const group = (filter) => {
    const rs = records.filter(filter);
    const ok = rs.filter(r => r.outcome === 'success');
    const outcomes = {};
    rs.forEach(r => { outcomes[r.outcome] = (outcomes[r.outcome] || 0) + 1; });
    return { total: rs.length, success: ok.length, errorRate: rs.length ? 1 - ok.length / rs.length : null, outcomes,
      clientMs: stat(ok.map(r => r.clientMs)),
      endpointMs: stat(ok.map(r => r.measurement?.endpointDurationMs)),
      retrievalMs: stat(rs.map(r => r.measurement?.retrievalDurationMs)),
      queueWaitMs: stat(rs.map(r => r.measurement?.queueWaitMs)),
      providerMs: stat(ok.map(r => r.measurement?.providerDurationMs)),
      rejectedClientMs: stat(rs.filter(r => r.outcome !== 'success').map(r => r.clientMs)),
      promptTokens: stat(ok.map(r => r.measurement?.promptTokens)) };
  };
  const byKey = {};
  for (const r of records) {
    const key = r.endpoint === 'compare' ? `compare-${r.arm}` : 'input';
    byKey[key] ??= true;
  }
  return {
    overall: { ...group(() => true), wallMs, throughputPerS: records.length / (wallMs / 1000) },
    groups: Object.fromEntries(Object.keys(byKey).sort().map(k => [k, group(r =>
      (r.endpoint === 'compare' ? `compare-${r.arm}` : 'input') === k)])),
  };
}
function fmt(x, d = 0) { return x == null ? '—' : Number(x).toFixed(d); }
function printSummary(summary, opts, extra) {
  const o = summary.overall;
  console.log(`\n=== RAG STRES TESTİ (${opts.mode}${opts.mode === 'local' ? `, sahte sağlayıcı ${opts.latencyMs.join('-')} ms, hata oranı ${opts.failRate}, kapasite ${opts.capacity}, kuyruk ${opts.queueMax}` : ''}) ===`);
  console.log(`İstek: ${o.total} | eşzamanlılık: ${opts.concurrency} | başarılı: ${o.success} | hata oranı: %${fmt(o.errorRate * 100, 1)} | süre: ${fmt(o.wallMs / 1000, 1)} s | verim: ${fmt(o.throughputPerS, 2)} istek/s`);
  console.log(`Sonuç dağılımı: ${JSON.stringify(o.outcomes)}`);
  if (extra) console.log(extra);
  console.log('\n| Grup | İstek | Başarılı | Hata % | İstemci p50/p95/p99 (ms) | Retrieval p50/p95 (ms) | Kuyruk p50/p95 (ms) | Sağlayıcı p50/p95 (ms) | Ret süresi p50 (ms) |');
  console.log('| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (const [k, g] of [['TOPLAM', o], ...Object.entries(summary.groups)]) {
    console.log(`| ${k} | ${g.total} | ${g.success} | ${fmt(g.errorRate * 100, 1)} | ${fmt(g.clientMs.p50)} / ${fmt(g.clientMs.p95)} / ${fmt(g.clientMs.p99)} | ${fmt(g.retrievalMs.p50, 2)} / ${fmt(g.retrievalMs.p95, 2)} | ${fmt(g.queueWaitMs.p50)} / ${fmt(g.queueWaitMs.p95)} | ${fmt(g.providerMs.p50)} / ${fmt(g.providerMs.p95)} | ${fmt(g.rejectedClientMs.p50)} |`);
  }
}

// --- Ana akış -----------------------------------------------------------------------------------
async function readKeyFromStdin() {
  const { createInterface } = require('node:readline');
  const rl = createInterface({ input: process.stdin, terminal: false });
  for await (const line of rl) { rl.close(); const key = JSON.parse(line).accessKey; if (typeof key === 'string' && key.trim()) return key; }
  throw Error('remote kipte oturum anahtarı stdin üzerinden {"accessKey":"..."} olarak verilmeli');
}

async function main(argv = process.argv.slice(2), { log = true } = {}) {
  const opts = parseArgs(argv);
  const jobs = plan(opts);
  let base, key, server, fake;
  if (opts.mode === 'local') {
    const { createApp } = require('./server');
    key = randomBytes(24).toString('hex'); // yalnız bu süreçte üretilen geçici yerel anahtar
    fake = createFakeGenerate(opts);
    const app = createApp({ env: { BACKEND_MODE: 'deployment', TEAM_ACCESS_KEY: key, GENERATION_MAX_CONCURRENT: String(opts.capacity),
      GENERATION_QUEUE_MAX: String(opts.queueMax), GENERATION_QUEUE_WAIT_MS: String(opts.queueWaitMs),
      SCENARIO_INPUT_MODEL: 'stres-testi-sahte-model' }, genAI: {}, generate: fake.generate, reportMeasurement: () => {} });
    server = await new Promise(resolve => { const s = app.listen(0, '127.0.0.1', () => resolve(s)); });
    base = `http://127.0.0.1:${server.address().port}`;
  } else {
    key = await readKeyFromStdin();
    base = opts.server;
  }
  const started = performance.now();
  let quotaStops = 0;
  const records = await runPool(jobs, opts.concurrency, job => runJob(job, base, key, opts.saveOutputs === true), record => {
    if (log) process.stdout.write(record.outcome === 'success' ? '.' : 'x');
    if (opts.mode === 'remote' && record.outcome === 'provider_quota' && !opts.continueOnQuota) { quotaStops++; return 'stop'; }
    return undefined;
  });
  const wallMs = performance.now() - started;
  if (server) await new Promise(resolve => server.close(resolve));
  const summary = summarize(records, wallMs);
  const result = { version: 'rag-stress-1', createdAt: new Date().toISOString(),
    options: { ...opts, server: opts.mode === 'remote' ? new URL(opts.server).origin : null },
    fakeProvider: fake ? fake.stats : null, stoppedOnQuota: quotaStops > 0, summary, records };
  if (log) {
    printSummary(summary, opts, fake ? `Sahte sağlayıcıya ulaşan çağrı: ${fake.stats.calls} | aynı anda en fazla: ${fake.stats.peakActive}` : null);
    if (quotaStops) console.log('\n[DURDU] Sağlayıcı kota reddi (429) alındı; ücret/kota korunması için kalan istekler gönderilmedi.');
  }
  if (opts.output) {
    fs.mkdirSync(path.dirname(path.resolve(opts.output)), { recursive: true });
    fs.writeFileSync(opts.output, JSON.stringify(result, null, 2));
    if (log) console.log(`\nAyrıntılı kayıt: ${opts.output}`);
  }
  return result;
}

if (require.main === module) {
  main().catch(error => { console.error(`[HATA] ${error.message}`); process.exitCode = 1; });
}
module.exports = { main, parseArgs, plan, summarize, classify, fakeOutput };
