"""Recorded-matrix 12FPS research only. Never loads Torch/model or calls an API."""
from pathlib import Path
import argparse
import copy
import csv
import json
import os
from datetime import datetime, timezone
from compare_headpose_methods import read, write, sha, series
from motion_candidates import detect, rotation


def sampled_rows(records, phase):
    selected=[]
    for r in records:
        index=r['frame_index']
        if index%2!=phase:continue
        # Source indexing is kept; ordinal gaps remain if input frames are absent.
        selected.append(dict(r,source_frame_index=index,frame_index=(index-phase)//2))
    return selected


def match_candidates(reference, sampled):
    """One-to-one overlap association, report all unmatched/unknown candidates."""
    used=set();pairs=[];missing=[]
    for i,a in enumerate(reference):
        if a['start_s'] is None or a['end_s'] is None:
            missing.append(dict(reference_index=i,reason='reference_boundary_unknown'));continue
        hits=[(j,b) for j,b in enumerate(sampled) if j not in used and b['start_s'] is not None and b['end_s'] is not None and
              max(a['start_s'],b['start_s'])<=min(a['end_s'],b['end_s'])]
        if len(hits)!=1:
            missing.append(dict(reference_index=i,reason='missing_or_ambiguous_overlap',overlaps=len(hits)));continue
        j,b=hits[0];used.add(j)
        pairs.append(dict(reference_index=i,sample_index=j,start_difference_s=b['start_s']-a['start_s'],
            end_difference_s=b['end_s']-a['end_s'],end_confirmation_difference_s=b['end_confirmed_s']-a['end_confirmed_s']))
    extra=[j for j in range(len(sampled)) if j not in used]
    eligible=bool(reference) and len(pairs)==len(reference) and not missing and not extra and all(
        abs(p['start_difference_s'])<=1/12+1e-9 and abs(p['end_difference_s'])<=1/12+1e-9 for p in pairs)
    return dict(pairs=pairs,missing_or_unknown=missing,extra_or_unmatched=extra,eligible=eligible)


def main(args):
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    os.environ['MPLCONFIGDIR']=str(out/'mpl_cache')
    job=args.job.resolve();run=job/'run';details=run/'details'
    protected=[job/'job.json',job/'manual.json',job/'roi.json',job/'upload.mp4',run/'state.json',run/'settings.json',details/'raw_frames.jsonl',
        Path(__file__),Path(__file__).parent/'motion_candidates.py',Path(__file__).parent/'parameters/motion_candidates_v1.json',
        Path(__file__).parent/'parameters/sampling12_v1.json',Path(__file__).parent/'rotation_processing.py',Path(__file__).parent/'compare_headpose_methods.py']
    before={str(p):sha(p) for p in protected}
    j=read(job/'job.json');state=read(run/'state.json');settings=read(run/'settings.json')
    protocol=read(Path(__file__).parent/'parameters/sampling12_v1.json');write(out/'declared_protocol.json',protocol)
    records=[json.loads(s) for s in (details/'raw_frames.jsonl').read_text().splitlines() if s.strip()]
    count=settings['video']['declared_frame_count']
    if settings['video']['fps']!=24 or len(records)!=count or [r['frame_index'] for r in records]!=list(range(count)):
        raise ValueError('Complete24fps matrix timeline required; no partial-series fallback')
    if sha(job/'upload.mp4')!=j['videoHash']:raise ValueError('Video hash mismatch')
    if any(not r.get('valid') or rotation(r.get('rotation_matrix')) is None for r in records):raise ValueError('Invalid reference pose; retain raw and review separately')
    rows=[dict(r,time_s=r['decoder_time_s']) for r in records]
    base=read(Path(__file__).parent/'parameters/motion_candidates_v1.json')
    setting=next(s for s in base['settings'] if s['id']=='base')
    timings=state.get('measurements',{}).get('timings_s',{})
    timing_report=dict(job_id=j['jobId'],backend_status=j['status'],backend_code=j.get('code'),cli_state_status=state['status'],
        processed_frames=len(records),valid_frames=sum(r['valid'] for r in records),
        upload_s=None,media_preflight_s=None,model_load_s=timings.get('model_load_s'),runtime_initialization_s=timings.get('runtime_initialization_s'),
        forward_s=timings.get('forward_s'),raw_phase_s=timings.get('raw_phase_s'),result_preparation_s=timings.get('postprocess_s'),
        last_cli_checkpoint_s=state.get('elapsed_s'),backend_reserved_to_terminal_s=(j['updatedAt']-j['createdAt'])/1000,
        mobile_start_to_visible_s=None,api_result_exists=(job/'api_result.json').exists(),cli_result_exists=(run/'result.json').exists(),
        runtime=state.get('runtime_environment'),notes=[
            'Backend lifecycle is not pure upload, HTTP response latency or mobile-visible elapsed.',
            'Runtime initialization includes model_load; raw_phase includes forward/decode/preprocess/writes; do not sum nested times.',
            'No separate upload/preflight timer. Null postprocess timer is incomplete, not zero.',
            'Backend terminal overrides stale CLI running checkpoint; full matrices do not prove successful API result.'])
    write(out/'stage_timings.json',timing_report)
    variants={};flat=[];comparisons={}
    full_series=series(rows,base)
    for mode,rs in full_series.items():
        key='full24_'+mode;variants[key]=detect(rs,base,setting)
    for phase in protocol['phases']:
        for window in protocol['median_intervals']:
            config=copy.deepcopy(base);config.update(nominal_fps=12,window_intervals=window,start_confirmation_samples=2,stop_confirmation_samples=3)
            selected=sampled_rows(rows,phase)
            for mode,rs in series(selected,config,alpha=protocol['ema_alpha']).items():
                label='raw' if mode=='raw' else 'ema_075'
                key=f'sample12_p{phase}_w{window}_{label}'
                variants[key]=detect(rs,config,setting)
                comparisons[key]=match_candidates(variants['full24_'+mode]['candidates'],variants[key]['candidates'])
                write(out/(key+'_config.json'),dict(config=config,phase=phase,alpha=protocol['ema_alpha'],sample_count=len(rs)))
    manual=read(job/'manual.json')
    call={key:manual.get('marks',{}).get(key,{}).get('media_time_ms') for key in ('call_start_s','call_end_s')}
    for key,d in variants.items():
        write(out/(key+'.json'),d)
        for c in d['candidates']:
            flat.append(dict(condition=key,**c,
                start_minus_call_start_s=None if c['start_s'] is None or call['call_start_s'] is None else c['start_s']-call['call_start_s']/1000,
                start_minus_call_end_s=None if c['start_s'] is None or call['call_end_s'] is None else c['start_s']-call['call_end_s']/1000,
                start_minus_manual_movement_s=None,end_minus_manual_movement_s=None))
    qualified=all(c['eligible'] for c in comparisons.values())
    result=dict(video_sha256=j['videoHash'],reference_is_complete_matrix_series=True,reference_api_completed=j['status']=='completed',
        source_frames=len(records),sampled_frames_per_phase=len(sampled_rows(rows,0)),protocol=protocol,
        conditions=comparisons,all_candidates=flat,manual_call_ms=call,manual_movement_bounds_available=False,
        real_sparse_inference_qualified=qualified,new_model_calls=0,
        limitation='Same-video reference fidelity only; manual motion labels absent; call marks do not establish movement correctness or causality.')
    write(out/'comparison.json',result)
    fields=list(dict.fromkeys(k for r in flat for k in r))
    with (out/'candidates.csv').open('x',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(flat)
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axes=plt.subplots(2,1,figsize=(12,8),sharex=True)
    for ax,mode in zip(axes,('raw','ema_050')):
        for key,d in variants.items():
            if (mode=='raw' and not key.endswith('raw')) or (mode!='raw' and '_ema_' not in key):continue
            fs=d['feature_records'];ax.plot([f['time_s'] for f in fs],[float('nan') if f['median_speed_deg_s'] is None else f['median_speed_deg_s'] for f in fs],label=key,alpha=.75)
        ax.axhline(45,color='red',linestyle='--');ax.axhline(20,color='green',linestyle='--')
        if all(v is not None for v in call.values()):ax.axvspan(call['call_start_s']/1000,call['call_end_s']/1000,color='gray',alpha=.2,label='manual call, not movement')
        ax.set_ylabel('SO(3) deg/s');ax.legend(fontsize=7);ax.set_title(mode)
    axes[-1].set_xlabel('Decoder video time (s); AV/LibVLC alignment unverified');fig.tight_layout();fig.savefig(out/'speed_comparison.png');plt.close(fig)
    lines=['# Recorded24fps vs sampled12fps research', '',f"Source job: {j['jobId']}; terminal: {j['status']}/{j.get('code')}. Full matrix coverage: {len(records)}. API result: {timing_report['api_result_exists']}.",
        '', '| Condition | Candidates | First start/end s | End confirmed s | Reference comparison |','|---|---:|---|---|---|']
    for key,d in variants.items():
        cs=d['candidates'];c=cs[0] if cs else {}
        lines.append(f"| {key} | {len(cs)} | {c.get('start_s')} / {c.get('end_s')} | {c.get('end_confirmed_s')} | {comparisons.get(key,'reference')} |")
    lines+=['',f'Real sparse inference gate: {qualified}. Manual movement error is UNKNOWN: only manual call marks exist.',
        'No model inference was run. No new thresholds fitted to manual labels. All candidates and uncertain bands retained. Settling not evaluated or equated to movement end.',
        'Timing: '+json.dumps(timing_report), 'Missing values mean unknown, not zero. Mobile-visible completion cannot be derived from backend job timestamps.']
    (out/'SUMMARY.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    after={p:sha(p) for p in before};write(out/'source_preservation.json',dict(before=before,after=after,unchanged=before==after))
    if before!=after:raise ValueError('Protected source changed')
    print('\n'.join(lines[:14]),flush=True);print('qualified',qualified,'output',out,flush=True)


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--job',required=True,type=Path);ap.add_argument('--output',required=True,type=Path)
    main(ap.parse_args())
