"""Post-run comparison only: no model or detector calls, labels never affect selection."""
from pathlib import Path
import argparse
import csv
import json
from compare_headpose_methods import read, write, sha


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]


def summarize(root, manual):
    import numpy as np
    from motion_candidates import angle_deg, rotation
    from pilot_time_relations import manual_mark
    full,hybrid=(read(root/m/'result.json') for m in ('full','hybrid'))
    if full['status']!='completed' or hybrid['status']!='completed':raise ValueError('Both runs must complete')
    if full['video_sha256']!=hybrid['video_sha256']:raise ValueError('Video identity mismatch')
    fc,hc=(read(root/m/'config.json') for m in ('full','hybrid'))
    if fc!=hc:raise ValueError('Paired settings mismatch')
    if any(full['runtime'][k]!=hybrid['runtime'][k] for k in ('torch_threads','torch_interop_threads','device','torch_runtime_version')):
        raise ValueError('Effective runtime mismatch')
    fs,hs=(rows(root/m/'sixd_frames.jsonl') for m in ('full','hybrid'))
    fm={r['frame_index']:r for r in fs}
    diffs=[]
    for r in hs:
        f=fm[r['frame_index']]
        valid_pair=r['valid'] and f['valid']
        diffs.append(dict(frame_index=r['frame_index'],valid_pair=valid_pair,
            image_hash_equal=r['input_rgb_sha256']==f['input_rgb_sha256'],tensor_hash_equal=r['normalized_tensor_sha256']==f['normalized_tensor_sha256'],
            matrix_max_abs=None if not valid_pair else float(np.max(np.abs(np.array(r['rotation_matrix'])-f['rotation_matrix']))),
            so3_deg=None if not valid_pair else angle_deg(rotation(r['rotation_matrix']),rotation(f['rotation_matrix']))))
    tolerance=full['comparison_tolerance']
    good=[d for d in diffs if d['valid_pair']]
    diff_summary=dict(shared_frames=len(diffs),valid_pairs=len(good),all_input_hashes_equal=all(d['image_hash_equal'] and d['tensor_hash_equal'] for d in diffs),
        max_matrix_abs=max((d['matrix_max_abs'] for d in good),default=None),max_so3_deg=max((d['so3_deg'] for d in good),default=None),
        tolerance=tolerance,all_valid_within_tolerance=len(good)==len(diffs) and all(d['matrix_max_abs']<=tolerance['matrix_element_atol'] and d['so3_deg']<=tolerance['so3_angle_deg'] for d in good))
    # Manual marks are loaded only after both frozen detections have been read.
    labels=read(manual)
    if labels['video_sha256']!=full['video_sha256']:raise ValueError('Manual/video mismatch')
    marks={key:manual_mark(labels,key) for key in ('call_start_s','call_end_s','response_start_s','response_end_s')}
    candidates=[]
    for name,result in (('full',full),('hybrid',hybrid)):
        for mode in ('raw','ema_050'):
            windows=[dict(candidates=result['detections'][mode]['candidates'])] if name=='full' else result['windows'][mode]['windows']
            for wi,w in enumerate(windows):
                for c in w['candidates']:
                    candidates.append(dict(method=name,series=mode,window=wi,**c,
                        start_minus_manual_s=None if c['start_s'] is None else c['start_s']-marks['response_start_s']['time_s'],
                        end_minus_manual_s=None if c['end_s'] is None else c['end_s']-marks['response_end_s']['time_s']))
    write(root/'comparison.json',dict(video_sha256=full['video_sha256'],manual=marks,manual_file_sha256=sha(manual),manual_status=labels.get('annotation_status'),
        candidates=candidates,shared_matrix_comparison=diff_summary,
        elapsed_difference_s=hybrid['elapsed_s']-full['elapsed_s'],elapsed_difference_percent=100*(hybrid['elapsed_s']/full['elapsed_s']-1),
        limitations=['Two fresh local CPU runs, one video, full before hybrid; no statistical speed claim','Human supplied fixed ROI','Manual endpoint approximate, LibVLC/decoder alignment unverified','No behavioral/target/confidence result','Future dwell samples confirm earlier candidate boundaries']))
    fields=list(dict.fromkeys(k for r in candidates for k in r))
    with (root/'candidates.csv').open('x',encoding='utf-8',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(candidates)
    write(root/'matrix_differences.json',diffs)
    lines=['# Fresh local full6D / buffered hybrid comparison','',
        '| Method | Total s | Actual 6D frames | Valid / invalid 6D | Model load s (nested) | PnP/track s |',
        '|---|---:|---:|---:|---:|---:|']
    for name,r in (('full6D',full),('MP/PnP + selective6D',hybrid)):
        lines.append(f"| {name} | {r['elapsed_s']:.3f} | {r['real_6d_frames']} | {r['valid_6d_frames']} / {r['failed_6d_frames']} | {r['timings_s']['model_load_s']:.3f} | {r['timings_s']['tracking_pnp_s']:.3f} |")
    lines+=['','| Method / series | First start s | First end s | End confirmed s | Start / end minus manual s |','|---|---:|---:|---:|---|']
    for name in ('full','hybrid'):
        for mode in ('raw','ema_050'):
            cs=[c for c in candidates if c['method']==name and c['series']==mode and c['start_s'] is not None]
            if not cs:
                lines.append(f'| {name}/{mode} | unknown | unknown | unknown | unknown |');continue
            c=cs[0]
            lines.append(f"| {name}/{mode} | {c['start_s']} | {c['end_s']} | {c['end_confirmed_s']} | {c['start_minus_manual_s']} / {c['end_minus_manual_s']} |")
    lines+=['',f"Paired matrix checks: {json.dumps(diff_summary)}",'',
        'Total scope: '+full['timing_scope'],'',
        'Manual movement interval is a candidate, not ground truth. No gaze/response classification. All candidates, including later movements and missing boundaries, remain in candidates.csv/comparison.json.',
        'Only this video and one fresh run per method. Run order is full then hybrid; initialization/cache/load variability is uncontrolled. Historical runtimes are not included.']
    (root/'SUMMARY.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('\n'.join(lines))


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--experiment',type=Path,required=True);ap.add_argument('--manual',type=Path,required=True)
    args=ap.parse_args();summarize(args.experiment,args.manual)
