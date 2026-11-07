"""Recorded-matrix replay. No 6D, MediaPipe, Torch or video model loading."""
from pathlib import Path
import argparse
import hashlib
import json
from collections import Counter

from motion_candidates import detect
from compare_headpose_methods import series


def load(file):return json.loads(Path(file).read_text(encoding='utf-8-sig'))
def digest(file):return hashlib.sha256(Path(file).read_bytes()).hexdigest()


def evaluate_window(rows, motion, mode):
    """Same causal prefix decision for replay and real buffered execution."""
    setting=next(s for s in motion['settings'] if s['id']=='base')
    det=detect(series(rows,motion)[mode],motion,setting)
    tail=det['feature_records'][-motion['stop_confirmation_samples']:]
    quiet=len(tail)==motion['stop_confirmation_samples'] and all(
        f['median_speed_deg_s'] is not None and f['median_speed_deg_s']<=setting['stop_deg_s'] for f in tail)
    return det,quiet


def select_windows(six, pnp, motion, policy, mode):
    if len(six)!=len(pnp) or not six:raise ValueError('Rows must share one timeline')
    for a,b in zip(six,pnp):
        if a['frame_index']!=b['frame_index'] or a['time_s'] is None or b['time_s'] is None or abs(a['time_s']-b['time_s'])>1e-6:
            raise ValueError('Frame/time mismatch; no alignment fallback')
    if mode not in policy['methods']:raise ValueError('Unknown fixed mode')
    pre=round(policy['pre_context_s']*motion['nominal_fps'])
    recovery_required=motion['window_intervals']+motion['stop_confirmation_samples']
    setting=next(s for s in motion['settings'] if s['id']=='base')
    selected=set();windows=[];active=None;recovery=0;first_checkpoint=None
    for i,r in enumerate(pnp):
        if active is None:
            if r['valid']:continue
            active={'trigger_frame':r['frame_index'],'trigger_s':r['time_s'],'start_index':max(0,i-pre)}
            recovery=0
        begin=active['start_index'];selected.update(range(begin,i+1))
        recovery=recovery+1 if r['valid'] else 0
        # Independent 6D-only temporal state; no PnP matrix is supplied here.
        det,quiet=evaluate_window(six[begin:i+1],motion,mode)
        completed=[c for c in det['candidates'] if c['end_s'] is not None]
        if completed and first_checkpoint is None:
            first_checkpoint={'frame':r['frame_index'],'time_s':r['time_s'],'selected_unique_frames_so_far':len(selected),'candidate':completed[0]}
        if (recovery>=recovery_required and quiet) or i==len(pnp)-1:
            windows.append({**active,'first_selected_frame':six[begin]['frame_index'],'last_selected_frame':r['frame_index'],
                'first_selected_s':six[begin]['time_s'],'last_selected_s':r['time_s'],'frame_count':i-begin+1,
                'close_reason':'pnp_recovered_and_6d_quiet' if recovery>=recovery_required and quiet else 'clip_ended',
                'candidates':det['candidates'],'uncertain_intervals':det['uncertain_intervals']})
            active=None
    return dict(mode=mode,triggered_windows=windows,selected_frame_indices=[six[i]['frame_index'] for i in sorted(selected)],
        selected_unique_frames=len(selected),total_frames=len(six),first_end_checkpoint=first_checkpoint,
        pre_context_frames=pre,recovery_valid_samples=recovery_required,no_rotation_fusion=True,real_model_calls=0)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--comparison-run',type=Path,required=True);ap.add_argument('--recorded-run',type=Path,required=True)
    ap.add_argument('--manual',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    motion_file=Path(__file__).parent/'parameters/motion_candidates_v1.json';policy_file=Path(__file__).parent/'parameters/selective_6d_v1.json'
    motion,policy=load(motion_file),load(policy_file)
    raw_file=args.recorded_run/'details/raw_frames.jsonl';pnp_file=args.comparison_run/'frames.jsonl'
    protected=[raw_file,pnp_file,args.manual,motion_file,policy_file,Path(__file__),Path(__file__).with_name('motion_candidates.py'),Path(__file__).with_name('rotation_processing.py')]
    before={str(p.resolve()):digest(p) for p in protected}
    def rows(file):return [json.loads(line) for line in file.read_text(encoding='utf-8').splitlines() if line.strip()]
    six=[dict(r,time_s=r['decoder_time_s']) for r in rows(raw_file)];pnp=rows(pnp_file)
    video=load(args.recorded_run/'result.json')['video']['sha256']
    if video!=load(args.comparison_run/'settings.json')['video_sha256']:raise ValueError('Video mismatch')
    # Freeze both selector results before loading manual times.
    results={mode:select_windows(six,pnp,motion,policy,mode) for mode in policy['methods']}
    from pilot_time_relations import manual_mark
    manual=load(args.manual)
    if manual['video_sha256']!=video:raise ValueError('Manual/video mismatch')
    marks={k:manual_mark(manual,k) for k in ['call_start_s','call_end_s','response_start_s','response_end_s']}
    full_series=series(six,motion);base=next(s for s in motion['settings'] if s['id']=='base')
    comparisons=[]
    for mode,result in results.items():
        full=detect(full_series[mode],motion,base)
        for wi,window in enumerate(result['triggered_windows']):
            for c in window['candidates']:
                start,end=c['start_s'],c['end_s']
                exact=[f for f in full['candidates'] if f['start_frame']==c['start_frame'] and f['end_frame']==c['end_frame']]
                comparisons.append(dict(mode=mode,window=wi+1,**c,match_full_6d_boundaries=bool(exact),
                    start_minus_manual_s=None if start is None else start-marks['response_start_s']['time_s'],
                    end_minus_manual_s=None if end is None else end-marks['response_end_s']['time_s'],
                    start_minus_call_end_s=None if start is None else start-marks['call_end_s']['time_s']))
        result['full_6d_candidates']=full['candidates']
    report=dict(protocol=policy,video_sha256=video,results=results,manual=marks,manual_annotation_status=manual.get('annotation_status'),comparisons=comparisons,
        real_model_inference=False,hybrid_runtime_measured=False,inter_method_reference_alignment=False,
        note='No joined trajectory. Separate 6D windows reset EMA. First end checkpoint is a workload prefix, not a standalone all-clip policy. Later candidates retained; manual marks not used by selector.')
    (args.output/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    import csv
    with (args.output/'candidates.csv').open('x',encoding='utf-8',newline='') as f:
        fields=list(dict.fromkeys(k for r in comparisons for k in r)) if comparisons else ['mode','start_s','end_s']
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(comparisons)
    after={p:digest(p) for p in before}
    (args.output/'source_preservation.json').write_text(json.dumps(dict(before=before,after=after,unchanged=before==after),indent=2),encoding='utf-8')
    if before!=after:raise ValueError('Protected input changed')
    print(json.dumps({mode:{k:v for k,v in result.items() if k in ['selected_unique_frames','total_frames','first_end_checkpoint']} for mode,result in results.items()},indent=2))


if __name__=='__main__':main()
