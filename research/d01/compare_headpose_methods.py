"""Offline method comparison; never loads 6DRepNet or changes its protocol.

measure: Python with MediaPipe Tasks, NumPy, OpenCV; local task asset only.
report: Python with existing NumPy/SciPy/Matplotlib; recorded rotations only.
"""
from pathlib import Path
import argparse
import collections
import hashlib
import importlib.metadata
import importlib.util
import json
import math
import sys
import time
from types import SimpleNamespace
import zipfile


def sha(file):
    return hashlib.sha256(Path(file).read_bytes()).hexdigest()


def read(file):
    return json.loads(Path(file).read_text(encoding='utf-8-sig'))


def write(file, data):
    file = Path(file)
    temp = file.with_suffix(file.suffix + '.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    temp.replace(file)


def time_sample(index, fps, decoder_s, previous_s):
    available = isinstance(decoder_s, (int, float)) and not isinstance(decoder_s, bool) and math.isfinite(decoder_s)
    valid = (available and decoder_s >= 0 and
             (previous_s is None or decoder_s > previous_s))
    return dict(time_s=decoder_s if valid else None, decoder_time_s=decoder_s if available else None,
                nominal_time_s=index/fps, time_source='OpenCV_POS_MSEC' if valid else 'decoder_time_unusable',
                time_alignment='PTS and LibVLC alignment not independently verified')


def euler_xyz(matrix):
    """R=Rz(z) Ry(y) Rx(x), degrees, matching official 6D Euler algebra.

    Mathematical convention only; physical neutral-pose equality is NOT assumed.
    """
    import numpy as np
    r = np.asarray(matrix)
    sy = math.hypot(r[0, 0], r[1, 0])
    x = math.atan2(r[2, 1], r[2, 2]) if sy >= 1e-6 else math.atan2(-r[1, 2], r[1, 1])
    return [math.degrees(x), math.degrees(math.atan2(-r[2, 0], sy)),
            math.degrees(math.atan2(r[1, 0], r[0, 0])) if sy >= 1e-6 else 0.0]


def series(rows, config):
    from motion_candidates import rotation
    from rotation_processing import causal_ema_matrices
    matrices, breaks = [], set()
    for i, r in enumerate(rows):
        matrices.append(rotation(r.get('rotation_matrix')) if r.get('valid') and r.get('time_s') is not None else None)
        if i and (r['frame_index'] != rows[i-1]['frame_index']+1 or r['time_s'] is None or
                  rows[i-1]['time_s'] is None or not 0 < r['time_s']-rows[i-1]['time_s'] <= config['max_dt_factor']/config['nominal_fps']):
            breaks.add(i)
    ema = causal_ema_matrices(matrices, .50, break_before=breaks)
    def build(ms):
        return [dict(frame_index=r['frame_index'], time_s=r['time_s'], valid=m is not None,
                     rotation_matrix=None if m is None else m.tolist()) for r, m in zip(rows, ms)]
    return {'raw': build(matrices), 'ema_050': build(ema)}


def phase(event, call_start, call_end):
    t = event['start_s']
    return 'unknown_start' if t is None else 'before_call' if t < call_start else 'during_call' if t <= call_end else 'after_call'


def load_tracker_module(package, face_model, vendor):
    """Shared unchanged friend tracker/PnP with the same local Tasks CPU adapter."""
    import mediapipe as mp
    import numpy as np
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
    entry = 'Isme_Tepki_Paylasim/kod/ses_yonelme/sesyon/vision.py'
    with zipfile.ZipFile(package) as archive:
        source = archive.read(entry)
        parameters = json.loads(archive.read('Isme_Tepki_Paylasim/kod/ses_yonelme/config/deniz.json'))['settings']
    vendor.write_bytes(source)
    spec = importlib.util.spec_from_file_location('friend_vision', vendor)
    original = importlib.util.module_from_spec(spec); spec.loader.exec_module(original)
    class TaskMesh:
        def __init__(self, **legacy):
            self.detector = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
                base_options=mp_python.BaseOptions(model_asset_path=str(Path(face_model).resolve()), delegate=mp_python.BaseOptions.Delegate.CPU),
                running_mode=vision.RunningMode.IMAGE, num_faces=legacy['max_num_faces'],
                min_face_detection_confidence=legacy['min_detection_confidence']))
        def process(self, rgb):
            result = self.detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(rgb)))
            return SimpleNamespace(multi_face_landmarks=[SimpleNamespace(landmark=points) for points in result.face_landmarks])
        def close(self): self.detector.close()
    # Only this imported module's FaceMesh constructor changes, not tracking/PnP.
    original.mp = SimpleNamespace(solutions=SimpleNamespace(face_mesh=SimpleNamespace(FaceMesh=TaskMesh)))
    return original, parameters, entry, source


def measure(args):
    import cv2
    import mediapipe as mp
    import numpy as np
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
    from motion_candidates import rotation
    start = time.perf_counter()
    out, ref = args.output.resolve(), args.recorded_run.resolve()
    if out.exists(): raise ValueError('Output must be new')
    reference = read(ref/'result.json'); settings = read(ref/'settings.json')
    video_hash = sha(args.video)
    if video_hash != reference['video']['sha256']: raise ValueError('Recorded/video hash mismatch')
    roi = settings['roi']
    if roi.get('human_supplied') is not True or any(roi['padding_ltrb_source_px']): raise ValueError('This comparison requires reviewed unpadded ROI')
    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened(): raise ValueError('Video cannot open')
    width, height, fps, count = (cap.get(k) for k in (cv2.CAP_PROP_FRAME_WIDTH, cv2.CAP_PROP_FRAME_HEIGHT, cv2.CAP_PROP_FPS, cv2.CAP_PROP_FRAME_COUNT))
    width, height, count = int(width), int(height), int(count)
    if (width, height, fps) != (settings['video']['width'], settings['video']['height'], settings['video']['fps']): raise ValueError('Video metadata mismatch')
    x, y, w, h = (roi[k] for k in ('x', 'y', 'width', 'height'))
    if min(x, y) < 0 or x+w > width or y+h > height: raise ValueError('ROI out of bounds')
    out.mkdir(parents=True); (out/'vendor').mkdir()
    original, parameters, entry, source = load_tracker_module(args.package, args.face_model, out/'vendor/vision_original.py')
    box = [x/width, y/height, (x+w)/width, (y+h)/height]
    sources = {str(f.resolve()): sha(f) for f in (args.video, args.package, args.face_model, ref/'result.json', ref/'settings.json', ref/'details/raw_frames.jsonl')}
    write(out/'settings.json', dict(video_sha256=video_hash, video_metadata=dict(width=width, height=height, fps=fps, declared_frames=count),
        human_search_roi=roi, initial_head_box=box, zip_entry=entry, zip_entry_sha256=hashlib.sha256(source).hexdigest(),
        reused_parameters={k: parameters[k] for k in ('max_flow_gap_s', 'max_pose_reprojection_px')},
        api_adaptation='Legacy static FaceMesh -> local Tasks IMAGE FaceLandmarker; no change to tracker/PnP; NOT identical legacy model weights/API',
        device='CPU', face_task_sha256=sha(args.face_model), sources_sha256=sources,
        runtime=dict(python=sys.version, executable=sys.executable, mediapipe=mp.__version__, opencv=cv2.__version__, numpy=np.__version__),
        no_gaze_no_audio_model=True, manual_labels_not_used_in_measurement=True))
    tracker = None; rows = []; samples = []; last = None; tracking_s = 0.0
    write(out/'state.json', dict(status='running', processed_frames=0))
    try:
        initialized = time.perf_counter(); tracker = original.FaceTrack(box, box, parameters['max_flow_gap_s'])
        initialization_s = time.perf_counter()-initialized
        with (out/'frames.jsonl').open('x', encoding='utf-8') as stream:
            while True:
                if time.perf_counter()-start > args.max_seconds: raise TimeoutError('Measurement time bound reached')
                ok, frame = cap.read()
                if not ok: break
                i = len(rows); t = time_sample(i, fps, float(cap.get(cv2.CAP_PROP_POS_MSEC))/1000, last)
                if t['time_s'] is not None: last = t['time_s']
                row = dict(frame_index=i, **t, track_source='lost', face_landmarks_found=False,
                           pose_status='not_measured', valid=False, rotation_matrix=None,
                           rotation_vector=None, pitch_deg=None, yaw_deg=None, roll_deg=None)
                clock = time.perf_counter()
                try:
                    track = tracker.update(frame, i/fps)  # Fixed-FPS tracker gap clock; logged separately.
                    row.update(track_source=track['source'], tracking_clock_s=i/fps, tracking_clock_source='nominal_frame_index_over_fps',
                               face_landmarks_found=track['landmarks'] is not None, child_bbox=track['bbox'], flow_points=track['flow_points'])
                    pose = original.head_pose(track['landmarks'], width, height, parameters['max_pose_reprojection_px'])
                    row.update(pose)
                    matrix = None if 'rotation_vector' not in pose else rotation(cv2.Rodrigues(np.array(pose['rotation_vector']))[0])
                    row['valid'] = matrix is not None
                    row['rotation_matrix'] = matrix.tolist() if matrix is not None else None
                    row['pose_status'] = 'valid_pose' if row['valid'] else 'landmarks_pose_rejected' if row['face_landmarks_found'] else 'no_landmarks_no_pose'
                    if row['track_source'] != 'landmarks': assert row['rotation_matrix'] is None
                except Exception as error:
                    row.update(valid=False, rotation_matrix=None, pose_status='measurement_error', error_type=type(error).__name__)
                row['measurement_s'] = time.perf_counter()-clock; tracking_s += row['measurement_s']
                rows.append(row); stream.write(json.dumps(row)+'\n'); stream.flush()
                write(out/'state.json', dict(status='running', processed_frames=len(rows), valid_frames=sum(r['valid'] for r in rows)))
                if (i+1) % 24 == 0 or i == count-1: print(f'MediaPipe/PnP {i+1}/{count}', flush=True)
                if i % 12 == 0 or i == count-1:
                    image = frame.copy(); cv2.rectangle(image, (x,y), (x+w,y+h), (0,255,255), 2)
                    if row.get('child_bbox'):
                        b = row['child_bbox']; cv2.rectangle(image, (int(b[0]*width),int(b[1]*height)), (int(b[2]*width),int(b[3]*height)), (0,255,0),2)
                    if pose_axis := row.get('head_axis_px'):
                        cv2.line(image, tuple(map(int,pose_axis[0])), tuple(map(int,pose_axis[1])), (0,0,255), 3)
                    cv2.putText(image, f'{i} {row["track_source"]} {row["pose_status"]}', (12,30), cv2.FONT_HERSHEY_SIMPLEX, .65, (0,255,255),2)
                    samples.append(cv2.resize(image, (640,360)))
        if len(rows) != count: raise ValueError('Decoded frame count mismatch; no missing-frame filling')
        while len(samples) % 2: samples.append(np.zeros_like(samples[0]))
        sheet = np.vstack([np.hstack(samples[j:j+2]) for j in range(0,len(samples),2)])
        cv2.imwrite(str(out/'tracking_review.png'), sheet)
        write(out/'measurement.json', dict(status='completed', decoded_frames=len(rows), valid_pose_frames=sum(r['valid'] for r in rows),
            tracking_counts=dict(collections.Counter(r['track_source'] for r in rows)), elapsed_s=time.perf_counter()-start,
            task_initialization_s=initialization_s, tracking_and_pnp_s=tracking_s,
            scope='Current local CPU measurement; not comparable speed to older 6D or server runs'))
        write(out/'state.json', dict(status='completed', processed_frames=len(rows), valid_frames=sum(r['valid'] for r in rows)))
    except BaseException as error:
        write(out/'state.json', dict(status='interrupted' if isinstance(error, KeyboardInterrupt) else 'failed',
                                    processed_frames=len(rows), error_type=type(error).__name__))
        raise
    finally:
        cap.release()
        if tracker is not None: tracker.close()
        write(out/'source_preservation.json', dict(before=sources, after={f: sha(f) for f in sources}, unchanged=all(sha(f)==h for f,h in sources.items())))


def report(args):
    import numpy as np
    from motion_candidates import detect, rotation, angle_deg
    from pilot_time_relations import manual_mark
    out, ref = args.output.resolve(), args.recorded_run.resolve()
    if read(out/'state.json')['status'] != 'completed': raise ValueError('Measurement not complete')
    if Path(args.report_name).name != args.report_name or args.report_name in ('.','..'): raise ValueError('Report name must be one directory component')
    destination = out/args.report_name; destination.mkdir(exist_ok=False)
    settings = read(out/'settings.json'); previous = read(ref/'result.json'); manual = read(args.manual)
    if settings['video_sha256'] != previous['video']['sha256'] or settings['video_sha256'] != manual['video_sha256']: raise ValueError('Video/manual/recorded hash mismatch')
    paths = [args.manual, ref/'details/raw_frames.jsonl', Path(__file__), Path(__file__).with_name('motion_candidates.py'), Path(__file__).with_name('rotation_processing.py'), Path(__file__).parent/'parameters/motion_candidates_v1.json']
    before = {str(p.resolve()): sha(p) for p in paths}
    load_rows = lambda f: [json.loads(line) for line in f.read_text(encoding='utf-8').splitlines() if line.strip()]
    mp_rows = load_rows(out/'frames.jsonl'); six = load_rows(ref/'details/raw_frames.jsonl')
    methods = {'6DRepNet360': [dict(r, time_s=r['decoder_time_s']) for r in six], 'MediaPipe_PnP': mp_rows}
    time_match = len(six) == len(mp_rows) and all(a['frame_index']==b['frame_index'] and b['time_s'] is not None and abs(a['decoder_time_s']-b['time_s'])<1e-6 for a,b in zip(six,mp_rows))
    config = read(Path(__file__).parent/'parameters/motion_candidates_v1.json'); base = next(s for s in config['settings'] if s['id']=='base')
    all_series, detected = {}, {}
    for name, rows in methods.items():
        all_series[name] = series(rows, config)
        detected[name] = {s: detect(rs, config, base) for s,rs in all_series[name].items()}
    # Confirm replay kept the previous fixed raw/EMA candidates byte-equivalent structurally.
    prior = read(ref/'details/motion.json')
    if prior['parameters'] != config: raise ValueError('Motion protocol changed since recorded run')
    for method in ('raw', 'ema_050'):
        if detected['6DRepNet360'][method]['candidates'] != prior['results'][method]['base']['candidates']: raise ValueError('Recorded candidate replay changed')
    marks = {k: manual_mark(manual,k) for k in ('call_start_s','call_end_s','response_start_s','response_end_s')}
    candidates = []
    for name, modes in detected.items():
        for mode, d in modes.items():
            for event in d['candidates']:
                candidates.append(dict(method=name, series=mode, **event, phase=phase(event, marks['call_start_s']['time_s'], marks['call_end_s']['time_s']),
                    start_minus_manual_s=None if event['start_s'] is None else event['start_s']-marks['response_start_s']['time_s'],
                    end_minus_manual_s=None if event['end_s'] is None else event['end_s']-marks['response_end_s']['time_s'],
                    start_minus_call_start_s=None if event['start_s'] is None else event['start_s']-marks['call_start_s']['time_s'],
                    start_minus_call_end_s=None if event['start_s'] is None else event['start_s']-marks['call_end_s']['time_s']))
    for name,modes in detected.items():
        for mode,d in modes.items(): write(destination/f'{name}_{mode}_detection.json',d)
    # Check mathematical Euler conventions, not anatomical neutral-pose equivalence.
    import cv2
    from scipy.spatial.transform import Rotation
    for degrees in ([0,0,0],[20,-30,40],[-40,50,-60]):
        matrix = Rotation.from_euler('xyz',degrees,degrees=True).as_matrix()
        assert np.allclose(euler_xyz(matrix),cv2.RQDecomp3x3(matrix)[0],atol=1e-6)
    for r in six:
        assert np.allclose(euler_xyz(r['rotation_matrix']),[r['pitch_deg'],r['yaw_deg'],r['roll_deg']],atol=1e-4)
    write(destination/'result.json',dict(video_sha256=settings['video_sha256'], methods={name:dict(frames=len(rs),valid=sum(r['valid'] for r in rs)) for name,rs in methods.items()},
        manual_marks=marks, manual_status=manual.get('annotation_status'), candidate_rows=candidates,
        common_decoder_time_verified=time_match, euler_algebra_checked=True, physical_pose_reference_alignment_verified=False,
        previous_6d_candidates_unchanged=True, no_model_loading_for_6d=True,
        limitations=['Tasks adaptation is not the archived legacy model/API.', 'No target/response classification or calibrated confidence.',
        'Manual boundaries are candidates and end is approximate; LibVLC/decoder and AV alignment unverified.',
        'SO(3) temporal rules unchanged; no label-derived tuning. Unknown boundaries and missing poses remain null.',
        'Native Euler panels have matching mathematical XYZ axes but uncalibrated physical zero/sign; no absolute inter-model angle error.',
        'Only current MediaPipe timing is newly measured; old 6D and server speeds are not directly compared.']))
    import os
    os.environ['MPLCONFIGDIR'] = str(destination/'matplotlib_cache')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axs=plt.subplots(3,2,figsize=(15,10),sharex=True)
    for column,(name,rows) in enumerate(methods.items()):
        ts=[r['time_s'] if r['time_s'] is not None else np.nan for r in rows]
        angles=[euler_xyz(r['rotation_matrix']) if r['valid'] else [np.nan]*3 for r in rows]
        for axis,label in enumerate(('pitch X','yaw Y','roll Z')):
            ax=axs[axis,column];ax.plot(ts,np.array(angles)[:,axis]);ax.set_ylabel(label+' deg');ax.set_title(name+' native frame')
            for r in rows:
                if not r['valid'] and r['time_s'] is not None:ax.axvspan(r['time_s'],r['time_s']+1/config['nominal_fps'],color='grey',alpha=.25)
            ax.axvspan(marks['response_start_s']['time_s'],marks['response_end_s']['time_s'],color='green',alpha=.12)
            ax.axvspan(marks['call_start_s']['time_s'],marks['call_end_s']['time_s'],color='orange',alpha=.18);ax.grid(alpha=.2)
    fig.suptitle('Native Euler curves; grey=missing pose, orange=manual call, green=manual movement candidate\nMathematical axes checked; physical zero/alignment and LibVLC clock match NOT calibrated')
    fig.tight_layout();fig.savefig(destination/'native_angles.png',dpi=150);plt.close(fig)
    fig,axs=plt.subplots(2,1,figsize=(14,8),sharex=True)
    for ax,(name,modes) in zip(axs,detected.items()):
        for mode,d in modes.items():
            ax.plot([r['time_s'] for r in d['feature_records']],[r['median_speed_deg_s'] for r in d['feature_records']],label=mode)
            for c in d['candidates']:
                if c['start_s'] is not None:ax.axvline(c['start_s'],alpha=.3)
        ax.set_title(name);ax.set_ylabel('median SO(3) speed deg/s');ax.axvspan(marks['call_start_s']['time_s'],marks['call_end_s']['time_s'],color='orange',alpha=.15)
        ax.axvspan(marks['response_start_s']['time_s'],marks['response_end_s']['time_s'],color='green',alpha=.12);ax.legend();ax.grid(alpha=.2)
    fig.tight_layout();fig.savefig(destination/'motion_comparison.png',dpi=150);plt.close(fig)
    write(destination/'source_preservation.json',dict(before=before,after={f:sha(f) for f in before},unchanged=all(sha(f)==h for f,h in before.items())))
    print(json.dumps(dict(output=str(destination),time_match=time_match,candidates=candidates),ensure_ascii=False,indent=2))


def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='stage',required=True)
    m=sub.add_parser('measure');m.add_argument('--video',type=Path,required=True);m.add_argument('--package',type=Path,required=True)
    m.add_argument('--face-model',type=Path,required=True);m.add_argument('--recorded-run',type=Path,required=True);m.add_argument('--output',type=Path,required=True)
    m.add_argument('--max-seconds',type=float,default=120)
    r=sub.add_parser('report');r.add_argument('--recorded-run',type=Path,required=True);r.add_argument('--manual',type=Path,required=True);r.add_argument('--output',type=Path,required=True)
    r.add_argument('--report-name',default='comparison')
    args=parser.parse_args();measure(args) if args.stage=='measure' else report(args)


if __name__=='__main__':main()
