"""Recorded-matrix settling windows; no inference and no manual-label input."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import csv
import json
import os

import numpy as np
from motion_candidates import rotation, angle_deg, load_records, sha

def medoid(matrices):
    distances=np.array([[angle_deg(a,b) for b in matrices] for a in matrices])
    index=int(np.argmin(distances.sum(axis=1)))
    return matrices[index],index

def block(records, config):
    if not records:return None,'missing_data'
    matrices=[rotation(r.get('rotation_matrix')) if r.get('valid',False) else None for r in records]
    if any(m is None for m in matrices):return None,'invalid_matrix'
    for a,b in zip(records,records[1:]):
        dt=b['time_s']-a['time_s']
        if b['frame_index']!=a['frame_index']+1 or not np.isfinite(dt) or not 0<dt<=config['max_dt_factor']/config['nominal_fps']:
            return None,'data_gap'
    return matrices,None

def departure(records, start, center, radius, config):
    run=[];excursions=[];last=None
    for i in range(start,len(records)):
        m=rotation(records[i].get('rotation_matrix')) if records[i].get('valid',False) else None
        if m is None or (i>0 and block(records[i-1:i+1],config)[0] is None):
            return dict(status='unknown_data_gap',start_s=None,confirmed_s=None,last_assessed_s=last,
                short_excursions=excursions,pending_outside_frames=[records[j]['frame_index'] for j in run])
        last=records[i]['time_s']
        if angle_deg(center,m)>radius*config['departure_radius_multiplier']:
            run.append(i)
            if len(run)>=config['departure_required_consecutive_samples']:
                return dict(status='confirmed_region_exit',start_s=records[run[0]]['time_s'],
                    confirmed_s=records[i]['time_s'],start_frame=records[run[0]]['frame_index'],
                    confirmed_frame=records[i]['frame_index'],short_excursions=excursions)
        else:
            if run:excursions.append(dict(start_s=records[run[0]]['time_s'],end_s=records[run[-1]]['time_s'],samples=len(run)))
            run=[]
    return dict(status='pending_exit_at_clip_end' if run else 'no_confirmed_exit_before_clip_end',
        start_s=None,confirmed_s=None,last_assessed_s=last,short_excursions=excursions,
        pending_outside_frames=[records[j]['frame_index'] for j in run])

def scan(records, v1_start_frame, radius, config):
    positions=[i for i,r in enumerate(records) if r['frame_index']==v1_start_frame]
    if len(positions)!=1:raise ValueError('Fixed V1 start frame missing or duplicated')
    start=positions[0];n=config['first_block_frames'];k=config['confirmation_block_frames']
    ref_records=records[max(0,start-config['initial_reference_frames']):start]
    ref_mats,ref_error=block(ref_records,config)
    if len(ref_records)!=config['initial_reference_frames']:ref_mats=None;ref_error='insufficient_initial_reference'
    reference=None
    if ref_mats is not None:
        center,which=medoid(ref_mats)
        reference=dict(matrix=center.tolist(),medoid_frame=ref_records[which]['frame_index'],
            first_frame=ref_records[0]['frame_index'],last_frame=ref_records[-1]['frame_index'],
            max_distance_deg=max(angle_deg(center,m) for m in ref_mats))
    windows=[]
    for j in range(start,len(records)):
        first=records[j:j+n];second=records[j+n:j+n+k];reasons=[]
        row=dict(window_id=f'window_{records[j]["frame_index"]:03d}',seed_frame=records[j]['frame_index'],
            fixed_v1_start_frame=v1_start_frame,radius_deg=radius,status=None,reasons=reasons,
            candidate_interval_s=[first[0]['time_s'],first[-1]['time_s']] if len(first)==n else None,
            available_interval_s=[records[j]['time_s'],records[min(len(records)-1,j+n+k-1)]['time_s']],
            confirmation_time_s=None,confirmation_delay_from_candidate_end_s=None,
            confirmation_delay_from_candidate_start_s=None,departure=None)
        if reference is None:reasons.append('initial_reference_unavailable:'+str(ref_error))
        if len(first)<n:reasons.append('insufficient_first_block_at_clip_end')
        if len(second)<k:reasons.append('insufficient_confirmation_at_clip_end')
        fm,fe=block(first,config);sm,se=block(second,config)
        if fe:reasons.append('first_block_'+fe)
        if se and len(second)==k:reasons.append('confirmation_block_'+se)
        if len(first)==n and len(second)==k and block(first[-1:]+second[:1],config)[0] is None:
            reasons.append('gap_between_blocks')
        if fm is not None and len(first)==n:
            c1,i1=medoid(fm);row['first_center_matrix']=c1.tolist();row['first_medoid_frame']=first[i1]['frame_index']
            distances=[angle_deg(c1,m) for m in fm]
            row['first_support_frames']=[r['frame_index'] for r,d in zip(first,distances) if d<=radius+1e-8]
            row['first_outside_frames']=[r['frame_index'] for r,d in zip(first,distances) if d>radius+1e-8]
            if len(row['first_support_frames'])<config['first_block_required_support']:reasons.append('insufficient_first_region_support')
            if reference is not None:
                d=angle_deg(np.array(reference['matrix']),c1);row['first_distance_from_initial_deg']=d
                if d<=config['initial_separation_radius_multiplier']*radius+1e-8:reasons.append('first_region_not_separated_from_initial')
            if sm is not None and len(second)==k:
                c2,i2=medoid(sm);row['second_center_matrix']=c2.tolist();row['second_medoid_frame']=second[i2]['frame_index']
                d=angle_deg(c1,c2);row['center_distance_deg']=d
                if d>radius*config['max_inter_center_distance_radius_multiplier']+1e-8:reasons.append('inter_center_drift_too_large')
                distances=[angle_deg(c1,m) for m in sm]
                row['confirmation_support_frames']=[r['frame_index'] for r,d in zip(second,distances) if d<=radius+1e-8]
                row['confirmation_outside_frames']=[r['frame_index'] for r,d in zip(second,distances) if d>radius+1e-8]
                if len(row['confirmation_support_frames'])<config['confirmation_required_support']:reasons.append('insufficient_support_against_frozen_first_center')
                if reference is not None:
                    d=angle_deg(np.array(reference['matrix']),c2);row['second_distance_from_initial_deg']=d
                    if d<=config['initial_separation_radius_multiplier']*radius+1e-8:reasons.append('confirmation_region_not_separated_from_initial')
        if not reasons:
            row['status']='accepted_settling_window';row['confirmation_time_s']=second[-1]['time_s']
            row['confirmation_delay_from_candidate_end_s']=second[-1]['time_s']-first[-1]['time_s']
            row['confirmation_delay_from_candidate_start_s']=second[-1]['time_s']-first[0]['time_s']
            row['departure']=departure(records,j+n+k,c1,radius,config)
        else:
            row['status']='unconfirmed_incomplete_data' if any('insufficient_' in x and 'at_clip_end' in x or 'unavailable' in x or 'gap' in x or 'invalid_matrix' in x for x in reasons) else 'rejected_conditions'
        windows.append(row)
    groups=[];current=[]
    def flush():
        if not current:return
        groups.append(dict(group_id=f'overlapping_group_{len(groups)+1:03d}',window_count=len(current),
            seed_frames=[r['seed_frame'] for r in current],
            candidate_start_time_range_s=[current[0]['candidate_interval_s'][0],current[-1]['candidate_interval_s'][0]],
            candidate_end_time_range_s=[current[0]['candidate_interval_s'][1],current[-1]['candidate_interval_s'][1]],
            confirmation_time_range_s=[current[0]['confirmation_time_s'],current[-1]['confirmation_time_s']],
            center_drift_from_first_window_deg=max(angle_deg(np.array(current[0]['first_center_matrix']),np.array(r['first_center_matrix'])) for r in current),
            caveat='Consecutive accepted seeds; not independent events and not one globally fixed center'))
    for row in windows:
        if row['status']=='accepted_settling_window':current.append(row)
        else:flush();current=[]
    flush()
    return dict(radius_deg=radius,fixed_v1_start_frame=v1_start_frame,initial_reference=reference,
        initial_reference_error=ref_error,windows=windows,overlapping_groups=groups)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('raw-dir','smoothed-dir','v1-dir','output-dir'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--config',type=Path,default=Path(__file__).parent/'parameters/settling_regions_v1.json')
    args=parser.parse_args();out=args.output_dir.resolve();repo=Path(__file__).resolve().parents[2]
    if out==repo or repo in out.parents:raise ValueError('Outputs outside checkout required')
    config=json.loads(args.config.read_text(encoding='utf-8'));assert config['manual_labels_used_by_detector'] is False
    for source in (args.raw_dir,args.smoothed_dir,args.v1_dir):
        if out==source.resolve() or source.resolve() in out.parents:raise ValueError('Outputs separate from sources required')
    if out.exists():
        if any(p.name not in ('conditions.json','synthetic_tests.txt') for p in out.iterdir()):raise ValueError('No overwrite')
        assert json.loads((out/'conditions.json').read_text(encoding='utf-8'))['parameters']==config
    else:
        out.mkdir(parents=True,exist_ok=False)
        (out/'conditions.json').write_text(json.dumps(dict(recorded_utc=datetime.now(timezone.utc).isoformat(),parameters=config),indent=2)+'\n',encoding='utf-8')
    before={str(p.resolve()):sha(p) for base in (args.raw_dir,args.smoothed_dir,args.v1_dir) for p in base.rglob('*') if p.is_file()}
    (out/'protected_manifest.json').write_text(json.dumps(before,indent=2)+'\n',encoding='utf-8')
    v1=json.loads((args.v1_dir/'detection.json').read_text(encoding='utf-8'))
    smooth=json.loads((args.smoothed_dir/'report.json').read_text(encoding='utf-8'))
    assert smooth['source_raw_sha256']==sha(args.raw_dir/'kareler.jsonl')
    results={};flat=[]
    for method,path in [('raw',args.raw_dir/'kareler.jsonl'),('ema_050',args.smoothed_dir/'turetilmis_sonuclar.jsonl')]:
        records=load_records(path,method);assert [r['frame_index'] for r in records]==list(range(168))
        starts=v1['results'][method][config['v1_start_setting']]['candidates']
        assert len(starts)==1 and starts[0]['start_frame'] is not None
        results[method]={}
        for radius in config['radii_deg']:
            result=scan(records,starts[0]['start_frame'],radius,config);results[method][str(radius)]=result
            for w in result['windows']:flat.append(dict(method=method,**w))
    with (out/'all_windows.jsonl').open('x',encoding='utf-8') as f:
        for w in flat:f.write(json.dumps(w,allow_nan=False)+'\n')
    with (out/'all_windows.csv').open('w',encoding='utf-8',newline='') as f:
        fields=['method','radius_deg','window_id','seed_frame','status','candidate_interval_s','confirmation_time_s','confirmation_delay_from_candidate_end_s','reasons','departure']
        writer=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore');writer.writeheader()
        for w in flat:writer.writerow({k:json.dumps(v) if isinstance(v,(dict,list)) else v for k,v in w.items() if k in fields})
    os.environ['MPLCONFIGDIR']=str(out/'matplotlib_config')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axs=plt.subplots(4,1,figsize=(15,12),sharex=True)
    for ax,(method,radius) in zip(axs,[(m,str(r)) for m in results for r in config['radii_deg']]):
        windows=results[method][radius]['windows']
        for w in windows:
            t=w['available_interval_s'][0];color={'accepted_settling_window':'tab:green','rejected_conditions':'tab:red','unconfirmed_incomplete_data':'gray'}[w['status']]
            ax.scatter(t,{'accepted_settling_window':2,'rejected_conditions':1,'unconfirmed_incomplete_data':0}[w['status']],s=9,color=color)
            if w['status']=='accepted_settling_window':ax.plot(w['candidate_interval_s'],[2,2],color='tab:green',alpha=.1)
        ax.set_yticks([0,1,2],['Unconfirmed','Rejected','Accepted']);ax.set_title(method+' / radius '+radius+' deg');ax.grid(alpha=.2)
    axs[-1].set_xlabel('Decoder seconds; all overlapping windows, no manual interval input')
    fig.tight_layout();fig.savefig(out/'all_settling_windows.png',dpi=150);fig.savefig(out/'all_settling_windows.svg');plt.close(fig)
    changed=[p for p,h in before.items() if sha(p)!=h];assert not changed
    report=dict(status='completed',protocol=config['protocol'],config_sha256=sha(args.config),script_sha256=sha(__file__),
        v1_sha256=sha(args.v1_dir/'detection.json'),parameters=config,results=results,
        protected_files=len(before),protected_changed=changed,model_inference_performed=False,manual_labels_read=False,
        interpretation='Settling hypotheses in predicted full head pose, not gaze, behavior, physical accuracy or independent events')
    (out/'settling.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({m:{r:dict(accepted=sum(w['status']=='accepted_settling_window' for w in v['windows']),groups=v['overlapping_groups']) for r,v in rs.items()} for m,rs in results.items()},indent=2))

if __name__=='__main__':main()
