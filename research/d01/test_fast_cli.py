"""Durable fast orchestration with controlled tracker/decoder, no model call."""
from pathlib import Path
from types import SimpleNamespace
from tempfile import TemporaryDirectory
from unittest.mock import patch
import json,unittest
import numpy as np
import cv2
import fast_cli


class Capture:
    def __init__(self):self.i=0
    def read(self):
        if self.i==10:return False,None
        self.i+=1;return True,np.zeros((48,64,3),dtype=np.uint8)
    def get(self,_):return (self.i-1)*1000/24
    def release(self):pass


class Tracker:
    def __init__(self,*_):pass
    def update(self,frame,t):return dict(valid=True,rotation_matrix=np.eye(3).tolist(),track_source='landmarks',
        identity_status='face_landmarks',target_provenance='single_face_candidate_role_unverified',pitch_deg=0.,yaw_deg=0.,roll_deg=0.)
    def close(self):pass


class CliTests(unittest.TestCase):
    def test_windows_state_replace_retries_only_short_access_errors(self):
        for code in (5,32,33):
            error=PermissionError('controlled Windows access error');error.winerror=code
            with TemporaryDirectory() as root:
                target=Path(root)/'state.json';fast_cli.atomic(target,dict(status='running'))
                original=fast_cli.atomic;calls=0
                def locked_then_write(path,data):
                    nonlocal calls
                    calls+=1
                    if calls<=2:raise error
                    return original(path,data)
                with patch.object(fast_cli,'atomic',side_effect=locked_then_write),patch.object(fast_cli.time,'sleep') as sleep:
                    fast_cli.atomic_state(target,dict(status='completed'))
                self.assertEqual(calls,3);self.assertEqual(sleep.call_args_list, [((.01,),),((.02,),)])
                self.assertEqual(json.loads(target.read_text()),dict(status='completed'))

    def test_persistent_or_unrelated_write_error_is_not_hidden(self):
        for code,expected_calls in [(5,5),(None,1),(123,1)]:
            error=PermissionError('controlled permanent error');error.winerror=code
            with TemporaryDirectory() as root:
                target=Path(root)/'state.json';fast_cli.atomic(target,dict(status='running'))
                with patch.object(fast_cli,'atomic',side_effect=error) as write,patch.object(fast_cli.time,'sleep') as sleep:
                    with self.assertRaises(PermissionError):fast_cli.atomic_state(target,dict(status='completed'))
                    self.assertEqual(write.call_count,expected_calls)
                    self.assertLessEqual(sum(c.args[0] for c in sleep.call_args_list),.15+1e-9)
                self.assertEqual(json.loads(target.read_text()),dict(status='running'))

    def run_controlled(self,root,manual=None):
        root=Path(root);video=root/'video.mp4';video.write_bytes(b'controlled-not-video');task=root/'face.task';task.write_bytes(b'controlled-not-model')
        args=SimpleNamespace(video=video,face_model=task,output_dir=root/'run',manual=manual,target_point=None)
        actual_sha=fast_cli.sha
        def checksum(p):return '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff' if Path(p)==task else actual_sha(p)
        with patch.object(fast_cli,'inspect_marked_video',return_value=dict(width=64,height=48,fps=24,decoded_frame_count=10,duration_s=10/24)),patch.object(fast_cli,'sha',side_effect=checksum),patch.object(fast_cli,'FastTracker',Tracker),patch.object(cv2,'VideoCapture',return_value=Capture()):
            return fast_cli.run(args)

    def test_durable_complete_unknown_calls_no_synthetic_response(self):
        with TemporaryDirectory() as root:
            r=self.run_controlled(root)
            self.assertEqual(r['counts'],dict(processed=10,valid=10,invalid=0))
            self.assertIsNone(r['manualTimes']['call_start_s']['time_s'])
            self.assertEqual(r['movements'],dict(raw=[],ema_050=[]))
            state=json.loads((Path(root)/'run/state.json').read_text());self.assertEqual(state['status'],'completed')
            rows=[json.loads(s) for s in (Path(root)/'run/details/frames.jsonl').read_text().splitlines()]
            self.assertEqual(len(rows),10);self.assertIn('decoded_rgb_sha256',rows[0]);self.assertIn('nominal_time_s',rows[0])
            for k in ['media_preflight_s','model_load_s','tracking_pnp_s','candidate_postprocess_s','report_preparation_s','total_s']:self.assertGreaterEqual(r['timings'][k],0)

    def test_bad_call_bounds_fail_before_tracker_creation(self):
        with TemporaryDirectory() as root:
            root=Path(root);video=root/'video.mp4';video.write_bytes(b'controlled-not-video')
            from motion_candidates import sha
            manual=root/'manual.json';manual.write_text(json.dumps(dict(video_sha256=sha(video),marks=dict(call_start_s=dict(media_time_ms=0),call_end_s=dict(media_time_ms=900)))))
            with self.assertRaises(fast_cli.PilotInputError):self.run_controlled(root,manual)
            state=json.loads((root/'run/state.json').read_text());self.assertEqual(state['status'],'failed');self.assertFalse(state['model_loaded'])


if __name__=='__main__':unittest.main()
