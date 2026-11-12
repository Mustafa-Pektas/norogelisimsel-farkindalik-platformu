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
  const { envOverrides = {}, ...pilotOptions } = extra;
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'd01-job-test-')); const fake = path.join(root, 'python.fixture'); fs.writeFileSync(fake, 'not executable');
  const bytes = Buffer.from('controlled fake video, never decoded'); const profiles = [{ id: 'controlled-only', sha256: hash(bytes), roi: { human_supplied: true } }];
  const env = { BACKEND_MODE: mode, TEAM_ACCESS_KEY: key, PILOT_D01_ENABLED: 'true', PILOT_D01_PYTHON: fake,
    PILOT_D01_FAST_PYTHON: fake, PILOT_D01_FACE_MODEL: fake,
    PILOT_D01_WEIGHTS: fake, PILOT_D01_OFFICIAL_SOURCE: root, PILOT_D01_JOBS_DIR: path.join(root, 'jobs'), ...envOverrides };
  const children = []; let clock = Date.now();
  function runner(executable, args, options) {
    const child = new EventEmitter(); child.stdout = new PassThrough(); child.stderr = new PassThrough(); child.signals = [];
    child.kill = signal => { child.signals.push(signal); return true; }; child.args = args; child.options = options;
    child.finish = (kind = 'completed', callTiming) => {
      const at = key => args[args.indexOf(key) + 1]; const run = at('--output-dir'); fs.mkdirSync(run);
      fs.mkdirSync(path.join(run, 'details')); fs.writeFileSync(path.join(run, 'details', 'controlled.json'), '{}');
      const manual = args.includes('--manual') ? JSON.parse(fs.readFileSync(at('--manual'))).marks : {};
      if (args.some(a => a.endsWith('fast_cli.py'))) {
        const callStart = manual.call_start_s ? manual.call_start_s.media_time_ms / 1000 : undefined;
        const callEnd = manual.call_end_s ? manual.call_end_s.media_time_ms / 1000 : undefined;
        const candidate = { candidate_id: 'candidate_001', movement_start_s: .05, movement_end_s: .1,
          start_confirmation_time_s: .08, end_confirmation_time_s: .12,
          start_minus_manual_call_start_s: callStart === undefined ? null : .05-callStart,
          start_minus_manual_call_end_s: callEnd === undefined ? null : .05-callEnd,
          callPhase: callStart === undefined ? 'call_unknown' : .05 < callStart ? 'before_call' : .05 <= callEnd ? 'during_call' : 'after_call' };
        fs.writeFileSync(path.join(run,'state.json'), JSON.stringify({status:kind,method:'mediapipe_pnp_flow',model_loaded:true,processed_frames:5,valid_frames:3,invalid_frames:2}));
        fs.writeFileSync(path.join(run,'result.json'), JSON.stringify({schema_version:'d01-fast-result-1.0',method:'mediapipe_pnp_flow',video_hash:hash(fs.readFileSync(at('--video'))),
          video_metadata:{width:640,height:480,fps:24,decoded_frame_count:5,duration_s:5/24},counts:{processed:5,valid:3,invalid:2},
          manualTimes:Object.fromEntries(['call_start_s','call_end_s','response_start_s','response_end_s'].map(k=>[k,{time_s:manual[k] ? manual[k].media_time_ms/1000:null}])),
          movements:{raw:[candidate],ema_050:[candidate]},coverage:{poseFrames:3,flowOnlyFrames:1,lostFrames:1,ambiguousFrames:0,totalFrames:5},
          missingPoseIntervals:[{startS:0,endS:.04,frames:2}],targetSelection:args.includes('--target-point')?'manual_initial_point':'single_face_candidate_role_unverified',identityStatus:'continuity_candidate_not_biometric_identity',
          timings:{media_preflight_s:.01,model_load_s:.02,tracking_pnp_s:.03,candidate_postprocess_s:.01,report_preparation_s:.01,total_s:.08},
          detail_files:{frames:{path:'details/controlled.json',sha256:hash(Buffer.from('{}'))}}}));
        if (callTiming) {
          const file=path.join(run,'result.json');const result=JSON.parse(fs.readFileSync(file));
          result.callTiming=callTiming;result.timings.audio_s=.04;
          for (const mode of ['raw','ema_050']) for (const c of result.movements[mode]) {
            const a=callTiming.startS,b=callTiming.endS;
            c.start_minus_manual_call_start_s=a===null?null:c.movement_start_s-a;
            c.start_minus_manual_call_end_s=b===null?null:c.movement_start_s-b;
            c.callPhase=a===null?'call_unknown':c.movement_start_s<a?'before_call':c.movement_start_s<=b?'during_call':'after_call';
          }
          fs.writeFileSync(file,JSON.stringify(result));
        }
        child.emit('close', kind === 'completed' ? 0 : 1); return;
      }
      fs.writeFileSync(path.join(run, 'state.json'), JSON.stringify({ status: kind, mode: 'cpu_inference', model_loaded: true, processed_frames: 5, valid_frames: 5, invalid_frames: 0 }));
      const candidate = { candidate_id: 'candidate_001', movement_start_s: 1, movement_end_s: 2,
        start_confirmation_time_s: 1.1, end_confirmation_time_s: 2.2,
        start_minus_manual_call_start_s: manual.call_start_s ? 1 - manual.call_start_s.media_time_ms / 1000 : null,
        start_minus_manual_call_end_s: manual.call_end_s ? 1 - manual.call_end_s.media_time_ms / 1000 : null };
      fs.writeFileSync(path.join(run, 'result.json'), JSON.stringify({ schema_version: 'd01-pilot-result-1.0', protocol_version: 'd01-pilot-fixed-1.0', model_inference_performed: true,
        user_marked_input: args.includes('--user-marked') ? { schema_version: 'd01-user-marked-input-1.0', source_type: 'user_marked',
          roi: JSON.parse(fs.readFileSync(at('--roi'))), video_metadata: { width: 640, height: 480, fps: 24, decoded_frame_count: 5, duration_s: 5 / 24 } } : null,
        detail_files: { controlled: { path: 'details/controlled.json', sha256: hash(Buffer.from('{}')) } },
        video: { sha256: hash(fs.readFileSync(at('--video'))), path: '/private/path-not-for-api' },
        manual: { marks: Object.fromEntries(['call_start_s', 'call_end_s', 'response_start_s', 'response_end_s'].map(k => [k, { time_s: manual[k] ? manual[k].media_time_ms / 1000 : null }])) },
        movement_results: Object.fromEntries(['raw', 'ema_050'].map(m => [m, { settings: { base: { candidates: [candidate] } } }])),
        settling: { conditions: [] }, secretFixture: 'must-not-be-returned' }));
      child.emit('close', kind === 'completed' ? 0 : 1);
    };
    children.push(child); return child;
  }
  const app = createApp({ env, pilotD01: { runner, profiles, now: () => clock, ...pilotOptions }, generate: async () => { throw new Error('no provider'); } });
  t.after(() => { if (children.length) children.at(-1).emit('close', 1); app.locals.pilotD01.close(); fs.rmSync(root, { recursive: true }); });
  return { app, env, root, bytes, children, profiles, runner, advance(ms) { clock += ms; }, upload(fields, data = bytes, auth = key) { return request(app, 'POST', '/api/pilot-d01/jobs', ...multipart(data, fields), auth); } };
}
test('Upload -> 202 job -> status/result; no model/provider, sanitized main result', async t => {
  const f = fixture(t); const uploaded = await f.upload(); assert.equal(uploaded.status, 202, JSON.stringify(uploaded.body)); const id = uploaded.body.jobId;
  assert.equal(f.children.length, 1); assert.equal(f.children[0].options.shell, false);
  assert.equal(f.children[0].options.env.TEAM_ACCESS_KEY, undefined); assert.equal(f.children[0].options.env.GEMINI_API_KEY, undefined);
  assert.equal(f.children[0].args.includes('--manual'), false); assert.equal(f.children[0].args.includes('--recorded-raw'), false);
  assert.equal(f.children[0].args.includes('--cpu-threads'), false);
  assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${id}/result`)).status, 409);
  f.children[0].finish(); const result = await request(f.app, 'GET', `/api/pilot-d01/jobs/${id}/result`);
  assert.equal(result.status, 200); assert.equal(result.body.algorithmicTarget, 'not_determined');
  assert.equal(JSON.stringify(result).includes('private'), false); assert.equal(JSON.stringify(result).includes('secretFixture'), false);
  assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${id}`)).body.status, 'completed');
});
test('Explicit CPU thread choice reaches CLI; invalid configuration fails before job creation', async t => {
  const f = fixture(t, 'deployment', { envOverrides: { PILOT_D01_CPU_THREADS: '2' } });
  assert.equal((await f.upload()).status, 202);
  const args = f.children[0].args;
  assert.equal(args[args.indexOf('--cpu-threads') + 1], '2');
  for (const value of ['', '0', '3', '2.0', ' 2', 'invalid']) {
    assert.throws(() => createPilotJobs({ ...f.env, PILOT_D01_CPU_THREADS: value }), /PILOT_D01_CPU_THREADS/);
  }
});
test('Unsupported video hash never starts runner and releases slot', async t => {
  const f = fixture(t); const rejected = await f.upload({}, Buffer.from('unknown'));
  assert.equal(rejected.status, 422); assert.equal(rejected.body.code, 'roi_required'); assert.equal(f.children.length, 0);
  assert.equal((await f.upload()).status, 202);
});

test('Unknown video + marked ROI/call interval -> existing job API, versioned sanitized source', async t => {
  const f = fixture(t); const bytes = Buffer.from('new controlled media identity');
  const r = await f.upload({ roi: JSON.stringify({ x: 10, y: 20, width: 100, height: 100 }), callStartS: '0.020', callEndS: '0.100' }, bytes);
  assert.equal(r.status, 202); assert.equal(r.body.videoHash, hash(bytes));
  const child = f.children[0]; assert.ok(child.args.includes('--user-marked'));
  assert.ok(child.args.includes('--manual')); assert.equal(child.args.includes('--recorded-raw'), false);
  assert.equal((await f.upload()).status, 429);
  child.finish();
  const response = await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}/result`);
  assert.equal(response.status, 200); const result = response.body;
  assert.equal(result.schemaVersion, 'd01-pilot-api-1.1'); assert.equal(result.profileId, null);
  assert.equal(result.source.type, 'user_marked'); assert.equal(result.source.schemaVersion, 'd01-input-source-1.0');
  assert.equal(result.source.roi.x, 10); assert.equal(result.source.video.fps, 24);
  assert.equal(result.videoHash, hash(bytes)); assert.equal(result.manualTimes.call_start_s.time_s, .02);
  assert.equal(result.manualTimes.response_start_s.time_s, null);
  assert.equal(JSON.stringify(result).includes('private'), false); assert.equal(JSON.stringify(result).includes('path'), false);
});

test('Bad custom fields rejected before spawn; no fallback to a prepared ROI', async t => {
  const f = fixture(t); const bytes = Buffer.from('unprofiled'); const validRoi = JSON.stringify({ x: 0, y: 0, width: 10, height: 10 });
  for (const roi of ['null', '{}', '[1,2,3,4]', '{bad', JSON.stringify({ x: -1, y: 0, width: 10, height: 10 }),
    JSON.stringify({ x: 0.5, y: 0, width: 10, height: 10 }), JSON.stringify({ x: 0, y: 0, width: 10, height: 10, path: '/ignored' })]) {
    const response = await f.upload({ roi, callStartS: '0', callEndS: '0.1' }, bytes);
    assert.equal(response.status, 400); assert.equal(response.body.code, 'invalid_roi');
  }
  assert.equal((await f.upload({ roi: validRoi }, bytes)).body.code, 'invalid_manual_times');
  assert.equal((await f.upload({ roi: validRoi, callStartS: '1', callEndS: '0' }, bytes)).status, 400);
  assert.equal(f.children.length, 0);
});

test('Preflight error code is exposed safely; slot released only on child close', async t => {
  const f = fixture(t); const r = await f.upload({ roi: '{"x":0,"y":0,"width":900,"height":900}', callStartS: '0', callEndS: '1' }, Buffer.from('new'));
  assert.equal(r.status, 202); const child = f.children[0];
  const run = child.args[child.args.indexOf('--output-dir') + 1]; fs.mkdirSync(run);
  fs.writeFileSync(path.join(run, 'state.json'), JSON.stringify({ status: 'failed', model_loaded: false, code: 'invalid_roi', error: '/private/trace' }));
  assert.equal((await f.upload()).status, 429); child.emit('close', 1);
  const s = (await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}`)).body;
  assert.equal(s.status, 'failed'); assert.equal(s.code, 'invalid_roi'); assert.equal(JSON.stringify(s).includes('private'), false);
  assert.equal((await f.upload()).status, 202);
});

test('Both bundled profiles retain their automatic ROI and 1.0 result contract', async t => {
  for (const profile of require('../resources/d01_pilot_profiles.json').profiles) {
    const bytes = Buffer.from('controlled fake video, never decoded');
    const f = fixture(t, 'deployment', { profiles: [{ ...profile, sha256: hash(bytes) }] });
    const r = await f.upload(); assert.equal(r.status, 202); const child = f.children[0];
    assert.equal(child.args.includes('--user-marked'), false); assert.equal(child.args.includes('--manual'), false);
    const roi = JSON.parse(fs.readFileSync(child.args[child.args.indexOf('--roi') + 1]));
    assert.deepEqual(roi, profile.roi); child.finish();
    const result = (await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}/result`)).body;
    assert.equal(result.schemaVersion, 'd01-pilot-api-1.0'); assert.equal(result.profileId, profile.id);
  }
});

test('Custom CLI video hash mismatch remains rejected', async t => {
  const f = fixture(t); const r = await f.upload({ roi: '{"x":0,"y":0,"width":10,"height":10}', callStartS: '0', callEndS: '0.1' }, Buffer.from('original'));
  const child = f.children[0]; fs.writeFileSync(child.args[child.args.indexOf('--video') + 1], 'changed'); child.finish();
  assert.equal((await request(f.app, 'GET', `/api/pilot-d01/jobs/${r.body.jobId}`)).body.code, 'invalid_cli_result');
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
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.env.PILOT_D01_JOBS_DIR,r.body.jobId,'job.json'))).childExitCode,7);
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

test('Fast method uses the same protected queue, preserves unknown calls and exposes coverage without paths', async t => {
  const f=fixture(t); const accepted=await f.upload({method:'mediapipe_pnp_flow'},Buffer.from('unknown fast media'));
  assert.equal(accepted.status,202);assert.equal(accepted.body.sourceType,'automatic_face_tracking');
  assert.equal((await f.upload()).status,429);
  const child=f.children[0];assert.ok(child.args.some(a=>a.endsWith('fast_cli.py')));assert.equal(child.args.includes('--weights'),false);
  assert.equal(child.options.env.TEAM_ACCESS_KEY,undefined);child.finish();
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.env.PILOT_D01_JOBS_DIR,accepted.body.jobId,'job.json'))).childExitCode,0);
  const reply=await request(f.app,'GET',`/api/pilot-d01/jobs/${accepted.body.jobId}/result`);
  assert.equal(reply.status,200);assert.equal(reply.body.schemaVersion,'d01-pilot-api-1.2');assert.equal(reply.body.manualTimes.call_start_s.time_s,null);
  assert.equal(reply.body.movements.raw[0].callPhase,'call_unknown');assert.equal(reply.body.coverage.flowOnlyFrames,1);
  assert.equal(JSON.stringify(reply.body).includes('path'),false);assert.equal(reply.body.videoHash,accepted.body.videoHash);
});
test('Fast input requires paired optional calls and bounded target; pre-call movement stays pre-call',async t=>{
  const f=fixture(t);
  for(const fields of [{targetPoint:'[2,0]'}, {targetPoint:'[0,null]'}, {callStartS:'0.1'}, {callStartS:'0.2',callEndS:'0.1'}, {roi:'{}'}]) {
    assert.equal((await f.upload({method:'mediapipe_pnp_flow',...fields})).status,400);
  }
  assert.equal(f.children.length,0);
  const accepted=await f.upload({method:'mediapipe_pnp_flow',targetPoint:'[0.3,0.4]',callStartS:'0.100',callEndS:'0.150'});
  f.children[0].finish();
  const reply=await request(f.app,'GET',`/api/pilot-d01/jobs/${accepted.body.jobId}/result`);
  assert.equal(reply.status,200);assert.equal(reply.body.movements.raw[0].callPhase,'before_call');assert.equal(reply.body.movements.raw[0].start_minus_manual_call_start_s,-.05);
});
test('Fast runtime missing is explicit, not a fallback to 6D or Gemini',async t=>{
  const f=fixture(t,'deployment',{envOverrides:{PILOT_D01_FAST_PYTHON:undefined}});
  assert.equal((await f.upload({method:'mediapipe_pnp_flow'})).body.code,'fast_runtime_not_configured');assert.equal(f.children.length,0);
});

test('Automatic Deniz timing is distinct from manual; unavailable/name absent preserves head candidates',async t=>{
  for (const status of ['accepted','not_found','ambiguous','low_confidence','unavailable','failed']) {
    const f=fixture(t,'deployment',{envOverrides:{PILOT_D01_AUDIO_MODEL:path.resolve('prepared-audio-model')}});
    const accepted=await f.upload({method:'mediapipe_pnp_flow'});
    assert.ok(f.children[0].args.includes('--audio-model'));
    const ok=status==='accepted';
    f.children[0].finish('completed',{schemaVersion:'d01-call-timing-1.0',source:ok?'automatic_word_timing':'unknown',startS:ok ? .1 : null,endS:ok ? .15 : null,audioStatus:status,matchCount:ok?1:status==='ambiguous'?2:status==='not_found'?0:null,name:'Deniz',language:'tr'});
    const reply=await request(f.app,'GET',`/api/pilot-d01/jobs/${accepted.body.jobId}/result`);
    assert.equal(reply.status,200);assert.equal(reply.body.callTiming.audioStatus,status);
    assert.equal(reply.body.manualTimes.call_start_s.time_s,null);
    assert.equal(reply.body.counts.valid,3);assert.equal(reply.body.movements.raw.length,1);
    assert.equal(reply.body.movements.raw[0].callPhase,ok?'before_call':'call_unknown');
    assert.equal(reply.body.movements.raw[0].start_minus_manual_call_start_s,ok?-.05:null);
    assert.equal(reply.body.timings.audio_s,.04);
  }
});
test('Spawn rejection retains only a local safe diagnostic; API never exposes process errors',async t=>{
  for (const code of ['EPERM','untrusted-secret-code']) {
    const f=fixture(t,'deployment',{runner(){const error=new Error('private path and secret must not escape');error.code=code;throw error;}});
    const accepted=await f.upload({method:'mediapipe_pnp_flow'});
    assert.equal(accepted.status,202);
    const job=JSON.parse(fs.readFileSync(path.join(f.env.PILOT_D01_JOBS_DIR,accepted.body.jobId,'job.json')));
    assert.deepEqual(job.startFailure,{phase:'spawn_throw',code:code==='EPERM'?'EPERM':'UNKNOWN'});
    assert.equal(JSON.stringify(job).includes('private path'),false);
    const state=await request(f.app,'GET',`/api/pilot-d01/jobs/${accepted.body.jobId}`);
    assert.equal(state.body.code,'cli_start_failed');assert.equal(state.body.startFailure,undefined);
    assert.equal((await request(f.app,'GET',`/api/pilot-d01/jobs/${accepted.body.jobId}/result`)).status,409);
  }
});
test('Fast cancel/timeout cannot release the shared slot or accept late success before close',async t=>{
  for (const cancellation of [true,false]) {
    const pending=[];
    const timers={setTimeout(fn,ms){const token={fn,ms,unref(){}};pending.push(token);return token;},clearTimeout(){}};
    const f=fixture(t,'deployment',{timers});const accepted=await f.upload({method:'mediapipe_pnp_flow'});
    if(cancellation) assert.equal((await request(f.app,'DELETE',`/api/pilot-d01/jobs/${accepted.body.jobId}`)).status,202);
    else pending[0].fn();
    assert.equal((await f.upload({method:'mediapipe_pnp_flow'})).status,429);
    assert.deepEqual(f.children[0].signals,['SIGTERM']);f.children[0].finish();
    const state=(await request(f.app,'GET',`/api/pilot-d01/jobs/${accepted.body.jobId}`)).body;
    assert.equal(state.status,'interrupted');assert.equal(state.code,cancellation?'cancelled_locally':'analysis_timeout');
    assert.equal((await request(f.app,'GET',`/api/pilot-d01/jobs/${accepted.body.jobId}/result`)).status,409);
  }
});
