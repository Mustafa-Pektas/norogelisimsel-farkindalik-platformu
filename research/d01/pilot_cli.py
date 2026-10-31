"""One pilot CLI: durable CPU inference OR saved-matrix replay, fixed rules, small report."""
from pathlib import Path
from datetime import datetime,timezone
import argparse
import collections
import copy
import csv
import hashlib
import json
import math
import os
import sys
import time

from motion_candidates import detect,rotation,sha
from settling_regions import scan
from rotation_processing import causal_ema_matrices
from pilot_time_relations import build_report,readable
from pilot_metrics import Metrics, environment

def atomic(path,data):
    tmp=path.with_suffix('.tmp')
    with tmp.open('w',encoding='utf-8') as f:
        json.dump(data,f,ensure_ascii=False,indent=2,allow_nan=False);f.write('\n');f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)

def append(stream,data):
    stream.write(json.dumps(data,allow_nan=False)+'\n');stream.flush();os.fsync(stream.fileno())

def finite_time(value):
    return isinstance(value,(float,int)) and not isinstance(value,bool) and math.isfinite(value) and value>=0

def cpu_threads(protocol, override=None):
    value=protocol['cpu_threads'] if override is None else override
    if type(value) is not int or value not in (1,2,4):
        raise ValueError('CPU threads must be an integer: 1, 2 or 4')
    return value

def crop_roi(image,roi):
    from PIL import Image
    x,y,w,h=(roi[k] for k in ('x','y','width','height'))
    if any(type(v) is not int for v in (x,y,w,h)) or min(w,h)<=0:raise ValueError('ROI requires integer x/y and positive width/height')
    width,height=image.size
    required=[max(0,-x),max(0,-y),max(0,x+w-width),max(0,y+h-height)]
    if roi.get('padding_ltrb_source_px')!=required:raise ValueError('Explicit ROI padding does not match source bounds')
    left,top,right,bottom=max(0,x),max(0,y),min(width,x+w),min(height,y+h)
    if right<=left or bottom<=top:raise ValueError('ROI does not intersect video')
    if not any(required):return image.crop((x,y,x+w,y+h))
    rgb=roi.get('padding_rgb')
    if not isinstance(rgb,list) or len(rgb)!=3 or any(type(v) is not int or not 0<=v<=255 for v in rgb):raise ValueError('Explicit constant RGB padding required')
    result=Image.new('RGB',(w,h),tuple(rgb));result.paste(image.crop((left,top,right,bottom)),(left-x,top-y))
    return result

def load_protocol(path):
    p=json.loads(path.read_text(encoding='utf-8'));base=path.parent
    if p['protocol_version']!='d01-pilot-fixed-1.0' or p['ema_alpha']!=.5 or p['movement_setting']!='base':raise ValueError('Unsupported fixed protocol')
    motion_path=base/p['motion_config'];settling_path=base/p['settling_config']
    if sha(motion_path)!=p['motion_config_sha256'] or sha(settling_path)!=p['settling_config_sha256']:raise ValueError('Fixed rule configuration hash mismatch')
    motion=json.loads(motion_path.read_text());settling=json.loads(settling_path.read_text())
    if motion['nominal_fps']!=p['fps'] or settling['nominal_fps']!=p['fps']:raise ValueError('Protocol FPS mismatch')
    if p['matrix_tolerance']!=1e-4:raise ValueError('Unsupported matrix tolerance')
    return p,motion,settling,[path,motion_path,settling_path]

def video_info(path):
    import cv2
    cap=cv2.VideoCapture(str(path))
    try:
        if not cap.isOpened():raise ValueError('Video could not be opened')
        return dict(width=int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),height=int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)),
            fps=cap.get(cv2.CAP_PROP_FPS),declared_frame_count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT)))
    finally:cap.release()

def replay_rows(path,info):
    indexed={}
    with path.open(encoding='utf-8') as f:
        for line in f:
            if not line.strip():continue
            r=json.loads(line);i=r['frame_index']
            if type(i) is not int or i<0 or i in indexed:raise ValueError('Invalid/duplicate recorded frame index')
            indexed[i]=r
    total=max(info['declared_frame_count'],max(indexed,default=-1)+1)
    if total==0:raise ValueError('No recorded frames')
    for i in range(total):
        r=copy.deepcopy(indexed.get(i,dict(frame_index=i,nominal_time_s=i/info['fps'],decoder_time_s=None,
            valid=False,rotation_matrix=None,error='missing_recorded_frame',time_source='unknown_not_imputed')))
        yield r

def live_rows(video,info,roi,runtime,out):
    import cv2
    from PIL import Image
    cap=cv2.VideoCapture(str(video));i=0
    try:
        if not cap.isOpened():raise ValueError('Video decode open failed')
        while True:
            decode_start=time.perf_counter();ok,bgr=cap.read();decode_s=time.perf_counter()-decode_start
            if not ok:break
            t=cap.get(cv2.CAP_PROP_POS_MSEC)/1000
            r=dict(frame_index=i,nominal_time_s=i/info['fps'],decoder_time_s=t if finite_time(t) else None,
                time_source='OpenCV decoder POS_MSEC; nominal frame/FPS separate; frame PTS/LibVLC alignment unverified',
                rotation_matrix=None,valid=False,error=None,inference_s=None,model_attempted=False,decode_s=decode_s,preprocess_s=None,input_save_s=None)
            try:
                if bgr.shape[:2]!=(info['height'],info['width']):raise ValueError('Frame resolution changed')
                prepare=time.perf_counter()
                try:image,tensor=runtime.prepare(crop_roi(Image.fromarray(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)),roi))
                finally:r['preprocess_s']=time.perf_counter()-prepare
                name=f'inputs/frame_{i:06d}.png';save_start=time.perf_counter();image.save(out/name);r['input_save_s']=time.perf_counter()-save_start
                r.update(input_image=name,input_rgb_sha256=hashlib.sha256(image.tobytes()).hexdigest(),
                    normalized_tensor_sha256=hashlib.sha256(tensor.numpy().tobytes()).hexdigest())
                r['model_attempted']=True;attempt=time.perf_counter()
                try:r.update(runtime.predict(tensor))
                finally:r['model_attempt_wall_s']=time.perf_counter()-attempt
            except Exception as exc:r['error']=f'{type(exc).__name__}: {exc}';r['valid']=False
            yield r;i+=1
        for missing in range(i,max(i,info['declared_frame_count'])):
            yield dict(frame_index=missing,nominal_time_s=missing/info['fps'],decoder_time_s=None,rotation_matrix=None,
                valid=False,error='not_decoded_after_decoder_stopped; EOF/corruption not independently distinguishable',time_source='unknown_not_imputed')
    finally:cap.release()

def analyze_records(raw,motion,settling,details,checkpoint,metrics=None):
    import numpy as np
    def save_json(path,data):
        started=time.perf_counter()
        try:atomic(path,data)
        finally:
            if metrics is not None:metrics.add('postprocess_detail_write_s',time.perf_counter()-started)
    def write_row(stream,data):
        started=time.perf_counter()
        try:append(stream,data)
        finally:
            if metrics is not None:metrics.add('postprocess_detail_write_s',time.perf_counter()-started)
    matrices=[];previous=None;breaks=set()
    for index,r in enumerate(raw):
        m=rotation(r.get('rotation_matrix')) if r.get('valid') and finite_time(r.get('decoder_time_s')) else None
        if previous is not None and (r['frame_index']!=previous['frame_index']+1 or not finite_time(r.get('decoder_time_s')) or not finite_time(previous.get('decoder_time_s')) or
                not 0<r['decoder_time_s']-previous['decoder_time_s']<=motion['max_dt_factor']/motion['nominal_fps']):
            # A gap resets EMA state by segment, rather than bridging missing evidence.
            breaks.add(index)
        matrices.append(m);previous=r
    # Preserve raw matrices/times; mark unavailable time as unusable, without replacing it.
    series={'raw':[dict(frame_index=r['frame_index'],time_s=r.get('decoder_time_s'),rotation_matrix=r.get('rotation_matrix'),
        valid=bool(r.get('valid')) and finite_time(r.get('decoder_time_s'))) for r in raw]}
    smoothed=causal_ema_matrices(matrices,.5,break_before=breaks)
    series['ema_050']=[dict(frame_index=r['frame_index'],time_s=r.get('decoder_time_s'),rotation_matrix=None if m is None else m.tolist(),valid=m is not None) for r,m in zip(raw,smoothed)]
    with (details/'ema_frames.jsonl').open('x',encoding='utf-8') as f:
        for r in series['ema_050']:write_row(f,r)
    base=next(s for s in motion['settings'] if s['id']=='base');det={};regions={};compact=[]
    with (details/'settling_windows.jsonl').open('x',encoding='utf-8') as log:
        for method,rs in series.items():
            checkpoint(stage='motion_'+method)
            result=detect(rs,motion,base)
            with (details/f'features_{method}.jsonl').open('x',encoding='utf-8') as f:
                for r in result.pop('feature_records'):write_row(f,r)
            det[method]={'base':result};regions[method]={}
            for radius in settling['radii_deg']:
                scans=[];unknown=[]
                for c in result['candidates']:
                    if c['start_frame'] is None:
                        unknown.append(dict(source_candidate_id=c['candidate_id'],reason='unknown_v1_start_no_substitute_used'));continue
                    s=scan(rs,c['start_frame'],radius,settling)
                    for w in s['windows']:write_row(log,dict(method=method,source_candidate_id=c['candidate_id'],**w))
                    counts=dict(collections.Counter(w['status'] for w in s['windows']))
                    summary=dict(method=method,radius_deg=radius,source_candidate_id=c['candidate_id'],fixed_v1_start_frame=c['start_frame'],
                        window_counts=counts,details_file='details/settling_windows.jsonl')
                    compact.append(summary);s.pop('windows');scans.append(dict(source_candidate_id=c['candidate_id'],**s))
                regions[method][str(radius)]=dict(scans=scans,unassessable_starts=unknown,no_v1_candidates=not result['candidates'])
                if not result['candidates'] or unknown:compact.append(dict(method=method,radius_deg=radius,no_v1_candidates=not result['candidates'],unassessable_starts=unknown))
    save_json(details/'motion.json',dict(protocol=motion['protocol'],parameters=motion,results=det,manual_labels_read=False))
    save_json(details/'settling_index.json',dict(protocol=settling['protocol'],parameters=settling,results=regions,manual_labels_read=False))
    return dict(protocol=motion['protocol'],results=det),compact

def run(args,info_reader=video_info,runtime_factory=None):
    out=args.output_dir.resolve();repo=Path(__file__).resolve().parents[2]
    if out.exists() or out==repo or repo in out.parents:raise ValueError('New external output directory required')
    out.mkdir(parents=True,exist_ok=False);details=out/'details';details.mkdir();start=time.perf_counter();metrics=Metrics()
    state=dict(schema_version='d01-pilot-run-1.0',status='running',stage='preflight',processed_frames=0,valid_frames=0,
        model_loaded=False,mode='recorded_replay' if args.recorded_raw else 'cpu_inference',pid=os.getpid(),runtime_environment=environment(device='not_loaded'))
    def checkpoint(**values):
        state.update(values);state['updated_utc']=datetime.now(timezone.utc).isoformat();state['elapsed_s']=time.perf_counter()-start
        state['measurements']=metrics.snapshot();state['resource_sample']=metrics.sample()
        save_start=time.perf_counter()
        atomic(out/'state.json',state)
        metrics.add('state_checkpoint_write_s',time.perf_counter()-save_start)
    checkpoint()
    try:
        protocol,motion,settling,config_paths=load_protocol(args.protocol.resolve())
        override=getattr(args,'cpu_threads',None)
        selected_threads=cpu_threads(protocol,override)
        execution=dict(requested_intraop_threads=selected_threads,
            source='protocol' if override is None else 'explicit_cli_override',effective_intraop_threads=None)
        checkpoint(execution=execution)
        roi=json.loads(args.roi.read_text(encoding='utf-8'))
        if roi.get('human_supplied') is not True:raise ValueError('Explicit human-supplied ROI declaration required')
        if bool(args.recorded_raw)!=bool(args.recorded_report):raise ValueError('Recorded raw and its report must be supplied together')
        inputs=[args.video,args.weights,args.roi,*config_paths]
        inputs.extend(Path(__file__).parent/name for name in ('pilot_cli.py','motion_candidates.py','settling_regions.py',
            'rotation_processing.py','official_runtime.py','pilot_time_relations.py','pilot_metrics.py'))
        if args.manual:inputs.append(args.manual)
        reviews=getattr(args,'user_review',None) or []
        inputs.extend(reviews)
        if args.recorded_raw:inputs.extend([args.recorded_raw,args.recorded_report])
        protected={str(p.resolve()):sha(p) for p in inputs}
        if sha(args.weights)!=protocol['weights_sha256']:raise ValueError('Local weight hash mismatch')
        info=info_reader(args.video)
        if info['fps']!=protocol['fps']:raise ValueError('Current fixed frame-window protocol requires 24 FPS; no automatic resampling or threshold adaptation')
        if info['width']<=0 or info['height']<=0:raise ValueError('Invalid video geometry')
        from PIL import Image
        crop_roi(Image.new('RGB',(info['width'],info['height'])),roi)
        atomic(out/'settings.json',dict(protocol=protocol,motion=motion,settling=settling,roi=roi,video=info,
            inputs_sha256=protected,human_roi_not_tracking=True,manual_times_not_given_to_detection=True,
            execution=dict(execution)))
        checkpoint(stage='raw',video_metadata=info)
        if args.recorded_raw:
            original=json.loads(args.recorded_report.read_text(encoding='utf-8'))
            if original['video_sha256']!=sha(args.video) or original['weight_sha256']!=protocol['weights_sha256']:raise ValueError('Recorded source/model mismatch')
            if original.get('official_source_sha256')!=protocol['official_source_sha256']:raise ValueError('Recorded official source provenance mismatch')
            if any(original['roi'][k]!=roi[k] for k in ('x','y','width','height')):raise ValueError('Recorded ROI mismatch')
            if any(roi['padding_ltrb_source_px']) and original['roi'].get('fill_rgb')!=roi.get('padding_rgb'):raise ValueError('Recorded padding mismatch')
            rows=replay_rows(args.recorded_raw,info)
        else:
            if args.official_source is None:raise ValueError('--official-source required for inference')
            for name,h in protocol['official_source_sha256'].items():
                p=args.official_source/'sixdrepnet360'/name
                if sha(p)!=h:raise ValueError('Official source hash mismatch: '+name)
                protected[str(p.resolve())]=h
            os.environ['MPLCONFIGDIR']=str(out/'matplotlib_config')
            if runtime_factory is None:
                from official_runtime import OfficialRuntime
                runtime_factory=OfficialRuntime
            load_start=time.perf_counter();runtime=runtime_factory(args.official_source,args.weights,selected_threads)
            metrics.add('runtime_initialization_s',time.perf_counter()-load_start)
            if getattr(runtime,'timings',{}).get('model_load_s') is not None:metrics.add('model_load_s',runtime.timings['model_load_s'])
            state['runtime_environment']=getattr(runtime,'environment',None) or environment(device='not_measured_controlled_runtime')
            execution['effective_intraop_threads']=state['runtime_environment'].get('torch_threads')
            if execution['effective_intraop_threads'] is not None and execution['effective_intraop_threads']!=selected_threads:
                raise ValueError('Effective CPU thread count differs from requested count')
            state['model_loaded']=True;atomic(details/'runtime_checks.json',runtime.checks)
            (out/'inputs').mkdir();rows=live_rows(args.video,info,roi,runtime,out)
        raw=[];raw_start=time.perf_counter()
        with (details/'raw_frames.jsonl').open('x',encoding='utf-8') as f:
            for r in rows:
                # Source values stay intact; validity and unusable-time reasons remain explicit.
                if args.recorded_raw:
                    r['source_recorded_valid']=r.get('valid')
                    if r.get('valid') and rotation(r.get('rotation_matrix')) is None:
                        r['valid']=False;r['replay_validation_error']='Recorded matrix failed unchanged geometric checks; original matrix retained'
                r['temporal_time_available']=finite_time(r.get('decoder_time_s'))
                if not args.recorded_raw:
                    for source,key in (('decode_s','decode_s'),('preprocess_s','preprocess_s'),('input_save_s','input_save_s'),('inference_s','forward_s'),('model_attempt_wall_s','prediction_call_s')):
                        if r.get(source) is not None:metrics.add(key,r[source])
                r['memory_current_run']=metrics.sample()
                save_start=time.perf_counter();append(f,r);metrics.add('raw_jsonl_write_s',time.perf_counter()-save_start);raw.append(r)
                checkpoint(processed_frames=len(raw),valid_frames=sum(bool(x.get('valid')) for x in raw))
        metrics.add('raw_phase_s',time.perf_counter()-raw_start)
        if not raw:raise ValueError('No video frames/records')
        checkpoint(stage='postprocess')
        post_start=time.perf_counter();detection,compact=analyze_records(raw,motion,settling,details,checkpoint,metrics)
        metrics.add('postprocess_s',time.perf_counter()-post_start)
        atomic(details/'detection_fixed.json',dict(fixed_utc=datetime.now(timezone.utc).isoformat(),
            motion_sha256=sha(details/'motion.json'),settling_index_sha256=sha(details/'settling_index.json'),
            settling_windows_sha256=sha(details/'settling_windows.jsonl'),manual_labels_read=False))
        checkpoint(stage='posthoc_manual_report')
        annotation=dict(video_path=str(args.video.resolve()),marks={})
        if args.manual:
            annotation=json.loads(args.manual.read_text(encoding='utf-8-sig'))
            if annotation.get('video_path') and Path(annotation['video_path']).resolve()!=args.video.resolve():raise ValueError('Manual input belongs to another video')
            if annotation.get('video_sha256') and annotation['video_sha256']!=sha(args.video):raise ValueError('Manual video hash mismatch')
            atomic(details/'manual_input.json',annotation)
        user_reviews=[]
        for index,path in enumerate(reviews):
            review=json.loads(path.read_text(encoding='utf-8'))
            if review.get('video_sha256') and review['video_sha256']!=sha(args.video):raise ValueError('User review belongs to another video')
            atomic(details/f'user_review_{index:03d}.json',review);user_reviews.append(review)
        pilot=build_report(args.video.stem,sha(args.video),annotation,detection,dict(results={}),user_reviews)
        for saved in pilot['movement_results'].values():
            for s in saved['settings'].values():
                s.pop('uncertain_intervals',None)
                s['uncertainty_details']='details/motion.json'
                for c in s['candidates']:c.pop('original_algorithm_record',None)
        atomic(details/'performance.json',dict(runtime_environment=state['runtime_environment'],measurements=metrics.snapshot(),resource_sample=metrics.sample(),
            snapshot_scope='Before main result publication; final measurements are in state.json; final checkpoint excludes its own write time.'))
        pilot.update(schema_version='d01-pilot-result-1.0',protocol_version=protocol['protocol_version'],run_mode=state['mode'],
            execution=execution,
            runtime_environment=state['runtime_environment'],measurement_details='details/performance.json',final_measurements_file='state.json',
            run_state_file='state.json',require_completed_run_state=True,model_inference_performed=not bool(args.recorded_raw),
            user_roi=dict(setting=roi,source='human_supplied_not_automatic_tracking'),
            settling=dict(is_movement_end=False,conditions=compact,details_file='details/settling_windows.jsonl'),
            detail_files={p.name:dict(path='details/'+p.name,sha256=sha(p)) for p in details.iterdir() if p.is_file()},
            verification=dict(model_pose_accuracy_validated=False,clock_alignment_verified=False,ground_truth_approved=False))
        # Small readable summary reuses the existing reporter, with an empty region list.
        text_report=copy.deepcopy(pilot);text_report['settling']['regions']=[]
        if not all(sha(p)==h for p,h in protected.items()):raise ValueError('Source changed during run')
        save_start=time.perf_counter();atomic(out/'result.json',pilot)
        (out/'summary.md').write_text(readable(text_report)+'\nYerleşme ayrıntıları: details/settling_windows.jsonl; hareket bitişi değildir.\n',encoding='utf-8')
        metrics.add('report_files_write_s',time.perf_counter()-save_start)
        if not all(sha(p)==h for p,h in protected.items()):raise ValueError('Source changed during run')
        save_start=time.perf_counter();atomic(out/'source_preservation.json',dict(files_sha256=protected,all_unchanged=True));metrics.add('report_files_write_s',time.perf_counter()-save_start)
        checkpoint(status='completed',stage='finished',result_file='result.json',invalid_frames=len(raw)-state['valid_frames'])
        return pilot
    except KeyboardInterrupt:
        checkpoint(status='interrupted');raise
    except BaseException as exc:
        checkpoint(status='failed',error=f'{type(exc).__name__}: {exc}');raise

def main():
    import signal
    def interrupted(signum,frame):raise KeyboardInterrupt(f'Signal {signum}')
    signal.signal(signal.SIGTERM,interrupted)
    if hasattr(signal,'SIGBREAK'):signal.signal(signal.SIGBREAK,interrupted)
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('video','weights','roi','protocol','output-dir'):parser.add_argument('--'+name,type=Path,required=True)
    for name in ('official-source','manual','recorded-raw','recorded-report'):parser.add_argument('--'+name,type=Path)
    parser.add_argument('--user-review',type=Path,action='append',help='Optional separate user observation; read only after detection is fixed')
    parser.add_argument('--cpu-threads',type=int,choices=(1,2,4),help='Explicit intra-op override; omitted uses unchanged protocol default')
    args=parser.parse_args();run(args);print(str(args.output_dir.resolve()/'result.json'))

if __name__=='__main__':main()
