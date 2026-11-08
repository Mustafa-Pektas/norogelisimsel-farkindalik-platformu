// Experimental local CPU jobs. No Gemini route, provider fallback, queue or user-supplied executable.
const fs = require('node:fs');
const path = require('node:path');
const { createHash, randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const multer = require('multer');
const { isDeepStrictEqual } = require('node:util');
const { fastMainResult } = require('./d01_fast_result');
const { backendTiming } = require('./pilot_timing');
const MAX_VIDEO = 25 * 1024 * 1024;
const RETENTION = 24 * 60 * 60 * 1000;
const MAX_TERMINAL = 10;
const TERMINAL = new Set(['completed', 'failed', 'interrupted']);
const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function write(file, data) {
  const temp = file + '.tmp';
  fs.writeFileSync(temp, JSON.stringify(data), { mode: 0o600 });
  fs.renameSync(temp, file);
}
function alive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; } catch (e) { return e.code !== 'ESRCH'; }
}
function createPilotJobs(env, { runner = spawn, profiles: suppliedProfiles, now = Date.now,
  timers = { setTimeout, clearTimeout } } = {}) {
  const timing = backendTiming(env);
  const cpuThreads = env.PILOT_D01_CPU_THREADS;
  if (cpuThreads !== undefined && !['1', '2', '4'].includes(cpuThreads)) {
    throw new Error('PILOT_D01_CPU_THREADS must be 1, 2 or 4, or omitted');
  }
  const required = ['PILOT_D01_PYTHON', 'PILOT_D01_WEIGHTS', 'PILOT_D01_OFFICIAL_SOURCE', 'PILOT_D01_JOBS_DIR'];
  for (const key of required) if (!env[key] || !path.isAbsolute(env[key])) throw new Error(`${key} requires an absolute server path`);
  for (const key of required.slice(0, 3)) if (!fs.existsSync(env[key])) throw new Error(`${key} is unavailable`);
  if (!fs.statSync(env.PILOT_D01_PYTHON).isFile() || !fs.statSync(env.PILOT_D01_WEIGHTS).isFile() || !fs.statSync(env.PILOT_D01_OFFICIAL_SOURCE).isDirectory()) throw new Error('Invalid pilot runtime path types');
  const cli = path.resolve(__dirname, '../research/d01/pilot_cli.py');
  const protocol = path.resolve(__dirname, '../research/d01/parameters/pilot_v1.json');
  if (!fs.existsSync(cli) || !fs.existsSync(protocol)) throw new Error('Pilot research runtime is not installed');
  const profiles = suppliedProfiles || JSON.parse(fs.readFileSync(path.join(__dirname, 'resources/d01_pilot_profiles.json'))).profiles;
  const root = path.resolve(env.PILOT_D01_JOBS_DIR);
  fs.mkdirSync(root, { recursive: true, mode: 0o700 });
  const marker = path.join(root, '.d01-pilot-owned');
  if (!fs.existsSync(marker)) {
    if (fs.readdirSync(root).length) throw new Error('Pilot jobs directory must be empty or marked');
    fs.writeFileSync(marker, 'd01-pilot-jobs-1', { flag: 'wx', mode: 0o600 });
  }
  const lock = path.join(root, '.owner.lock');
  if (fs.existsSync(lock)) {
    const pid = JSON.parse(fs.readFileSync(lock)).pid;
    if (alive(pid)) throw new Error('Pilot job directory already owned by a live process');
    fs.unlinkSync(lock);
  }
  const jobs = new Map(); let active = null; let closed = false;
  for (const name of fs.readdirSync(root)) {
    if (!ID.test(name)) continue;
    const dir = path.join(root, name);
    if (!fs.lstatSync(dir).isDirectory()) continue;
    const file = path.join(dir, 'job.json');
    if (!fs.existsSync(file)) throw new Error('Unrecognized pilot job directory; operator inspection required');
    const job = JSON.parse(fs.readFileSync(file));
    if (job.jobId !== name) throw new Error('Invalid persisted pilot job identity');
    if (!TERMINAL.has(job.status)) {
      if (alive(job.childPid)) throw new Error('An orphan pilot process may still be running; operator inspection required');
      job.status = 'interrupted'; job.code = 'backend_restarted'; job.updatedAt = now(); write(file, job);
    }
    jobs.set(name, job);
  }
  fs.writeFileSync(lock, JSON.stringify({ pid: process.pid }), { flag: 'wx', mode: 0o600 });
  const dirOf = id => path.join(root, id);
  function save(job) { job.updatedAt = now(); write(path.join(dirOf(job.jobId), 'job.json'), job); }
  function cleanup() {
    const terminal = [...jobs.values()].filter(j => TERMINAL.has(j.status)).sort((a, b) => b.updatedAt - a.updatedAt);
    for (let i = 0; i < terminal.length; i++) {
      const job = terminal[i];
      if (now() - job.updatedAt < RETENTION && i < MAX_TERMINAL) continue;
      const dir = dirOf(job.jobId);
      if (path.dirname(fs.realpathSync(dir)) !== fs.realpathSync(root) || !fs.lstatSync(dir).isDirectory()) throw new Error('Unsafe pilot cleanup target');
      fs.rmSync(dir, { recursive: true }); jobs.delete(job.jobId);
    }
  }
  cleanup();
  function status(id) {
    cleanup();
    const j = jobs.get(id);
if (!j) return null;
    let processedFrames = null;
    let totalFrames = null;
    try {
      const stateFile = path.join(dirOf(id), 'run', 'state.json');
      if (fs.existsSync(stateFile)) {
        const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
        if (Number.isInteger(state.processed_frames)) processedFrames = state.processed_frames;
        const total = state.video_metadata?.decoded_frame_count ?? state.video_metadata?.declared_frame_count ?? state.video_metadata?.frame_count;
        if (Number.isInteger(total)) totalFrames = total;
      }
    } catch {}
    return {
      jobId: id,
      status: j.status,
      code: j.code || null,
      profileId: j.profileId || null,
      interruptRequested: Boolean(j.cancelCode),
      ...(processedFrames !== null ? { processedFrames } : {}),
      ...(totalFrames !== null ? { totalFrames } : {})
    };
  }
  function finish(job, state, code) {
    if (TERMINAL.has(job.status)) return;
    job.status = state; job.code = code; delete job.childPid; save(job);
    if (active?.job.jobId === job.jobId) { timers.clearTimeout(active.killTimer); active = null; }
    cleanup();
  }
  function reserve() {
    cleanup();
    if (closed || active) return null;
    const job = { jobId: randomUUID(), status: 'uploading', createdAt: now(), updatedAt: now(), timeoutMs: timing.timeoutMs, killGraceMs: timing.killGraceMs };
    fs.mkdirSync(dirOf(job.jobId), { mode: 0o700 }); jobs.set(job.jobId, job); active = { job }; save(job); return job;
  }
  function mainResult(job) {
    const run = path.join(dirOf(job.jobId), 'run');
    const read = (name, max) => { const p = path.join(run, name); if (fs.statSync(p).size > max) throw new Error('oversize'); return JSON.parse(fs.readFileSync(p)); };
    const state = read('state.json', 65536); const result = read('result.json', 131072);
    if (job.method === 'mediapipe_pnp_flow') return fastMainResult(job, run, state, result);
    if (state.status !== 'completed' || state.mode !== 'cpu_inference' || state.model_loaded !== true ||
        result.schema_version !== 'd01-pilot-result-1.0' || result.protocol_version !== 'd01-pilot-fixed-1.0' || result.model_inference_performed !== true ||
        result.video?.sha256 !== job.videoHash || !Array.isArray(result.settling?.conditions) ||
        !Number.isInteger(state.processed_frames) || state.processed_frames <= 0 ||
        state.valid_frames + state.invalid_frames !== state.processed_frames) throw new Error('invalid result');
    const references = result.detail_files && Object.values(result.detail_files);
    if (!references || !references.length || references.length > 32) throw new Error('invalid detail references');
    for (const ref of references) {
      if (typeof ref.path !== 'string' || !/^details\/[a-zA-Z0-9_.-]+$/.test(ref.path) || !/^[0-9a-f]{64}$/.test(ref.sha256)) throw new Error('invalid reference');
      const file = path.join(run, ref.path);
      if (!fs.lstatSync(file).isFile() || path.dirname(fs.realpathSync(file)) !== fs.realpathSync(path.join(run, 'details')) ||
          fs.statSync(file).size > 32 * 1024 * 1024 || hash(fs.readFileSync(file)) !== ref.sha256) throw new Error('invalid detail file');
    }
    const manual = {};
    for (const key of ['call_start_s', 'call_end_s', 'response_start_s', 'response_end_s']) {
      const m = result.manual?.marks?.[key];
      const expected = job.manual?.[key] ?? null;
      if (!m || m.time_s !== expected) throw new Error('manual mismatch');
      manual[key] = { time_s: m.time_s, source: m.time_s === null ? null : 'manual_user_input' };
    }
    const movement = {};
    for (const method of ['raw', 'ema_050']) {
      const candidates = result.movement_results?.[method]?.settings?.base?.candidates;
      if (!Array.isArray(candidates) || candidates.length > 1000) throw new Error('invalid candidates');
      movement[method] = candidates.map(c => {
        const safe = {};
        for (const key of ['candidate_id', 'movement_start_s', 'movement_end_s', 'start_confirmation_time_s', 'end_confirmation_time_s',
          'start_minus_manual_call_start_s', 'start_minus_manual_call_end_s']) {
          const v = c[key];
          if (key === 'candidate_id' ? typeof v !== 'string' || !/^candidate_\d+$/.test(v) : v !== null && (typeof v !== 'number' || !Number.isFinite(v))) throw new Error('invalid field');
          safe[key] = v;
        }
        for (const key of ['start_status', 'end_status']) safe[key] = ['observed_rule_boundary', 'unknown_start_no_quiet_baseline', 'unknown_end_data_gap', 'unknown_end_clip_ended'].includes(c[key]) ? c[key] : 'not_recorded';
        return safe;
      });
    }
    let source;
    if (job.sourceType === 'user_marked') {
      const marked = result.user_marked_input; const media = marked?.video_metadata;
      if (marked?.schema_version !== 'd01-user-marked-input-1.0' || marked.source_type !== 'user_marked' ||
          !isDeepStrictEqual(marked.roi, job.roi) || media?.fps !== 24 ||
          !Number.isInteger(media.width) || media.width <= 0 || !Number.isInteger(media.height) || media.height <= 0 ||
          !Number.isInteger(media.decoded_frame_count) || media.decoded_frame_count !== state.processed_frames || media.decoded_frame_count > 720 ||
          !Number.isFinite(media.duration_s) || media.duration_s <= 0 || media.duration_s > 30 ||
          Math.abs(media.duration_s - media.decoded_frame_count / 24) > .001 ||
          job.roi.x + job.roi.width > media.width || job.roi.y + job.roi.height > media.height ||
          Object.values(job.manual).some(t => t > media.duration_s)) throw new Error('invalid marked source');
      source = { schemaVersion: 'd01-input-source-1.0', type: 'user_marked', roi: job.roi,
        video: { width: media.width, height: media.height, fps: media.fps, durationS: media.duration_s,
          decodedFrames: media.decoded_frame_count, durationSource: 'decoded_CFR_video_frame_extent' },
        validation: 'media_bounds_only_not_content_or_ROI_quality_approval' };
    }
    return { schemaVersion: job.sourceType === 'user_marked' ? 'd01-pilot-api-1.1' : 'd01-pilot-api-1.0',
      jobId: job.jobId, profileId: job.profileId ?? null, videoHash: job.videoHash,
      ...(source ? { source } : {}),
      manualTimes: manual, movements: movement, settling: result.settling.conditions.map(c => ({
        method: ['raw', 'ema_050'].includes(c.method) ? c.method : null, radiusDeg: [10, 15].includes(c.radius_deg) ? c.radius_deg : null,
        candidateId: /^candidate_\d+$/.test(c.source_candidate_id) ? c.source_candidate_id : null,
        windowCounts: Object.fromEntries(['accepted_settling_window', 'rejected_conditions', 'unconfirmed_incomplete_data'].map(k => [k, Number.isSafeInteger(c.window_counts?.[k]) && c.window_counts[k] >= 0 ? c.window_counts[k] : null])) })),
      counts: { processed: state.processed_frames, valid: state.valid_frames, invalid: state.invalid_frames },
      algorithmicTarget: 'not_determined', manualCandidateStatus: 'unreviewed', clockAlignmentVerified: false,
      interpretation: 'temporal_relations_only_not_response_or_target_classification' };
  }
  function startFast(job, fields) {
    const fail = (status, code) => { finish(job, 'failed', code); return { status, code }; };
    if (Object.keys(fields).some(k => !['method', 'targetPoint', 'callStartS', 'callEndS'].includes(k))) return fail(400, 'invalid_target');
    const python = env.PILOT_D01_FAST_PYTHON;
    const model = env.PILOT_D01_FACE_MODEL;
    if (![python, model].every(p => p && path.isAbsolute(p) && fs.existsSync(p) && fs.statSync(p).isFile())) return fail(503, 'fast_runtime_not_configured');
    const manual = {};
    try {
      for (const [field, key] of [['callStartS', 'call_start_s'], ['callEndS', 'call_end_s']]) {
        if (fields[field] === undefined) continue;
        if (!/^\d+(\.\d{1,3})?$/.test(fields[field]) || !Number.isFinite(Number(fields[field]))) throw new Error('time');
        manual[key] = Number(fields[field]);
      }
      if (![0, 2].includes(Object.keys(manual).length) || (manual.call_end_s !== undefined && manual.call_end_s < manual.call_start_s)) throw new Error('time');
    } catch { return fail(400, 'invalid_manual_times'); }
    let point;
    if (fields.targetPoint !== undefined) {
      try {
        point = JSON.parse(fields.targetPoint);
        if (!Array.isArray(point) || point.length !== 2 || !point.every(n => typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= 1)) throw new Error('point');
      } catch { return fail(400, 'invalid_target'); }
    }
    const dir = dirOf(job.jobId), video = path.join(dir, 'upload.mp4');
    job.videoHash = hash(fs.readFileSync(video)); job.profileId = null;
    job.method = 'mediapipe_pnp_flow'; job.sourceType = 'automatic_face_tracking'; job.manual = manual; job.targetPoint = point ?? null;
    const args = ['-X', 'utf8', '-B', path.resolve(__dirname, '../research/d01/fast_cli.py'), '--video', video,
      '--face-model', model, '--output-dir', path.join(dir, 'run')];
    if (point) { write(path.join(dir, 'target_point.json'), point); args.push('--target-point', path.join(dir, 'target_point.json')); }
    if (Object.keys(manual).length) {
      write(path.join(dir, 'manual.json'), { video_path: video, video_sha256: job.videoHash, candidate_status: 'manual_candidate_unreviewed',
        marks: Object.fromEntries(Object.entries(manual).map(([k, t]) => [k, { media_time_ms: Math.round(t * 1000), time_source: 'manual_user_input', candidate_status: 'unreviewed' }])) });
      args.push('--manual', path.join(dir, 'manual.json'));
    }
    launch(job, args, python, dir);
  }
  function start(job, fields) {
    if (active?.job !== job || job.status !== 'uploading') return;
    if (fields.method === 'mediapipe_pnp_flow') return startFast(job, fields);
    try {
      if (Object.keys(fields).some(k => !['callStartS', 'callEndS', 'roi'].includes(k))) throw new Error('fields');
      const manual = {};
      for (const [field, key] of [['callStartS', 'call_start_s'], ['callEndS', 'call_end_s']]) {
        if (fields[field] === undefined || fields[field] === '') continue;
        if (typeof fields[field] !== 'string' || !/^\d+(\.\d+)?$/.test(fields[field]) || !Number.isFinite(Number(fields[field]))) throw new Error('time');
        const ms = Number(fields[field]) * 1000;
        if (Math.abs(ms - Math.round(ms)) > 1e-6) throw new Error('precision');
        manual[key] = Number(fields[field]);
      }
      if (manual.call_start_s !== undefined && manual.call_end_s !== undefined && manual.call_end_s < manual.call_start_s) throw new Error('order');
      job.manual = manual;
    } catch { finish(job, 'failed', 'invalid_manual_times'); return { status: 400, code: 'invalid_manual_times' }; }
    const dir = dirOf(job.jobId); const video = path.join(dir, 'upload.mp4');
    const digest = hash(fs.readFileSync(video)); const profile = profiles.find(p => p.sha256 === digest);
    if (!profile && fields.roi === undefined) { finish(job, 'failed', 'roi_required'); return { status: 422, code: 'roi_required' }; }
    if (profile && fields.roi !== undefined) { finish(job, 'failed', 'profile_roi_fixed'); return { status: 400, code: 'profile_roi_fixed' }; }
    let roi = profile?.roi;
    if (!profile) {
      try {
        const input = JSON.parse(fields.roi);
        if (!input || Object.keys(input).sort().join(',') !== 'height,width,x,y' ||
            !['x', 'y', 'width', 'height'].every(k => Number.isSafeInteger(input[k])) ||
            input.x < 0 || input.y < 0 || input.width <= 0 || input.height <= 0 ||
            Object.values(input).some(v => v > 16384)) throw new Error('roi');
        roi = { x: input.x, y: input.y, width: input.width, height: input.height,
          padding_ltrb_source_px: [0, 0, 0, 0], human_supplied: true };
      } catch { finish(job, 'failed', 'invalid_roi'); return { status: 400, code: 'invalid_roi' }; }
      if (job.manual.call_start_s === undefined || job.manual.call_end_s === undefined) {
        finish(job, 'failed', 'invalid_manual_times'); return { status: 400, code: 'invalid_manual_times' };
      }
    }
    job.videoHash = digest; job.profileId = profile?.id ?? null; job.sourceType = profile ? 'reviewed_profile' : 'user_marked'; job.roi = roi;
    write(path.join(dir, 'roi.json'), roi);
    const args = ['-X', 'utf8', '-B', cli, '--video', video, '--weights', env.PILOT_D01_WEIGHTS,
      '--roi', path.join(dir, 'roi.json'), '--protocol', protocol, '--official-source', env.PILOT_D01_OFFICIAL_SOURCE, '--output-dir', path.join(dir, 'run')];
    if (cpuThreads !== undefined) args.push('--cpu-threads', cpuThreads);
    if (!profile) args.push('--user-marked');
    job.requestedCpuThreads = cpuThreads === undefined ? 4 : Number(cpuThreads);
    if (Object.keys(job.manual).length) {
      write(path.join(dir, 'manual.json'), { video_path: video, video_sha256: digest, candidate_status: 'manual_candidate_unreviewed',
        marks: Object.fromEntries(Object.entries(job.manual).map(([k, t]) => [k, { media_time_ms: Math.round(t * 1000), time_source: 'manual_user_input', candidate_status: 'unreviewed' }])) });
      args.push('--manual', path.join(dir, 'manual.json'));
    }
    launch(job, args, env.PILOT_D01_PYTHON, dir);
  }
  function launch(job, args, python, dir) {
    job.status = 'running'; save(job);
    // Explicit environment: never inherit backend Gemini/team secrets into Python.
    const childEnv = {};
    for (const k of ['PATH', 'SystemRoot', 'WINDIR', 'TEMP', 'TMP', 'LANG', 'LC_ALL']) if (process.env[k]) childEnv[k] = process.env[k];
    childEnv.PYTHONIOENCODING = 'utf-8'; childEnv.MPLCONFIGDIR = path.join(dir, 'matplotlib_config');
    const recordStartFailure = (error, phase) => {
      // Local job diagnostic only; never serialize error.message/stack/argv/env.
      job.startFailure = { phase, code: ['EPERM', 'EACCES', 'ENOENT', 'ENOTDIR', 'EINVAL', 'EMFILE', 'ENOMEM'].includes(error?.code) ? error.code : 'UNKNOWN' };
      finish(job, 'failed', 'cli_start_failed');
    };
    let child;
    try { child = runner(python, args, { shell: false, windowsHide: true, cwd: dir, env: childEnv, stdio: ['ignore', 'pipe', 'pipe'] }); }
    catch (error) { recordStartFailure(error, 'spawn_throw'); return; }
    active.child = child; job.childPid = child.pid; job.childStartedAt = now(); save(job);
    let logBytes = 0; const logFile = path.join(dir, 'cli.log');
    fs.writeFileSync(logFile, '', { mode: 0o600 });
    const log = data => { const b = Buffer.from(data); const keep = b.subarray(0, Math.max(0, 65536 - logBytes)); fs.appendFileSync(logFile, keep); logBytes += keep.length; };
    child.stdout?.on('data', log); child.stderr?.on('data', log);
    const timeout = timers.setTimeout(() => { if (active?.job === job) interrupt(job.jobId, 'analysis_timeout'); }, timing.timeoutMs); timeout.unref?.();
    child.once('error', error => { if (!child.pid) { timers.clearTimeout(timeout); recordStartFailure(error, 'spawn_error_event'); } });
    child.once('close', (code, signal) => {
      job.childClosedAt = now();
      job.childExitCode = Number.isInteger(code) ? code : null;
      job.childExitSignal = ['SIGTERM','SIGKILL','SIGINT'].includes(signal) ? signal : null;
      timers.clearTimeout(timeout); if (active?.job === job) timers.clearTimeout(active.killTimer);
      // A failed-start job may already be terminal; retain close diagnostics locally.
      if (TERMINAL.has(job.status)) { save(job); return; }
      if (job.cancelCode) return finish(job, 'interrupted', job.cancelCode);
      let state;
      try { state = JSON.parse(fs.readFileSync(path.join(dir, 'run/state.json'))); } catch { /* safe error below */ }
      if (state?.status === 'interrupted') return finish(job, 'interrupted', 'cli_interrupted');
      if (code !== 0) return finish(job, 'failed', ['invalid_roi', 'invalid_manual_times', 'unsupported_fps', 'unsupported_timeline', 'video_too_long', 'invalid_video', 'invalid_target', 'fast_cli_failed'].includes(state?.code) ? state.code : 'cli_failed');
      try { const safe = mainResult(job); write(path.join(dir, 'api_result.json'), safe); finish(job, 'completed', null); }
      catch { finish(job, 'failed', 'invalid_cli_result'); }
    });
  }
  function interrupt(id, code = 'cancelled_locally') {
    if (!active || active.job.jobId !== id || TERMINAL.has(active.job.status)) return false;
    const { job, child } = active;
    if (job.cancelCode) return true;
    if (!child) { finish(job, 'interrupted', code); return true; }
    job.cancelCode = code; save(job); child.kill('SIGTERM');
    // Capacity stays occupied until process close, even after kill request.
    active.killTimer = timers.setTimeout(() => child.kill('SIGKILL'), timing.killGraceMs); active.killTimer.unref?.(); return true;
  }
  const upload = multer({ storage: multer.diskStorage({ destination(req, file, cb) { cb(null, dirOf(req.pilotJob.jobId)); },
    filename(req, file, cb) { cb(null, 'upload.mp4'); } }), limits: { fileSize: MAX_VIDEO, files: 1, fields: 4, fieldSize: 256, parts: 6 } }).single('video');
  function install(app) {
    app.post('/api/pilot-d01/jobs', (req, res) => {
      const job = reserve(); if (!job) return res.status(429).json({ code: 'pilot_busy', error: 'Pilot analiz meşgul; kuyruk oluşturulmadı.' });
      req.pilotJob = job;
      req.once('aborted', () => { if (job.status === 'uploading') finish(job, 'interrupted', 'upload_interrupted'); });
      upload(req, res, error => {
        if (error || !req.file) { finish(job, 'failed', error?.code === 'LIMIT_FILE_SIZE' ? 'video_too_large' : 'invalid_upload'); return res.status(error?.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({ code: error?.code === 'LIMIT_FILE_SIZE' ? 'video_too_large' : 'invalid_upload' }); }
        if (job.status !== 'uploading') return res.status(400).json({ code: 'upload_interrupted' });
        job.uploadCompletedAt = now();
        let failure;
        try { failure = start(job, req.body); } catch { finish(job, 'failed', 'pilot_io_error'); failure = { status: 500, code: 'pilot_io_error' }; }
        if (failure) return res.status(failure.status).json({ code: failure.code });
        res.status(202).json({ jobId: job.jobId, status: job.status,
          ...(['user_marked', 'automatic_face_tracking'].includes(job.sourceType) ? { videoHash: job.videoHash, sourceType: job.sourceType } : {}) });
      });
    });
    app.get('/api/pilot-d01/jobs/:id', (req, res) => { const s = ID.test(req.params.id) && status(req.params.id); res.status(s ? 200 : 404).json(s || { code: 'job_not_found' }); });
    app.get('/api/pilot-d01/jobs/:id/result', (req, res) => {
      const j = ID.test(req.params.id) && jobs.get(req.params.id);
      if (!j) return res.status(404).json({ code: 'job_not_found' });
      if (j.status !== 'completed') return res.status(409).json({ code: 'result_not_completed', status: j.status });
      try { res.json(JSON.parse(fs.readFileSync(path.join(dirOf(j.jobId), 'api_result.json')))); }
      catch { res.status(500).json({ code: 'result_unavailable' }); }
    });
    app.delete('/api/pilot-d01/jobs/:id', (req, res) => res.status(interrupt(req.params.id) ? 202 : 409).json({ code: 'local_interrupt_requested' }));
    app.use('/api/pilot-d01', (err, req, res, next) => res.status(err.type === 'entity.too.large' ? 413 : err.type === 'entity.parse.failed' ? 400 : 500).json({ code: err.type === 'entity.too.large' ? 'request_too_large' : 'pilot_request_failed' }));
  }
  const sweep = setInterval(() => { try { cleanup(); } catch { console.error('[pilot] cleanup_failed'); } }, 60 * 60 * 1000); sweep.unref?.();
  function close() { closed = true; if (active) throw new Error('Wait for pilot child close before releasing ownership'); clearInterval(sweep); fs.unlinkSync(lock); }
  return { install, status, cleanup, interrupt, reserve, start, close,
    async shutdown() {
      closed = true;
      if (active?.child) { const child = active.child; const done = new Promise(resolve => child.once('close', resolve)); interrupt(active.job.jobId, 'backend_shutdown'); await done; }
      else if (active) interrupt(active.job.jobId, 'backend_shutdown');
      close();
    } };
}
module.exports = { createPilotJobs, MAX_VIDEO, RETENTION };
