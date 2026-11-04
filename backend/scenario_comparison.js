// 223bc7d: A/B/C ve 26 sahne deneyinin uyarlaması. Klinik eşik/ikinci KB alınmadı.
const { createHash } = require('node:crypto');
const { InputError, validateRequest, narrativeSchema, narrativeSchemaFor, narrativeSettings, narrativeContract, buildNarrativePrompts, validateNarrative } = require('./scenario_input_generation');
const { validateFSMContinuity } = require('./validators/fsm_validator');
const retriever = require('./rag/retriever');
const settings = narrativeSettings;
const string = { type: 'string' };
const legacySchema = { type: 'object', properties: { title: string, summary: string,
  scenes: { type: 'array', items: { type: 'object', properties: {
    phase: { type: 'string', enum: ['TABAN', 'UYARAN', 'KAPANIS'] },
    videoPrompt: string, dialogue: { type: 'string', nullable: true },
    speaker: { type: 'string', enum: ['ADULT', 'CHILD'], nullable: true }, startState: string, endState: string,
  }, required: ['phase', 'videoPrompt', 'startState', 'endState'] } } }, required: ['title', 'summary', 'scenes'] };
const text = value => typeof value === 'string' && value.trim().length > 0;
function check(ok, message) { if (!ok) throw new InputError(message); }
function fields(value, allowed) {
  return value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).every(k => allowed.includes(k));
}
function validateComparisonRequest(body) {
  check(fields(body, ['request', 'arm', 'action', 'protocolId']), 'Karşılaştırma alanları geçersiz.');
  const request = validateRequest(body.request);
  check(['A', 'B', 'C', 'D'].includes(body.arm), 'A, B, C veya D deney kolu seçilmelidir.');
  check(['preview', 'generate'].includes(body.action), 'Karşılaştırma eylemi geçersiz.');
  if (body.action === 'generate') check(typeof body.protocolId === 'string' && /^[a-f0-9]{64}$/.test(body.protocolId),
    'Üretimden önce karşılaştırma istemlerini inceleyin.');
  return { request, arm: body.arm, action: body.action, protocolId: body.protocolId };
}
function prepareComparison(trial, card, modelName) {
  const sourceMode = {
    A: 'Temel istem: davranış adları ve ortak güvenlik; ek kart metni yok.',
    B: 'Seçilen bütün kartların tam metni ve ortak kart kuralları (Markdown).',
    C: 'Kanonik Markdown dosyasının tüm kartları ve ortak kuralları (Full-Text).',
    D: 'Yeni Klinik JSON RAG: Ontoloji ve yaş grubuna göre seçici kural enjeksiyonu.',
  }[trial.arm];
  let sourceText;
  if (trial.arm === 'A') {
    sourceText = '';
  } else if (trial.arm === 'B') {
    sourceText = `${card.commonRules}\n${card.section}`;
  } else if (trial.arm === 'C') {
    sourceText = card.fullText;
  } else if (trial.arm === 'D') {
    const codes = trial.request.behaviors && trial.request.behaviors.length
      ? trial.request.behaviors.map(b => b.behaviorId)
      : [trial.request.behaviorId || 'D01'];
    let ageMonths = 24;
    if (trial.request.ageMonths) {
      ageMonths = trial.request.ageMonths;
    } else if (trial.request.ageGroup === '12_18') {
      ageMonths = 15;
    } else if (trial.request.ageGroup === '18_24') {
      ageMonths = 21;
    } else if (trial.request.ageGroup === '24_36') {
      ageMonths = 30;
    }
    const activeRules = codes.map(c => {
      const sel = retriever.getSelectiveRuleContext({
        behaviorCode: c,
        ageMonths,
        riskProfile: 'ATIPIK',
      });
      return sel.ruleText;
    });
    sourceText = activeRules.join('\n\n');
  }
  const base = buildNarrativePrompts(trial.request, card, { sourceText: '' }).system;
  const protocolId = createHash('sha256').update(JSON.stringify({ revision: narrativeContract,
    request: trial.request, cardHash: card.sha256, modelName, settings, base, schema: narrativeSchemaFor(trial.request),
  })).digest('hex');
  if (trial.action === 'generate' && trial.protocolId !== protocolId) {
    throw new InputError('Girdi, kaynak veya model ayarları değişti; istem önizlemesini yenileyin.', 409);
  }
  const system = buildNarrativePrompts(trial.request, card, { sourceText }).system;
  return { arm: trial.arm, protocolId, outputContract: narrativeContract, model: modelName, settings, sourceMode,
    source: { sourceId: card.sourceId, cardVersion: card.version, sha256: card.sha256,
      behaviors: card.selectedCards.map(ref => ({ behaviorId: ref.behaviorId, cardVersion: ref.cardVersion })) },
    system, user: JSON.stringify(trial.request) };
}
function validateLegacyComparisonOutput(raw) {
  let result;
  try { result = JSON.parse(raw); } catch (_) { throw new InputError('Deney cevabı geçerli JSON değil; ham cevap korundu.', 502); }
  const fail = message => { throw new InputError(message, 502); };
  if (!fields(result, ['title', 'summary', 'scenes']) || !text(result.title) || !text(result.summary) ||
      !Array.isArray(result.scenes) || result.scenes.length !== 26) fail('Deney cevabı 26 sahne sözleşmesini karşılamıyor.');
  result.scenes.forEach((scene, i) => {
    const phase = i < 6 ? 'TABAN' : i < 17 ? 'UYARAN' : 'KAPANIS';
    if (!fields(scene, ['phase', 'videoPrompt', 'dialogue', 'speaker', 'startState', 'endState']) ||
        scene.phase !== phase || !['videoPrompt', 'startState', 'endState'].every(k => text(scene[k])) ||
        (scene.dialogue != null && !text(scene.dialogue)) ||
        (scene.speaker != null && !['ADULT', 'CHILD'].includes(scene.speaker)) ||
        (scene.dialogue != null && !scene.speaker)) fail(`Deney sahnesi ${i + 1} eksik/geçersiz.`);
  });
  return result;
}
// Mobildeki mevcut 26 sahne çıktı araçlarının sıralama/süre alanları türetilir.
// Ham model metni ayrı rawResponse alanında aynen korunur; 8 saniye plan süresidir.
function finalizeLegacyComparisonOutput(result) {
  const time = seconds => `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
  return { ...result, scenes: result.scenes.map((scene, index) => ({
    ...scene,
    id: index + 1,
    time: time(index * 8),
    durationSec: 8,
    veoPrompt: scene.videoPrompt,
  })) };
}
// Etkin bütün kollar aynı anlatı sözleşmesini doğrular; eski doğrusal işlevler yalnız geçmiş veriler içindir.
function validateComparisonOutput(raw, request) { return validateNarrative(raw, request); }
function finalizeComparisonOutput(result) { return result; }
module.exports = { settings, schema: narrativeSchema, validateComparisonRequest, prepareComparison,
  validateComparisonOutput, finalizeComparisonOutput,
  legacySchema, validateLegacyComparisonOutput, finalizeLegacyComparisonOutput, validateFSMContinuity };
