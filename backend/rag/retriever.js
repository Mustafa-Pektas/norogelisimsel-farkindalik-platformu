const fs = require('fs');
const path = require('path');
const { performance } = require('perf_hooks');

const kbPath = path.join(__dirname, 'clinical_knowledge_base.json');
let knowledgeBase = null;

function loadKnowledgeBase() {
  if (!knowledgeBase) {
    const raw = fs.readFileSync(kbPath, 'utf8');
    knowledgeBase = JSON.parse(raw);
  }
  return knowledgeBase;
}

function resolveAgeBandKey(ageMonths) {
  const m = Number(ageMonths) || 18;
  if (m < 18) return '12-18';
  if (m < 24) return '18-24';
  return '24-36';
}

function normalizeCode(rawCode) {
  if (!rawCode) return 'D01';
  const c = String(rawCode).trim().toUpperCase();
  // ONT mapping
  const ontMap = {
    'ONT-01': 'D01',
    'ONT-02': 'D02',
    'ONT-03': 'D05',
    'ONT-04': 'D02',
    'ONT-05': 'D03',
    'ONT-06': 'D03',
    'ONT-07': 'D05',
    'ONT-08': 'D07',
    'ONT-09': 'D04',
    'ONT-10': 'D06',
    'ONT-11': 'D08',
    'ONT-12': 'D09',
  };
  return ontMap[c] || c;
}

/**
 * Kol B (Selective Rule Injection): Yalnızca istenen vakaya ait kuralları çeker.
 */
function getSelectiveRuleContext({ behaviorCode, ageMonths, riskProfile }) {
  const kb = loadKnowledgeBase();
  const code = normalizeCode(behaviorCode);
  const bandKey = resolveAgeBandKey(ageMonths);
  const bandInfo = kb.ageBands[bandKey] || kb.ageBands['18-24'];
  const card = kb.cards.find((c) => c.id === code) || kb.cards[0];
  const normRisk = (riskProfile || '').replace(/İ/g, 'I').replace(/ı/g, 'i').toUpperCase();
  const isAtypical = normRisk.includes('ATIPIK') || normRisk.includes('ATYPICAL') || normRisk.includes('RISK');

  const ruleLines = [
    `[KLİNİK KURAL ENJEKSİYONU - VAKA BAZLI RETRIEVAL (KOL B)]`,
    `Kaynak: ${kb.sourceDoc} (Sürüm ${kb.version})`,
    `Hedef Kart: ${card.id} — ${card.title}`,
    `Gözlem Amacı: ${card.purpose}`,
    `Yetişkin Uygulama Kuralı: ${card.instruction}`,
    `Çocuk Başlangıç Şartı: ${card.preparation}`,
    `Yaş Bandı (${bandInfo.label}): ${bandInfo.focus}`,
    `Gözlem Penceresi: ${card.pilotWindowSeconds} saniye`,
    `Klinik Tepki Eşiği (${isAtypical ? 'ATİPİK' : 'TİPİK'}):`,
    isAtypical
      ? `  - UYARAN fazında çocuğun tepki gecikmesi (latencySeconds) en az ${bandInfo.atypicalMinDelaySec} saniye olmalı veya pencere boyunca hiç tepki verilmemelidir.`
      : `  - UYARAN fazında çocuğun tepki gecikmesi (latencySeconds) ${bandInfo.typicalMaxDelaySec} saniyenin altında olmalı ve yetişkine net yönelme görülmelidir.`,
    `Tipik Ölçüt: ${card.typicalCriteria}`,
    `Atipik Ölçüt: ${card.atypicalCriteria}`,
    `Geçersizlik Şartları (BU HATALARI KESİNLİKLE YAPMA):`,
    ...card.invalidityConditions.map((cond) => `  * ${cond}`),
  ];

  return {
    cardId: card.id,
    cardTitle: card.title,
    bandKey,
    bandLabel: bandInfo.label,
    ruleText: ruleLines.join('\n'),
    expectedAtypicalDelayMin: bandInfo.atypicalMinDelaySec,
    expectedTypicalDelayMax: bandInfo.typicalMaxDelaySec,
  };
}

/**
 * Kol C (Full-Context): Bilgi tabanındaki 10 kartın ve tüm yaş eşiklerinin tamamını döner.
 */
function getFullContext() {
  const kb = loadKnowledgeBase();
  const lines = [
    `[TÜM KLİNİK BİLGİ TABANI - FULL-CONTEXT (KOL C)]`,
    `Kaynak: ${kb.sourceDoc} (Sürüm ${kb.version})`,
    `Kapsam: 10 Davranış Kartı ve Gelişimsel Yaş Eşikleri Tablosu`,
    ``,
    `=== YAŞ BANTLARI VE EŞİKLERİ ===`,
  ];

  Object.entries(kb.ageBands).forEach(([k, b]) => {
    lines.push(`• ${b.label}: ${b.focus} | Tipik Maks Gecikme: ${b.typicalMaxDelaySec}s | Atipik Min Gecikme: ${b.atypicalMinDelaySec}s`);
  });

  lines.push(``);
  lines.push(`=== 10 DAVRANIŞ KARTI KATALOĞU ===`);

  kb.cards.forEach((c) => {
    lines.push(`[${c.id}] ${c.title}`);
    lines.push(`  - Amaç: ${c.purpose}`);
    lines.push(`  - Yönerge: ${c.instruction}`);
    lines.push(`  - Hazırlık: ${c.preparation}`);
    lines.push(`  - Tipik: ${c.typicalCriteria}`);
    lines.push(`  - Atipik: ${c.atypicalCriteria}`);
    lines.push(`  - Geçersizlikler: ${c.invalidityConditions.join('; ')}`);
    lines.push(``);
  });

  return {
    fullText: lines.join('\n'),
    totalCards: kb.cards.length,
  };
}

/**
 * Retrieval süresini mikrosaniye hassasiyetinde ölçer.
 */
function timedRetrieval(params) {
  const t0 = performance.now();
  const res = getSelectiveRuleContext(params);
  const t1 = performance.now();
  return {
    ...res,
    retrievalDurationMs: Number((t1 - t0).toFixed(4)),
  };
}

module.exports = {
  loadKnowledgeBase,
  resolveAgeBandKey,
  normalizeCode,
  getSelectiveRuleContext,
  getFullContext,
  timedRetrieval,
};
