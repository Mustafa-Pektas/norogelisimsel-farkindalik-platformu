"""Bounded CPU Tasks/PnP/flow job with optional local-only ASR word timing."""
from pathlib import Path
import argparse
import json
import time
import signal
import os
import importlib.metadata
import hashlib
from collections import Counter
from fast_tracking import FastTracker,call_phase
from pilot_cli import inspect_marked_video,atomic,append,PilotInputError,load_protocol
from motion_candidates import sha,detect
from compare_headpose_methods import series
from pilot_metrics import environment,memory
from automatic_call import detect_call,effective_timing


def atomic_state(path, data):
    """Keep atomic replacement; tolerate only bounded Windows access/sharing races.

    Readers/security software may temporarily hold the destination. Persistent
    permission failures still propagate; no truncate-in-place or model retry.
    """
    delays=(.01,.02,.04,.08)
    for attempt in range(len(delays)+1):
        try:
            return atomic(path,data)
        except PermissionError as error:
            if getattr(error,'winerror',None) not in (5,32,33) or attempt==len(delays):raise
            time.sleep(delays[attempt])


def gaps(rows):
    result=[];active=None
    for row in rows:
        if not row['valid']:
            if active is None:active=dict(startS=row['time_s'],endS=row['time_s'],frames=0)
            active['endS']=row['time_s'];active['frames']+=1
        elif active is not None:result.append(active);active=None
    if active is not None:result.append(active)
    return result


def run(args):
    start=time.perf_counter();out=args.output_dir.resolve();out.mkdir(parents=True,exist_ok=False)
    os.environ.setdefault('MPLCONFIGDIR',str(out/'matplotlib_config'))
    details=out/'details';details.mkdir();rows=[];tracker=None
    timings={};state=dict(status='running',stage='preflight',method='mediapipe_pnp_flow',model_loaded=False,processed_frames=0,valid_frames=0)
    def checkpoint(**data):
        state.update(data);state.update(elapsed_s=time.perf_counter()-start,timings_s=timings,resource=memory());atomic_state(out/'state.json',state)
    checkpoint()
    protected={str(p.resolve()):sha(p) for p in [args.video,args.face_model,Path(__file__),Path(__file__).with_name('fast_tracking.py'),Path(__file__).parent/'vendor/friend_vision.py']+[p for p in [args.manual,args.target_point] if p is not None]}
    try:
        pose_engine=getattr(args,'pose_engine','mediapipe_pnp_flow')
        if pose_engine not in ('mediapipe_pnp_flow','cascade_stride4_onnx'):
            raise ValueError('Unsupported pose engine')
        t=time.perf_counter();info=inspect_marked_video(args.video);timings['media_preflight_s']=time.perf_counter()-t
        checksum=sha(args.video)
        if sha(args.face_model)!='64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff':raise PilotInputError('invalid_video','Unexpected local Tasks asset')
        marks={};call_start=call_end=None
        if args.manual:
            annotation=json.loads(args.manual.read_text(encoding='utf-8-sig'))
            if annotation['video_sha256']!=checksum:raise PilotInputError('invalid_video','Manual identity mismatch')
            marks=annotation.get('marks',{})
            if set(marks)!={'call_start_s','call_end_s'}:raise PilotInputError('invalid_manual_times','Both call times or neither required')
            values=[marks[k]['media_time_ms'] for k in ('call_start_s','call_end_s')]
            if any(type(v) is not int or v<0 or v>info['duration_s']*1000 for v in values) or values[1]<values[0]:raise PilotInputError('invalid_manual_times','Call bounds invalid')
            call_start,call_end=[v/1000 for v in values]
        point=None
        if args.target_point:
            point=json.loads(args.target_point.read_text())
            if not isinstance(point,list) or len(point)!=2 or any(type(v) not in (int,float) or not 0<=v<=1 for v in point):raise PilotInputError('invalid_target','Normalized initial target point invalid')
        if pose_engine=='cascade_stride4_onnx' and point is None:
            raise PilotInputError('invalid_target','Stride4 requires an explicit target point')
        manual_start,manual_end=call_start,call_end
        checkpoint(stage='automatic_call',video_metadata=info)
        audio=detect_call(args.video,getattr(args,'audio_model',None),info['duration_s'])
        atomic(details/'audio_call.json',audio)
        timings['audio_s']=audio['timings']['total_s']
        timings['audio_model_load_s']=audio['timings'].get('model_load_s')
        timings['audio_transcribe_s']=audio['timings'].get('transcribe_s')
        timing=effective_timing(audio,manual_start,manual_end)
        call_start,call_end=timing['startS'],timing['endS']
        atomic(out/'settings.json',dict(video_hash=checksum,video=info,target_point=point,manual_call_times=[manual_start,manual_end],protocol='d01-fast-1.0',face_model_sha256=sha(args.face_model),association=dict(min_iou=.15,max_histogram_l2=.45,max_loss_s=2.5,no_reacquisition_after_long_loss=pose_engine!='cascade_stride4_onnx'),automatic_call=dict(name='Deniz',language='tr',local_files_only=True,word_probability_min=.8,segment_no_speech_max=.5,segment_avg_logprob_min=-1.,not_clinical_thresholds=True)))
        checkpoint(stage='model_load',video_metadata=info)
        t=time.perf_counter()
        if pose_engine=='cascade_stride4_onnx':
            from stride4_tracking import Stride4Tracker
            tracker=Stride4Tracker(args.face_model,point,args.stride4_source,args.onnx_model)
            atomic(details/'pose_engine.json',tracker.provenance)
        else:
            tracker=FastTracker(args.face_model,point)
        timings['model_load_s']=time.perf_counter()-t
        timings.update(getattr(tracker,'load_timings',{}))
        checkpoint(pose_engine=pose_engine)
        checkpoint(stage='tracking',model_loaded=True)
        import cv2
        cap=cv2.VideoCapture(str(args.video));elapsed_tracking=0.
        try:
            with (details/'frames.jsonl').open('x',encoding='utf-8') as stream:
                while True:
                    ok,frame=cap.read()
                    if not ok:break
                    i=len(rows);t=cap.get(cv2.CAP_PROP_POS_MSEC)/1000
                    begin=time.perf_counter();row=tracker.update(frame,t);duration=time.perf_counter()-begin;elapsed_tracking+=duration
                    row.update(decoded_rgb_sha256=hashlib.sha256(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB).tobytes()).hexdigest(),frame_index=i,nominal_time_s=i/24,time_s=t,decoder_time_s=t,time_source='OpenCV_POS_MSEC_checked_CFR24',measurement_s=duration)
                    rows.append(row);append(stream,row);checkpoint(processed_frames=len(rows),valid_frames=sum(r['valid'] for r in rows))
        finally:cap.release()
        timings['tracking_pnp_s']=elapsed_tracking
        if len(rows)!=info['decoded_frame_count']:raise PilotInputError('invalid_video','Decode changed after preflight')
        checkpoint(stage='candidates');t=time.perf_counter()
        _,config,_,_=load_protocol(Path(__file__).parent/'parameters/pilot_v1.json')
        base=next(s for s in config['settings'] if s['id']=='base');movements={}
        for mode,rs in series(rows,config).items():
            detection=detect(rs,config,base);atomic(details/(mode+'.json'),detection)
            movements[mode]=[dict(candidate_id=c['candidate_id'],movement_start_s=c['start_s'],movement_end_s=c['end_s'],
                start_confirmation_time_s=c['start_confirmed_s'],end_confirmation_time_s=c['end_confirmed_s'],
                start_minus_manual_call_start_s=None if c['start_s'] is None or call_start is None else c['start_s']-call_start,
                start_minus_manual_call_end_s=None if c['start_s'] is None or call_end is None else c['start_s']-call_end,
                callPhase=call_phase(c['start_s'],call_start,call_end)) for c in detection['candidates']]
        timings['candidate_postprocess_s']=time.perf_counter()-t
        engine_counts=dict(repnetCalls=getattr(tracker,'repnet_calls',None))
        tracker.close();tracker=None;t=time.perf_counter()
        counts=Counter(r['track_source'] for r in rows)
        runtime=environment(device='CPU Tasks + ONNX Runtime' if pose_engine=='cascade_stride4_onnx' else 'Tasks CPU')
        for name in ['mediapipe','opencv-contrib-python','onnxruntime']:
            try:runtime['packages'][name]=importlib.metadata.version(name)
            except importlib.metadata.PackageNotFoundError:runtime['packages'][name]=None
        result=dict(schema_version='d01-fast-result-1.0',method='mediapipe_pnp_flow',poseEngine=pose_engine,engineCounts=engine_counts,video_hash=checksum,video_metadata=info,
            counts=dict(processed=len(rows),valid=sum(r['valid'] for r in rows),invalid=sum(not r['valid'] for r in rows)),
            coverage=dict(poseFrames=sum(r['valid'] for r in rows),flowOnlyFrames=sum(r['track_source']=='optical_flow' and not r['valid'] for r in rows),
                lostFrames=sum(r['track_source']=='lost' for r in rows),ambiguousFrames=sum(r['identity_status']=='target_ambiguous' for r in rows),totalFrames=len(rows)),
            targetSelection=rows[0]['target_provenance'],identityStatus='ambiguous_or_unselected' if not any(r['target_provenance']!='not_determined' for r in rows) else 'continuity_candidate_not_biometric_identity',
            missingPoseIntervals=gaps(rows),callTiming=timing,manualTimes={k:dict(time_s=v,source='manual_user_input' if v is not None else None) for k,v in [('call_start_s',manual_start),('call_end_s',manual_end),('response_start_s',None),('response_end_s',None)]},
            movements=movements,algorithmicTarget='not_determined',clockAlignmentVerified=False,manualCandidateStatus='unreviewed',
            interpretation='temporal_relations_only_not_response_or_target_classification',runtime=runtime,
            detail_files={p.name:dict(path='details/'+p.name,sha256=sha(p)) for p in details.iterdir() if p.is_file()},
            limitations=['Flow-only has no absolute angles','Generic PnP camera/face model; no calibrated shared neutral with6D','Track identity is conservative continuity, not verified age/child classification','ASR word timing is an unreviewed estimate; no speaker/actual call/response/correct-target/clinical classification'])
        timings['report_preparation_s']=time.perf_counter()-t;timings['total_s']=time.perf_counter()-start;result['timings']=timings
        if any(sha(p)!=h for p,h in protected.items()):raise ValueError('Protected source changed')
        atomic(out/'result.json',result);atomic(out/'source_preservation.json',dict(files=protected,unchanged=True));checkpoint(status='completed',stage='finished',invalid_frames=result['counts']['invalid'])
        return result
    except BaseException as error:
        checkpoint(status='interrupted' if isinstance(error,KeyboardInterrupt) else 'failed',code=getattr(error,'code','fast_cli_failed'));raise
    finally:
        if tracker is not None:tracker.close()


if __name__=='__main__':
    def interrupted(*_):raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM,interrupted)
    parser=argparse.ArgumentParser(description=__doc__)
    for k in ('video','face-model','output-dir'):parser.add_argument('--'+k,type=Path,required=True)
    parser.add_argument('--manual',type=Path);parser.add_argument('--target-point',type=Path)
    parser.add_argument('--audio-model',type=Path,help='Prepared local faster-whisper directory only; never download during analysis')
    parser.add_argument('--pose-engine',choices=['mediapipe_pnp_flow','cascade_stride4_onnx'],default='mediapipe_pnp_flow')
    parser.add_argument('--stride4-source',type=Path)
    parser.add_argument('--onnx-model',type=Path)
    run(parser.parse_args())
