'use strict';
// No dotenv, retries, legacy benchmark endpoint or provider SDK here.
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { execFileSync } = require('node:child_process');
const { performance } = require('node:perf_hooks');
const { validateRequest } = require('./scenario_input_generation');
const defaultSpec = require('./experiments/comparison_24.json');
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
function write(file, value) {
  const temp = `${file}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(value, null, 2), { mode: 0o600 });
  fs.renameSync(temp, file);
}
function plan(spec = defaultSpec) {
  if (spec.inputs.length !== 3 || spec.repeats !== 2 || JSON.stringify(spec.arms) !== '["A","B","C","D"]') throw Error('Invalid 24-trial plan');
  return spec.inputs.flatMap(input => {
    validateRequest(input.request);
    return Array.from({ length: spec.repeats }, (_, repeat) => spec.arms.map(arm => ({
      trialId: randomUUID(), inputId: input.id, request: input.request, arm, repeat: repeat + 1,
    }))).flat();
  });
}
function previewIdentity(preview) {
  return { protocolId: preview.protocolId, model: preview.model, settings: preview.settings,
    outputContract: preview.outputContract, experiment: preview.experiment };
}
function isProviderQuotaFailure(value) {
  const provider = value.providerError ?? value.error?.provider;
  const code = value.code ?? value.error?.code;
  return provider?.httpStatus === 429 || provider?.category === 'quota_or_rate_limit' ||
    ['QUOTA_EXCEEDED', 'RESOURCE_EXHAUSTED', 'RATE_LIMIT_EXCEEDED'].includes(provider?.code ?? code) ||
    (value.httpStatus === 429 && code !== 'local_capacity_exceeded');
}
async function run({ directory, transport, gitRevision, dirty, spec = defaultSpec, acknowledgeProviderStopped = false,
  trialPlan, validatePreview }) {
  fs.mkdirSync(directory, { recursive: true });
  // Exclusive ownership; a stale lock requires explicit human inspection/removal.
  const lock = path.join(directory, 'runner.lock');
  const fd = fs.openSync(lock, 'wx');
  fs.writeFileSync(fd, String(process.pid));
  try {
    const manifestFile = path.join(directory, 'manifest.json');
    let manifest;
    if (fs.existsSync(manifestFile)) {
      manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
      if (manifest.specHash !== hash(spec) || manifest.gitRevision !== gitRevision || manifest.dirty !== dirty) throw Error('Plan/Git state changed; use a new experiment directory');
    } else {
      if (fs.readdirSync(directory).some(name => name !== 'runner.lock')) throw Error('Use an empty experiment directory');
      manifest = { version: 'comparison-records-1', specHash: hash(spec), gitRevision, dirty,
        gitRevisionScope: 'local_runner', serverGitRevision: null,
        createdAt: new Date().toISOString(), trials: trialPlan ?? plan(spec), frozen: {} };
      write(manifestFile, manifest);
    }
    if (manifest.halted) {
      if (!acknowledgeProviderStopped) throw Error(`Experiment remains halted: ${manifest.halted.reason}`);
      manifest.haltHistory = [...(manifest.haltHistory ?? []), { ...manifest.halted, acknowledgedAt: new Date().toISOString() }];
      manifest.halted = null;
      write(manifestFile, manifest);
    }
    function halt(trialId, reason = 'provider_outcome_uncertain') {
      manifest.halted = { trialId, reason, at: new Date().toISOString() };
      write(manifestFile, manifest);
      if (reason === 'provider_quota_rejected') throw Error('Provider quota rejected; no further generation sent');
      if (reason === 'original_conditions_mismatch') throw Error('Original conditions mismatch; no further generation sent');
      throw Error('Provider outcome uncertain; no further generation sent');
    }
    for (const trial of manifest.trials) {
      const file = path.join(directory, `${trial.trialId}.json`);
      if (fs.existsSync(file)) {
        const prior = JSON.parse(fs.readFileSync(file, 'utf8'));
        if (prior.status === 'running') {
          write(file, { ...prior, status: 'interrupted', remoteOutcomeUncertain: true,
            error: 'Remote outcome unknown; not retried', endedAt: new Date().toISOString() });
          halt(trial.trialId);
        }
        // Also recognize records written by the earlier runner, before halted existed.
        const acknowledged = manifest.haltHistory?.some(entry => entry.trialId === trial.trialId && entry.acknowledgedAt);
        if (!acknowledgeProviderStopped && !acknowledged && isProviderQuotaFailure(prior)) {
          halt(trial.trialId, 'provider_quota_rejected');
        }
        if (!acknowledgeProviderStopped && !acknowledged && (prior.remoteOutcomeUncertain === true ||
            prior.error?.remoteOutcome === 'unknown' || prior.status === 'interrupted' ||
            prior.httpStatus === 504 || ['timeout', 'disconnected'].includes(prior.measurement?.outcome))) {
          halt(trial.trialId);
        }
        continue; // success, failure and ambiguous interruption are never automatically recalled.
      }
      const record = { version: 'comparison-trial-1', ...trial, gitRevision, dirty,
        gitRevisionScope: 'local_runner', serverGitRevision: null,
        startedAt: new Date().toISOString(), status: 'running', preview: null,
        rawResponse: null, validation: null, measurement: null, clientDurationMs: null,
        cachedTokens: null, reasoningTokens: null, cost: null, error: null,
        generationSent: false, remoteOutcomeUncertain: false, haltReason: null };
      write(file, record);
      try {
        const inspected = await transport({ request: trial.request, arm: trial.arm, action: 'preview' });
        if (inspected.status !== 200 || !inspected.body.success || !inspected.body.preview) {
          record.httpStatus = inspected.status;
          record.measurement = inspected.body.measurement ?? null;
          record.error = { code: inspected.body.code ?? 'preview_failed', message: inspected.body.error ?? null };
          throw Error('Preview failed');
        }
        record.preview = inspected.body.preview;
        if (validatePreview) {
          try { validatePreview(inspected.body, trial); }
          catch (_) {
            record.haltReason = 'original_conditions_mismatch';
            record.error = { code: 'original_conditions_mismatch' };
            throw Error('Original conditions mismatch');
          }
        }
        const identity = previewIdentity(record.preview);
        const frozen = manifest.frozen[trial.inputId];
        if (frozen && JSON.stringify(frozen.identity) !== JSON.stringify(identity)) throw Error('Model/settings/protocol/source changed; no generation sent');
        if (!frozen) manifest.frozen[trial.inputId] = { identity, sources: {} };
        const sourceHash = hash(record.preview.source);
        const sources = manifest.frozen[trial.inputId].sources;
        if (sources[trial.arm] && sources[trial.arm] !== sourceHash) throw Error('Arm source changed; no generation sent');
        sources[trial.arm] = sourceHash;
        write(manifestFile, manifest);
        write(file, record);
        const started = performance.now();
        let response;
        try {
          record.generationSent = true;
          write(file, record);
          response = await transport({ request: trial.request, arm: trial.arm, action: 'generate', protocolId: record.preview.protocolId });
        } finally { record.clientDurationMs = performance.now() - started; }
        record.httpStatus = response.status;
        record.rawResponse = response.body.rawResponse ?? null;
        record.validation = response.body.validation ?? null;
        record.measurement = response.body.measurement ?? null;
        record.scenarioInput = response.body.scenarioInput ?? null;
        record.comparison = response.body.comparison ?? null;
        record.status = response.status === 200 && response.body.success && record.scenarioInput && record.validation === 'structure_only' ? 'completed' : 'failed';
        record.error = record.status === 'failed' ? { code: response.body.code ?? null, message: response.body.error ?? null,
          outcome: record.measurement?.outcome ?? null, provider: response.body.providerError ?? null } : null;
        if (record.status === 'failed' && isProviderQuotaFailure({ ...response.body, httpStatus: response.status })) {
          record.haltReason = 'provider_quota_rejected';
        }
        record.remoteOutcomeUncertain = response.status === 504 ||
          record.measurement?.outcome === 'timeout' || record.measurement?.outcome === 'disconnected' ||
          response.body.code === 'local_capacity_exceeded' ||
          (record.measurement?.providerStarted === true && record.measurement?.providerFinished !== true) ||
          (record.status === 'failed' && !record.measurement);
      } catch (_) {
        // Never persist network exception URLs/headers or secrets.
        record.status = 'failed';
        record.error ??= { code: 'transport_or_protocol_error', remoteOutcome: 'unknown' };
        record.remoteOutcomeUncertain = record.generationSent;
      }
      record.endedAt = new Date().toISOString();
      write(file, record);
      if (record.haltReason) halt(trial.trialId, record.haltReason);
      if (record.remoteOutcomeUncertain) halt(trial.trialId);
    }
    return manifest;
  } finally { fs.closeSync(fd); fs.unlinkSync(lock); }
}
function httpTransport(server, key) {
  const base = new URL(server);
  if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password || base.search || base.hash) throw Error('Invalid server address');
  return async body => {
    const response = await fetch(new URL('/api/compare-scenario', base), {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...(key ? { Authorization: `Bearer ${key}` } : {}) },
      body: JSON.stringify(body), signal: AbortSignal.timeout(150000), redirect: 'error',
    });
    return { status: response.status, body: await response.json() };
  };
}
async function main() {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--plan') { console.log(JSON.stringify(plan(), null, 2)); return; }
  if (args.length !== 5 || args[0] !== '--execute' || args[1] !== '--server' || args[3] !== '--output') throw Error('Use --plan or --execute --server URL --output DIRECTORY');
  const { createInterface } = require('node:readline');
  // One JSON line piped from PowerShell; no key in argv, files, logs or environment.
  const rl = createInterface({ input: process.stdin, terminal: false });
  let key = '';
  for await (const line of rl) { key = JSON.parse(line).accessKey; break; }
  if (typeof key !== 'string' || !key.trim()) throw Error('Session key required on stdin');
  const root = path.resolve(__dirname, '..');
  const gitRevision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  // Bind resume to actual tracked AND untracked source state; never read .env.
  const dirty = hash(execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }));
  await run({ directory: path.resolve(args[4]), transport: httpTransport(args[2], key), gitRevision, dirty });
  console.log('Experiment finished. Inspect all 24 trial records, including failures.');
}
if (require.main === module) main().catch(() => { console.error('Experiment stopped; inspect preserved records. No automatic retry.'); process.exitCode = 1; });
module.exports = { plan, run, httpTransport, previewIdentity, isProviderQuotaFailure };
