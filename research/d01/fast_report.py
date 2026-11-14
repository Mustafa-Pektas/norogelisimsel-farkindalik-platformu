"""Saved matrices only: native-angle/gap comparison; no new inference."""
from pathlib import Path
import argparse,json,os
from fast_cli import load_protocol
from compare_headpose_methods import series,euler_xyz
from motion_candidates import detect


def report(fast,six,out,manual_start=None,manual_end=None):
    out.mkdir(exist_ok=False)
    result=json.loads((fast/'result.json').read_text())
    settings=json.loads((six/'settings.json').read_text())
    if result['video_hash'] not in settings['inputs_sha256'].values():raise ValueError('Video identity mismatch')
    def rows(p):return [json.loads(line) for line in p.read_text().splitlines()]
    a=rows(fast/'details/frames.jsonl');b=rows(six/'details/raw_frames.jsonl')
    if len(a)!=len(b):raise ValueError('Frame count differs')
    for x,y in zip(a,b):
        y['time_s']=y['decoder_time_s']
        if x['frame_index']!=y['frame_index'] or abs(x['time_s']-y['time_s'])>1e-6:raise ValueError('Timeline mismatch')
    _,config,_,_=load_protocol(Path(__file__).parent/'parameters/pilot_v1.json')
    base=next(s for s in config['settings'] if s['id']=='base')
    detections={}
    for method,rs in [('recorded_6d',b),('fast_pnp',a)]:
        detections[method]={}
        for mode,rotations in series(rs,config).items():
            d=detect(rotations,config,base)
            candidates=[dict(candidate=c,
                start_minus_manual_s=None if manual_start is None or c['start_s'] is None else c['start_s']-manual_start,
                end_minus_manual_s=None if manual_end is None or c['end_s'] is None else c['end_s']-manual_end) for c in d['candidates']]
            detections[method][mode]=candidates
    summary=dict(video_sha256=result['video_hash'],decoder_timeline_equal=True,mathematical_axes='Rz(roll) Ry(yaw) Rx(pitch); degrees',
        physical_reference_aligned=False,manual_motion_candidate=[manual_start,manual_end],manual_clock_alignment_verified=False,
        fast_runtime=result['runtime'],fast_timings_s=result['timings'],fast_coverage=result['coverage'],
        six_scope='saved reference only; no new inference or speed comparison',
        detections=detections,optical_flow_absolute_angles=None,
        limitations=['PnP generic camera/face, no shared calibrated neutral with6D.',
          'Automatic identity continuity is not child/age/target verification.',
          'Unknown ends remain unknown; no gap interpolation or6D fill.',
          'Manual motion times are approximate unapproved candidates, LibVLC/decoder alignment unverified.'])
    (out/'comparison.json').write_text(json.dumps(summary,indent=2))
    os.environ['MPLCONFIGDIR']=str(out/'matplotlib_cache')
    import numpy as np
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axes=plt.subplots(3,3,figsize=(17,10),sharex=True)
    for column,(label,rs) in enumerate([('recorded6D',b),('Tasks/PnP',a),('flow only: NO absolute pose',a)]):
        ts=[r['time_s'] for r in rs]
        angles=[euler_xyz(r['rotation_matrix']) if r['valid'] and column!=2 else [np.nan]*3 for r in rs]
        for axis,name in enumerate(['pitch X','yaw Y','roll Z']):
            ax=axes[axis,column];ax.plot(ts,np.array(angles)[:,axis]);ax.set_title(label);ax.set_ylabel(name+' deg');ax.grid(alpha=.2)
            for r in rs:
                if not r['valid'] or column==2:ax.axvspan(r['time_s'],r['time_s']+1/24,color='grey',alpha=.15)
            calls=result['manualTimes'];start=calls['call_start_s']['time_s'];end=calls['call_end_s']['time_s']
            if start is not None:ax.axvspan(start,end,color='orange',alpha=.2)
            if manual_start is not None and manual_end is not None:ax.axvspan(manual_start,manual_end,color='green',alpha=.1)
    fig.suptitle('Same video/time; native frames NOT physically calibrated. Grey=missing pose; orange=manual call; green=manual motion candidate')
    fig.tight_layout();fig.savefig(out/'native_angles_and_gaps.png',dpi=150);plt.close(fig)
    text=['# Fast D01 saved-result comparison','',f"Video SHA256: `{result['video_hash']}`",'',
          '| Method | Valid pose / total | Duration scope | First raw start / end / confirmed end | Manual start / end difference |',
          '|---|---|---|---|---|']
    for name in ['recorded_6d','fast_pnp']:
        rs=b if name=='recorded_6d' else a;first=detections[name]['raw'][0] if detections[name]['raw'] else None
        c=first['candidate'] if first else {}
        duration='Historical saved reference; not measured now' if name=='recorded_6d' else f"Python total {result['timings']['total_s']:.3f}s; tracking/PnP {result['timings']['tracking_pnp_s']:.3f}s"
        text.append(f"| {name} | {sum(r['valid'] for r in rs)}/{len(rs)} | {duration} | {c.get('start_s')} / {c.get('end_s')} / {c.get('end_confirmed_s')} | {first['start_minus_manual_s'] if first else None} / {first['end_minus_manual_s'] if first else None} |")
    text+=['| Optical flow | 0 absolute poses | Included in tracking/PnP; no isolated flow duration recorded | Not inferred | Not available |','',
           'All raw/EMA candidates are in comparison.json. Unknown boundaries were not filled. No response, correct-target, clinical class or confidence is produced.',
           'Different inputs:6D uses the reviewed cropped224x224 head input; PnP uses detected face landmarks mapped into the source image. Matching video hash/time does not make model inputs identical.',
           'Mobile tap-to-visible duration is NOT measured by this report. The recorded incomplete6D job is not a completed API result.']
    (out/'SUMMARY.md').write_text('\n'.join(text),encoding='utf-8')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--fast',type=Path,required=True);p.add_argument('--six',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--manual-start',type=float);p.add_argument('--manual-end',type=float);a=p.parse_args()
    report(a.fast,a.six,a.output,a.manual_start,a.manual_end)
