const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { plan, previewIdentity } = require('../run_comparison_24');
const { loadOriginals, verifyPreview, pacedTransport, complete } = require('../run_comparison_completion');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'complete-seven-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const source = path.join(root, 'original'); fs.mkdirSync(source);
  const manifest = { trials: plan(), frozen: {} };
  manifest.trials.forEach((trial, i) => {
    const preview = { arm: trial.arm, protocolId: 'p-' + trial.inputId, model: 'controlled', settings: { temperature: 0.2 },
      experiment: { revision: 'controlled' }, outputContract: 'controlled', sourceMode: trial.arm,
      source: { sourceId: trial.arm === 'D' ? 'json' : 'markdown', sha256: hash('source') },
      system: 'controlled instructions ' + trial.arm, user: JSON.stringify(trial.request) };
    const record = { ...trial, preview, status: i < 17 ? 'completed' : 'failed', httpStatus: i < 17 ? 200 : 502,
      error: i < 17 ? null : { provider: { httpStatus: 429, code: 'QUOTA_EXCEEDED' } } };
    manifest.frozen[trial.inputId] ??= { identity: previewIdentity(preview), sources: {} };
    manifest.frozen[trial.inputId].sources[trial.arm] = hash(JSON.stringify(preview.source));
    fs.writeFileSync(path.join(source, `${trial.trialId}.json`), JSON.stringify(record));
  });
  fs.writeFileSync(path.join(source, 'manifest.json'), JSON.stringify(manifest));
  const originals = loadOriginals(source);
  let clock = Date.now();
  return { root, source, originals, directory: path.join(root, 'new'), gitRevision: 'test', dirty: 'test',
    intervalMs: 1000, pacing: { now: () => clock, wait: async ms => { clock += ms; } } };
}
const success = { status: 200, body: { success: true, rawResponse: ' \ncontrolled raw\n ',
  scenarioInput: { commonStart: 'Controlled', alternatives: [] }, validation: 'structure_only',
  measurement: { providerStarted: true, providerFinished: true, promptTokens: null, outputTokens: null } } };
function transportFor(originals, generated) {
  return async body => {
    const source = originals.selected.find(r => r.arm === body.arm && r.inputId === originals.selected.find(r =>
      JSON.stringify(r.request) === JSON.stringify(body.request))?.inputId);
    if (!source) throw Error('A successful original was incorrectly sent');
    if (body.action === 'preview') return { status: 200, body: { success: true, request: source.request, preview: source.preview } };
    return generated(body, source);
  };
}
test('only seven quota failures are called; link new IDs, preserve 25 originals and resume without calls', async t => {
  const options = fixture(t); let calls = 0;
  const transport = transportFor(options.originals, async () => { calls++; return success; });
  await complete({ ...options, transport });
  assert.equal(calls, 7);
  const manifest = JSON.parse(fs.readFileSync(path.join(options.directory, 'manifest.json')));
  assert.equal(manifest.trials.length, 7);
  assert.deepEqual(manifest.trials.map(r => r.originalTrialId), options.originals.selected.map(r => r.trialId));
  for (const trial of manifest.trials) {
    assert.notEqual(trial.trialId, trial.originalTrialId);
    const record = JSON.parse(fs.readFileSync(path.join(options.directory, `${trial.trialId}.json`)));
    assert.equal(record.status, 'completed');
    assert.equal(record.originalRecordSha256, options.originals.hashes[`${record.originalTrialId}.json`]);
    assert.equal(record.rawResponse, success.body.rawResponse);
  }
  for (const [name, before] of Object.entries(options.originals.hashes)) assert.equal(hash(fs.readFileSync(path.join(options.source, name))), before);
  await complete({ ...options, transport: () => { throw Error('Resume must send no calls'); } });
  assert.equal(calls, 7);
});
test('every original condition mismatch stops before generation', async t => {
  for (const field of ['model', 'settings', 'protocolId', 'source', 'arm', 'system', 'user', 'outputContract', 'experiment']) {
    const options = fixture(t); let generated = 0;
    const base = transportFor(options.originals, async () => { generated++; return success; });
    await assert.rejects(complete({ ...options, transport: async body => {
      const response = structuredClone(await base(body));
      if (body.action === 'preview') response.body.preview[field] = 'changed';
      return response;
    } }), /conditions mismatch/);
    assert.equal(generated, 0, field);
  }
  const options = fixture(t);
  const original = options.originals.selected[0];
  assert.throws(() => verifyPreview({ request: { ...original.request, sceneContext: 'changed' }, preview: original.preview },
    { ...original, originalTrialId: original.trialId }, options.originals), /conditions mismatch/);
});
test('quota or transport uncertainty stops, preserves failure and never automatically retries', async t => {
  for (const disconnect of [false, true]) {
    const options = fixture(t); let calls = 0;
    const transport = transportFor(options.originals, async () => {
      calls++;
      if (disconnect) throw Error('controlled disconnect');
      return { status: 502, body: { success: false, providerError: { httpStatus: 429, code: 'QUOTA_EXCEEDED' },
        measurement: { providerStarted: true, providerFinished: true, promptTokens: null, outputTokens: null } } };
    });
    await assert.rejects(complete({ ...options, transport }), disconnect ? /uncertain/ : /quota rejected/);
    await assert.rejects(complete({ ...options, transport }), /remains halted/);
    assert.equal(calls, 1);
    const saved = fs.readdirSync(options.directory).filter(n => /^[a-f0-9-]{36}\.json$/.test(n));
    assert.equal(saved.length, 1);
    assert.equal(JSON.parse(fs.readFileSync(path.join(options.directory, saved[0]))).status, 'failed');
  }
});
test('interval is enforced for HTTP requests using controlled clock, invalid intervals fail', async () => {
  let clock = 0; const calls = [];
  const transport = pacedTransport(async () => { calls.push(clock); clock += 20; return success; }, 1500,
    { now: () => clock, wait: async ms => { clock += ms; } });
  await transport({ action: 'preview' }); await transport({ action: 'generate' }); await transport({ action: 'preview' });
  assert.deepEqual(calls, [0, 1520, 3040]);
  for (const bad of [0, -1, 1.5, NaN]) assert.throws(() => pacedTransport(async () => {}, bad), /Interval/);
});
