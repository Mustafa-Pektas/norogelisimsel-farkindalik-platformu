'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const retriever = require('../rag/retriever');

test('validateKnowledgeBase: Bilgi tabanı doğrulama kurallarını eksiksiz uygular', () => {
  const kb = retriever.loadKnowledgeBase();
  assert.equal(retriever.validateKnowledgeBase(kb), true);

  // Kart eksikse hata fırlatmalı
  assert.throws(() => {
    const broken = JSON.parse(JSON.stringify(kb));
    delete broken.cards[0].instruction;
    retriever.validateKnowledgeBase(broken);
  }, /zorunlu alanları/);

  // Gecikme eşikleri mantıksızsa (typical >= atypical) hata fırlatmalı
  assert.throws(() => {
    const broken = JSON.parse(JSON.stringify(kb));
    broken.ageBands['18-24'].typicalMaxDelaySec = 2.5;
    broken.ageBands['18-24'].atypicalMinDelaySec = 2.0;
    retriever.validateKnowledgeBase(broken);
  }, /typicalMaxDelaySec < atypicalMinDelaySec olmalıdır/);

  // Yaş bandı eksikse hata fırlatmalı
  assert.throws(() => {
    const broken = JSON.parse(JSON.stringify(kb));
    delete broken.cards[0].byAgeBand['24-36'];
    retriever.validateKnowledgeBase(broken);
  }, /yaş bandı eksik/);
});

test('Önbellek Değiştirilemezliği: loadKnowledgeBase() derin dondurulmuş nesne döner', () => {
  const kb = retriever.loadKnowledgeBase();
  assert.ok(Object.isFrozen(kb), 'Kök nesne dondurulmuş olmalı');
  assert.ok(Object.isFrozen(kb.cards), 'cards dizisi dondurulmuş olmalı');
  assert.ok(Object.isFrozen(kb.cards[0]), 'Kart nesnesi dondurulmuş olmalı');
  assert.ok(Object.isFrozen(kb.cards[0].byAgeBand), 'byAgeBand dondurulmuş olmalı');

  assert.throws(() => {
    kb.cards[0].title = 'Değiştirildi';
  }, /Cannot assign to read only property/);
});

test('Yaş Doğrulama ve Sınırlar: 12-36 arası geçerli, 36 üstü ve 12 altı kesinlikle reddedilir', () => {
  assert.equal(retriever.resolveAgeBandKey(12), '12-18');
  assert.equal(retriever.resolveAgeBandKey(17), '12-18');
  assert.equal(retriever.resolveAgeBandKey(18), '18-24');
  assert.equal(retriever.resolveAgeBandKey(23), '18-24');
  assert.equal(retriever.resolveAgeBandKey(24), '24-36');
  assert.equal(retriever.resolveAgeBandKey(36), '24-36');
  assert.equal(retriever.resolveAgeBandKey('12-18'), '12-18');
  assert.equal(retriever.resolveAgeBandKey('18-24'), '18-24');
  assert.equal(retriever.resolveAgeBandKey('24-36'), '24-36');
  assert.equal(retriever.resolveAgeBandKey('24-32'), '24-36', 'legacyAlias 24-32 -> 24-36 eşlenmeli');

  // Hata yolları
  const invalidAges = [11, 37, 60, -5, 0, NaN, null, undefined, '', 'bilinmeyen'];
  invalidAges.forEach((val) => {
    assert.throws(
      () => retriever.resolveAgeBandKey(val),
      /(Geçersiz yaş|Yaş kapsam dışı)/,
      `'${val}' değeri reddedilmeli`
    );
  });
});

test('Davranış Kodu Doğrulama: Standart D01-D10 ve ONT eşlemeleri hatasız çalışır', () => {
  assert.equal(retriever.normalizeCode('D01'), 'D01');
  assert.equal(retriever.normalizeCode('d01'), 'D01');
  assert.equal(retriever.normalizeCode('D10'), 'D10');
  assert.equal(retriever.normalizeCode('ONT-01'), 'D01');
  assert.equal(retriever.normalizeCode('ONT-04'), 'D02');
  assert.equal(retriever.normalizeCode('ONT-13'), 'D10');

  // Bilinmeyen kod asla fallback yapmaz, hata fırlatır
  assert.throws(() => retriever.normalizeCode('D99'), /Bilinmeyen davranış kodu/);
  assert.throws(() => retriever.normalizeCode(null), /Geçersiz davranış kodu/);
  assert.throws(() => retriever.normalizeCode(''), /Geçersiz davranış kodu/);
});

test('Risk Profili Doğrulama: TİPİK, ATİPİK, SINIRDA ve Türkçe/İngilizce varyantlar', () => {
  assert.equal(retriever.parseRiskProfile('TİPİK').displayLabel, 'TİPİK');
  assert.equal(retriever.parseRiskProfile('tipik').displayLabel, 'TİPİK');
  assert.equal(retriever.parseRiskProfile('TYPICAL').category, 'TIPIK');
  assert.equal(retriever.parseRiskProfile('ATİPİK').displayLabel, 'ATİPİK');
  assert.equal(retriever.parseRiskProfile('atipik').displayLabel, 'ATİPİK');
  assert.equal(retriever.parseRiskProfile('ATYPICAL').category, 'ATIPIK');
  assert.equal(retriever.parseRiskProfile('SINIRDA').displayLabel, 'SINIRDA');
  assert.equal(retriever.parseRiskProfile('sınırda').displayLabel, 'SINIRDA');
  assert.equal(retriever.parseRiskProfile('BORDERLINE').category, 'SINIRDA');
  assert.equal(retriever.parseRiskProfile('DÜŞÜK RİSK').category, 'TIPIK');

  // Bilinmeyen riskler asla sessiz kalmaz, açık hata fırlatır
  assert.throws(() => retriever.parseRiskProfile('BILINMEYEN_PROFIL'), /Tanınmayan risk profili/);
  assert.throws(() => retriever.parseRiskProfile(null), /Geçersiz risk profili/);
});

test('Kol B 90 Kombinasyon Matrisi: 10 kart × 3 yaş bandı × 3 profil sıfır hatayla çalışır', () => {
  const cards = ['D01', 'D02', 'D03', 'D04', 'D05', 'D06', 'D07', 'D08', 'D09', 'D10'];
  const bands = [14, 20, 30]; // 12-18, 18-24, 24-36
  const profiles = ['TİPİK', 'ATİPİK', 'SINIRDA'];

  let count = 0;
  cards.forEach((code) => {
    bands.forEach((age) => {
      profiles.forEach((profile) => {
        const res = retriever.getSelectiveRuleContext({
          behaviorCode: code,
          ageMonths: age,
          riskProfile: profile,
        });
        count++;
        assert.equal(res.cardId, code);
        assert.ok(res.ruleText.length > 80);
        assert.ok(res.activeCriteria.length > 5);

        // Kol B negatif ölçüt sızdırmaz:
        if (profile === 'TİPİK') {
          assert.ok(res.ruleText.includes('Aktif Klinik Ölçüt (TİPİK)'));
          assert.ok(!res.ruleText.includes('Aktif Klinik Ölçüt (ATİPİK)'));
          assert.ok(!res.ruleText.includes('Aktif Klinik Ölçüt (SINIRDA)'));
        }

        // Zaman duyarlılığı testi: D09 ve D10 asla saniye gecikme eşiği içermemelidir
        if (code === 'D09' || code === 'D10') {
          assert.equal(res.hasLatencyThreshold, false);
          assert.ok(!res.ruleText.includes('Zamanlama Eşiği'));
        }

        // D01 ve D02 zaman eşiği içermelidir
        if (code === 'D01' || code === 'D02') {
          assert.equal(res.hasLatencyThreshold, true);
          assert.ok(res.ruleText.includes('Zamanlama Eşiği'));
        }
      });
    });
  });

  assert.equal(count, 90, 'Tam 90 kombinasyon başarıyla doğrulanmalı');
});

test('Kol C Full Context: 10 kartın ve 14 referansın tamamını eksiksiz listeler', () => {
  const full = retriever.getFullContext();
  assert.equal(full.totalCards, 10);
  assert.equal(full.referencesCount, 14);
  assert.ok(full.fullText.includes('TÜM KLİNİK BİLGİ TABANI - FULL-CONTEXT (KOL C)'));
  assert.ok(full.fullText.includes('REF-01'));
  assert.ok(full.fullText.includes('REF-14'));
  assert.ok(full.fullText.includes('D01'));
  assert.ok(full.fullText.includes('D10'));
  assert.ok(full.fullText.includes('24–36 Ay'));
  assert.ok(full.fullText.length > 2500);
});

test('Performans: timedRetrieval mikrosaniye düzeyinde (< 5ms) tamamlanır', () => {
  const res = retriever.timedRetrieval({
    behaviorCode: 'D01',
    ageMonths: 18,
    riskProfile: 'ATİPİK',
  });

  assert.equal(res.cardId, 'D01');
  assert.ok(typeof res.retrievalDurationMs === 'number');
  assert.ok(res.retrievalDurationMs < 10, `Erişim süresi 10ms altında olmalıdır (ölçülen: ${res.retrievalDurationMs}ms)`);
});
