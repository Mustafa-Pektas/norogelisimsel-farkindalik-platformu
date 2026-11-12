const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const finite = v => typeof v === 'number' && Number.isFinite(v);
function fastMainResult(job, run, state, result) {
  const bad = () => { throw new Error('invalid fast result'); };
  const meta = result.video_metadata; const counts = result.counts;
  const poseEngine = result.poseEngine ?? 'mediapipe_pnp_flow';
  if (!['mediapipe_pnp_flow','cascade_stride4_onnx'].includes(poseEngine) ||
      poseEngine !== (job.poseEngine ?? 'mediapipe_pnp_flow')) bad();
  if (poseEngine !== (state.pose_engine ?? 'mediapipe_pnp_flow')) bad();
  const repnetCalls=result.engineCounts?.repnetCalls ?? null;
  if (repnetCalls !== null && (!Number.isInteger(repnetCalls) || repnetCalls<0)) bad();
  if (state.status !== 'completed' || state.method !== 'mediapipe_pnp_flow' || state.model_loaded !== true ||
      result.schema_version !== 'd01-fast-result-1.0' || result.method !== 'mediapipe_pnp_flow' || result.video_hash !== job.videoHash ||
      !meta || meta.fps !== 24 || !Number.isInteger(meta.width) || !Number.isInteger(meta.height) || meta.width <= 0 || meta.height <= 0 ||
      !finite(meta.duration_s) || meta.duration_s <= 0 || meta.duration_s > 30 ||
      !counts || !Number.isInteger(counts.processed) || counts.processed <= 0 || counts.processed > 720 ||
      !Number.isInteger(counts.valid) || !Number.isInteger(counts.invalid) || counts.valid < 0 || counts.invalid < 0 ||
      counts.valid + counts.invalid !== counts.processed || counts.processed !== state.processed_frames || counts.valid !== state.valid_frames ||
      meta.decoded_frame_count !== counts.processed || Math.abs(meta.duration_s - counts.processed / 24) > .001) bad();
  const refs = Object.values(result.detail_files || {});
  if (!refs.length || refs.length > 32) bad();
  for (const ref of refs) {
    if (typeof ref.path !== 'string' || !/^details\/[a-zA-Z0-9_.-]+$/.test(ref.path)) bad();
    const file = path.join(run, ref.path);
    if (!fs.lstatSync(file).isFile() || path.dirname(fs.realpathSync(file)) !== fs.realpathSync(path.join(run, 'details')) ||
        fs.statSync(file).size > 32 * 1024 * 1024 || hash(fs.readFileSync(file)) !== ref.sha256) bad();
  }
  const manualTimes = {};
  for (const key of ['call_start_s', 'call_end_s', 'response_start_s', 'response_end_s']) {
    const expected = job.manual[key] ?? null;
    if (result.manualTimes?.[key]?.time_s !== expected || (expected !== null && expected > meta.duration_s)) bad();
    manualTimes[key] = { time_s: expected, source: expected === null ? null : 'manual_user_input' };
  }
  const movements = {};
  let callTiming;
  if (result.callTiming !== undefined) {
    const t = result.callTiming;
    const statuses = ['accepted','not_found','ambiguous','low_confidence','unavailable','failed'];
    if (!t || t.schemaVersion !== 'd01-call-timing-1.0' || t.name !== 'Deniz' || t.language !== 'tr' ||
        !statuses.includes(t.audioStatus) || !['manual_user_input','automatic_word_timing','unknown'].includes(t.source) ||
        (t.matchCount !== null && (!Number.isInteger(t.matchCount) || t.matchCount < 0 || t.matchCount > 1000))) bad();
    const manual = job.manual.call_start_s !== undefined;
    if (manual ? t.source !== 'manual_user_input' || t.startS !== job.manual.call_start_s || t.endS !== job.manual.call_end_s
      : t.audioStatus === 'accepted' ? t.source !== 'automatic_word_timing' || t.matchCount !== 1 : t.source !== 'unknown') bad();
    if (t.source === 'unknown' ? t.startS !== null || t.endS !== null
      : !finite(t.startS) || !finite(t.endS) || t.startS < 0 || t.endS < t.startS ||
        (t.source === 'automatic_word_timing' && t.endS === t.startS) || t.endS > meta.duration_s) bad();
    callTiming = {schemaVersion:t.schemaVersion,source:t.source,startS:t.startS,endS:t.endS,
      audioStatus:t.audioStatus,matchCount:t.matchCount,name:'Deniz',language:'tr'};
  }
  for (const mode of ['raw', 'ema_050']) {
    const rows = result.movements?.[mode]; if (!Array.isArray(rows) || rows.length > 1000) bad();
    if (new Set(rows.map(c => c.candidate_id)).size !== rows.length) bad();
    movements[mode] = rows.map(c => {
      const safe = {};
      if (typeof c.candidate_id !== 'string' || !/^candidate_\d+$/.test(c.candidate_id)) bad();
      safe.candidate_id = c.candidate_id;
      for (const k of ['movement_start_s', 'movement_end_s', 'start_confirmation_time_s', 'end_confirmation_time_s', 'start_minus_manual_call_start_s', 'start_minus_manual_call_end_s']) {
        if (c[k] !== null && !finite(c[k])) bad(); safe[k] = c[k];
      }
      const a = callTiming ? callTiming.startS ?? undefined : job.manual.call_start_s;
      const b = callTiming ? callTiming.endS ?? undefined : job.manual.call_end_s, start = c.movement_start_s;
      for (const key of ['movement_start_s','movement_end_s','start_confirmation_time_s','end_confirmation_time_s']) {
        if (c[key] !== null && (c[key] < 0 || c[key] > meta.duration_s)) bad();
      }
      if (start !== null && c.movement_end_s !== null && c.movement_end_s < start) bad();
      const phase = a === undefined || b === undefined ? 'call_unknown' : start === null ? 'unknown_movement_start' : start < a ? 'before_call' : start <= b ? 'during_call' : 'after_call';
      if (c.callPhase !== phase) bad();
      for (const [key, call] of [['start_minus_manual_call_start_s', a], ['start_minus_manual_call_end_s', b]]) {
        const expected = start === null || call === undefined ? null : start - call;
        if (expected === null ? c[key] !== null : !finite(c[key]) || Math.abs(c[key] - expected) > 1e-6) bad();
      }
      return { ...safe, callPhase: phase };
    });
  }
  const coverage = {};
  for (const key of ['poseFrames', 'flowOnlyFrames', 'lostFrames', 'ambiguousFrames', 'totalFrames']) {
    const v = result.coverage?.[key]; if (!Number.isInteger(v) || v < 0 || v > counts.processed) bad(); coverage[key] = v;
  }
  if (coverage.poseFrames !== counts.valid || coverage.totalFrames !== counts.processed ||
      coverage.poseFrames + coverage.flowOnlyFrames + coverage.lostFrames > counts.processed || coverage.ambiguousFrames > coverage.lostFrames) bad();
  const intervals = result.missingPoseIntervals;
  if (!Array.isArray(intervals) || intervals.length > 720) bad();
  const missingPoseIntervals = intervals.map(i => {
    if (!finite(i.startS) || !finite(i.endS) || i.startS < 0 || i.endS < i.startS || i.endS > meta.duration_s || !Number.isInteger(i.frames) || i.frames <= 0) bad();
    return { startS: i.startS, endS: i.endS, frames: i.frames };
  });
  if (!['manual_initial_point', 'single_face_candidate_role_unverified', 'not_determined'].includes(result.targetSelection) ||
      !['ambiguous_or_unselected', 'continuity_candidate_not_biometric_identity'].includes(result.identityStatus)) bad();
  if (result.targetSelection === 'manual_initial_point' && !job.targetPoint) bad();
  const timings = {};
  for (const key of ['media_preflight_s', 'model_load_s', 'tracking_pnp_s', 'candidate_postprocess_s', 'report_preparation_s', 'total_s']) {
    const v = result.timings?.[key]; if (!finite(v) || v < 0) bad(); timings[key] = v;
  }
  timings.upload_s = job.uploadCompletedAt === undefined ? null : (job.uploadCompletedAt - job.createdAt) / 1000;
  timings.child_process_s = job.childClosedAt === undefined ? null : (job.childClosedAt - job.childStartedAt) / 1000;
  for (const key of ['audio_s','audio_model_load_s','audio_transcribe_s']) {
    timings[key] = result.timings?.[key] ?? null;
    if (timings[key] !== null && (!finite(timings[key]) || timings[key] < 0)) bad();
  }
  for (const key of ['target_tracker_load_s','cascade_load_s']) {
    const value=result.timings?.[key] ?? null;
    if (value!==null && (!finite(value) || value<0)) bad();
    timings[key]=value;
  }
  return { schemaVersion: 'd01-pilot-api-1.2', jobId: job.jobId, profileId: null, videoHash: job.videoHash,
    source: { schemaVersion: 'd01-input-source-1.2', type: 'automatic_face_tracking', method: 'mediapipe_pnp_flow',
      poseEngine,
      targetSelection: result.targetSelection, identityStatus: result.identityStatus,
      video: { width: meta.width, height: meta.height, fps: 24, durationS: meta.duration_s, decodedFrames: counts.processed } },
    manualTimes, ...(callTiming ? {callTiming} : {}), movements, counts, coverage, missingPoseIntervals, timings,
    engineCounts:{repnetCalls}, settling: [],
    algorithmicTarget: 'not_determined', clockAlignmentVerified: false, manualCandidateStatus: 'unreviewed',
    interpretation: 'temporal_relations_only_not_response_or_target_classification' };
}
module.exports = { fastMainResult };
