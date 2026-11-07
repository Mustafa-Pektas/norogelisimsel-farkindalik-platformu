"""Real CPU smoke/full/24-frame-buffered hybrid; no pose fusion or manual input.

Each mode runs in a fresh process. Timing starts before heavy imports and ends
after decode, prediction, causal selection, detection and tracker cleanup. Input
hashing/checkpoint writes are included. Final result serialization is excluded.
Python process startup/shutdown and Torch object destruction are not measured.
One run is not a benchmark
distribution. A bounded 25-image deque stores 24 past images plus the current.
"""
from pathlib import Path
import argparse
from collections import deque
import hashlib
import importlib.metadata
import json
import os
import time

from compare_headpose_methods import read, write, sha, time_sample, series, load_tracker_module
from selective_6d_replay import evaluate_window


class BufferedWindows:
    """Independent raw/EMA selectors; prediction cache is shared, matrices are not fused."""
    def __init__(self, motion, policy, mode):
        self.motion, self.mode = motion, mode
        self.pre = round(policy['pre_context_s'] * motion['nominal_fps'])
        self.required = motion['window_intervals'] + motion['stop_confirmation_samples']
        self.active = None
        self.recovery = 0
        self.windows = []
        self.checkpoint = None

    def request(self, pnp):
        i = pnp['frame_index']
        if self.active is None and not pnp['valid']:
            self.active = dict(trigger_frame=i, trigger_s=pnp['time_s'], start_index=max(0,i-self.pre))
            self.recovery = 0
        if self.active is None:
            return []
        self.recovery = self.recovery+1 if pnp['valid'] else 0
        return list(range(self.active['start_index'],i+1))

    def observe(self, pnp, cache, final=False):
        if self.active is None:
            return
        i = pnp['frame_index']; begin = self.active['start_index']
        rows = [cache[j] for j in range(begin,i+1)]
        det, quiet = evaluate_window(rows,self.motion,self.mode)
        closed = [c for c in det['candidates'] if c['end_s'] is not None]
        if closed and self.checkpoint is None:
            self.checkpoint = dict(frame=i,time_s=pnp['time_s'],candidate=closed[0])
        ready = self.recovery>=self.required and quiet
        if ready or final:
            self.windows.append(dict(**self.active,first_selected_frame=begin,last_selected_frame=i,
                first_selected_s=rows[0]['time_s'],last_selected_s=rows[-1]['time_s'],frame_count=len(rows),
                close_reason='pnp_recovered_and_6d_quiet' if ready else 'clip_ended',
                candidates=det['candidates'],uncertain_intervals=det['uncertain_intervals']))
            self.active = None


def validate(config):
    """Validate recorded identity, official source, protocol and reviewed unpadded ROI."""
    reference = read(Path(config['recorded_run'])/'settings.json')
    pilot = read(Path(__file__).parent/'parameters/pilot_v1.json')
    if sha(config['video']) != config['video_sha256']:
        raise ValueError('Video hash mismatch')
    if sha(config['weights']) != pilot['weights_sha256']:
        raise ValueError('Weights hash mismatch')
    if sha(config['face_model']) != config['face_model_sha256'] or sha(config['package']) != config['package_sha256']:
        raise ValueError('Tasks/package hash mismatch')
    for name,value in pilot['official_source_sha256'].items():
        if sha(Path(config['source'])/'sixdrepnet360'/name) != value:
            raise ValueError('Official source hash mismatch: '+name)
    roi = reference['roi']
    if roi.get('human_supplied') is not True or any(roi['padding_ltrb_source_px']):
        raise ValueError('Reviewed unpadded ROI required')
    if [roi[k] for k in ('x','y','width','height')] != config['roi']:
        raise ValueError('Reviewed ROI mismatch')
    if config['threads'] != pilot['cpu_threads'] or config['interop_threads'] != 4:
        raise ValueError('This paired experiment fixes intra/inter-op to 4/4')
    motion = read(Path(__file__).parent/'parameters/motion_candidates_v1.json')
    if sha(Path(__file__).parent/'parameters/motion_candidates_v1.json') != pilot['motion_config_sha256']:
        raise ValueError('Motion protocol hash mismatch')
    return reference,motion,read(Path(__file__).parent/'parameters/selective_6d_v1.json')


def run(args):
    start = time.perf_counter(); cpu_start = time.process_time()
    out = args.output.resolve(); out.mkdir(parents=True,exist_ok=False)
    # Avoid Matplotlib writing to a shared/personal cache during MediaPipe imports.
    os.environ['MPLCONFIGDIR'] = str(out/'mpl_cache')
    config = read(args.config)
    write(out/'config.json',config)
    write(out/'state.json',dict(status='running',phase='validation',processed_frames=0))
    cap=tracker=None; cache={}; pnp_rows=[]; decoded=0; attempted=0
    timings=dict(runtime_initialization_s=0.,model_load_s=0.,task_initialization_s=0.,tracking_pnp_s=0.,forward_s=0.,prediction_call_s=0.,preprocess_s=0.,postprocess_s=0.)
    try:
        reference,motion,policy = validate(config)
        import cv2
        import numpy as np
        import torch
        from PIL import Image
        from motion_candidates import rotation, detect
        from official_runtime import OfficialRuntime
        from pilot_metrics import environment, memory
        torch.set_num_threads(config['threads']); torch.set_num_interop_threads(config['interop_threads'])
        cap=cv2.VideoCapture(config['video'])
        if not cap.isOpened(): raise ValueError('Video cannot open')
        width,height,fps=(cap.get(k) for k in (cv2.CAP_PROP_FRAME_WIDTH,cv2.CAP_PROP_FRAME_HEIGHT,cv2.CAP_PROP_FPS))
        width,height=int(width),int(height)
        if (width,height,fps)!=(reference['video']['width'],reference['video']['height'],reference['video']['fps']):
            raise ValueError('Video metadata mismatch')
        x,y,w,h=config['roi']
        if min(x,y)<0 or x+w>width or y+h>height: raise ValueError('ROI outside video')
        if fps!=motion['nominal_fps']: raise ValueError('Fixed protocol FPS mismatch')
        before={str(Path(p).resolve()):sha(p) for p in [config['video'],config['weights'],config['face_model'],args.config]}
        ref_rows=[json.loads(s) for s in (Path(config['recorded_run'])/'details/raw_frames.jsonl').read_text().splitlines() if s.strip()]
        ref_map={r['frame_index']:r for r in ref_rows}
        if args.mode in ('smoke','hybrid'):
            t=time.perf_counter()
            module,params,entry,source=load_tracker_module(Path(config['package']),Path(config['face_model']),out/'vision_original.py')
            box=[x/width,y/height,(x+w)/width,(y+h)/height]
            tracker=module.FaceTrack(box,box,params['max_flow_gap_s'])
            timings['task_initialization_s']=time.perf_counter()-t
        runtime=None
        def ensure_runtime():
            nonlocal runtime
            if runtime is None:
                t=time.perf_counter(); runtime=OfficialRuntime(config['source'],config['weights'],config['threads'])
                timings['runtime_initialization_s']=time.perf_counter()-t
                timings['model_load_s']=runtime.timings['model_load_s']
        if args.mode in ('smoke','full'): ensure_runtime()
        selectors={mode:BufferedWindows(motion,policy,mode) for mode in policy['methods']}
        buffer=deque(maxlen=round(policy['pre_context_s']*fps)+1)
        last=None
        with (out/'sixd_frames.jsonl').open('x',encoding='utf-8') as sixfile, (out/'pnp_frames.jsonl').open('x',encoding='utf-8') as pnpfile, (out/'resources.jsonl').open('x',encoding='utf-8') as resources:
            def predict(item):
                nonlocal attempted
                i,frame,timing=item
                if i in cache:return
                ensure_runtime(); attempted+=1
                t=time.perf_counter()
                image=Image.fromarray(cv2.cvtColor(frame[y:y+h,x:x+w],cv2.COLOR_BGR2RGB))
                image,tensor=runtime.prepare(image)
                rgb_hash=hashlib.sha256(np.asarray(image).tobytes()).hexdigest()
                tensor_hash=hashlib.sha256(tensor.contiguous().numpy().tobytes()).hexdigest()
                timings['preprocess_s']+=time.perf_counter()-t
                expected=ref_map.get(i)
                matches=bool(expected and expected['input_rgb_sha256']==rgb_hash and expected['normalized_tensor_sha256']==tensor_hash)
                if not matches:raise ValueError('Reviewed input hash mismatch at frame '+str(i))
                row=dict(frame_index=i,**timing,input_rgb_sha256=rgb_hash,normalized_tensor_sha256=tensor_hash,reviewed_input_match=matches,valid=False,rotation_matrix=None)
                t=time.perf_counter()
                try:
                    row.update(runtime.predict(tensor));timings['forward_s']+=row['inference_s']
                except Exception as e:
                    row.update(error_type=type(e).__name__,error=str(e))
                timings['prediction_call_s']+=time.perf_counter()-t
                cache[i]=row;sixfile.write(json.dumps(row)+'\n');sixfile.flush()
            while True:
                if time.perf_counter()-start>config['max_seconds']:raise TimeoutError('Run duration bound reached')
                ok,frame=cap.read()
                if not ok:break
                i=decoded;decoded+=1
                timing=time_sample(i,fps,float(cap.get(cv2.CAP_PROP_POS_MSEC))/1000,last)
                if timing['time_s'] is not None:last=timing['time_s']
                item=(i,frame,timing);buffer.append(item)
                if args.mode in ('smoke','hybrid'):
                    t=time.perf_counter()
                    track=tracker.update(frame,i/fps)
                    pose=module.head_pose(track['landmarks'],width,height,params['max_pose_reprojection_px'])
                    matrix=None if 'rotation_vector' not in pose else rotation(cv2.Rodrigues(np.array(pose['rotation_vector']))[0])
                    pnp=dict(frame_index=i,**timing,track_source=track['source'],face_landmarks_found=track['landmarks'] is not None,
                        valid=matrix is not None,rotation_matrix=None if matrix is None else matrix.tolist(),
                        tracking_clock_s=i/fps,tracking_clock_source='nominal_frame_index_over_fps',**pose)
                    if track['source']!='landmarks' and pnp['valid']:raise ValueError('Flow-only angle prohibited')
                    timings['tracking_pnp_s']+=time.perf_counter()-t
                    pnp_rows.append(pnp);pnpfile.write(json.dumps(pnp)+'\n');pnpfile.flush()
                if args.mode in ('smoke','full'):predict(item)
                else:
                    needed=set()
                    for selector in selectors.values():needed.update(selector.request(pnp))
                    available={r[0]:r for r in buffer}
                    for j in sorted(needed-set(cache)):
                        if j not in available:raise ValueError('Required pre-context no longer buffered')
                        predict(available[j])
                    t=time.perf_counter()
                    for selector in selectors.values():selector.observe(pnp,cache)
                    timings['postprocess_s']+=time.perf_counter()-t
                resources.write(json.dumps(dict(frame_index=i,elapsed_s=time.perf_counter()-start,process_cpu_s=time.process_time()-cpu_start,**memory()))+'\n');resources.flush()
                write(out/'state.json',dict(status='running',processed_frames=decoded,real_6d_attempts=attempted,real_6d_completed=len(cache),elapsed_s=time.perf_counter()-start))
                if decoded%24==0 or args.mode=='smoke':print(f'{args.mode}: decoded={decoded}, real6D={len(cache)}',flush=True)
                if args.mode=='smoke':break
            t=time.perf_counter()
            if args.mode=='hybrid' and pnp_rows:
                for selector in selectors.values():selector.observe(pnp_rows[-1],cache,final=True)
            base=next(s for s in motion['settings'] if s['id']=='base')
            detections=None
            if args.mode in ('full','smoke'):
                detections={mode:detect(rows,motion,base) for mode,rows in series(list(cache.values()),motion).items()}
            timings['postprocess_s']+=time.perf_counter()-t
        if args.mode=='smoke' and (decoded!=1 or not pnp_rows[0]['valid'] or not cache[0]['valid']):
            raise ValueError('Both models must return a valid pose for the same smoke frame')
        if args.mode!='smoke' and decoded!=len(ref_rows):raise ValueError('Decoded/reference count mismatch')
        runtime_info=environment(torch,'cpu')
        versions={d.metadata['Name']:d.version for d in importlib.metadata.distributions()}
        checks=runtime.checks if runtime is not None else None
        if tracker is not None:tracker.close();tracker=None
        cap.release();cap=None
        elapsed=time.perf_counter()-start
        result=dict(status='completed',mode=args.mode,video_sha256=config['video_sha256'],decoded_frames=decoded,
            real_6d_attempts=attempted,real_6d_frames=len(cache),valid_6d_frames=sum(r['valid'] for r in cache.values()),
            failed_6d_frames=sum(not r['valid'] for r in cache.values()),valid_pnp_frames=sum(r['valid'] for r in pnp_rows),
            elapsed_s=elapsed,process_cpu_s=time.process_time()-cpu_start,timings_s=timings,runtime=runtime_info,packages=versions,
            memory=memory(),strict_runtime_checks=checks,reviewed_inputs_match=all(r['reviewed_input_match'] for r in cache.values()),
            windows={mode:dict(windows=s.windows,first_end_checkpoint=s.checkpoint) for mode,s in selectors.items()} if args.mode=='hybrid' else None,
            detections=detections,manual_used=False,pose_fusion=False,max_buffered_images=buffer.maxlen,
            timing_scope=__doc__,comparison_tolerance=dict(matrix_element_atol=1e-6,so3_angle_deg=0.001),
            limitations=['Human supplied child ROI','No target or behavioral classification','LibVLC-decoder alignment unverified','Single run, full then hybrid, cache/order effects uncontrolled'])
        write(out/'result.json',result)
        write(out/'state.json',dict(status='completed',processed_frames=decoded,real_6d_frames=len(cache),elapsed_s=elapsed))
        after={p:sha(p) for p in before}
        write(out/'source_preservation.json',dict(before=before,after=after,unchanged=before==after))
        if before!=after:raise ValueError('Protected source changed')
        print(json.dumps({k:result[k] for k in ('status','mode','decoded_frames','real_6d_frames','valid_6d_frames','valid_pnp_frames','elapsed_s')}),flush=True)
    except BaseException as e:
        write(out/'state.json',dict(status='interrupted' if isinstance(e,KeyboardInterrupt) else 'failed',processed_frames=decoded,real_6d_frames=len(cache),error_type=type(e).__name__,error=str(e)))
        raise
    finally:
        if cap is not None:cap.release()
        if tracker is not None:tracker.close()


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--config',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--mode',choices=('smoke','full','hybrid'),required=True)
    run(ap.parse_args())
