"""Separate post-hoc comparison; cannot change candidate detection or parameters."""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import math
import os

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--detection-dir',type=Path,required=True)
    parser.add_argument('--manual-json',type=Path,required=True)
    args=parser.parse_args();out=args.detection_dir.resolve()
    repo=Path(__file__).resolve().parents[2]
    if out==repo or repo in out.parents:raise ValueError('Comparison outputs must be outside checkout')
    names=['manual_comparison.json','manual_comparison.csv','manual_comparison.png','manual_comparison.svg']
    if any((out/n).exists() for n in names):raise ValueError('No overwrite of previous comparison')
    detection=out/'detection.json';before=sha(detection);manual_before=sha(args.manual_json)
    data=json.loads(detection.read_text(encoding='utf-8'))
    annotation=json.loads(args.manual_json.read_text(encoding='utf-8-sig'))
    def mark(name):
        m=annotation.get('marks',{}).get(name)
        if m is None:return None
        ms=m.get('media_time_ms')
        if not isinstance(ms,(int,float)) or isinstance(ms,bool) or not math.isfinite(ms):raise ValueError('Invalid manual time')
        return dict(time_s=ms/1000,time_source=m.get('time_source'))
    manual_start=mark('response_start_s');manual_end=mark('response_end_s')
    comparison=[]
    for method,settings in data['results'].items():
        for setting,result in settings.items():
            for event in result['candidates']:
                comparison.append(dict(method=method,setting=setting,candidate_id=event['candidate_id'],
                    start_s=event['start_s'],end_s=event['end_s'],
                    start_difference_s=None if event['start_s'] is None or manual_start is None else event['start_s']-manual_start['time_s'],
                    end_difference_s=None if event['end_s'] is None or manual_end is None else event['end_s']-manual_end['time_s'],
                    start_confirmed_s=event['start_confirmed_s'],end_confirmed_s=event['end_confirmed_s'],
                    start_status=event['start_status'],end_status=event['end_status']))
    with (out/'manual_comparison.csv').open('w',encoding='utf-8',newline='') as f:
        keys=list(comparison[0]) if comparison else ['method','setting','candidate_id','start_s','end_s']
        w=csv.DictWriter(f,fieldnames=keys);w.writeheader();w.writerows(comparison)
    os.environ['MPLCONFIGDIR']=str(out/'matplotlib_config')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,ax=plt.subplots(figsize=(15,7))
    labels=[]
    for y,row in enumerate(comparison):
        labels.append(f"{row['method']} / {row['setting']} / {row['candidate_id']}")
        if row['start_s'] is not None and row['end_s'] is not None:
            ax.plot([row['start_s'],row['end_s']],[y,y],'o-',color='tab:blue' if row['method']=='raw' else 'tab:green')
        else:ax.text(0,y,'Unknown/censored boundary',fontsize=8)
    if manual_start is not None and manual_end is not None:
        ax.axvspan(manual_start['time_s'],manual_end['time_s'],color='orange',alpha=.2,label='Manual candidate only; approximate end / clock alignment unverified')
    ax.set_yticks(range(len(labels)),labels=labels);ax.set_xlim(0,7);ax.grid(alpha=.3);ax.legend(fontsize=8)
    ax.set_xlabel('Decoder seconds; manual LibVLC time overlaid under UNVERIFIED alignment')
    ax.set_title('ALL candidates; no best-match selection and no accuracy score')
    fig.tight_layout();fig.savefig(out/'manual_comparison.png',dpi=150);fig.savefig(out/'manual_comparison.svg');plt.close(fig)
    result=dict(detection_sha256=before,manual_sha256=manual_before,manual_start=manual_start,manual_end=manual_end,
        manual_end_is_approximate=True,alignment_verified=False,manual_is_ground_truth=False,
        all_candidates_compared_to_same_single_manual_candidate=True,no_best_candidate_selected=True,
        comparison=comparison,behavior_result=None,
        caveat='Differences are arithmetic under unverified LibVLC/decoder alignment, not exact millisecond errors; other candidates lack independent labels and are not false positives by default.')
    assert sha(detection)==before and sha(args.manual_json)==manual_before
    (out/'manual_comparison.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(comparison,indent=2))

if __name__=='__main__':main()
