"""Prepare/run opt-in 3-frame CPU diagnostic, never full video or backend/API.

Order: recorded mobile intra/inter-op; intra2 with same inter-op; intra4 with
same inter-op. The repeated4 condition intentionally exposes order/load drift.
One warmup on frame0, then measured0/36/72. No label-based frame selection.
180 seconds per condition plus bounded own-child cleanup; no automatic retries.
"""
from pathlib import Path
import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from types import SimpleNamespace
from cpu_diagnostic import worker, sha, save, FRAMES
from compare_cpu_environments import stop_own_child, event_rows


def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))


def summarize(events,intra,interop):
    inputs=[r for r in events if r.get('kind')=='input']
    runtime=next((r for r in events if r.get('kind')=='runtime'),{})
    measured=[r for r in events if r.get('kind')=='prediction' and not r['warmup']]
    warmup=[r for r in events if r.get('kind')=='prediction' and r['warmup']]
    env=runtime.get('environment',{})
    verified=(len(inputs)==3 and {r['frame_index'] for r in inputs}==set(FRAMES) and
        len(measured)==3 and {r['frame_index'] for r in measured}==set(FRAMES) and len(warmup)==1 and
        env.get('torch_threads')==intra and env.get('torch_interop_threads')==interop and env.get('device')=='cpu' and
        all(r.get('hashes_verified') is True for r in inputs) and
        all(r.get('valid') is True and r.get('recorded_matrix_within_tolerance') is True for r in measured+warmup))
    return dict(inputs=inputs,runtime=env,model_load_s=runtime.get('model_load_s'),runtime_initialization_s=runtime.get('load_wall_s'),
        warmup_forward_s=[r['inference_s'] for r in warmup],measured_forward_s=[dict(frame=r['frame_index'],forward_s=r['inference_s'],
            prediction_wall_s=r['prediction_wall_s'],cpu_s=r['prediction_cpu_s'],matrix_max_difference=r['recorded_matrix_max_difference']) for r in measured],
        mean_forward_s=statistics.mean(r['inference_s'] for r in measured) if len(measured)==3 else None,verified=verified)


def main(args):
    job=args.job.resolve();state=read(job/'run/state.json');settings=read(job/'run/settings.json');j=read(job/'job.json')
    recorded=state['runtime_environment'];intra=recorded['torch_threads'];interop=recorded['torch_interop_threads']
    if intra not in (1,2,4) or type(interop) is not int or not 1<=interop<=128:raise ValueError('Invalid recorded thread counts')
    python=Path(recorded['python_executable']).resolve(strict=True)
    weights=[Path(p) for p in settings['inputs_sha256'] if Path(p).suffix=='.pth']
    if len(weights)!=1:raise ValueError('One unambiguous recorded weight path required')
    weight=weights[0]
    official=Path(args.official_source).resolve(strict=True)
    if sha(job/'upload.mp4')!=j['videoHash'] or sha(weight)!=settings['protocol']['weights_sha256']:raise ValueError('Source video/weight hash mismatch')
    if settings['roi']!=j['roi']:raise ValueError('Job/settings ROI mismatch')
    rows=[json.loads(s) for s in (job/'run/details/raw_frames.jsonl').read_text().splitlines() if s.strip()]
    if any(not any(r['frame_index']==i and r.get('valid') for r in rows) for i in FRAMES):raise ValueError('Missing fixed valid frames')
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    conditions=[('mobile_recorded',intra,interop),('intra_2',2,interop),('intra_4_repeat',4,interop)]
    report=dict(status='running',source_job=j['jobId'],source_video_sha256=j['videoHash'],python=str(python),recorded_runtime=recorded,
        roi=settings['roi'],weights=str(weight),weights_sha256=sha(weight),official_source=str(official),frames=FRAMES,
        per_condition_limit_s=180,cleanup_grace_s=15,one_warmup_then_three_measured=True,matrix_tolerance=1e-6,conditions=[],
        limitations='Fixed order, three frames and one pass only. Same inter-op throughout; not an inter-op14 vs4 test. Fastest here is not a guaranteed full-video winner.')
    save(out/'report.json',report)
    for label,threads,inter in conditions:
        condition=out/label;condition.mkdir()
        row=dict(id=label,intra=threads,interop=inter,status='starting')
        report['conditions'].append(row);save(out/'report.json',report)
        # Match backend's child environment allowlist; do not inherit API keys/.env or shell thread overrides.
        env={k:os.environ[k] for k in ('PATH','SystemRoot','WINDIR','TEMP','TMP','LANG','LC_ALL') if k in os.environ}
        env.update(PYTHONIOENCODING='utf-8',MPLCONFIGDIR=str(condition/'mpl_cache'))
        command=[str(python),'-u','-X','utf8',str(Path(__file__).resolve()),'--worker','--job',str(job),'--output',str(condition),
            '--official-source',str(official),'--intra',str(threads),'--interop',str(inter),'--label',label]
        print(f'{label}: {threads}/{inter}, limit180s, warmup1 + measured{FRAMES}',flush=True)
        with (condition/'console.log').open('x',encoding='utf-8') as log:
            child=subprocess.Popen(command,stdout=log,stderr=log,env=env,cwd=job)
            started=time.monotonic()
            try:
                code=child.wait(timeout=180);row.update(status='completed' if code==0 else 'failed',exit_code=code)
            except subprocess.TimeoutExpired:
                row.update(status='timeout',cleanup_confirmed=stop_own_child(child))
            except BaseException:
                row.update(status='interrupted',cleanup_confirmed=stop_own_child(child));save(out/'report.json',report);raise
            row['parent_wall_s']=time.monotonic()-started
        row.update(summarize(event_rows(condition/(label+'.jsonl')),threads,inter))
        current=row['runtime']
        row['recorded_versions_equal']=current.get('python_version')==recorded['python_version'] and current.get('packages')==recorded['packages'] and current.get('torch_runtime_version')==recorded['torch_runtime_version']
        row['verified']=row['verified'] and row['recorded_versions_equal'] and row['status']=='completed'
        save(out/'report.json',report)
        print(label+': '+row['status']+', mean_forward='+str(row['mean_forward_s'])+', verified='+str(row['verified']),flush=True)
        if row.get('cleanup_confirmed') is False:raise RuntimeError('Own child cleanup unconfirmed; no next condition')
    reference=report['conditions'][0].get('inputs',[])
    report['all_input_hashes_equal']=len(reference)==3 and all(r['inputs']==reference for r in report['conditions'])
    eligible=[r for r in report['conditions'] if r['verified'] and report['all_input_hashes_equal']]
    report['fastest_measured_condition']=min(eligible,key=lambda r:r['mean_forward_s'])['id'] if len(eligible)==3 else None
    first,last=report['conditions'][0],report['conditions'][-1]
    report['repeated_4_thread_mean_difference_percent']=100*(last['mean_forward_s']/first['mean_forward_s']-1) if first['verified'] and last['verified'] else None
    report['status']='completed' if len(eligible)==3 else 'incomplete_or_unverified'
    save(out/'report.json',report)
    lines=['# Recorded mobile job CPU diagnostic','', '| Condition intra/inter | Status | Model load s | Warmup forward s | Three forwards s | Mean s | Verified |', '|---|---|---:|---|---|---:|---|']
    for r in report['conditions']:
        lines.append(f"| {r['id']} {r['intra']}/{r['interop']} | {r['status']} | {r['model_load_s']} | {r['warmup_forward_s']} | {[m['forward_s'] for m in r['measured_forward_s']]} | {r['mean_forward_s']} | {r['verified']} |")
    lines+=['',f"RGB/tensor hashes all equal: {report['all_input_hashes_equal']}",f"Fastest in this diagnostic: {report['fastest_measured_condition']}",
        f"Repeated4-thread mean difference percent: {report['repeated_4_thread_mean_difference_percent']}",
        'Model load is inside runtime initialization. Warmup excluded from means. Each measured frame differs, but the same three inputs are used in each condition.',report['limitations']]
    (out/'SUMMARY.md').write_text('\n'.join(lines)+'\n',encoding='utf-8');print('\n'.join(lines),flush=True);print('Output: '+str(out),flush=True)
    if report['status']!='completed':raise SystemExit(1)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--job',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--official-source',type=Path,required=True)
    parser.add_argument('--worker',action='store_true');parser.add_argument('--intra',type=int);parser.add_argument('--interop',type=int);parser.add_argument('--label')
    args=parser.parse_args()
    if args.worker:
        setting=read(args.job/'run/settings.json')
        weight=next(Path(p) for p in setting['inputs_sha256'] if Path(p).suffix=='.pth')
        worker(SimpleNamespace(recorded_run=args.job/'run',weights=weight,official_source=args.official_source,output_dir=args.output,
            worker_threads=args.intra,worker_interop=args.interop,condition_id=args.label))
    else:main(args)
