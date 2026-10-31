const fs = require('fs');
const path = require('path');
const { performance } = require('perf_hooks');

const kbPath = path.join(__dirname, 'clinical_knowledge_base.json');
let knowledgeBase = null;

function deepFreeze(obj) {
  if (obj === null || typeof obj !== 'object') return obj;
  Object.freeze(obj);
  Object.keys(obj).forEach((key) => {
    if (typeof obj[key] === 'object' && obj[key] !== null && !Object.isFrozen(obj[key])) {
      deepFreeze(obj[key]);
    }
  });
  return obj;
}

/**
 * Bilgi tabanını belleğe yükler ve tüm mimari kuralları doğrular.
 */
function validateKnowledgeBase(kb) {
  if (!kb || typeof kb !== 'object') {
    throw new Error('Bilgi tabanı geçerli bir nesne olmalıdır.');
  }

  if (!Array.isArray(kb.cards) || kb.cards.length !== 10) {
    throw new Error(`Bilgi tabanında tam 10 davranış kartı bulunmalıdır (mevcut: ${kb.cards?.length}).`);
  }

  const refIds = new Set((kb.clinicalReferences || []).map((r) => r.id));
  const cardIds = new Set(kb.cards.map((c) => c.id));

  // Yaş bantları kontrolü
  const targetBands = ['12-18', '18-24', '24-36'];
  targetBands.forEach((band) => {
    const b = kb.ageBands?.[band];
    if (!b) throw new Error(`ageBands içinde '${band}' tanımlı olmalıdır.`);
    if (typeof b.typicalMaxDelaySec !== 'number' || typeof b.atypicalMinDelaySec !== 'number') {
      throw new Error(`'${band}' bandında gecikme eşikleri sayısal olmalıdır.`);
    }
    if (b.typicalMaxDelaySec >= b.atypicalMinDelaySec) {
      throw new Error(`'${band}' bandında typicalMaxDelaySec < atypicalMinDelaySec olmalıdır.`);
    }
  });

  // Her kartın kontrolü
  kb.cards.forEach((card) => {
    if (!card.id || !card.title || !card.instruction) {
      throw new Error(`Kart ${card.id || 'tanımsız'} zorunlu alanları (id, title, instruction) içermelidir.`);
    }
    if (typeof card.hasLatencyThreshold !== 'boolean') {
      throw new Error(`Kart ${card.id} için hasLatencyThreshold boolean olmalıdır.`);
    }

    if (!card.goldStandardMapping || typeof card.goldStandardMapping !== 'object' ||
        !card.goldStandardMapping.scale || !card.goldStandardMapping.itemCode || !card.goldStandardMapping.domain) {
      throw new Error(`Kart ${card.id} standart bir goldStandardMapping (scale, itemCode, domain) içermelidir.`);
    }

    if (!card.byAgeBand || typeof card.byAgeBand !== 'object') {
      throw new Error(`Kart ${card.id} byAgeBand nesnesi içermelidir.`);
    }

    targetBands.forEach((band) => {
      const byAge = card.byAgeBand[band];
      if (!byAge) {
        throw new Error(`Kart ${card.id} içinde '${band}' yaş bandı eksik.`);
      }
      if (!byAge.typicalCriteria || typeof byAge.typicalCriteria !== 'string' || byAge.typicalCriteria.trim().length === 0) {
        throw new Error(`Kart ${card.id} [${band}] typicalCriteria dolu bir metin olmalıdır.`);
      }
      if (!byAge.atypicalCriteria || typeof byAge.atypicalCriteria !== 'string' || byAge.atypicalCriteria.trim().length === 0) {
        throw new Error(`Kart ${card.id} [${band}] atypicalCriteria dolu bir metin olmalıdır.`);
      }
      if (!byAge.borderlineCriteria || typeof byAge.borderlineCriteria !== 'string' || byAge.borderlineCriteria.trim().length === 0) {
        throw new Error(`Kart ${card.id} [${band}] borderlineCriteria dolu bir metin olmalıdır.`);
      }
    });

    (card.clinicalSources || []).forEach((src) => {
      const match = src.match(/REF-\d{2}/);
      if (match && !refIds.has(match[0])) {
        throw new Error(`Kart ${card.id} içindeki '${match[0]}' referans listesinde bulunamadı.`);
      }
    });
  });

  // ONT eşleme kontrolü
  Object.entries(ONT_MAP).forEach(([ontCode, targetId]) => {
    if (!cardIds.has(targetId)) {
      throw new Error(`ONT eşlemesi ${ontCode} -> ${targetId} geçerli bir karta yönlenmiyor.`);
    }
  });

  return true;
}

function loadKnowledgeBase() {
  if (!knowledgeBase) {
    const raw = fs.readFileSync(kbPath, 'utf8');
    const parsed = JSON.parse(raw);
    validateKnowledgeBase(parsed);
    knowledgeBase = deepFreeze(parsed);
  }
  return knowledgeBase;
}

/**
 * Yaş değerini doğrular ve geçerli yaş bandı anahtarına ('12-18', '18-24', '24-36') çevirir.
 * 12 altı veya 36 üstü yaş değerlerinde açıkça hata fırlatır.
 */
function resolveAgeBandKey(ageMonths) {
  const kb = loadKnowledgeBase();

  if (typeof ageMonths === 'string') {
    const clean = ageMonths.trim();
    if (kb.legacyAliases && kb.legacyAliases[clean]) {
      return kb.legacyAliases[clean];
    }
    if (clean === '12-18' || clean === '18-24' || clean === '24-36') {
      return clean;
    }
  }

  if (ageMonths === null || ageMonths === undefined || ageMonths === '') {
    throw new Error('Geçersiz yaş: ageMonths boş veya tanımsız olamaz.');
  }

  const m = Number(ageMonths);
  if (!Number.isFinite(m)) {
    throw new Error(`Geçersiz yaş: '${ageMonths}'. Sayısal bir ay değeri veya geçerli yaş bandı ('12-18', '18-24', '24-36') bekleniyor.`);
  }

  if (m < 12 || m > 36) {
    throw new Error(`Yaş kapsam dışı: ${m} ay. Platform yalnız 12–36 ay gelişimsel tarama aralığını desteklemektedir.`);
  }

  if (m < 18) return '12-18';
  if (m < 24) return '18-24';
  return '24-36';
}

/**
 * ONT kodlarını ve küçük/büyük harf D kodlarını standart D01-D10 koduna eşler.
 */
const ONT_MAP = Object.freeze({
  'ONT-01': 'D01', // İsme tepki verme
  'ONT-02': 'D02', // Yetişkinin işaretine yönelme (yakın hedef)
  'ONT-03': 'D05', // Nesne gösterme
  'ONT-04': 'D02', // Yetişkinin işaretine yönelme (uzak hedef)
  'ONT-05': 'D03', // İstemek için işaret (nesne odaklı)
  'ONT-06': 'D03', // İstemek için işaret (yetişkin odaklı)
  'ONT-07': 'D05', // Nesne gösterme (sosyal paylaşım)
  'ONT-08': 'D07', // Gülümsemeye karşılık verme
  'ONT-09': 'D04', // Mış gibi hayali oyun
  'ONT-10': 'D06', // Basit motor taklit
  'ONT-11': 'D08', // Sözel yönergeyi yerine getirme
  'ONT-12': 'D09', // Nesneyi kaba yerleştirme
  'ONT-13': 'D10', // Kalemle kendiliğinden karalama
});

function normalizeCode(rawCode) {
  if (!rawCode || typeof rawCode !== 'string') {
    throw new Error('Geçersiz davranış kodu: Kod boş veya tanımsız olamaz.');
  }
  const c = rawCode.trim().toUpperCase();
  const mapped = ONT_MAP[c] || c;

  const kb = loadKnowledgeBase();
  const exists = kb.cards.some((card) => card.id === mapped);
  if (!exists) {
    throw new Error(`Bilinmeyen davranış kodu: '${rawCode}'. İzin verilen kodlar: D01-D10 veya ONT-01-ONT-13.`);
  }
  return mapped;
}

/**
 * Risk profilini / hedef davranış sonucunu güvenli biçimde ayrıştırır.
 * 'DÜŞÜK RİSK' kesinlikle TİPİK sınıfına girer.
 */
function parseRiskProfile(rawProfile) {
  if (!rawProfile || typeof rawProfile !== 'string') {
    throw new Error('Geçersiz risk profili: Boş veya tanımsız değer verilemez.');
  }

  const p = rawProfile
    .trim()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/_/g, ' ')
    .toUpperCase()
    .trim();

  if (p === 'TIPIK' || p === 'TYPICAL' || p === 'DUSUK RISK' || p === 'LOW RISK' || p === 'NORMAL') {
    return { category: 'TIPIK', displayLabel: 'TİPİK' };
  }
  if (p === 'ATIPIK' || p === 'ATYPICAL' || p === 'YUKSEK RISK' || p === 'HIGH RISK') {
    return { category: 'ATIPIK', displayLabel: 'ATİPİK' };
  }
  if (p === 'SINIRDA' || p === 'BORDERLINE' || p === 'ORTA RISK' || p === 'MEDIUM RISK') {
    return { category: 'SINIRDA', displayLabel: 'SINIRDA' };
  }

  throw new Error(`Tanınmayan risk profili: '${rawProfile}'. İzin verilen değerler: 'TİPİK', 'ATİPİK', 'SINIRDA', 'DÜŞÜK RİSK', 'YÜKSEK RİSK', 'ORTA RİSK'.`);
}

/**
 * Kol B (Selective Rule Injection): Yalnızca istenen vaka ve yaş bandına ait seçici kuralları çeker.
 * Bilgi sızıntısını önlemek için modele yalnızca hedeflenen aktif ölçüt ve geçersizlik şartları iletilir.
 */
function getSelectiveRuleContext({ behaviorCode, ageMonths, riskProfile }) {
  const kb = loadKnowledgeBase();
  const code = normalizeCode(behaviorCode);
  const bandKey = resolveAgeBandKey(ageMonths);
  const risk = parseRiskProfile(riskProfile);

  const bandInfo = kb.ageBands[bandKey];
  const card = kb.cards.find((c) => c.id === code);

  if (!card.byAgeBand || !card.byAgeBand[bandKey]) {
    throw new Error(`Kart için yaş bandı ölçütleri bulunamadı: ${card.id} [${bandKey}]`);
  }

  const byAge = card.byAgeBand[bandKey];

  let activeCriteria = '';
  if (risk.category === 'TIPIK') activeCriteria = byAge.typicalCriteria;
  else if (risk.category === 'ATIPIK') activeCriteria = byAge.atypicalCriteria;
  else activeCriteria = byAge.borderlineCriteria;

  const ruleLines = [
    `[YASAL / ETİK UYARI]`,
    `${kb.scopeNotice}`,
    ``,
    `[KLİNİK KURAL ENJEKSİYONU - SEÇİCİ RETRIEVAL (KOL B)]`,
    `Hedef Kart: ${card.id} — ${card.title}`,
    `Gözlem Amacı: ${card.purpose}`,
    `Altın Standart Ölçek Dayanağı: ${card.goldStandardMapping.scale} — Madde ${card.goldStandardMapping.itemCode} (${card.goldStandardMapping.domain})`,
    `DSM-5-TR Eşleşmesi: ${card.dsm5Criteria}`,
    `Yetişkin Uygulama Kuralı: ${card.instruction}`,
    `Çocuk Başlangıç Şartı: ${card.preparation}`,
    `Gözlem Penceresi: ${card.pilotWindowSeconds} saniye`,
    `Geçerli Gözlem Koşulu: ${card.validityCriteria}`,
    `Hedef Yaş Bandı: ${bandInfo.label}`,
    `Hedef Davranış Çıktısı: ${risk.displayLabel}`,
  ];

  if (card.hasLatencyThreshold) {
    ruleLines.push(`Zamanlama Eşiği (${risk.displayLabel}):`);
    if (risk.category === 'TIPIK') {
      ruleLines.push(`  - UYARAN fazında çocuğun tepki gecikmesi (latencySeconds) en fazla ${bandInfo.typicalMaxDelaySec} saniye olmalı ve yetişkine net yönelme görülmelidir.`);
    } else if (risk.category === 'ATIPIK') {
      ruleLines.push(`  - UYARAN fazında çocuğun tepki gecikmesi (latencySeconds) en az ${bandInfo.atypicalMinDelaySec} saniye olmalı veya pencere boyunca hiç tepki verilmemelidir.`);
    } else {
      ruleLines.push(`  - UYARAN fazında çocuğun tepki gecikmesi (latencySeconds) ${bandInfo.typicalMaxDelaySec} ile ${bandInfo.atypicalMinDelaySec} saniye arasında (sınırda / tereddütlü) kalmalıdır.`);
    }
    ruleLines.push(`  - Ölçüm Referansı: latencySeconds, tepkiyi tetikleyen son uyarının başlangıcından çocuğun ilk yönelim hareketine kadar geçen süre olarak ölçülür.`);
  } else {
    ruleLines.push(`Zamanlama Kuralı: Bu davranış için anlık tepki gecikmesi (latency) aranmaz; ${card.pilotWindowSeconds} saniyelik gözlem penceresi içindeki niteliksel eylem doğruluğu ve hedef uygunluğu değerlendirilir.`);
  }

  ruleLines.push(
    `Aktif Klinik Ölçüt (${risk.displayLabel}):`,
    `  ${activeCriteria}`,
    `Geçersizlik Şartları (BU HATALARI KESİNLİKLE YAPMA):`,
    ...(card.invalidityConditions || []).map((cond) => `  * ${cond}`)
  );

  return {
    cardId: card.id,
    cardTitle: card.title,
    bandKey,
    bandLabel: bandInfo.label,
    riskCategory: risk.category,
    displayLabel: risk.displayLabel,
    hasLatencyThreshold: card.hasLatencyThreshold,
    ruleText: ruleLines.join('\n'),
    expectedAtypicalDelayMin: card.hasLatencyThreshold ? bandInfo.atypicalMinDelaySec : null,
    expectedTypicalDelayMax: card.hasLatencyThreshold ? bandInfo.typicalMaxDelaySec : null,
    clinicalSources: card.clinicalSources || [],
    goldStandardMapping: card.goldStandardMapping || null,
    dsm5Criteria: card.dsm5Criteria || null,
    activeCriteria,
  };
}

/**
 * Kol C (Full-Context): Bilgi tabanındaki 10 kartın, tüm klinik referansların,
 * tüm yaş bantlarının ve kural/geçersizlik şartlarının tamamını döner.
 */
function getFullContext() {
  const kb = loadKnowledgeBase();
  const lines = [
    `[YASAL / ETİK UYARI]`,
    `${kb.scopeNotice}`,
    ``,
    `[TÜM KLİNİK BİLGİ TABANI - FULL-CONTEXT (KOL C)]`,
    `Kapsam: 10 Davranış Kartı, Uluslararası Altın Standart Kaynaklar ve 3 Yaş Bandı Gelişimsel Eşikleri`,
    ``,
    `=== KLİNİK VE BİLİMSEL REFERANSLAR ===`,
  ];

  if (Array.isArray(kb.clinicalReferences)) {
    kb.clinicalReferences.forEach((ref) => {
      lines.push(`• [${ref.id}] ${ref.name} (${ref.authors}) — ${ref.role}`);
    });
    lines.push(``);
  }

  lines.push(`=== YAŞ BANTLARI VE EŞİKLERİ ===`);
  const targetBands = ['12-18', '18-24', '24-36'];
  targetBands.forEach((k) => {
    const b = kb.ageBands[k];
    if (b) {
      lines.push(`• ${b.label}: ${b.focus} | Tipik Maks Gecikme: ${b.typicalMaxDelaySec}s | Atipik Min Gecikme: ${b.atypicalMinDelaySec}s`);
      if (b.primaryReferences) {
        lines.push(`  Dayanaklar: ${b.primaryReferences.join(', ')}`);
      }
    }
  });

  lines.push(``);
  lines.push(`=== 10 DAVRANIŞ KARTI KATALOĞU ===`);

  kb.cards.forEach((c) => {
    lines.push(`[${c.id}] ${c.title}`);
    lines.push(`  - Özet: ${c.summary}`);
    lines.push(`  - Amaç: ${c.purpose}`);
    if (c.clinicalSources && c.clinicalSources.length) {
      lines.push(`  - Klinik Kaynaklar: ${c.clinicalSources.join('; ')}`);
    }
    if (c.goldStandardMapping) {
      lines.push(`  - Altın Standart: ${c.goldStandardMapping.scale} — Madde ${c.goldStandardMapping.itemCode} (${c.goldStandardMapping.domain})`);
    }
    if (c.dsm5Criteria) {
      lines.push(`  - DSM-5 Karşılığı: ${c.dsm5Criteria}`);
    }
    lines.push(`  - Yönerge: ${c.instruction}`);
    lines.push(`  - Hazırlık: ${c.preparation}`);
    lines.push(`  - Gözlem Penceresi: ${c.pilotWindowSeconds} saniye | Gecikme Eşiği Uygulanır mı: ${c.hasLatencyThreshold ? 'EVET' : 'HAYIR'}`);
    lines.push(`  - Geçerli Gözlem Koşulu: ${c.validityCriteria}`);
    lines.push(`  - Yaş Bantlarına Göre Ölçütler:`);
    targetBands.forEach((bk) => {
      const byAge = c.byAgeBand && c.byAgeBand[bk];
      if (byAge) {
        lines.push(`    [${bk} Ay] Tipik: ${byAge.typicalCriteria}`);
        lines.push(`    [${bk} Ay] Atipik: ${byAge.atypicalCriteria}`);
        lines.push(`    [${bk} Ay] Sınırda: ${byAge.borderlineCriteria}`);
      }
    });
    lines.push(`  - Geçersizlikler: ${(c.invalidityConditions || []).join('; ')}`);
    lines.push(``);
  });

  return {
    fullText: lines.join('\n'),
    totalCards: kb.cards.length,
    referencesCount: (kb.clinicalReferences || []).length,
    scopeNotice: kb.scopeNotice,
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
  validateKnowledgeBase,
  resolveAgeBandKey,
  normalizeCode,
  parseRiskProfile,
  getSelectiveRuleContext,
  getFullContext,
  timedRetrieval,
  ONT_MAP,
};
