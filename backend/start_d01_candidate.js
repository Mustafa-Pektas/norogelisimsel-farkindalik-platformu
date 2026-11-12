// Isolated loopback-only pilot, no dotenv, no Gemini; key comes from JSON stdin.
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');

async function main() {
  const input=JSON.parse(fs.readFileSync(0,'utf8'));
  if(typeof input.accessKey!=='string' || !/^[\x21-\x7e]+$/.test(input.accessKey)) throw new Error('invalid_session_key');
  const port=process.env.PILOT_CANDIDATE_PORT;
  if(!/^[1-9]\d*$/.test(port??'') || Number(port)>65535) throw new Error('invalid_candidate_port');
  const root=process.env.PILOT_D01_JOBS_DIR;
  if(!root || !path.isAbsolute(root) || fs.existsSync(root)) throw new Error('new_absolute_job_root_required');
  const env={BACKEND_MODE:'deployment',TEAM_ACCESS_KEY:input.accessKey,GENERATION_MAX_CONCURRENT:'1',PILOT_D01_ENABLED:'true'};
  for(const name of ['PILOT_D01_PYTHON','PILOT_D01_WEIGHTS','PILOT_D01_OFFICIAL_SOURCE','PILOT_D01_JOBS_DIR',
    'PILOT_D01_FAST_PYTHON','PILOT_D01_FACE_MODEL','PILOT_D01_AUDIO_MODEL','PILOT_D01_FAST_ENGINE',
    'PILOT_D01_STRIDE4_SOURCE','PILOT_D01_ONNX_MODEL','PILOT_D01_TIMEOUT_MS','PILOT_D01_KILL_GRACE_MS']) {
    if(process.env[name]!==undefined)env[name]=process.env[name];
  }
  delete input.accessKey;
  let app,stopping;
  const server=http.createServer((req,res)=>{
    if(app)return app(req,res);
    res.writeHead(503,{'content-type':'application/json'});res.end('{"code":"candidate_initializing"}');
  });
  async function stop() {
    if(stopping)return stopping;
    stopping=(async()=>{
      const closed=new Promise(resolve=>server.close(resolve));server.closeIdleConnections?.();
      try{await app?.locals.pilotD01?.shutdown();}
      finally{server.closeAllConnections?.();await closed;}
    })();return stopping;
  }
  server.on('error',error=>{console.error(error.code==='EADDRINUSE'?'candidate_port_in_use':'candidate_listen_failed');process.exitCode=1;});
  server.listen({host:'127.0.0.1',port:Number(port),exclusive:true},()=>{
    try{
      const {createApp}=require('./server');
      app=createApp({env,generate:async()=>{throw new Error('provider_disabled_in_candidate');}});
      console.log(`D01 candidate ready 127.0.0.1:${port}; ${env.PILOT_D01_FAST_ENGINE ?? 'mediapipe_pnp_flow'}; keep terminal open`);
    }catch{console.error('candidate_start_failed');process.exitCode=1;void stop();}
  });
  for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>{void stop();});
}
if(require.main===module)main().catch(()=>{console.error('candidate_preflight_failed');process.exitCode=1;});
