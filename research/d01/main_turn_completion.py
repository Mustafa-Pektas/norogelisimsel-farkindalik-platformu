"""Single exploratory SO(3) new-region criterion; independent of low-speed end."""
import math
import numpy as np
from motion_candidates import rotation, angle_deg


def medoid(mats):
    return min(mats, key=lambda a: sum(angle_deg(a, b) for b in mats))


def main_turn_region(rows, candidate):
    if candidate.get('start_s') is None or candidate.get('start_frame') is None:
        return dict(status='uncertain', reason='unknown_start', candidate=None, windows=[])
    by_frame = {r['frame_index']: r for r in rows}
    start = candidate['start_frame']

    def block(first, count):
        rr = [by_frame.get(i) for i in range(first, first+count)]
        if any(r is None or not r['valid'] or r.get('time_s') is None for r in rr):
            return None
        if any(not math.isclose(b['time_s']-a['time_s'], 1/24, abs_tol=1e-6)
               for a,b in zip(rr,rr[1:])):
            return None
        mm = [rotation(r['rotation_matrix']) for r in rr]
        return None if any(m is None for m in mm) else mm

    baseline = block(start-6, 6)
    if baseline is None:
        return dict(status='uncertain', reason='missing_pre_start_context', candidate=None, windows=[])
    initial = medoid(baseline)
    baseline_radius = max(angle_deg(initial, m) for m in baseline)
    if baseline_radius > 8:
        return dict(status='uncertain', reason='unstable_initial_region', initial_radius_deg=baseline_radius, candidate=None, windows=[])
    windows = []; first_match = None
    for first in range(start, max(by_frame)-16):
        last = first+17
        if by_frame[last]['time_s']-candidate['start_s'] > 3+1e-6:
            break
        mats = block(first, 18)
        if mats is None:
            windows.append(dict(first_frame=first,last_frame=last,accepted=False,reason='missing_or_invalid_context'))
            continue
        target = medoid(mats[:9]); second = medoid(mats[9:])
        separation = angle_deg(initial, target)
        a = sum(angle_deg(target,m) <= 8 for m in mats[:9])
        b = sum(angle_deg(target,m) <= 8 for m in mats[9:])
        drift = angle_deg(target,second)
        reasons=[]
        if separation < 20:reasons.append('insufficient_new_orientation')
        if angle_deg(target,mats[0]) > 8:reasons.append('first_sample_outside_region')
        if a < 8:reasons.append('first_block_insufficient_support')
        if b < 8:reasons.append('second_block_insufficient_support')
        if drift > 4:reasons.append('target_center_drift')
        record=dict(first_frame=first,last_frame=last,separation_deg=separation,first_support=a,second_support=b,center_drift_deg=drift,accepted=not reasons,reasons=reasons)
        windows.append(record)
        if not reasons and first_match is None:
            first_match=dict(frame_index=first,time_s=by_frame[first]['time_s'],confirmed_frame=last,confirmed_s=by_frame[last]['time_s'],lookahead_s=by_frame[last]['time_s']-by_frame[first]['time_s'],target_matrix=target.tolist())
    return dict(status='candidate' if first_match else 'uncertain',reason=None if first_match else 'no_reliable_new_region',initial_radius_deg=baseline_radius,initial_matrix=initial.tolist(),candidate=first_match,windows=windows)
