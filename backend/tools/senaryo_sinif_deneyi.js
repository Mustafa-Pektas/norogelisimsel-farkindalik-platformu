'use strict';
/*
 * Senaryo sınıf doğruluğu deneyi (karışıklık matrisi için veri toplar).
 *
 * /api/generate-scenario'ya kol (A/B/C/D) × risk profili (TİPİK/ATİPİK/SINIRDA) × davranış × yaş
 * bileşimleri gönderilir. Her çıktının UYARAN sahnelerindeki latencySeconds değerleri bilgi tabanı
 * eşikleriyle sınıflanır (delta_t.js) ve istenen profille karşılaştırılır.
 *
 * Kullanım (sunucuda): node tools/senaryo_sinif_deneyi.js --server http://127.0.0.1:80 --rate-per-min 4 \
 *   --output logs/senaryo_sinif.json [--arms A,B,C,D] [--behaviors D01,D02] [--ages 15,21,30] [--max-requests 72]
 * Gemini ücretsiz katman dakika sınırı nedeniyle istekler sırayla ve hız sınırlı gönderilir.
 */
const fs = require('node:fs');
const path = require('node:path');
const retriever = require('../rag/retriever');
const { uyaranLatencies, classifyScenario } = require('../delta_t');

function args(argv) {
  const o = { server: null, ratePerMin: 4, output: null, arms: ['A', 'B', 'C', 'D'], behaviors: ['D01', 'D02'],
    ages: [15, 21, 30], risks: ['TİPİK', 'ATİPİK', 'SINIRDA'], maxRequests: null, timeoutMs: 240000 };
  for (let i = 0; i < argv.length; i += 2) {
    const k = argv[i], v = argv[i + 1];
    if (k === '--server') o.server = v;
    else if (k === '--rate-per-min') o.ratePerMin = Number(v);
    else if (k === '--output') o.output = v;
    else if (k === '--arms') o.arms = v.split(',');
    else if (k === '--behaviors') o.behaviors = v.split(',');
    else if (k === '--ages') o.ages = v.split(',').map(Number);
    else if (k === '--max-requests') o.maxRequests = Number(v);
    else throw Error(`Bilinmeyen argüman: ${k}`);
  }
  if (!o.server || !o.output || !(o.maxRequests > 0)) throw Error('--server, --output ve --max-requests zorunlu');
  return o;
}

async function main() {
  const o = args(process.argv.slice(2));
  const jobs = [];
  for (const behavior of o.behaviors) for (const age of o.ages) for (const risk of o.risks) for (const arm of o.arms) {
    jobs.push({ behavior, age, risk, arm });
  }
  if (jobs.length > o.maxRequests) throw Error(`${jobs.length} istek --max-requests (${o.maxRequests}) sınırını aşıyor`);
  const records = [];
  const interval = 60000 / o.ratePerMin;
  const save = () => {
    fs.mkdirSync(path.dirname(path.resolve(o.output)), { recursive: true });
    fs.writeFileSync(o.output, JSON.stringify({ version: 'senaryo-sinif-1', createdAt: new Date().toISOString(), options: o, records }, null, 1));
  };
  for (let i = 0; i < jobs.length; i++) {
    const j = jobs[i];
    const started = Date.now();
    const sel = retriever.getSelectiveRuleContext({ behaviorCode: j.behavior, ageMonths: j.age, riskProfile: j.risk });
    const rec = { index: i, ...j, expected: sel.riskCategory, band: sel.bandKey,
      typicalMax: sel.expectedTypicalDelayMax, atypicalMin: sel.expectedAtypicalDelayMin };
    try {
      const res = await fetch(new URL('/api/generate-scenario', o.server), {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(o.timeoutMs),
        body: JSON.stringify({ ageMonths: j.age, riskProfile: j.risk, ontologyCodes: [j.behavior], arm: j.arm,
          caseId: `sinif-${j.behavior}-${j.age}-${j.arm}` }) });
      const body = await res.json().catch(() => null);
      rec.status = res.status;
      rec.success = Boolean(body?.success);
      if (rec.success) {
        const scenes = body.scenario?.scenes || [];
        rec.model = body.model;
        rec.latencies = uyaranLatencies(scenes);
        rec.actual = classifyScenario(rec.latencies, rec.typicalMax, rec.atypicalMin);
        rec.atypicalFlags = scenes.filter(s => s.phase === 'UYARAN').map(s => s.clinical?.atypical ?? null);
        rec.serverDeltaT = body.benchmark?.deltaT ?? null;
        rec.uyaranNotes = scenes.filter(s => s.phase === 'UYARAN').map(s => s.clinical?.note || '').slice(0, 11);
        rec.summary = body.scenario?.summary || '';
      } else {
        rec.error = String(body?.error || `HTTP ${res.status}`).slice(0, 300);
      }
    } catch (e) {
      rec.success = false;
      rec.error = e.name === 'TimeoutError' ? 'client_timeout' : String(e.message).slice(0, 200);
    }
    rec.clientMs = Date.now() - started;
    records.push(rec);
    save();
    console.log(`${i + 1}/${jobs.length} ${j.behavior} ${j.age}ay ${j.risk} kol ${j.arm}: ` +
      (rec.success ? `beklenen ${rec.expected} → gerçekleşen ${rec.actual ?? 'gecikme yok'} [${rec.latencies.join(', ')}]` : `HATA ${rec.error}`));
    const wait = interval - (Date.now() - started);
    if (wait > 0 && i < jobs.length - 1) await new Promise(r => setTimeout(r, wait));
  }
  save();
}

main().catch(e => { console.error(`[HATA] ${e.message}`); process.exitCode = 1; });
