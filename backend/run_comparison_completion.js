'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { isDeepStrictEqual } = require('node:util');
const { execFileSync } = require('node:child_process');
const { run, httpTransport, previewIdentity, isProviderQuotaFailure } = require('./run_comparison_24');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

function loadOriginals(directory) {
  directory = path.resolve(directory);
  if (fs.existsSync(path.join(directory, 'runner.lock'))) throw Error('Original experiment may be active');
  const hashes = {};
  const read = name => {
    const bytes = fs.readFileSync(path.join(directory, name));
    hashes[name] = hash(bytes);
    return JSON.parse(bytes.toString('utf8'));
  };
  const manifest = read('manifest.json');
  if (manifest.trials.length !== 24 || new Set(manifest.trials.map(t => t.trialId)).size !== 24) throw Error('Expected original 24-trial manifest');
  const selected = [];
  for (const t of manifest.trials) {
    if (!/^[a-f0-9-]{36}$/.test(t.trialId)) throw Error('Invalid original ID');
    const r = read(`${t.trialId}.json`);
    if (r.trialId !== t.trialId || r.inputId !== t.inputId || r.arm !== t.arm || r.repeat !== t.repeat ||
      !isDeepStrictEqual(r.request, t.request)) throw Error('Original record/manifest mismatch');
    if (r.status === 'completed') continue;
    if (r.status !== 'failed' || !isProviderQuotaFailure(r)) throw Error('Only recorded quota failures may be completed');
    const frozen = manifest.frozen?.[r.inputId];
    if (!r.preview || !frozen || !isDeepStrictEqual(previewIdentity(r.preview), frozen.identity) ||
        hash(JSON.stringify(r.preview.source)) !== frozen.sources[r.arm]) throw Error('Original source/protocol inconsistent');
    selected.push(r);
  }
  if (selected.length !== 7) throw Error('Expected exactly seven original quota failures');
  return { directory, hashes, selected };
}
function assertUnchanged(originals) {
  for (const [name, expected] of Object.entries(originals.hashes)) {
    if (hash(fs.readFileSync(path.join(originals.directory, name))) !== expected) throw Error('Original records changed');
  }
}
function verifyPreview(body, trial, originals) {
  assertUnchanged(originals);
  const original = originals.selected.find(r => r.trialId === trial.originalTrialId);
  const a = body.preview, b = original?.preview;
  if (!a || !b || !isDeepStrictEqual(body.request, original.request) ||
      !isDeepStrictEqual(trial.request, original.request) || trial.arm !== original.arm ||
      !isDeepStrictEqual(previewIdentity(a), previewIdentity(b)) ||
      !isDeepStrictEqual(a.source, b.source) || a.arm !== b.arm || a.sourceMode !== b.sourceMode ||
      a.system !== b.system || a.user !== b.user) throw Error('Original conditions mismatch');
}
function pacedTransport(transport, intervalMs, { now = Date.now, wait = ms => new Promise(resolve => setTimeout(resolve, ms)), lastFinished = null } = {}) {
  if (!Number.isSafeInteger(intervalMs) || intervalMs < 1000 || intervalMs > 3600000) throw Error('Interval must be 1000..3600000 ms');
  return async body => {
    if (lastFinished !== null) {
      // Short chunks keep the wait interruptible and avoid one long blocking wait.
      while (now() - lastFinished < intervalMs) await wait(Math.min(1000, intervalMs - (now() - lastFinished)));
    }
    try { return await transport(body); }
    finally { lastFinished = now(); }
  };
}
async function complete({ source, directory, transport, intervalMs = 30000, gitRevision, dirty, pacing }) {
  source = path.resolve(source); directory = path.resolve(directory);
  const relative = path.relative(source, directory);
  if (!relative || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative))) throw Error('Output must be outside original experiment');
  const originals = loadOriginals(source);
  const trialPlan = originals.selected.map(r => ({ trialId: randomUUID(), originalTrialId: r.trialId,
    originalRecordSha256: originals.hashes[`${r.trialId}.json`], sourceExperiment: source,
    inputId: r.inputId, request: r.request, arm: r.arm, repeat: r.repeat }));
  const spec = { version: 'comparison-quota-completion-1', source, sourceHashes: originals.hashes,
    selectedOriginalTrialIds: originals.selected.map(r => r.trialId), intervalMs };
  let lastFinished = null;
  if (fs.existsSync(directory)) {
    for (const name of fs.readdirSync(directory).filter(n => /^[a-f0-9-]{36}\.json$/.test(n))) {
      const previous = JSON.parse(fs.readFileSync(path.join(directory, name), 'utf8'));
      const time = Date.parse(previous.endedAt);
      if (Number.isFinite(time)) lastFinished = Math.max(lastFinished ?? time, time);
    }
  }
  try {
    return await run({ directory, spec, trialPlan, gitRevision, dirty,
      transport: pacedTransport(transport, intervalMs, { lastFinished, ...pacing }),
      validatePreview: (body, trial) => verifyPreview(body, trial, originals) });
  } finally { assertUnchanged(originals); }
}
async function main() {
  const args = process.argv.slice(2);
  if (args.length === 3 && args[0] === '--plan' && args[1] === '--source') {
    const originals = loadOriginals(args[2]);
    console.log(JSON.stringify(originals.selected.map(r => ({ originalTrialId: r.trialId, inputId: r.inputId, arm: r.arm, repeat: r.repeat, model: r.preview.model })), null, 2));
    return;
  }
  if (args.length !== 9 || args[0] !== '--execute' || args[1] !== '--source' || args[3] !== '--server' ||
      args[5] !== '--output' || args[7] !== '--interval-ms') throw Error('Use --plan --source DIR or --execute --source DIR --server URL --output DIR --interval-ms MS');
  const payload = JSON.parse(fs.readFileSync(0, 'utf8'));
  if (typeof payload.accessKey !== 'string' || !payload.accessKey.trim()) throw Error('Session key required on stdin');
  const root = path.resolve(__dirname, '..');
  const gitRevision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  const dirty = hash(execFileSync('git', ['status', '--porcelain'], { cwd: root }));
  await complete({ source: args[2], directory: args[6], intervalMs: Number(args[8]), gitRevision, dirty,
    transport: httpTransport(args[4], payload.accessKey) });
  console.log('Completion run finished; inspect all seven new records. Originals unchanged.');
}
if (require.main === module) main().catch(() => { console.error('Completion stopped. Inspect preserved records; no automatic retry.'); process.exitCode = 1; });
module.exports = { loadOriginals, verifyPreview, pacedTransport, complete };
