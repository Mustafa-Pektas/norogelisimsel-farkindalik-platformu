const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const { plan, run } = require('../run_comparison_24');
const { createScenarioInputHandler } = require('../scenario_input_generation');

function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'comparison-24-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}
function fakeTransport(generate) {
  const handler = createScenarioInputHandler({ comparison: true, modelName: 'controlled-only', generate: async (model, prompts) => {
    const generated = await generate(model, prompts);
    const ids = JSON.parse(prompts.user).behaviors.map(b => b.behaviorId);
    const text = value => value === raw ? ' \n' + JSON.stringify({ ...JSON.parse(raw), structure: 'branched', commonBehaviorIds: ids,
      alternatives: JSON.parse(raw).alternatives.map(a => ({ ...a, behaviorIds: ids })) }) + '\n ' : value;
    return typeof generated === 'string' ? text(generated) : { ...generated, text: text(generated.text) };
  } });
  return async body => {
    const res = new EventEmitter();
    res.statusCode = 200;
    res.status = value => { res.statusCode = value; return res; };
    res.json = value => { res.body = value; };
    await handler({ body }, res);
    return { status: res.statusCode, body: res.body };
  };
}
const raw = ' \n' + JSON.stringify({ commonStart: 'Ortak başlangıç.', alternatives: [
  { title: 'Bir', continuation: 'İlk devam.', ending: 'İlk bitiş.' },
  { title: 'İki', continuation: 'İkinci devam.', ending: 'İkinci bitiş.' },
] }) + '\n ';
const records = directory => fs.readdirSync(directory).filter(n => /^[a-f0-9-]{36}\.json$/.test(n))
  .map(n => JSON.parse(fs.readFileSync(path.join(directory, n), 'utf8')));

test('connection failure halts the experiment and resume sends no further calls', async t => {
  const directory = fixture(t);
  const previewTransport = fakeTransport(async () => { throw Error('Provider must not run'); });
  let calls = 0;
  const transport = async body => {
    if (body.action === 'preview') return previewTransport(body);
    calls++;
    if (calls === 1) throw Error('secret network detail');
    return { status: 504, body: { success: false, error: 'Controlled timeout',
      measurement: { outcome: 'timeout', promptTokens: null, outputTokens: null, providerDurationMs: null } } };
  };
  const options = { directory, transport, gitRevision: 'test', dirty: 'test' };
  await assert.rejects(run(options), /uncertain/);
  const saved = records(directory);
  assert.equal(saved.length, 1);
  assert.ok(saved.every(r => r.status === 'failed'));
  assert.equal(saved[0].remoteOutcomeUncertain, true);
  assert.ok(!JSON.stringify(saved).includes('secret network detail'));
  await assert.rejects(run(options), /remains halted/);
  assert.equal(calls, 1);
});

test('504 and local capacity rejection stop before the next arm; terminal provider error may continue', async t => {
  for (const response of [
    { status: 504, body: { success: false, measurement: { outcome: 'timeout', providerStarted: true, providerFinished: false } } },
    { status: 429, body: { success: false, code: 'local_capacity_exceeded', measurement: { outcome: 'capacity_rejected' } } },
  ]) {
    const directory = fixture(t);
    let calls = 0;
    const preview = fakeTransport(async () => { throw Error('Provider must not run'); });
    const options = { directory, gitRevision: 'test', dirty: 'test', transport: async body => {
      if (body.action === 'preview') return preview(body);
      calls++;
      return response;
    } };
    await assert.rejects(run(options), /uncertain/);
    assert.equal(calls, 1);
    await assert.rejects(run(options), /remains halted/);
    assert.equal(calls, 1);
    assert.equal(records(directory)[0].httpStatus, response.status);
  }
});

test('24 unique trials cover three groups, four arms and two identical-input repeats', () => {
  const trials = plan();
  assert.equal(trials.length, 24);
  assert.equal(new Set(trials.map(t => t.trialId)).size, 24);
  assert.deepEqual([...new Set(trials.map(t => t.request.ageGroup.id))], ['12_18', '18_24', '24_36']);
  for (const id of new Set(trials.map(t => t.inputId))) {
    const group = trials.filter(t => t.inputId === id);
    assert.equal(new Set(group.map(t => JSON.stringify(t.request))).size, 1);
    for (const arm of ['A', 'B', 'C', 'D']) assert.equal(group.filter(t => t.arm === arm).length, 2);
  }
});

test('real comparison handler + fake provider: preserve all 24 records, sources, raw text and null usage; resume sends zero calls', async t => {
  const directory = fixture(t);
  let calls = 0;
  const transport = fakeTransport(async () => { calls++; return { text: raw, usage: { promptTokens: 123, outputTokens: 45 } }; });
  const options = { directory, transport, gitRevision: 'controlled', dirty: 'controlled' };
  await run(options);
  assert.equal(calls, 24);
  const saved = records(directory);
  assert.equal(saved.length, 24);
  for (const record of saved) {
    assert.equal(record.status, 'completed');
    assert.ok(record.rawResponse.startsWith(' \n') && record.rawResponse.endsWith('\n '));
    assert.deepEqual(JSON.parse(record.rawResponse), record.scenarioInput);
    assert.equal(record.validation, 'structure_only');
    assert.equal(record.measurement.promptTokens, 123);
    assert.equal(record.measurement.outputTokens, 45);
    assert.ok(record.measurement.providerDurationMs >= 0);
    assert.match(record.preview.source.sha256, /^[a-f0-9]{64}$/);
    assert.match(record.preview.protocolId, /^[a-f0-9]{64}$/);
    assert.equal(record.cachedTokens, null);
    assert.equal(record.cost, null);
  }
  const before = saved.map(r => fs.readFileSync(path.join(directory, `${r.trialId}.json`), 'utf8'));
  await run({ ...options, transport: () => { throw Error('Resume must not send even a preview'); } });
  assert.equal(calls, 24);
  saved.forEach((r, i) => assert.equal(fs.readFileSync(path.join(directory, `${r.trialId}.json`), 'utf8'), before[i]));
});

test('provider/validation/transport failures stay recorded, unknown tokens null and no retry', async t => {
  const directory = fixture(t);
  let calls = 0;
  const transport = fakeTransport(async () => {
    calls++;
    if (calls === 1) throw Error('controlled provider error');
    return calls === 2 ? ' malformed raw ' : raw;
  });
  const options = { directory, transport, gitRevision: 'test', dirty: 'test' };
  await run(options);
  const saved = records(directory);
  assert.equal(saved.filter(r => r.status === 'failed').length, 2);
  assert.ok(saved.some(r => r.rawResponse === ' malformed raw ' && r.measurement.outcome === 'validation_error'));
  assert.ok(saved.some(r => r.measurement.outcome === 'provider_error'));
  assert.ok(saved.every(r => r.measurement.promptTokens === null));
  await run(options);
  assert.equal(calls, 24);
});

test('interrupted running record is never recalled; remaining trials resume; changed protocol prevents generation', async t => {
  const directory = fixture(t);
  let calls = 0;
  const transport = fakeTransport(async () => { calls++; return raw; });
  await run({ directory, transport, gitRevision: 'test', dirty: 'test' });
  const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json'), 'utf8'));
  const first = path.join(directory, `${manifest.trials[0].trialId}.json`);
  const firstRecord = JSON.parse(fs.readFileSync(first, 'utf8'));
  fs.writeFileSync(first, JSON.stringify({ ...firstRecord, status: 'running' }));
  const last = manifest.trials.at(-1);
  fs.unlinkSync(path.join(directory, `${last.trialId}.json`));
  await assert.rejects(run({ directory, transport, gitRevision: 'test', dirty: 'test' }), /uncertain/);
  assert.equal(calls, 24);
  assert.equal(JSON.parse(fs.readFileSync(first, 'utf8')).status, 'interrupted');
  await run({ directory, transport, gitRevision: 'test', dirty: 'test', acknowledgeProviderStopped: true });
  assert.equal(calls, 25);
  fs.unlinkSync(path.join(directory, `${last.trialId}.json`));
  await run({ directory, gitRevision: 'test', dirty: 'test', transport: async body => {
    assert.equal(body.action, 'preview');
    const response = await transport(body);
    response.body.preview.model = 'changed';
    return response;
  } });
  assert.equal(calls, 25);
  assert.equal(JSON.parse(fs.readFileSync(path.join(directory, `${last.trialId}.json`), 'utf8')).status, 'failed');
});
