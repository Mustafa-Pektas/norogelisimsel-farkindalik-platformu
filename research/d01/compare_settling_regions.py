"""Post-hoc comparison only; no changes to fixed settling results or labels."""
from pathlib import Path
import argparse
import csv
import json
import os
from motion_candidates import sha

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-dir',type=Path,required=True)
    parser.add_argument('--manual-json',type=Path,required=True)
    args=parser.parse_args();out=args.experiment_dir.resolve();repo=Path(__file__).resolve().parents[2]
    if out==repo or repo in out.parents:raise ValueError('Outputs outside checkout required')
    if any((out/name).exists() for name in ('manual_comparison.json','manual_comparison.csv','manual_comparison.png')):raise ValueError('No comparison overwrite')
    source=out/'settling.json';source_hash=sha(source);manual_hash=sha(args.manual_json)
    report=json.loads(source.read_text(encoding='utf-8'));assert report['status']=='completed'
    annotation=json.loads(args.manual_json.read_text(encoding='utf-8-sig'))
    def mark(name):
        value=annotation.get('marks',{}).get(name)
        return None if value is None else dict(time_s=value['media_time_ms']/1000,time_source=value.get('time_source'))
    start,end=mark('response_start_s'),mark('response_end_s')
    comparisons=[]
    for method,conditions in report['results'].items():
        for radius,result in conditions.items():
            for w in result['windows']:
                interval=w['candidate_interval_s']
                comparisons.append(dict(method=method,radius_deg=int(radius),window_id=w['window_id'],status=w['status'],
                    candidate_interval_s=interval,confirmation_time_s=w['confirmation_time_s'],
                    candidate_interval_minus_manual_end_s=None if interval is None or end is None else [v-end['time_s'] for v in interval],
                    confirmation_minus_manual_end_s=None if w['confirmation_time_s'] is None or end is None else w['confirmation_time_s']-end['time_s'],
                    departure=w['departure']))
    with (out/'manual_comparison.csv').open('w',encoding='utf-8',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(comparisons[0]));writer.writeheader()
        for r in comparisons:writer.writerow({k:json.dumps(v) if isinstance(v,(list,dict)) else v for k,v in r.items()})
    os.environ['MPLCONFIGDIR']=str(out/'matplotlib_config')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axs=plt.subplots(2,2,figsize=(17,12))
    for ax,(method,radius) in zip(axs.flat,[(m,r) for m,conditions in report['results'].items() for r in conditions]):
        accepted=[w for w in report['results'][method][radius]['windows'] if w['status']=='accepted_settling_window']
        for i,w in enumerate(accepted):
            ax.plot(w['candidate_interval_s'],[i,i],color='green',marker='.',label='First block interval' if i==0 else None)
            ax.plot(w['confirmation_time_s'],i,'^',color='blue',label='Confirmation' if i==0 else None)
            departure=w['departure']
            if departure['confirmed_s'] is not None:ax.plot(departure['confirmed_s'],i,'x',color='red',label='Later exit confirmed' if i==0 else None)
        if start is not None and end is not None:ax.axvspan(start['time_s'],end['time_s'],color='orange',alpha=.15,label='Manual candidate; alignment/end unverified')
        ax.set_yticks(range(len(accepted)),labels=[w['seed_frame'] for w in accepted]);ax.set_ylabel('Window seed frame (overlapping candidates)')
        ax.set_title(method+' / '+radius+' deg');ax.set_xlim(0,7);ax.grid(alpha=.2);ax.legend(fontsize=7);ax.set_xlabel('Decoder seconds; retrospective interval is NOT decision time')
    fig.tight_layout();fig.savefig(out/'manual_comparison.png',dpi=150);fig.savefig(out/'manual_comparison.svg');plt.close(fig)
    assert sha(source)==source_hash and sha(args.manual_json)==manual_hash
    (out/'manual_comparison.json').write_text(json.dumps(dict(settling_sha256=source_hash,manual_sha256=manual_hash,
        manual_start=start,manual_end=end,manual_end_is_approximate=True,alignment_verified=False,manual_is_ground_truth=False,
        no_best_result_selected=True,comparison=comparisons,
        caveat='All windows retained including rejected ones; arithmetic offsets under unverified LibVLC/decoder alignment, not exact error or accuracy.'),indent=2)+'\n',encoding='utf-8')
    print(f'Compared all {len(comparisons)} windows after detection; no labels or fixed results changed.')

if __name__=='__main__':main()
