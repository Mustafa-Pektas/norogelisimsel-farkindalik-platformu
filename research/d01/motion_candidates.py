"""Experimental temporal head-motion candidates from recorded SO(3) matrices only.

No manual-label input, model loading, Euler averaging, target classification or confidence.
"""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import math
import os
from datetime import datetime, timezone

import numpy as np

PROTOCOL = 'head-motion-candidates-engineering-v1'

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda: f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()

def rotation(value):
    """Reject invalid source matrices; project only small floating-point roundoff."""
    if value is None: return None
    m = np.asarray(value, dtype=float)
    if (m.shape != (3, 3) or not np.isfinite(m).all() or
            abs(np.linalg.det(m)-1) > 1e-4 or np.max(abs(m.T@m-np.eye(3))) > 1e-4): return None
    u, _, vt = np.linalg.svd(m)
    return u @ np.diag([1., 1., np.linalg.det(u@vt)]) @ vt

def angle_deg(a, b):
    return math.degrees(math.acos(float(np.clip((np.trace(a.T@b)-1)/2, -1., 1.))))

def evidence(records, config):
    """Feature at i summarizes W ending intervals, never future frames."""
    w = config['window_intervals']; dt_max = config['max_dt_factor']/config['nominal_fps']
    mats = [rotation(r.get('rotation_matrix')) if r.get('valid', False) else None for r in records]
    speed = [None]*len(records); reasons = ['missing_previous_frame']+[None]*(len(records)-1)
    for i in range(1, len(records)):
        if records[i].get('time_s') is None or records[i-1].get('time_s') is None:
            reasons[i] = 'missing_time'
            continue
        dt = records[i]['time_s']-records[i-1]['time_s']
        if mats[i] is None or mats[i-1] is None: reasons[i] = 'invalid_matrix'
        elif records[i]['frame_index'] != records[i-1]['frame_index']+1: reasons[i] = 'missing_frame'
        elif not math.isfinite(dt) or dt <= 0 or dt > dt_max: reasons[i] = 'invalid_or_large_time_gap'
        else: speed[i] = angle_deg(mats[i-1], mats[i])/dt
    result = []
    for i, record in enumerate(records):
        window = speed[max(0, i-w+1):i+1]
        valid = i >= w and len(window) == w and all(v is not None for v in window)
        result.append(dict(frame_index=record['frame_index'], time_s=record['time_s'],
            speed_deg_s=speed[i], median_speed_deg_s=float(np.median(window)) if valid else None,
            window_start_s=records[i-w]['time_s'] if valid else None,
            reason=None if valid else ('insufficient_initial_context' if i < w else reasons[i] or 'invalid_window_context')))
    return result

def detect(records, config, setting):
    if not records: raise ValueError('Empty matrix sequence')
    if not (0 < setting['stop_deg_s'] < setting['start_deg_s']): raise ValueError('Threshold order')
    if any(config[k] < 1 or not isinstance(config[k], int) for k in
           ('window_intervals', 'start_confirmation_samples', 'stop_confirmation_samples')): raise ValueError('Positive sample counts required')
    features = evidence(records, config)
    events, uncertain = [], []
    active = None; high = []; low = []; baseline = False
    def uncertainty(kind, inds):
        if inds: uncertain.append(dict(kind=kind, first_frame=features[inds[0]]['frame_index'],
            last_frame=features[inds[-1]]['frame_index'],start_s=features[inds[0]]['time_s'],end_s=features[inds[-1]]['time_s']))
    def close_unknown(reason, index):
        nonlocal active
        active.update(end_s=None,end_frame=None,end_confirmed_s=None,end_status=reason,
            last_supported_time_s=features[index]['time_s'])
        events.append(active);active=None
    for i, f in enumerate(features):
        value = f['median_speed_deg_s']
        if value is None:
            uncertainty('unconfirmed_high_before_gap', high);high=[];low=[]
            if active is not None: close_unknown('unknown_end_data_gap', max(0,i-1))
            baseline=False
            continue
        if active is None:
            if value <= setting['stop_deg_s']:
                low.append(i)
                if len(low)>=config['stop_confirmation_samples']: baseline=True
            else: low=[]
            if value >= setting['start_deg_s']:
                high.append(i)
                if len(high)>=config['start_confirmation_samples']:
                    first=features[high[0]]
                    active=dict(candidate_id=f'candidate_{len(events)+1:03d}',
                        start_s=first['time_s'] if baseline else None,
                        start_frame=first['frame_index'] if baseline else None,
                        start_status='observed_rule_boundary' if baseline else 'unknown_start_no_quiet_baseline',
                        first_high_evidence_s=first['time_s'],start_confirmed_s=f['time_s'],
                        start_evidence_window_start_s=first['window_start_s'],
                        start_evidence_window_end_s=first['time_s'])
                    high=[];low=[]
            else:
                uncertainty('brief_high_not_confirmed',high);high=[]
        else:
            if value <= setting['stop_deg_s']:
                low.append(i)
                if len(low)>=config['stop_confirmation_samples']:
                    first=features[low[0]]
                    active.update(end_s=first['time_s'],end_frame=first['frame_index'],
                        end_status='observed_rule_boundary',end_confirmed_s=f['time_s'],
                        end_evidence_window_start_s=first['window_start_s'],end_evidence_window_end_s=first['time_s'])
                    events.append(active);active=None;baseline=True;high=[];low=[]
            else:
                uncertainty('brief_quiet_no_confirmed_stop',low);low=[]
    if active is not None:
        uncertainty('unconfirmed_quiet_at_clip_end',low);close_unknown('unknown_end_clip_ended',len(features)-1)
    uncertainty('unconfirmed_high_at_clip_end',high)
    # Retain all ambiguous bands and missing evidence, not only accepted movement events.
    for kind, predicate in [
        ('insufficient_or_invalid_evidence',lambda f:f['median_speed_deg_s'] is None),
        ('hysteresis_transition_band',lambda f:f['median_speed_deg_s'] is not None and
         setting['stop_deg_s'] < f['median_speed_deg_s'] < setting['start_deg_s'])]:
        inds=[]
        for i,f in enumerate(features):
            if predicate(f):inds.append(i)
            else:uncertainty(kind,inds);inds=[]
        uncertainty(kind,inds)
    return dict(protocol=PROTOCOL,setting=setting,candidates=events,uncertain_intervals=uncertain,
        feature_records=features,no_candidate_is_not_no_movement=True)

def load_records(path, method):
    all_rows=[json.loads(l) for l in Path(path).read_text(encoding='utf-8').splitlines() if l.strip()]
    if method=='raw': return [dict(frame_index=r['frame_index'],time_s=r['decoder_time_s'],
        rotation_matrix=r['rotation_matrix'],valid=r['valid']) for r in all_rows]
    return [dict(frame_index=r['frame_index'],time_s=r['decoder_time_s'],rotation_matrix=r['rotation_matrix'],valid=r['valid'])
        for r in all_rows if r['method']==method]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw-dir',type=Path,required=True)
    parser.add_argument('--smoothed-dir',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--config',type=Path,default=Path(__file__).parent/'parameters/motion_candidates_v1.json')
    args=parser.parse_args();out=args.output_dir.resolve();repo=Path(__file__).resolve().parents[2]
    if out==repo or repo in out.parents:raise ValueError('Outputs must be outside checkout')
    for source in (args.raw_dir.resolve(),args.smoothed_dir.resolve()):
        if out==source or source in out.parents:raise ValueError('Outputs must be separate from sources')
    config=json.loads(args.config.read_text(encoding='utf-8'));assert config['protocol']==PROTOCOL
    assert config['manual_labels_used_by_detector'] is False
    protected={str(p.resolve()):sha(p) for base in (args.raw_dir,args.smoothed_dir) for p in base.rglob('*') if p.is_file()}
    out.mkdir(parents=True,exist_ok=False)
    (out/'parameters.json').write_text(json.dumps(config,indent=2)+'\n',encoding='utf-8')
    results={};series={}
    for method,path in [('raw',args.raw_dir/'kareler.jsonl'),('ema_050',args.smoothed_dir/'turetilmis_sonuclar.jsonl')]:
        records=load_records(path,method);assert [r['frame_index'] for r in records]==list(range(168))
        series[method]=records;results[method]={}
        for setting in config['settings']:results[method][setting['id']]=detect(records,config,setting)
    # No manual time or annotation is available to detection/plotting in this command.
    os.environ['MPLCONFIGDIR']=str(out/'matplotlib_config')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axs=plt.subplots(3,2,figsize=(17,11),sharex=True)
    flat=[]
    for col,method in enumerate(results):
        for row,setting in enumerate(config['settings']):
            r=results[method][setting['id']];ax=axs[row,col];features=r['feature_records']
            ax.plot([f['time_s'] for f in features],[np.nan if f['median_speed_deg_s'] is None else f['median_speed_deg_s'] for f in features],label='Causal median speed')
            ax.axhline(setting['start_deg_s'],color='red',linestyle='--',label='Start engineering threshold')
            ax.axhline(setting['stop_deg_s'],color='gray',linestyle='--',label='Stop engineering threshold')
            for e in r['candidates']:
                left=e['start_s'] if e['start_s'] is not None else e['first_high_evidence_s']
                right=e['end_s'] if e['end_s'] is not None else series[method][-1]['time_s']
                ax.axvspan(left,right,color='orange',alpha=.15)
                flat.append(dict(method=method,setting=setting['id'],**e))
            ax.set_title(f'{method} / {setting["id"]}');ax.set_ylabel('Median predicted speed (deg/s)');ax.grid(alpha=.3)
            if row==0:ax.legend(fontsize=7)
    for ax in axs[-1]:ax.set_xlabel('Decoder time (s); no manual label input')
    fig.tight_layout();fig.savefig(out/'tum_klip_adaylar.png',dpi=150);fig.savefig(out/'tum_klip_adaylar.svg');plt.close(fig)
    with (out/'candidates.csv').open('w',encoding='utf-8',newline='') as f:
        keys=sorted({k for e in flat for k in e}) if flat else ['method','setting','candidate_id','start_s','end_s']
        w=csv.DictWriter(f,fieldnames=keys);w.writeheader();w.writerows(flat)
    changed=[p for p,h in protected.items() if sha(p)!=h];assert not changed
    report=dict(status='completed',created_utc=datetime.now(timezone.utc).isoformat(),protocol=PROTOCOL,
        config_sha256=sha(args.config),script_sha256=sha(__file__),source_hashes={str(args.raw_dir/'kareler.jsonl'):sha(args.raw_dir/'kareler.jsonl'),
        str(args.smoothed_dir/'turetilmis_sonuclar.jsonl'):sha(args.smoothed_dir/'turetilmis_sonuclar.jsonl')},
        parameters=config,results=results,protected_files=len(protected),protected_changed=changed,
        manual_labels_read=False,model_inference_performed=False,behavior_result=None,pose_accuracy_reference=False)
    (out/'detection.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({m:{s:r['candidates'] for s,r in v.items()} for m,v in results.items()},indent=2),flush=True)

if __name__=='__main__':main()
