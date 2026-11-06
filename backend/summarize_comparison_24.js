'use strict';
// Offline only: no fetch, provider SDK, dotenv or experiment runner import.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const template = require('./experiments/evaluation_template.json');
const validNumber = value => typeof value === 'number' && Number.isFinite(value) && value >= 0;
const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function stats(values) {
  const known = values.filter(validNumber);
  return { n: known.length, mean: known.length ? known.reduce((a, b) => a + b, 0) / known.length : null,
    min: known.length ? Math.min(...known) : null, max: known.length ? Math.max(...known) : null };
}
function aggregate(rows) {
  const successful = rows.filter(r => r.status === 'completed');
  return { planned: rows.length, completed: successful.length, failed: rows.filter(r => r.status === 'failed').length,
    promptTokens: stats(successful.map(r => r.promptTokens)), outputTokens: stats(successful.map(r => r.outputTokens)),
    retrievalDurationMs: stats(successful.map(r => r.retrievalDurationMs)),
    providerDurationMs: stats(successful.map(r => r.providerDurationMs)),
    endpointDurationMs: stats(successful.map(r => r.endpointDurationMs)),
    clientDurationMs: stats(successful.map(r => r.clientDurationMs)) };
}
function summarize(input, output) {
  input = path.resolve(input); output = path.resolve(output);
  const relative = path.relative(input, output);
  if (!relative || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative))) throw Error('Output must be outside original experiment');
  if (fs.existsSync(output)) throw Error('Summary directory must be new');
  const names = fs.readdirSync(input).filter(name => name.endsWith('.json')).sort();
  const before = Object.fromEntries(names.map(name => [name, digest(path.join(input, name))]));
  const read = name => JSON.parse(fs.readFileSync(path.join(input, name), 'utf8'));
  const manifest = read('manifest.json');
  if (manifest.trials.length !== 24 || new Set(manifest.trials.map(t => t.trialId)).size !== 24) throw Error('Expected 24 unique planned trials');
  const records = manifest.trials.map(t => {
    if (!/^[a-f0-9-]{36}$/.test(t.trialId)) throw Error('Invalid trial ID');
    const r = read(`${t.trialId}.json`);
    if (r.trialId !== t.trialId || r.inputId !== t.inputId || r.arm !== t.arm || r.repeat !== t.repeat ||
        JSON.stringify(r.request) !== JSON.stringify(t.request)) throw Error('Record/manifest mismatch');
    return r;
  });
  const rows = records.map(r => ({ trialId: r.trialId, inputId: r.inputId,
    behaviorIds: r.request.behaviors?.map(b => b.behaviorId).join(',') ?? r.request.behaviorId,
    ageGroup: r.request.ageGroup?.id ?? null, arm: r.arm, repeat: r.repeat, status: r.status,
    model: r.preview?.model ?? null, httpStatus: r.httpStatus ?? null,
    providerHttpStatus: r.error?.provider?.httpStatus ?? null, providerCode: r.error?.provider?.code ?? null,
    promptTokens: r.measurement?.promptTokens ?? null, outputTokens: r.measurement?.outputTokens ?? null,
    retrievalDurationMs: r.measurement?.retrievalDurationMs ?? null,
    providerDurationMs: r.measurement?.providerDurationMs ?? null,
    endpointDurationMs: r.measurement?.endpointDurationMs ?? null, clientDurationMs: r.clientDurationMs ?? null,
    rawResponsePresent: typeof r.rawResponse === 'string', validation: r.validation ?? null,
    protocolId: r.preview?.protocolId ?? null, sourceId: r.preview?.source?.sourceId ?? null,
    sourceSha256: r.preview?.source?.sha256 ?? null, startedAt: r.startedAt, endedAt: r.endedAt,
  }));
  const successful = records.filter(r => r.status === 'completed');
  if (successful.some(r => typeof r.rawResponse !== 'string' || !r.scenarioInput || r.validation !== 'structure_only')) throw Error('Completed record lacks validated response');
  const inputIds = [...new Set(rows.map(r => r.inputId))];
  const groups = inputIds.flatMap(inputId => ['A', 'B', 'C', 'D'].map(arm => ({ inputId, arm,
    ...aggregate(rows.filter(r => r.inputId === inputId && r.arm === arm)) })));
  const failures = rows.filter(r => r.status !== 'completed');
  const summary = { version: 'offline-comparison-summary-1', originalDirectory: input,
    originalGitRevision: manifest.gitRevision, originalServerGitRevision: manifest.serverGitRevision ?? null,
    overall: aggregate(rows), byInputAndArm: groups,
    byArm: ['A', 'B', 'C', 'D'].map(arm => ({ arm, ...aggregate(rows.filter(r => r.arm === arm)) })),
    quotaRejections: { count: failures.filter(r => r.providerHttpStatus === 429).length,
      providerDurationMs: stats(failures.filter(r => r.providerHttpStatus === 429).map(r => r.providerDurationMs)) },
    limitations: [
      'Means include completed records only, each with its own non-null n; quota rejections excluded.',
      'Null measurements remain unknown; empty CSV cells are null, not zero.',
      'Structural validation does not establish content quality, age appropriateness or clinical correctness.',
      'Client duration is runner HTTP round-trip, not mobile user elapsed time; nested durations must not be added.',
      'Fixed input/repeat/A-to-D order and unequal successful samples confound pooled arm comparisons.',
      'Server update/tests/previews are user reports, not independently verified by these offline records.',
    ] };
  fs.mkdirSync(output, { recursive: false });
  const save = (name, value) => fs.writeFileSync(path.join(output, name), JSON.stringify(value, null, 2), { flag: 'wx' });
  save('summary.json', summary); save('trials.json', rows); save('missing_successful_outputs.json', failures);
  const columns = Object.keys(rows[0]);
  const csv = value => value == null ? '' : `"${String(value).replaceAll('"', '""')}"`;
  fs.writeFileSync(path.join(output, 'trials.csv'), '\ufeff' + [columns.join(','), ...rows.map(r => columns.map(c => csv(r[c])).join(','))].join('\r\n'), { flag: 'wx' });
  fs.mkdirSync(path.join(output, 'reviews'));
  for (const r of successful) {
    save(`reviews/${r.trialId}.json`, { ...structuredClone(template), trialId: r.trialId,
      structuralValidation: r.validation, originalRecord: path.join(input, `${r.trialId}.json`),
      candidate: { inputId: r.inputId, arm: r.arm, repeat: r.repeat, request: r.request,
        model: r.preview.model, source: r.preview.source, protocolId: r.preview.protocolId,
        rawResponse: r.rawResponse, scenarioInput: r.scenarioInput } });
  }
  const f = value => value === null ? 'bilinmiyor' : value.toFixed(3);
  const metric = m => `${f(m.mean)} (n=${m.n})`;
  const text = [
    '# Çevrimdışı 24 deneme özeti', '',
    `${summary.overall.completed}/24 completed; ${summary.overall.failed}/24 failed. Model: ${[...new Set(rows.map(r => r.model))].join(', ')}.`, '',
    '## Girdi / kol / tekrar sonuçları', '',
    '| Girdi | Kol | Tekrar | Durum | Sağlayıcı HTTP/kod | Deneme kimliği |',
    '|---|---|---:|---|---|---|',
    ...rows.map(r => `| ${r.inputId} (${r.behaviorIds}, ${r.ageGroup}) | ${r.arm} | ${r.repeat} | ${r.status} | ${r.providerHttpStatus ?? '—'} ${r.providerCode ?? ''} | ${r.trialId} |`), '',
    '## Yalnız başarılı üretimlerin ortalamaları', '',
    'Süreler ms; parantez her alanın gerçek örnek sayısıdır. Kota reddi süreleri dahil değildir.', '',
    '| Girdi | Kol | Başarılı/plan | Giriş tokenı | Çıkış tokenı | Retrieval ms | Sağlayıcı ms |',
    '|---|---|---:|---|---|---|---|',
    ...groups.map(g => `| ${g.inputId} | ${g.arm} | ${g.completed}/${g.planned} | ${metric(g.promptTokens)} | ${metric(g.outputTokens)} | ${metric(g.retrievalDurationMs)} | ${metric(g.providerDurationMs)} |`), '',
    `Başarılı kayıt toplamı ${successful.length}. Genel giriş ${metric(summary.overall.promptTokens)}, çıkış ${metric(summary.overall.outputTokens)}, retrieval ${metric(summary.overall.retrievalDurationMs)} ms, sağlayıcı ${metric(summary.overall.providerDurationMs)} ms.`, '',
    `Kota reddi ayrı: ${summary.quotaRejections.count}, sağlayıcı bekleme ${metric(summary.quotaRejections.providerDurationMs)} ms. Bu süre üretim hızı değildir.`, '',
    '## Üretilemeyen çıktılar (yeniden çağrılmadı)', '',
    ...failures.map(r => `- ${r.inputId} / ${r.arm} / tekrar ${r.repeat}: ${r.trialId}; sağlayıcı ${r.providerHttpStatus ?? 'bilinmiyor'} ${r.providerCode ?? ''}.`), '',
    '## İnceleme ve sınırlar', '',
    `${successful.length} yanıt için reviews/ altında mevcut insan değerlendirme şablonu hazırlandı. Alanlar not_reviewed/null kalır; adayın özgün isteği, tam ham cevabı ve anlatısı birlikte bulunur. Otomatik içerik onayı yapılmadı.`, '',
    'Sabit A→D sırası, zaman/kota etkileri ve farklı girdi bileşimleri nedeniyle havuzlanmış kol ortalamaları tek başına RAG etkisini göstermez. D01/D02 küçük yaş uyarlaması uzman tarafından onaylanmış değildir. Başarı burada yalnız endpoint/şema durumudur; yanıt doğruluğu değildir.', '',
    'Token/süre null değerleri CSV içinde boş hücredir. Ayrıntılı n/min/max, backend/client süreleri summary.json içindedir; süreler iç içedir ve toplanmaz. Maliyet/cached/reasoning ölçümleri orijinal kayıtlarda bilinmiyorsa bilinmiyor kalır. Orijinal sunucu HEAD alanı null; kullanıcı sunucunun da73d30 güncellemesini,49 test ve12 önizlemeyi ayrıca bildirdi.', '',
  ].join('\n');
  fs.writeFileSync(path.join(output, 'SUMMARY.md'), text, { flag: 'wx' });
  const after = Object.fromEntries(names.map(name => [name, digest(path.join(input, name))]));
  const unchanged = JSON.stringify(before) === JSON.stringify(after) && JSON.stringify(names) === JSON.stringify(fs.readdirSync(input).filter(n => n.endsWith('.json')).sort());
  save('source_hashes.json', { algorithm: 'SHA256', before, after, originalsUnchanged: unchanged });
  if (!unchanged) throw Error('Original records changed during summary');
  return { output, summary, failures };
}
if (require.main === module) {
  const [input, output] = process.argv.slice(2);
  if (!input || !output || process.argv.length !== 4) throw Error('Usage: node summarize_comparison_24.js INPUT_DIRECTORY NEW_SUMMARY_DIRECTORY');
  const result = summarize(input, output);
  console.log(JSON.stringify({ output: result.output, overall: result.summary.overall, quotaRejections: result.summary.quotaRejections, missing: result.failures.map(r => `${r.inputId}/${r.arm}/${r.repeat}`) }, null, 2));
}
module.exports = { stats, aggregate, summarize };
