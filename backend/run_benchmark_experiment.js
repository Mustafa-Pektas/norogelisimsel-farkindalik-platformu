/**
 * 10 Vaka x 3 Kol (A, B, C) Otomatik Benchmark Koşucusu
 * Metodoloji v2 standartlarına tam uygundur.
 * Kullanım: node backend/run_benchmark_experiment.js [--repeats=1] [--arm=ALL|A|B|C]
 */

const path = require('path');
const dotenv = require('dotenv');
dotenv.config({ path: path.join(__dirname, '.env') });
dotenv.config();

const { GoogleGenerativeAI } = require('@google/generative-ai');
const retriever = require('./rag/retriever');
const fsmValidator = require('./validators/fsm_validator');
const benchmarkService = require('./services/benchmark_service');

const rawKey = (process.env.GEMINI_API_KEY || '').trim();
const apiKey = rawKey.replace(/^["']|["']$/g, '').trim();

if (!apiKey || apiKey.includes('BURAYA_GEMINI')) {
  console.error('[HATA] Lütfen backend/.env dosyasında geçerli bir GEMINI_API_KEY tanımlayın.');
  process.exit(1);
}

const genAI = new GoogleGenerativeAI(apiKey);

// v2 Matrisindeki 10 Test Vakası
const TEST_CASES = [
  { id: 'V01', ageMonths: 18, behaviorCode: 'D01', riskProfile: 'TİPİK', childName: 'Ali' },
  { id: 'V02', ageMonths: 18, behaviorCode: 'D01', riskProfile: 'ATİPİK', childName: 'Deniz' },
  { id: 'V03', ageMonths: 14, behaviorCode: 'D01', riskProfile: 'SINIRDA', childName: 'Can' },
  { id: 'V04', ageMonths: 24, behaviorCode: 'D02', riskProfile: 'TİPİK', childName: 'Ece' },
  { id: 'V05', ageMonths: 24, behaviorCode: 'D02', riskProfile: 'ATİPİK', childName: 'Mert' },
  { id: 'V06', ageMonths: 30, behaviorCode: 'D03', riskProfile: 'TİPİK', childName: 'Selin' },
  { id: 'V07', ageMonths: 30, behaviorCode: 'D03', riskProfile: 'ATİPİK', childName: 'Kaan' },
  { id: 'V08', ageMonths: 36, behaviorCode: 'D04', riskProfile: 'TİPİK', childName: 'Zeynep' },
  { id: 'V09', ageMonths: 36, behaviorCode: 'D04', riskProfile: 'ATİPİK', childName: 'Emir' },
  { id: 'V10', ageMonths: 18, behaviorCode: 'D07', riskProfile: 'ATİPİK', childName: 'Bora' },
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function runBenchmark() {
  console.log('================================================================');
  console.log('🧪 GEMINI vs. RAG KARŞILAŞTIRMA BENCHMARK KOŞUCUSU (Metodoloji v2)');
  console.log('================================================================');
  console.log(`[*] Toplam Test Vakası: ${TEST_CASES.length}`);
  console.log(`[*] Hedef Kollar: Kol A (Baseline), Kol B (Kural Enj.), Kol C (Full-Context)`);
  console.log('----------------------------------------------------------------\n');

  const arms = ['A', 'B', 'C'];
  let runCount = 0;

  for (const vaka of TEST_CASES) {
    for (const arm of arms) {
      runCount++;
      console.log(`[${runCount}/30] Çalıştırılıyor: Vaka ${vaka.id} (${vaka.ageMonths} ay, ${vaka.behaviorCode}, ${vaka.riskProfile}) ➔ Kol ${arm}...`);

      try {
        const response = await fetch('http://localhost:8000/api/generate-scenario', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            arm,
            caseId: vaka.id,
            ageMonths: vaka.ageMonths,
            ontologyCode: vaka.behaviorCode,
            riskProfile: vaka.riskProfile,
            childName: vaka.childName,
          }),
        });

        if (!response.ok) {
          const errText = await response.text();
          console.warn(`  [!] Hata (${response.status}): ${errText}`);
        } else {
          const resJson = await response.json();
          const b = resJson.benchmark || {};
          console.log(`  [OK] Başarılı! Model: ${resJson.model} | Latency: ${b.latencyApiMs} ms | FSM: %${Math.round(b.fsmMatchRate * 100)} | Δt Uyum: ${b.deltaTCompliant ? 'EVET' : 'HAYIR'}`);
        }
      } catch (err) {
        console.warn(`  [!] İstek başarısız: ${err.message}`);
      }

      // Rate limit koruması: İstekler arası 4 saniye bekle
      await sleep(4000);
    }
  }

  console.log('\n================================================================');
  console.log('📊 BENCHMARK TAMAMLANDI! ÖZET İSTATİSTİKLER:');
  console.log('================================================================');
  const stats = benchmarkService.getBenchmarkStats();
  console.log(JSON.stringify(stats, null, 2));
}

if (require.main === module) {
  runBenchmark();
}

module.exports = { runBenchmark, TEST_CASES };
