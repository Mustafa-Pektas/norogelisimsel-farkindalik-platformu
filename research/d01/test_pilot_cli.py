"""Synthetic CLI replay, persistence and missing-data checks; never load a model."""
from pathlib import Path
from types import SimpleNamespace
import json
import tempfile
import unittest
from unittest.mock import patch
import numpy as np
from scipy.spatial.transform import Rotation
from PIL import Image

import pilot_cli as p
from rotation_processing import causal_ema_matrices

class PilotCliTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.video=self.root/'synthetic.bin';self.video.write_bytes(b'not a real video; metadata is injected')
        self.weights=self.root/'weights.fixture';self.weights.write_bytes(b'not real weights')
        self.roi=self.root/'roi.json';self.roi.write_text(json.dumps(dict(x=0,y=0,width=10,height=10,padding_ltrb_source_px=[0,0,0,0],human_supplied=True)))
        source=Path(p.__file__).parent/'parameters'
        for name in ('motion_candidates_v1.json','settling_regions_v1.json'):(self.root/name).write_bytes((source/name).read_bytes())
        protocol=json.loads((source/'pilot_v1.json').read_text());protocol['weights_sha256']=p.sha(self.weights)
        self.protocol=self.root/'protocol.json';self.protocol.write_text(json.dumps(protocol))
        self.raw=self.root/'saved.jsonl';self.original=self.root/'original.json'
        self.make_rows(12)
        self.args=SimpleNamespace(video=self.video,weights=self.weights,roi=self.roi,protocol=self.protocol,output_dir=self.root/'out',
            recorded_raw=self.raw,recorded_report=self.original,manual=None,official_source=None)

    def make_rows(self,n,movement=False):
        self.n=n
        self.rows=[dict(frame_index=i,nominal_time_s=i/24,decoder_time_s=i/24,time_source='synthetic_clock',valid=True,
            rotation_matrix=Rotation.from_euler('z',min(max(i-12,0),12)*6 if movement else 0,degrees=True).as_matrix().tolist()) for i in range(n)]
        self.raw.write_text(''.join(json.dumps(r)+'\n' for r in self.rows))
        self.original.write_text(json.dumps(dict(video_sha256=p.sha(self.video),weight_sha256=p.sha(self.weights),
            official_source_sha256=json.loads(self.protocol.read_text())['official_source_sha256'],roi=dict(x=0,y=0,width=10,height=10))))

    def info(self,path):return dict(width=10,height=10,fps=24,declared_frame_count=self.n)

    def run_replay(self):
        def forbidden(*a):raise AssertionError('Replay attempted model load')
        return p.run(self.args,info_reader=self.info,runtime_factory=forbidden)

    def test_dynamic_count_small_contract_no_manual_and_no_model(self):
        self.make_rows(60,movement=True);before=p.sha(self.raw)
        r=self.run_replay();out=self.args.output_dir
        self.assertEqual(json.loads((out/'state.json').read_text())['processed_frames'],60)
        self.assertEqual(r['schema_version'],'d01-pilot-result-1.0')
        self.assertEqual(r['run_mode'],'recorded_replay')
        self.assertLess((out/'result.json').stat().st_size,65536)
        for method in r['movement_results'].values():
            self.assertTrue(method['settings']['base']['candidates'])
            for c in method['settings']['base']['candidates']:
                self.assertIsNone(c['start_minus_manual_call_start_s']);self.assertIsNone(c['start_minus_manual_call_end_s'])
        self.assertEqual(p.sha(self.raw),before)
        self.assertNotIn('windows',r['settling'])
        self.assertFalse(r['runtime_environment']['torch_runtime_measured'])
        state=json.loads((out/'state.json').read_text())
        self.assertIsNone(state['measurements']['timings_s']['forward_s'])
        self.assertIsNotNone(state['measurements']['timings_s']['postprocess_s'])
        self.assertGreaterEqual(state['measurements']['timings_s']['postprocess_detail_write_s'],0)
        self.assertGreaterEqual(state['measurements']['timings_s']['raw_jsonl_write_s'],0)
        self.assertGreaterEqual(state['measurements']['timings_s']['state_checkpoint_write_s'],0)
        self.assertGreaterEqual(state['measurements']['timings_s']['report_files_write_s'],0)
        self.assertTrue((out/'details/performance.json').is_file())

    def test_call_only_manual_is_posthoc_missing_movement_remains_unknown(self):
        self.make_rows(40,movement=True)
        manual=self.root/'manual.json';manual.write_text(json.dumps(dict(video_path=str(self.video),marks={
            'call_start_s':dict(media_time_ms=0,time_source='manual_fixture'),
            'call_end_s':dict(media_time_ms=500,time_source='manual_fixture')})))
        self.args.manual=manual;r=self.run_replay()
        self.assertIsNone(r['manual']['marks']['response_end_s']['time_s'])
        self.assertEqual(r['manual']['marks']['call_start_s']['time_s'],0)
        self.assertFalse(r['verification']['ground_truth_approved'])
        self.assertTrue((self.args.output_dir/'details/detection_fixed.json').exists())

    def test_missing_frame_and_time_preserved_no_crash_or_imputation(self):
        self.make_rows(20);self.rows.pop(8);self.rows[9]['decoder_time_s']=None
        self.raw.write_text(''.join(json.dumps(r)+'\n' for r in self.rows))
        self.run_replay();out=self.args.output_dir
        rows=[json.loads(s) for s in (out/'details/raw_frames.jsonl').read_text().splitlines()]
        self.assertEqual(len(rows),20);self.assertFalse(rows[8]['valid']);self.assertIsNone(rows[8]['decoder_time_s'])
        self.assertIsNone(rows[10]['decoder_time_s'])
        e=[json.loads(s) for s in (out/'details/ema_frames.jsonl').read_text().splitlines()]
        self.assertFalse(e[8]['valid']);self.assertFalse(e[10]['valid'])

    def test_bad_matrix_is_retained_and_explicitly_invalid(self):
        self.rows[5]['rotation_matrix']=[[0.,0.,0.]]*3
        self.raw.write_text(''.join(json.dumps(r)+'\n' for r in self.rows));self.run_replay()
        rows=[json.loads(s) for s in (self.args.output_dir/'details/raw_frames.jsonl').read_text().splitlines()]
        self.assertFalse(rows[5]['valid']);self.assertTrue(rows[5]['source_recorded_valid'])
        self.assertEqual(rows[5]['rotation_matrix'],[[0.,0.,0.]]*3)
        self.assertIn('geometric checks',rows[5]['replay_validation_error'])

    def test_ema_gap_resets_without_losing_next_valid_matrix(self):
        a=np.eye(3);b=Rotation.from_euler('z',60,degrees=True).as_matrix()
        result=causal_ema_matrices([a,None,b],.5)
        self.assertIsNone(result[1]);np.testing.assert_array_equal(result[2],b)
        np.testing.assert_array_equal(causal_ema_matrices([a,b],.5,break_before={1})[1],b)

    def test_interrupt_keeps_last_flushed_frame_and_status(self):
        def interrupted(*args):
            yield self.rows[0]
            raise KeyboardInterrupt()
        with patch.object(p,'replay_rows',interrupted):
            with self.assertRaises(KeyboardInterrupt):self.run_replay()
        out=self.args.output_dir
        self.assertEqual(json.loads((out/'state.json').read_text())['status'],'interrupted')
        self.assertEqual(len((out/'details/raw_frames.jsonl').read_text().splitlines()),1)
        self.assertFalse((out/'result.json').exists())

    def test_failed_state_without_overwriting_sources(self):
        before=p.sha(self.weights);self.weights.write_bytes(b'mismatch');changed=p.sha(self.weights)
        with self.assertRaisesRegex(ValueError,'weight hash'):self.run_replay()
        self.assertEqual(json.loads((self.args.output_dir/'state.json').read_text())['status'],'failed')
        self.assertNotEqual(before,changed);self.assertEqual(p.sha(self.weights),changed)

    def test_existing_output_is_never_overwritten(self):
        self.args.output_dir.mkdir();sentinel=self.args.output_dir/'keep';sentinel.write_text('keep')
        with self.assertRaises(ValueError):self.run_replay()
        self.assertEqual(sentinel.read_text(),'keep')

    def test_other_fps_rejected_without_silent_protocol_change(self):
        with self.assertRaisesRegex(ValueError,'24 FPS'):
            p.run(self.args,info_reader=lambda path:dict(width=10,height=10,fps=30,declared_frame_count=12))
        self.assertEqual(json.loads((self.args.output_dir/'state.json').read_text())['status'],'failed')

    def test_roi_outside_requires_exact_explicit_padding(self):
        image=Image.new('RGB',(10,10),(255,0,0))
        roi=dict(x=0,y=-2,width=8,height=8,padding_ltrb_source_px=[0,0,0,0])
        with self.assertRaises(ValueError):p.crop_roi(image,roi)
        roi.update(padding_ltrb_source_px=[0,2,0,0],padding_rgb=[128,128,128])
        crop=p.crop_roi(image,roi);self.assertEqual(crop.size,(8,8))
        self.assertEqual(crop.getpixel((0,0)),(128,128,128));self.assertEqual(crop.getpixel((0,2)),(255,0,0))

    def test_changed_rule_configuration_is_rejected(self):
        target=self.root/'motion_candidates_v1.json';value=json.loads(target.read_text());value['settings'][1]['start_deg_s']=46;target.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError,'hash mismatch'):self.run_replay()

    def test_manual_does_not_change_detection_records(self):
        self.make_rows(40,movement=True)
        self.run_replay();before=p.sha(self.args.output_dir/'details/motion.json')
        self.args.output_dir=self.root/'with_manual';self.args.manual=self.root/'manual.json'
        self.args.manual.write_text(json.dumps(dict(marks={'call_start_s':dict(media_time_ms=0,time_source='manual_fixture')})))
        self.run_replay()
        self.assertEqual(p.sha(self.args.output_dir/'details/motion.json'),before)

    def test_empty_decoding_and_controlled_inference_failure_are_explicit(self):
        self.args.recorded_raw=None;self.args.recorded_report=None;self.args.official_source=self.root/'official'
        source=self.args.official_source/'sixdrepnet360';source.mkdir(parents=True)
        protocol=json.loads(self.protocol.read_text())
        for name in protocol['official_source_sha256']:
            path=source/name;path.write_text('# fake official fixture, never imported')
            protocol['official_source_sha256'][name]=p.sha(path)
        self.protocol.write_text(json.dumps(protocol))
        class FakeRuntime:
            def __init__(self,*args):self.checks={'controlled_fixture_only':True}
        with patch.object(p,'live_rows',lambda *args:iter([])):
            with self.assertRaisesRegex(ValueError,'No video frames'):
                p.run(self.args,info_reader=self.info,runtime_factory=FakeRuntime)
        self.assertEqual(json.loads((self.args.output_dir/'state.json').read_text())['status'],'failed')
        self.assertFalse((self.args.output_dir/'result.json').exists())

    def test_live_decoder_errors_and_prediction_error_keep_frame_records(self):
        import cv2
        class FakeCap:
            def __init__(self):self.index=0;self.closed=False
            def isOpened(self):return True
            def read(self):
                if self.index==3:return False,None
                self.index+=1;return True,np.zeros((10,10,3),dtype=np.uint8)
            def get(self,prop):return (self.index-1)*1000/24
            def release(self):self.closed=True
        class FakeRuntime:
            def __init__(self):self.calls=0
            def prepare(self,image):return image.resize((224,224)),SimpleNamespace(numpy=lambda:np.zeros((3,224,224),dtype=np.float32))
            def predict(self,tensor):
                self.calls+=1
                if self.calls==2:raise ValueError('controlled fake prediction failure')
                return dict(rotation_matrix=np.eye(3).tolist(),valid=True,inference_s=.01)
        output=self.root/'live_fixture';(output/'inputs').mkdir(parents=True)
        runtime=FakeRuntime();cap=FakeCap()
        with patch.object(cv2,'VideoCapture',return_value=cap):
            rows=list(p.live_rows(self.video,dict(width=10,height=10,fps=24,declared_frame_count=5),
                json.loads(self.roi.read_text()),runtime,output))
        self.assertEqual(len(rows),5);self.assertEqual(runtime.calls,3);self.assertTrue(cap.closed)
        self.assertTrue(rows[0]['valid']);self.assertFalse(rows[1]['valid']);self.assertTrue(rows[2]['valid'])
        self.assertIn('controlled fake',rows[1]['error']);self.assertIsNone(rows[1]['inference_s'])
        self.assertTrue(rows[1]['model_attempted']);self.assertIsNotNone(rows[1]['model_attempt_wall_s'])
        self.assertEqual(rows[0]['inference_s'],.01)
        for row in rows[:3]:
            for key in ('decode_s','preprocess_s','input_save_s'):
                self.assertGreaterEqual(row[key],0)
        self.assertIsNone(rows[3]['decoder_time_s']);self.assertFalse(rows[4]['valid'])

if __name__=='__main__':unittest.main()
