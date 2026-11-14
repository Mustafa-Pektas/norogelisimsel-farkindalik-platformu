"""Research-only window variant. No pose repair or detector modification."""
import math


def gap_groups(rows):
    """Join invalid runs across exactly one present, valid frame; retain it."""
    runs = []
    for row in rows:
        if not row['valid']:
            if runs and runs[-1][-1]['frame_index'] == row['frame_index'] - 1:
                runs[-1].append(row)
            else:
                runs.append([row])
    by_index = {r['frame_index']: r for r in rows}
    groups = []
    for run in runs:
        if groups:
            prev = groups[-1]
            bridge_index = prev['end']['frame_index'] + 1
            bridge = by_index.get(bridge_index)
            if (run[0]['frame_index'] == bridge_index + 1 and bridge
                    and bridge['valid']):
                prev['runs'].append(run)
                prev['bridges'].append(bridge_index)
                prev['end'] = run[-1]
                continue
        groups.append(dict(start=run[0], end=run[-1], runs=[run], bridges=[]))
    return groups


def select(rows, detections, fps):
    if fps != 24:
        raise ValueError('This research variant supports24FPS only')
    eligible, rejected = [], []
    for mode in ('raw', 'ema_050'):
        for c in detections[mode]['candidates']:
            if (c.get('start_s') is None or c.get('start_frame') is None
                    or c.get('end_s') is not None
                    or c.get('end_status') != 'unknown_end_data_gap'):
                rejected.append(dict(series=mode, reason='not_known_start_gap_ended_candidate', candidate=c))
                continue
            groups = gap_groups([r for r in rows if r['frame_index'] > c['start_frame']])
            matches = [g for g in groups
                       if sum(len(run) for run in g['runs']) >= math.ceil(.125 * fps)
                       and c.get('last_supported_time_s') is not None
                       and 0 < g['start']['time_s'] - c['last_supported_time_s'] <= 1.5 / fps]
            if not matches:
                rejected.append(dict(series=mode, reason='no_matching_sustained_gap', candidate=c))
                continue
            g = matches[0]
            eligible.append(dict(series=mode, candidate=c,
                                 gap_start_frame=g['start']['frame_index'],
                                 gap_end_frame=g['end']['frame_index'],
                                 bridge_valid_frames=g['bridges'],
                                 invalid_runs=[[r[0]['frame_index'], r[-1]['frame_index']] for r in g['runs']]))
    eligible.sort(key=lambda e: (e['candidate']['start_frame'], e['series'] != 'raw'))
    if not eligible:
        return dict(selected=None, reason='no_eligible_candidate', rejected=rejected)
    chosen = eligible[0]
    desired_start = chosen['candidate']['start_frame'] - 24
    start = max(rows[0]['frame_index'], desired_start)
    desired_end = chosen['gap_start_frame'] + 36 - 1
    end = min(rows[-1]['frame_index'], desired_end, start + 96 - 1)
    return dict(protocol='fast-gap-single-recovery-window-1.1-research',
                selected=dict(**chosen, start_frame=start, end_frame_inclusive=end,
                              frames=end-start+1, start_s=start/fps, end_s=end/fps,
                              pre_context_clipped=start != desired_start,
                              post_context_clipped=end != desired_end),
                eligible=eligible, rejected=rejected)
