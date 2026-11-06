const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { plan } = require('../run_comparison_24');
const { stats, aggregate, summarize } = require('../summarize_comparison_24');

test('offline statistics exclude quota failures and nulls without treating unknown tokens as zero', () => {
  assert.deepEqual(stats([null, undefined, 0, 10]), { n: 2, mean: 5, min: 0, max: 10 });
  assert.equal(stats([null]).mean, null);
  const result = aggregate([
    { status: 'completed', promptTokens: 10, providerDurationMs: 2000 },
    { status: 'completed', promptTokens: null, providerDurationMs: 4000 },
    { status: 'failed', promptTokens: null, providerDurationMs: 100 },
  ]);
  assert.equal(result.promptTokens.n, 1);
  assert.equal(result.promptTokens.mean, 10);
  assert.equal(result.providerDurationMs.mean, 3000);
  assert.equal(result.providerDurationMs.n, 2);
});

test('offline export keeps 24 originals byte-identical and prepares only 17 unreviewed response forms', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'summary-24-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const input = path.join(root, 'original'); fs.mkdirSync(input);
  const output = path.join(root, 'summary');
  const trials = plan();
  fs.writeFileSync(path.join(input, 'manifest.json'), JSON.stringify({ trials, gitRevision: 'controlled' }));
  trials.forEach((trial, i) => {
    const success = i < 17;
    const record = { ...trial, status: success ? 'completed' : 'failed',
      rawResponse: success ? ' \nraw response\n ' : null,
      scenarioInput: success ? { commonStart: 'Controlled' } : null,
      validation: success ? 'structure_only' : null,
      preview: { model: 'fake', source: { sourceId: 'controlled', sha256: 'abc' }, protocolId: 'controlled' },
      measurement: { promptTokens: success ? 10 : null, outputTokens: success ? 20 : null,
        retrievalDurationMs: 1, providerDurationMs: success ? 2000 : 100 },
      error: success ? null : { provider: { httpStatus: 429, code: 'QUOTA_EXCEEDED' } } };
    fs.writeFileSync(path.join(input, `${trial.trialId}.json`), JSON.stringify(record));
  });
  const result = summarize(input, output);
  assert.equal(result.summary.overall.completed, 17);
  assert.equal(result.summary.quotaRejections.count, 7);
  assert.equal(result.summary.overall.providerDurationMs.mean, 2000);
  const hashes = JSON.parse(fs.readFileSync(path.join(output, 'source_hashes.json')));
  assert.equal(hashes.originalsUnchanged, true);
  assert.equal(Object.keys(hashes.before).length, 25);
  assert.equal(fs.readdirSync(path.join(output, 'reviews')).length, 17);
  const form = JSON.parse(fs.readFileSync(path.join(output, 'reviews', `${trials[0].trialId}.json`)));
  assert.equal(form.reviewStatus, 'not_reviewed');
  assert.equal(form.ageAppropriateness.assessment, null);
  assert.equal(form.candidate.rawResponse, ' \nraw response\n ');
  assert.equal(result.failures.length, 7);
  assert.throws(() => summarize(input, output), /must be new/);
  assert.throws(() => summarize(input, path.join(input, 'nested')), /outside original/);
});
