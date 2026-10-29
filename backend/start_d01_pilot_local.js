// Local manual emulator session; no dotenv, upload, model call or provider call.
// The one-use team key arrives as JSON on stdin, never argv or a saved file.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { randomBytes } = require('node:crypto');

async function main() {
  const payload = JSON.parse(fs.readFileSync(0, 'utf8').trim());
  if (typeof payload.accessKey !== 'string' || !/^[\x21-\x7e]+$/.test(payload.accessKey)) {
    throw new Error('invalid_session_key');
  }
  const repo = path.resolve(__dirname, '..');
  const data = path.dirname(repo);
  const python = path.join(data, '.venv_headpose', 'Scripts', 'python.exe');
  const weights = path.join(data, 'araclar', '6DRepNet360_Full-Rotation_300W_LP+Panoptic.pth');
  const official = path.join(data, 'dis_kaynaklar', '6DRepNet360');
  const cli = path.join(repo, 'research', 'd01', 'pilot_cli.py');
  const protocol = path.join(repo, 'research', 'd01', 'parameters', 'pilot_v1.json');
  for (const file of [python, weights, cli, protocol, path.join(official, 'sixdrepnet360', 'test.py')]) {
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) throw new Error('local_runtime_path_missing');
  }
  const outputParent = path.join(data, 'outputs', 'd01_headpose_6drepnet360');
  if (!fs.existsSync(outputParent) || !fs.statSync(outputParent).isDirectory()) throw new Error('local_output_parent_missing');
  const runRoot = path.join(outputParent, 'emulator_api_' + new Date().toISOString().replace(/[-:.]/g, '') + '_' + randomBytes(8).toString('hex'));
  // Only this explicit object configures createApp. Inherited provider keys,
  // .env files and environment settings from other experiments are not used.
  const env = {
    BACKEND_MODE: 'deployment', GENERATION_MAX_CONCURRENT: '1',
    TEAM_ACCESS_KEY: payload.accessKey, PILOT_D01_ENABLED: 'true',
    PILOT_D01_PYTHON: python, PILOT_D01_WEIGHTS: weights,
    PILOT_D01_OFFICIAL_SOURCE: official, PILOT_D01_JOBS_DIR: path.join(runRoot, 'jobs'),
    PILOT_D01_TIMEOUT_MS: '900000', PILOT_D01_KILL_GRACE_MS: '10000',
  };
  delete payload.accessKey;
  let app;
  let stopping;
  const server = http.createServer((req, res) => {
    if (app) return app(req, res);
    res.writeHead(503, { 'content-type': 'application/json' });
    res.end('{"code":"pilot_initializing"}');
  });
  async function shutdown() {
    if (stopping) return stopping;
    stopping = (async () => {
      const closed = new Promise(resolve => server.close(resolve));
      server.closeIdleConnections?.();
      try { await app?.locals.pilotD01?.shutdown(); }
      catch { console.error('[pilot-local] shutdown_failed'); process.exitCode = 1; }
      finally {
        server.closeAllConnections?.();
        await closed;
        console.log('[pilot-local] stopped; job files preserved');
      }
    })();
    return stopping;
  }
  server.once('error', error => {
    console.error(error.code === 'EADDRINUSE'
      ? '[pilot-local] port_in_use: 127.0.0.1:8000; existing processes were not stopped'
      : '[pilot-local] listen_failed');
    process.exitCode = 1;
  });
  // Reserve the real port before creating a job root/owner lock. No probe/bind race.
  server.listen({ host: '127.0.0.1', port: 8000, exclusive: true }, () => {
    try {
      fs.mkdirSync(runRoot, { recursive: false, mode: 0o700 }); // Never reuse an old run.
      const { createApp } = require('./server'); // require.main guard prevents dotenv/startup.
      app = createApp({ env, generate: async () => { throw new Error('provider_disabled_in_local_pilot'); } });
      fs.writeFileSync(path.join(runRoot, 'local_server.json'), JSON.stringify({
        startedUtc: new Date().toISOString(), address: 'http://127.0.0.1:8000',
        python, weights, officialSource: official, cli, protocol,
        jobsDirectory: env.PILOT_D01_JOBS_DIR, analysisTimeoutMs: 900000, killGraceMs: 10000,
        dotenvLoaded: false, accessKeySaved: false, automaticAnalysis: false,
      }, null, 2), { flag: 'wx', mode: 0o600 });
      console.log('[pilot-local] ready http://127.0.0.1:8000');
      console.log('[pilot-local] jobs ' + env.PILOT_D01_JOBS_DIR);
      console.log('[pilot-local] timeout=900s kill_grace=10s; no analysis submitted');
      console.log('[pilot-local] keep this terminal open; Ctrl+C requests owned-job shutdown');
    } catch {
      console.error('[pilot-local] startup_failed; no error dump or secret logged');
      process.exitCode = 1;
      void shutdown();
    }
  });
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { void shutdown(); });
}

if (require.main === module) main().catch(error => {
  const safeCodes = new Set(['invalid_session_key', 'local_runtime_path_missing', 'local_output_parent_missing']);
  console.error('[pilot-local] ' + (safeCodes.has(error.message) ? error.message : 'preflight_failed'));
  process.exitCode = 1;
});
