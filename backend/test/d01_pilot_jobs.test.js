const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { EventEmitter } = require('node:events');
const { Duplex, PassThrough } = require('node:stream');
const { IncomingMessage, ServerResponse } = require('node:http');
const { createHash, randomBytes, randomUUID } = require('node:crypto');
const { createApp } = require('../server');
const { createPilotJobs, MAX_VIDEO, RETENTION } = require('../d01_pilot_jobs');
const key = randomBytes(32).toString('hex');
const hash = b => createHash('sha256').update(b).digest('hex');
function request(app, method, url, body = Buffer.alloc(0), type = 'application/json', auth = key) {
  return new Promise((resolve, reject) => {
    const socket = new Duplex({ read() {}, write(c, e, cb) { cb(); } });
    const req = new IncomingMessage(socket); req.method = method; req.url = url; req.httpVersion = '1.1';
    req.headers = { 'content-type': type, 'content-length': String(body.length), ...(auth ? { authorization: `Bearer ${auth}` } : {}) };
    const res = new ServerResponse(req);
    res.end = chunk => { resolve({ status: res.statusCode, body: chunk ? JSON.parse(chunk.toString()) : null }); socket.destroy(); return res; };
    req.on('error', reject); res.on('error', reject); req.push(body); req.push(null);
    req.complete = true; // Node HTTP parser has received the whole simulated request, including multipart.
    app.handle(req, res, reject);
  });
}
function multipart(bytes, fields = {}) {
  const boundary = 'controlled-boundary'; const parts = [];
  for (const [k, v] of Object.entries(fields)) parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`));
  parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="video"; filename="ignored.mp4"\r\nContent-Type: video/mp4\r\n\r\n`), bytes, Buffer.from(`\r\n--${boundary}--\r\n`));
  return [Buffer.concat(parts), `multipart/form-data; boundary=${boundary}`];
}
function fixture(t, mode = 'deployment', extra = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'd01-job-test-')); const fake = path.join(root, 'python.fixture'); fs.writeFileSync(fake, 'not executable');
  const bytes = Buffer.from('controlled fake video, never decoded'); const profiles = [{ id: 'controlled-only', sha256: hash(bytes), roi: { human_supplied: true } }];
  const env = { BACKEND_MODE: mode, TEAM_ACCESS_KEY: key, PILOT_D01_ENABLED: 'true', PILOT_D01_PYTHON: fake,
    PILOT_D01_WEIGHTS: fake, PILOT_D01_OFFICIAL_SOURCE: root, PILOT_D01_JOBS_DIR: path.join(root, 'jobs') };
  const children = []; let clock = Date.now();
  function runner(executable, args, options) {
    const child = new EventEmitter(); child.stdout = new PassThrough(); child.stderr = new PassThrough(); child.signals = [];
    child.kill = signal => { child.signals.push(signal); return true; }; child.args = args; child.options = options;
    child.finish = (kind = 'completed') => {
      const at = key => args[args.indexOf(key) + 1]; const run = at('--output-dir'); fs.mkdirSync(run);
      fs.mkdirSync(path.join(run, 'details')); fs.writeFileSync(path.join(run, 'details', 'controlled.json'), '{}');
      const manual = args.includes('--manual') ? JSON.parse(fs.readFileSync(at('--manual'))).marks : {};
      fs.writeFileSync(path.join(run, 'state.json'), JSON.stringify({ status: kind, mode: 'cpu_inference', model_loaded: true, processed_frames: 5, valid_frames: 5, invalid_frames: 0 }));
      const candidate = { candidate_id: 'candidate_001', movement_start_s: 1, movement_end_s: 2,
        start_confirmation_time_s: 1.1, end_confirmation_time_s: 2.2,
        start_minus_manual_call_start_s: manual.call_start_s ? 1 - manual.call_start_s.media_time_ms / 1000 : null,
        start_minus_manual_call_end_s: manual.call_end_s ? 1 - manual.call_end_s.media_time_ms / 1000 : null };
      fs.writeFileSync(path.join(run, 'result.json'), JSON.stringify({ schema_version: 'd01-pilot-result-1.0', protocol_version: 'd01-pilot-fixed-1.0', model_inference_performed: true,
        detail_files: { controlled: { path: 'details/controlled.json', sha256: hash(Buffer.from('{}')) } },
        video: { sha256: hash(fs.readFileSync(at('--video'))), path: '/private/path-not-for-api' },
        manual: { marks: Object.fromEntries(['call_start_s', 'call_end_s', 'response_start_s', 'response_end_s'].map(k => [k, { time_s: manual[k] ? manual[k].media_time_ms / 1000 : null }])) },
        movement_results: Object.fromEntries(['raw', 'ema_050'].map(m => [m, { settings: { base: { candidates: [candidate] } } }])),
        settling: { conditions: [] }, secretFixture: 'must-not-be-returned' }));
      child.emit('close', kind === 'completed' ? 0 : 1);
    };
    children.push(child); return child;
  }
  const app = createApp({ env, pilotD01: { runner, profiles, now: () => clock, ...extra }, generate: async () => { throw new Error('no provider'); } });
  t.after(() => { if (children.length) children.at(-1).emit('close', 1); app.locals.pilotD01.close(); fs.rmSync(root, { recursive: true }); });
  return { app, env, root, bytes, children, profiles, runner, advance(ms) { clock += ms; }, upload(fields, data = bytes, auth = key) { return request(app, 'POST', '/api/pilot-d01/jobs', ...multipart(data, fields), auth); } };
}
test('Upload -> 202 job -> status/result; no model/provider, sanitized main result', async t => {
  const f = fixture(t); const uploaded = await f.upload(); assert.equal(uploaded.status, 202, JSON.stringify(uploaded.body)); const id = uploaded.body.jobId;
  assert.equal(f.children.length, 1); assert.equal(f.children[0].options.shell, false);
  assert.equal(f.children[0].options.env.TEAM_ACCESS_KEY, undefined); assert.equal(f.children[0].options.env.GEMINI_API_KEY, undefined);
  assert.equal(f.children[0].args.includes('--manual'), false); assert.equal(f.children[0].args.includes('--recorded-raw'), false);
  assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${id}/result`)).status, 409);
  f.children[0].finish(); const result = await request(f.app, 'GET', `/api/pilot-d01/jobs/${id}/result`);
  assert.equal(result.status, 200); assert.equal(result.body.algorithmicTarget, 'not_determined');
  assert.equal(JSON.stringify(result).includes('private'), false); assert.equal(JSON.stringify(result).includes('secretFixture'), false);
  assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${id}`)).body.status, 'completed');
});
test('Unsupported video hash never starts runner and releases slot', async t => {
  const f = fixture(t); assert.equal((await f.upload({}, Buffer.from('unknown'))).status, 422); assert.equal(f.children.length, 0);
  assert.equal((await f.upload()).status, 202);
});
test('Shared single analysis slot has no queue; OPTIONS/health do not reserve it', async t => {
  const f = fixture(t); assert.equal((await request(f.app, 'GET', '/health')).status, 200);
  assert.equal((await request(f.app, 'OPTIONS', '/api/pilot-d01/jobs')).status, 204);
  assert.equal((await f.upload()).status, 202); assert.equal((await f.upload()).body.code, 'pilot_busy'); assert.equal(f.children.length, 1);
  f.children[0].finish(); assert.equal((await f.upload()).status, 202);
});
test('Missing/wrong key rejected before upload in deployment AND development pilot', async t => {
  const f = fixture(t, 'development'); assert.equal((await f.upload({}, f.bytes, '')).status, 401);
  assert.equal((await f.upload({}, f.bytes, 'wrong')).status, 401); assert.equal(f.children.length, 0);
});
test('Manual call-only input; reject movement times, paths and reversed calls', async t => {
  const f = fixture(t);
  for (const fields of [{ responseStartS: '1' }, { python: 'anything' }, { callStartS: '2', callEndS: '1' }]) assert.equal((await f.upload(fields)).status, 400);
  const r = await f.upload({ callStartS: '0.401', callEndS: '1.152' }); assert.equal(r.status, 202);
  f.children[0].finish(); const result = await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}/result`);
  assert.equal(result.body.manualTimes.call_start_s.time_s, .401); assert.equal(result.body.manualTimes.response_start_s.time_s, null);
});
test('CLI nonzero/error and interrupted state never become completed', async t => {
  const f = fixture(t); let r = await f.upload(); f.children[0].emit('close', 7);
  assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}`)).body.code, 'cli_failed');
  r = await f.upload(); f.children[1].finish('interrupted');
  assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}`)).body.status, 'interrupted');
});
test('Cancellation holds slot until actual process close; late success rejected', async t => {
  const f = fixture(t); const r = await f.upload();
  assert.equal((await request(f.app, 'DELETE', `/api/pilot-d01/jobs/${r.body.jobId}`)).status, 202);
  assert.equal((await f.upload()).status, 429); assert.deepEqual(f.children[0].signals, ['SIGTERM']);
  f.children[0].finish(); assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}`)).body.status, 'interrupted');
});
test('Upload size has its own 25 MiB limit; global deployment JSON remains 1 MiB', async t => {
  const f = fixture(t); assert.equal((await f.upload({}, Buffer.alloc(MAX_VIDEO + 1))).status, 413);
  assert.equal((await request(f.app, 'POST', '/api/generate-scenario-input', Buffer.from(JSON.stringify({ x: 'a'.repeat(1024 * 1024) })))).status, 413);
  assert.equal(f.children.length, 0);
});
test('Startup recovers dead partial jobs; retention removes only owned terminal jobs', async t => {
  const f = fixture(t); const id = randomUUID(); const dir = path.join(f.env.PILOT_D01_JOBS_DIR, id); fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'job.json'), JSON.stringify({ jobId: id, status: 'running', updatedAt: 0 }));
  // Remove from disk before manager teardown; use a separate owned root for recovery instance.
  const env = { ...f.env, PILOT_D01_JOBS_DIR: path.join(f.root, 'recover') }; fs.mkdirSync(env.PILOT_D01_JOBS_DIR);
  fs.writeFileSync(path.join(env.PILOT_D01_JOBS_DIR, '.d01-pilot-owned'), 'd01-pilot-jobs-1');
  const d = path.join(env.PILOT_D01_JOBS_DIR, id); fs.mkdirSync(d); fs.writeFileSync(path.join(d, 'job.json'), JSON.stringify({ jobId: id, status: 'running', updatedAt: 0 }));
  let clock = 1000; const manager = createPilotJobs(env, { runner: f.runner, profiles: f.profiles, now: () => clock });
  assert.equal(manager.status(id).status, 'interrupted'); clock += RETENTION + 1; manager.cleanup(); assert.equal(manager.status(id), null); manager.close();
});
test('Old Gemini analysis stays disabled and pilot defaults disabled', async () => {
  const app = createApp({ env: { BACKEND_MODE: 'deployment', TEAM_ACCESS_KEY: key } });
  assert.equal((await request(app, 'POST', '/api/analyze-video')).status, 404);
  assert.equal((await request(app, 'POST', '/api/pilot-d01/jobs')).status, 404);
});
test('Malformed completed output and startup failure cannot become success', async t => {
  const f = fixture(t); let r = await f.upload();
  const child = f.children[0]; const run = child.args[child.args.indexOf('--output-dir') + 1]; fs.mkdirSync(run);
  fs.writeFileSync(path.join(run, 'state.json'), JSON.stringify({ status: 'completed' })); fs.writeFileSync(path.join(run, 'result.json'), '{}');
  child.emit('close', 0); assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}`)).body.code, 'invalid_cli_result');
  r = await f.upload(); f.children[1].emit('error', new Error('private local path must not escape'));
  assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}`)).body.code, 'cli_start_failed');
});
test('Missing pilot team key fails startup; profiles contain only the reviewed pair', () => {
  assert.throws(() => createApp({ env: { PILOT_D01_ENABLED: 'true' } }), /TEAM_ACCESS_KEY/);
  const profiles = require('../resources/d01_pilot_profiles.json').profiles;
  assert.equal(profiles.length, 2); assert.deepEqual(profiles.map(p => p.roi.padding_ltrb_source_px[1]), [40, 0]);
});
test('Retention count bounded and another owner cannot reuse the live directory', async t => {
  const f = fixture(t);
  assert.throws(() => createPilotJobs(f.env, { runner: f.runner, profiles: f.profiles }), /live process/);
  for (let i = 0; i < 12; i++) await f.upload({}, Buffer.from('unsupported'));
  const dirs = fs.readdirSync(f.env.PILOT_D01_JOBS_DIR).filter(n => /^[0-9a-f-]{36}$/.test(n));
  assert.equal(dirs.length, 10);
});
test('Timeout requests termination, keeps slot until close, never uses late success', async t => {
  const pending = []; const timers = { setTimeout(fn, ms) { const token = { fn, ms, unref() {} }; pending.push(token); return token; }, clearTimeout() {} };
  const f = fixture(t, 'deployment', { timers }); const response = await f.upload();
  assert.equal(pending[0].ms, 600000); pending[0].fn();
  assert.equal((await f.upload()).status, 429); assert.deepEqual(f.children[0].signals, ['SIGTERM']);
  assert.equal(pending[1].ms, 10000); pending[1].fn(); assert.deepEqual(f.children[0].signals, ['SIGTERM', 'SIGKILL']);
  f.children[0].finish(); assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${response.body.jobId}`)).body.code, 'analysis_timeout');
});
