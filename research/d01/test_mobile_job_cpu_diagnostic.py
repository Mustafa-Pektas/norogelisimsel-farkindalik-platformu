"""Controlled summary checks; never load Torch or spawn a process."""
import unittest
from mobile_job_cpu_diagnostic import summarize


class DiagnosticTests(unittest.TestCase):
    def events(self):
        rows=[dict(kind='input',frame_index=i,hashes_verified=True) for i in (0,36,72)]
        rows.append(dict(kind='runtime',environment=dict(torch_threads=4,torch_interop_threads=14,device='cpu'),model_load_s=2.,load_wall_s=3.))
        for warm,index,seconds in [(True,0,99.),(False,0,1.),(False,36,2.),(False,72,3.)]:
            rows.append(dict(kind='prediction',warmup=warm,frame_index=index,inference_s=seconds,
                prediction_wall_s=seconds+.01,prediction_cpu_s=seconds*2,recorded_matrix_max_difference=0.,recorded_matrix_within_tolerance=True,valid=True))
        return rows

    def test_warmup_excluded_and_model_load_separate(self):
        r=summarize(self.events(),4,14)
        self.assertTrue(r['verified']);self.assertEqual(r['mean_forward_s'],2.)
        self.assertEqual(r['warmup_forward_s'],[99.]);self.assertEqual(r['model_load_s'],2.)

    def test_incomplete_is_unknown_not_zero_or_success(self):
        r=summarize(self.events()[:-1],4,14)
        self.assertFalse(r['verified']);self.assertIsNone(r['mean_forward_s'])

    def test_hash_or_matrix_failure_cannot_be_verified(self):
        events=self.events();events[0]['hashes_verified']=False
        self.assertFalse(summarize(events,4,14)['verified'])
        events=self.events();events[-1]['recorded_matrix_within_tolerance']=False
        self.assertFalse(summarize(events,4,14)['verified'])

    def test_wrong_actual_thread_count_cannot_be_verified(self):
        self.assertFalse(summarize(self.events(),2,14)['verified'])
        self.assertFalse(summarize(self.events(),4,4)['verified'])


if __name__=='__main__':unittest.main()
