import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from compare_stride4_api import compare


class CompareTests(unittest.TestCase):
    def fixtures(self,root):
        roots=[]
        for engine in ('mediapipe_pnp_flow','cascade_stride4_onnx'):
            out=Path(root)/engine;job=out/'jobs'/'controlled-id';job.mkdir(parents=True)
            (job/'job.json').write_text(json.dumps(dict(targetPoint=[.4,.3],childExitCode=0,childClosedAt=2)))
            (out/'acceptance.json').write_text(json.dumps(dict(runs=[dict(status='completed',jobId='controlled-id',upload_to_result_s=3.)])))
            (out/'api_result_0.json').write_text(json.dumps(dict(videoHash='same',source=dict(poseEngine=engine),
                manualTimes={k:dict(time_s=None) for k in ['call_start_s','call_end_s']},coverage={},counts={},
                callTiming=dict(source='unknown',startS=None,endS=None),movements={'raw':[],'ema_050':[]},timings={})))
            roots.append(out)
        return roots

    def test_same_video_target_unknown_calls_preserved_no_fake_mobile_measurement(self):
        with TemporaryDirectory() as root:
            r=compare(self.fixtures(root))
            self.assertEqual(len(r['runs']),2)
            self.assertIsNone(r['runs'][0]['mobileVisibleElapsedS'])
            self.assertIsNone(r['runs'][1]['correctChildVisuallyVerified'])

    def test_mismatched_target_or_video_and_unclosed_child_rejected(self):
        for key,value in [('targetPoint',[.8,.7]),('childExitCode',1)]:
            with self.subTest(field=key),TemporaryDirectory() as root:
                roots=self.fixtures(root);p=roots[1]/'jobs/controlled-id/job.json'
                data=json.loads(p.read_text());data[key]=value;p.write_text(json.dumps(data))
                with self.assertRaises(ValueError):compare(roots)
        with TemporaryDirectory() as root:
            roots=self.fixtures(root);p=roots[1]/'api_result_0.json'
            data=json.loads(p.read_text());data['videoHash']='other';p.write_text(json.dumps(data))
            with self.assertRaises(ValueError):compare(roots)


if __name__=='__main__':unittest.main()
