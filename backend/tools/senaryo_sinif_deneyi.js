'use strict';
/*
 * Senaryo sınıf doğruluğu deneyi (karışıklık matrisi için veri toplar).
 *
 * /api/generate-scenario'ya ontoloji kombinasyonu (her istekte 10 karttan 3-4'ü) × risk profili
 * (TİPİK/ATİPİK/SINIRDA) × kol (A/B/C/D) gönderilir. Varsayılan olarak yalnız UYARAN fazı (11 sahne)
 * istenir (stimulusOnly); --full-scenario ile 26 sahne.
 *
 * Sınıflama:
 *  - Gecikme sınıfı: UYARAN sahnelerindeki latencySeconds, yaş bandı eşikleriyle (delta_t.js) sınıflanır.
 *    Eşikler yaş bandına bağlıdır ve gecikmeli kartlarda (D01/D02/D07/D08) ortaktır; bu yüzden her
 *    kombinasyonda en az bir gecikmeli kart bulunur.
 *  - Öz-etiket sınıfı: modelin sahnelere koyduğu clinical.atypical işaretleri (herhangi biri true → ATIPIK).
 *
 * Kullanım (sunucuda): node tools/senaryo_sinif_deneyi.js --server http://127.0.0.1:80 --rate-per-min 4 \
 *   --output logs/senaryo_sinif.json --max-requests 96 [--combos 8] [--arms A,B,C,D]
 * Gemini ücretsiz katman dakika sınırı nedeniyle istekler sırayla ve hız sınırlı gönderilir.
 */
const fs = require('node:fs');
const path = require('node:path');
const retriever = require('../rag/retriever');
const { uyaranLatencies, classifyScenario } = require('../delta_t');

const LATENCY_CARDS = ['D01', 'D02', 'D07', 'D08'];
const OTHER_CARDS = ['D03', 'D04', 'D05', 'D06', 'D09', 'D10'];
const AGES = [15, 21, 30]; // 12-18 / 18-24 / 24-36 ay

// Belirlenimci kombinasyonlar: her biri 1 gecikmeli + 2-3 gecikmesiz kart (toplam 3-4), yaş bandı döner.
function buildCombos(n) {
  const combos = [];
  let cursor = 0;
  for (let k = 0; k < n; k++) {
    const size = k % 2 === 0 ? 3 : 4;
    const codes = [LATENCY_CARDS[k % LATENCY_CARDS.length]];
    while (codes.length < size) codes.push(OTHER_CARDS[cursor++ % OTHER_CARDS.length]);
    combos.push({ codes, age: AGES[k % AGES.length] });
  }
  return combos;
}

function args(argv) {
  const o = { server: null, ratePerMin: 4, output: null, arms: ['A', 'B', 'C', 'D'], combos: 8,
    risks: ['TİPİK', 'ATİPİK', 'SINIRDA'], maxRequests: null, timeoutMs: 240000, stimulusOnly: true };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    const v = () => argv[++i];
    if (k === '--server') o.server = v();
    else if (k === '--rate-per-min') o.ratePerMin = Number(v());
    else if (k === '--output') o.output = v();
    else if (k === '--arms') o.arms = v().split(',');
    else if (k === '--combos') o.combos = Number(v());
    else if (k === '--full-scenario') o.stimulusOnly = false;
    else if (k === '--max-requests') o.maxRequests = Number(v());
    else throw Error(`Bilinmeyen argüman: ${k}`);
  }
  if (!o.server || !o.output || !(o.maxRequests > 0)) throw Error('--server, --output ve --max-requests zorunlu');
  return o;
}

async function main() {
  const o = args(process.argv.slice(2));
  const jobs = [];
  for (const combo of buildCombos(o.combos)) for (const risk of o.risks) for (const arm of o.arms) {
    jobs.push({ ...combo, risk, arm });
  }
  if (jobs.length > o.maxRequests) throw Error(`${jobs.length} istek --max-requests (${o.maxRequests}) sınırını aşıyor`);
  const records = [];
  const interval = 60000 / o.ratePerMin;
  const save = () => {
    fs.mkdirSync(path.dirname(path.resolve(o.output)), { recursive: true });
    fs.writeFileSync(o.output, JSON.stringify({ version: 'senaryo-sinif-2', createdAt: new Date().toISOString(), options: o, records }, null, 1));
  };
  for (let i = 0; i < jobs.length; i++) {
    const j = jobs[i];
    const started = Date.now();
    const basis = j.codes.find(c => LATENCY_CARDS.includes(c));
    const sel = retriever.getSelectiveRuleContext({ behaviorCode: basis, ageMonths: j.age, riskProfile: j.risk });
    const rec = { index: i, codes: j.codes, behavior: j.codes.join('+'), basisCard: basis, age: j.age, risk: j.risk, arm: j.arm,
      expected: sel.riskCategory, band: sel.bandKey, typicalMax: sel.expectedTypicalDelayMax, atypicalMin: sel.expectedAtypicalDelayMin };
    try {
      const res = await fetch(new URL('/api/generate-scenario', o.server), {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(o.timeoutMs),
        body: JSON.stringify({ ageMonths: j.age, riskProfile: j.risk, ontologyCodes: j.codes, arm: j.arm,
          caseId: `sinif-${j.codes.join('')}-${j.age}-${j.arm}`, stimulusOnly: o.stimulusOnly }) });
      const body = await res.json().catch(() => null);
      rec.status = res.status;
      rec.success = Boolean(body?.success);
      if (rec.success) {
        const scenes = body.scenario?.scenes || [];
        const uyaran = scenes.filter(s => s.phase === 'UYARAN');
        rec.model = body.model;
        rec.sceneCount = scenes.length;
        rec.latencies = uyaranLatencies(scenes);
        rec.actual = classifyScenario(rec.latencies, rec.typicalMax, rec.atypicalMin);
        rec.atypicalFlags = uyaran.map(s => s.clinical?.atypical ?? null);
        const flags = rec.atypicalFlags.filter(f => typeof f === 'boolean');
        rec.flagClass = flags.length ? (flags.includes(true) ? 'ATIPIK' : 'TIPIK') : null;
        rec.serverDeltaT = body.benchmark?.deltaT ?? null;
        rec.uyaranNotes = uyaran.map(s => s.clinical?.note || '');
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
    console.log(`${i + 1}/${jobs.length} ${rec.behavior} ${j.age}ay ${j.risk} kol ${j.arm}: ` +
      (rec.success ? `beklenen ${rec.expected} → gecikme ${rec.actual ?? 'yok'} [${rec.latencies.join(', ')}], öz-etiket ${rec.flagClass ?? '-'} (${rec.sceneCount} sahne)`
        : `HATA ${rec.error}`));
    const wait = interval - (Date.now() - started);
    if (wait > 0 && i < jobs.length - 1) await new Promise(r => setTimeout(r, wait));
  }
  save();
}

if (require.main === module) main().catch(e => { console.error(`[HATA] ${e.message}`); process.exitCode = 1; });
module.exports = { buildCombos, LATENCY_CARDS, OTHER_CARDS };
