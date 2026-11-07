"""Two fresh CPU processes: same frame, one warmup, two timed forwards each.

No model executes until this command is explicitly run. Each environment has a
180-second wall limit including process startup/imports/loading and all forwards.
Partial events are flushed/fsynced. Timeout cleanup targets only this runner's
own child PID/tree; no process-name matching. Does not change either environment.
"""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

from cpu_diagnostic import cpu_info, save, sha


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def worker(args):
    out=args.output.resolve()
    started=time.perf_counter()
    os.environ['MPLCONFIGDIR']=str(out/'mpl_cache')
    save(out/'state.json',dict(status='running',phase='imports',pid=os.getpid()))
    with (out/'events.jsonl').open('x',encoding='utf-8') as stream:
        def emit(kind, **values):
            stream.write(json.dumps(dict(kind=kind,elapsed_s=time.perf_counter()-started,**values),allow_nan=False)+'\n')
            stream.flush();os.fsync(stream.fileno())
        try:
            emit('environment',python=sys.version,executable=sys.executable,cpu=cpu_info(),
                 packages={d.metadata['Name']:d.version for d in importlib.metadata.distributions()})
            import cv2
            import numpy as np
            import torch
            from PIL import Image
            from official_runtime import OfficialRuntime, input_transforms
            from pilot_metrics import memory
            torch.set_num_threads(4);torch.set_num_interop_threads(4)
            config=read(args.config)
            protocol=read(Path(__file__).parent/'parameters/pilot_v1.json')
            if sha(config['video'])!=config['video_sha256']:raise ValueError('Video SHA256 mismatch')
            if sha(config['weights'])!=protocol['weights_sha256']:raise ValueError('Weights SHA256 mismatch')
            for name,digest in protocol['official_source_sha256'].items():
                if sha(Path(config['source'])/'sixdrepnet360'/name)!=digest:raise ValueError('Official source hash mismatch: '+name)
            settings=read(Path(config['recorded_run'])/'settings.json')
            roi=settings['roi']
            if not roi['human_supplied'] or any(roi['padding_ltrb_source_px']):raise ValueError('Reviewed unpadded ROI required')
            if config['roi']!=[roi[k] for k in ('x','y','width','height')]:raise ValueError('ROI mismatch')
            cap=cv2.VideoCapture(config['video'])
            try:
                ok,frame=cap.read()
                if not ok:raise ValueError('Frame zero cannot decode')
                decoder_time_s=float(cap.get(cv2.CAP_PROP_POS_MSEC))/1000
            finally:cap.release()
            x,y,w,h=config['roi'];height,width=frame.shape[:2]
            if min(x,y)<0 or x+w>width or y+h>height:raise ValueError('ROI outside frame')
            reference=None
            with (Path(config['recorded_run'])/'details/raw_frames.jsonl').open(encoding='utf-8') as records:
                for line in records:
                    row=json.loads(line)
                    if row['frame_index']==0:reference=row;break
            if reference is None:raise ValueError('Missing audited frame zero')
            preprocess_start=time.perf_counter()
            resize,crop,normalize=input_transforms()
            image=crop(resize(Image.fromarray(cv2.cvtColor(frame[y:y+h,x:x+w],cv2.COLOR_BGR2RGB))))
            tensor=normalize(image)
            rgb_hash=hashlib.sha256(np.asarray(image).tobytes()).hexdigest()
            tensor_hash=hashlib.sha256(tensor.contiguous().numpy().tobytes()).hexdigest()
            match=rgb_hash==reference['input_rgb_sha256'] and tensor_hash==reference['normalized_tensor_sha256']
            emit('input',frame_index=0,decoder_time_s=decoder_time_s,time_source='OpenCV_POS_MSEC; PTS/LibVLC alignment unverified',
                 roi=config['roi'],video_sha256=config['video_sha256'],weights_sha256=protocol['weights_sha256'],
                 input_rgb_sha256=rgb_hash,normalized_tensor_sha256=tensor_hash,reviewed_input_match=match,
                 preprocess_s=time.perf_counter()-preprocess_start)
            if not match:raise ValueError('Reviewed RGB/tensor input hash mismatch; no inference sent')
            save(out/'state.json',dict(status='running',phase='model_load',pid=os.getpid()))
            t=time.perf_counter();cpu=time.process_time()
            runtime=OfficialRuntime(config['source'],config['weights'],4)
            emit('model_load',runtime_initialization_s=time.perf_counter()-t,model_load_s=runtime.timings['model_load_s'],
                 runtime_initialization_cpu_s=time.process_time()-cpu,runtime=runtime.environment,checks=runtime.checks,
                 scope='model_load_s is nested inside runtime_initialization_s; do not add',memory=memory())
            if (torch.get_num_threads(),torch.get_num_interop_threads())!=(4,4):raise ValueError('Effective threads are not 4/4')
            for label in ('warmup','measurement_1','measurement_2'):
                save(out/'state.json',dict(status='running',phase=label,pid=os.getpid()))
                t=time.perf_counter();cpu=time.process_time()
                prediction=runtime.predict(tensor)
                emit('prediction',label=label,prediction_call_s=time.perf_counter()-t,process_cpu_s=time.process_time()-cpu,
                     **prediction,memory=memory())
                print(label+' forward_s='+str(prediction['inference_s']),flush=True)
            save(out/'state.json',dict(status='completed',elapsed_s=time.perf_counter()-started,pid=os.getpid()))
        except BaseException as error:
            emit('error',error_type=type(error).__name__,message=str(error))
            save(out/'state.json',dict(status='interrupted' if isinstance(error,KeyboardInterrupt) else 'failed',error_type=type(error).__name__,message=str(error)))
            raise


def stop_own_child(child):
    """Bound cleanup; Windows venv launcher descendants must stop too."""
    if child.poll() is not None:return True
    if os.name=='nt':
        # PID comes directly from this Popen, never from a name/global search.
        try:
            killed=subprocess.run(['taskkill','/PID',str(child.pid),'/T','/F'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10,check=False)
            if killed.returncode!=0:return False
        except (OSError,subprocess.TimeoutExpired):return False
    else:child.kill()
    try:child.wait(timeout=5)
    except subprocess.TimeoutExpired:return False
    return True


def event_rows(file):
    result=[]
    if file.exists():
        for line in file.read_text(encoding='utf-8').splitlines():
            try:result.append(json.loads(line))
            except json.JSONDecodeError:pass  # An interrupted final write remains untouched on disk.
    return result


def main(args):
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    config=read(args.config)
    save(out/'experiment.json',dict(config=config,frame_index=0,threads=4,interop_threads=4,
        order=['old_headpose','new_hybrid'],warmup_count=1,measurement_count=2,per_environment_limit_s=180,
        cleanup_grace_s=15,matrix_element_tolerance=1e-6,
        limitations='One frame, fixed old->new order, two measurements; cache/warmup/system-load effects not controlled. Not full-video performance.'))
    report=dict(status='running',conditions=[],rgb_hashes_equal=None,tensor_hashes_equal=None)
    save(out/'report.json',report)
    for label,python in [('old_headpose',args.old_python),('new_hybrid',args.new_python)]:
        condition=out/label;condition.mkdir()
        row=dict(environment=label,status='starting',limit_s=180)
        report['conditions'].append(row);save(out/'report.json',report)
        print(label+': starting, 180s limit',flush=True)
        try:
            python=python.resolve(strict=True)
            with (condition/'stdout.log').open('x',encoding='utf-8') as stdout,(condition/'stderr.log').open('x',encoding='utf-8') as stderr:
                started=time.monotonic()
                child=subprocess.Popen([str(python),'-u','-X','utf8',str(Path(__file__).resolve()),'--worker',
                    '--config',str(args.config.resolve()),'--output',str(condition)],stdout=stdout,stderr=stderr)
                row['pid']=child.pid
                try:
                    code=child.wait(timeout=max(.001,180-(time.monotonic()-started)))
                    row.update(status='completed' if code==0 else 'failed',exit_code=code)
                except subprocess.TimeoutExpired:
                    row.update(status='timeout',cleanup_confirmed=stop_own_child(child))
                except BaseException:
                    row.update(status='interrupted',cleanup_confirmed=stop_own_child(child));raise
                row['parent_wall_s']=time.monotonic()-started
        except KeyboardInterrupt:
            report['status']='interrupted';save(out/'report.json',report);raise
        except Exception as error:
            row.update(status='failed',error_type=type(error).__name__,message=str(error))
        events=event_rows(condition/'events.jsonl')
        inp=next((e for e in events if e['kind']=='input'),{})
        model=next((e for e in events if e['kind']=='model_load'),{})
        predictions=[e for e in events if e['kind']=='prediction']
        measurements=[e for e in predictions if e['label']!='warmup']
        row.update(input=inp,model_load_s=model.get('model_load_s'),runtime_initialization_s=model.get('runtime_initialization_s'),
            warmup_forward_s=next((e['inference_s'] for e in predictions if e['label']=='warmup'),None),
            measured_forward_s=[e['inference_s'] for e in measurements],measurement_count=len(measurements),
            mean_measured_forward_s=statistics.mean(e['inference_s'] for e in measurements) if len(measurements)==2 else None,
            runtime=model.get('runtime'),predictions=predictions)
        if row['status']=='completed' and (len(measurements)!=2 or len(predictions)!=3 or not inp.get('reviewed_input_match')):
            row['status']='failed_incomplete_output'
        save(condition/'parent_state.json',row);save(out/'report.json',report)
        print(label+': '+row['status']+', model_load='+str(row['model_load_s'])+', forward='+str(row['measured_forward_s']),flush=True)
        if row.get('cleanup_confirmed') is False:
            report['status']='cleanup_unconfirmed';save(out/'report.json',report)
            raise RuntimeError('Own child cleanup not confirmed; second environment not started')
    a,b=report['conditions']
    for key,field in [('rgb_hashes_equal','input_rgb_sha256'),('tensor_hashes_equal','normalized_tensor_sha256')]:
        values=[r['input'].get(field) for r in report['conditions']]
        report[key]=None if any(v is None for v in values) else values[0]==values[1]
    complete=all(r['status']=='completed' for r in report['conditions'])
    report['status']='completed' if complete and report['rgb_hashes_equal'] and report['tensor_hashes_equal'] else 'incomplete_or_mismatch'
    # Matrices are compared only for measured predictions; tolerance declared above.
    report['matrix_comparisons']=[]
    for pa,pb in zip([e for e in a['predictions'] if e['label']!='warmup'],[e for e in b['predictions'] if e['label']!='warmup']):
        delta=max(abs(pa['rotation_matrix'][i][j]-pb['rotation_matrix'][i][j]) for i in range(3) for j in range(3))
        report['matrix_comparisons'].append(dict(label=pa['label'],max_element_difference=delta,within_1e_6=delta<=1e-6))
    save(out/'report.json',report)
    lines=['| Environment | Status | Model load s | Warmup forward s | Measured forwards s | Mean (2 only) s |',
           '|---|---|---:|---:|---|---:|']
    for r in report['conditions']:
        lines.append(f"| {r['environment']} | {r['status']} | {r['model_load_s']} | {r['warmup_forward_s']} | {r['measured_forward_s']} | {r['mean_measured_forward_s']} |")
    lines+=['',f"RGB hashes equal: {report['rgb_hashes_equal']}; tensor hashes equal: {report['tensor_hashes_equal']}.",
            'model_load is nested in runtime_initialization; forwards exclude post-forward validation, while prediction_call includes it. Warmup excluded from mean.',
            'A timeout may leave worker state running; parent_state.json/report.json are authoritative for forced interruption. Partial records remain.']
    (out/'SUMMARY.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('\n'.join(lines),flush=True);print('Results: '+str(out),flush=True)
    if report['status']!='completed':raise SystemExit(1)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--old-python',type=Path);parser.add_argument('--new-python',type=Path)
    parser.add_argument('--worker',action='store_true',help=argparse.SUPPRESS)
    args=parser.parse_args()
    if args.worker:worker(args)
    else:
        if args.old_python is None or args.new_python is None:parser.error('old-python and new-python required')
        main(args)
