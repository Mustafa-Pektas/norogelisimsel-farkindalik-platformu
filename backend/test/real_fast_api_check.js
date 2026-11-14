// Explicit local acceptance only. Never loaded by node --test.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
async function main() {
  const at = key => process.argv[process.argv.indexOf(key) + 1];
  if (!process.argv.includes('--run') || !process.argv.includes('--output-dir') || !process.argv.includes('--sources')) throw new Error('explicit_arguments_required');
  const root = path.resolve(at('--output-dir')); fs.mkdirSync(root, { recursive: false });
  const repo = path.resolve(__dirname, '../..'), data = path.dirname(repo);
  const sources = JSON.parse(fs.readFileSync(at('--sources'), 'utf8'));
  const automaticCall = process.argv.includes('--automatic-call');
  if (automaticCall && !envPathReady(process.env.PILOT_D01_AUDIO_MODEL)) throw new Error('prepared_audio_model_required');
  function envPathReady(p) { return typeof p === 'string' && path.isAbsolute(p) &&
    ['model.bin','config.json','tokenizer.json'].every(f=>fs.existsSync(path.join(p,f))); }
  const key = crypto.randomBytes(32).toString('hex');
  const env = { BACKEND_MODE:'deployment',TEAM_ACCESS_KEY:key,GENERATION_MAX_CONCURRENT:'1',PILOT_D01_ENABLED:'true',
    PILOT_D01_PYTHON:process.env.PILOT_D01_PYTHON || path.join(data,'.venv_headpose/Scripts/python.exe'),
    PILOT_D01_WEIGHTS:process.env.PILOT_D01_WEIGHTS || path.join(data,'araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.pth'),
    PILOT_D01_OFFICIAL_SOURCE:process.env.PILOT_D01_OFFICIAL_SOURCE || path.join(data,'dis_kaynaklar/6DRepNet360'),PILOT_D01_JOBS_DIR:path.join(root,'jobs'),
    PILOT_D01_FAST_PYTHON:process.env.PILOT_D01_FAST_PYTHON || path.join(data,'calisma/venv_d01_hybrid_20261107_01/Scripts/python.exe'),
    PILOT_D01_AUDIO_MODEL:process.env.PILOT_D01_AUDIO_MODEL,
    PILOT_D01_FAST_ENGINE:process.env.PILOT_D01_FAST_ENGINE,
    PILOT_D01_STRIDE4_SOURCE:process.env.PILOT_D01_STRIDE4_SOURCE,
    PILOT_D01_ONNX_MODEL:process.env.PILOT_D01_ONNX_MODEL,
    PILOT_D01_FACE_MODEL:process.env.PILOT_D01_FACE_MODEL || path.join(data,'calisma/Video Analizinin Feasibility Testi/face_landmarker.task'),
    PILOT_D01_TIMEOUT_MS:process.env.PILOT_D01_TIMEOUT_MS ?? '120000',PILOT_D01_KILL_GRACE_MS:process.env.PILOT_D01_KILL_GRACE_MS ?? '10000' };
  const timing=require('../pilot_timing').backendTiming(env);
  const {createApp}=require('../server');
  const app=createApp({env,generate:async()=>{throw new Error('provider_disabled');}}),server=http.createServer(app);
  const report=[];
  try {
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
    const address=`http://127.0.0.1:${server.address().port}`;
    async function request(method,suffix,body,expected) {
      const r=await fetch(address+'/api/pilot-d01/jobs'+suffix,{method,headers:{Authorization:`Bearer ${key}`},body,signal:AbortSignal.timeout(15000)});
      const json=await r.json();assert.equal(r.status,expected,`HTTP ${r.status}: ${json.code ?? ''}`);return json;
    }
    for (let i=0;i<sources.length;i++) {
      const source=sources[i],bytes=fs.readFileSync(source.video),digest=crypto.createHash('sha256').update(bytes).digest('hex');
      assert.equal(digest,source.sha256);
      const started=performance.now(),form=new FormData();form.set('video',new Blob([bytes]),'pilot.mp4');
      form.set('method','mediapipe_pnp_flow');
      if(Array.isArray(source.targetPoint))form.set('targetPoint',JSON.stringify(source.targetPoint));
      if(!automaticCall && source.callStartS!==null){form.set('callStartS',source.callStartS.toFixed(3));form.set('callEndS',source.callEndS.toFixed(3));}
      const accepted=await request('POST','',form,202);assert.equal(accepted.videoHash,digest);
      let state; const deadline=performance.now()+timing.timeoutMs+timing.killGraceMs+5000;
      do {
        state=await request('GET','/'+accepted.jobId,undefined,200);
        if(['completed','failed','interrupted'].includes(state.status)) break;
        await new Promise(r=>setTimeout(r,250));
      } while(performance.now()<deadline);
      assert.equal(state.status,'completed',state.code ?? 'client_wait_limit');
      const result=await request('GET','/'+accepted.jobId+'/result',undefined,200);
      assert.equal(result.schemaVersion,'d01-pilot-api-1.2');assert.equal(result.videoHash,digest);assert.equal(result.jobId,accepted.jobId);
      assert.equal(result.source.poseEngine ?? 'mediapipe_pnp_flow',env.PILOT_D01_FAST_ENGINE ?? 'mediapipe_pnp_flow');
      assert.equal(result.manualTimes.response_start_s.time_s,null);assert.equal(JSON.stringify(result).includes(root),false);
      assert.equal(result.counts.processed,result.source.video.decodedFrames);
      if(automaticCall) {
        assert.ok(result.callTiming);assert.equal(result.manualTimes.call_start_s.time_s,null);
        assert.equal(result.manualTimes.call_end_s.time_s,null);
        assert.ok(!['unavailable','failed'].includes(result.callTiming.audioStatus),'real_audio_step_not_completed');
      }
      const job=JSON.parse(fs.readFileSync(path.join(root,'jobs',accepted.jobId,'job.json')));
      assert.ok(job.childClosedAt>=job.childStartedAt);
      assert.equal(job.childExitCode,0);
      report.push({index:i,jobId:accepted.jobId,status:state.status,videoHash:digest,poseEngine:result.source.poseEngine,engineCounts:result.engineCounts,counts:result.counts,coverage:result.coverage,
        upload_to_result_s:(performance.now()-started)/1000,mobile_visible_elapsed_s:null,timings:result.timings,
        ...(automaticCall ? {callTiming:result.callTiming,manualComparison:{status:'approximate_candidate_not_ground_truth',
          referenceStartS:source.callStartS,referenceEndS:source.callEndS,
          startDifferenceS:result.callTiming.source==='automatic_word_timing' && Number.isFinite(source.callStartS)?result.callTiming.startS-source.callStartS:null,
          endDifferenceS:result.callTiming.source==='automatic_word_timing' && Number.isFinite(source.callEndS)?result.callTiming.endS-source.callEndS:null}} : {})});
      fs.writeFileSync(path.join(root,`api_result_${i}.json`),JSON.stringify(result,null,2));
      fs.writeFileSync(path.join(root,'acceptance.json'),JSON.stringify({runs:report,mobileAcceptance:'not_run'},null,2));
      console.log(JSON.stringify(report.at(-1)));
    }
  } catch (error) {
    const states=fs.readdirSync(env.PILOT_D01_JOBS_DIR).filter(n=>/^[0-9a-f-]{36}$/.test(n)).map(n=>{
      const job=JSON.parse(fs.readFileSync(path.join(env.PILOT_D01_JOBS_DIR,n,'job.json')));
      return {jobId:job.jobId,status:job.status,code:job.code ?? null,startFailure:job.startFailure ?? null,
        childExitCode:job.childExitCode ?? null,childExitSignal:job.childExitSignal ?? null};
    });
    fs.writeFileSync(path.join(root,'failure.json'),JSON.stringify({completedRuns:report,jobs:states,errorCode:error.code ?? 'acceptance_failed',mobileVisibleElapsed:null},null,2));
    throw error;
  } finally {
    await app.locals.pilotD01.shutdown();server.closeAllConnections?.();
    await new Promise(r=>server.close(r));
    fs.writeFileSync(path.join(root,'closed.json'),JSON.stringify({backendClosed:!server.listening,ownChildrenClosed:true}));
  }
}
if(require.main===module)main().catch(e=>{console.error('fast_acceptance_failed:',e.code ?? e.message);process.exitCode=1;});
