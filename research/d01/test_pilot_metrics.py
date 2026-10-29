import unittest
from unittest.mock import patch
from types import SimpleNamespace
from pilot_metrics import Metrics, environment

class MetricsTests(unittest.TestCase):
    def test_cpu_samples_are_timestamped_and_not_host_utilization(self):
        clock=iter([0.,1.,3.]);cpu=iter([2.,6.])
        metrics=Metrics(clock=lambda:next(clock),cpu=lambda:next(cpu))
        with patch('pilot_metrics.memory',return_value=dict(working_set_bytes=None,memory_status='unavailable')):
            first=metrics.sample();second=metrics.sample()
        self.assertIsNone(first['process_cpu_percent_since_previous_sample'])
        self.assertEqual(second['process_cpu_percent_since_previous_sample'],200)
        self.assertIn('timestamp_utc',second);self.assertIsNone(second['working_set_bytes'])
        self.assertIn('one CPU core',second['cpu_percent_scope'])

    def test_nested_times_are_not_summed_into_false_total(self):
        metrics=Metrics(clock=lambda:10,cpu=lambda:0)
        metrics.add('forward_s',4);metrics.add('prediction_call_s',5);metrics.add('raw_phase_s',6)
        r=metrics.snapshot();self.assertEqual(r['elapsed_s'],0)
        self.assertEqual(r['timings_s']['forward_s'],4);self.assertIsNone(r['timings_s']['model_load_s'])
        self.assertIn('not additive',r['timing_scope'])

    def test_runtime_metadata_without_model_loading(self):
        fake=SimpleNamespace(__version__='controlled',get_num_threads=lambda:4,get_num_interop_threads=lambda:2)
        r=environment(fake,'cpu')
        self.assertEqual(r['torch_threads'],4);self.assertEqual(r['torch_interop_threads'],2)
        self.assertTrue(r['python_executable']);self.assertIn('numpy',r['packages']);self.assertEqual(r['device'],'cpu')
        missing=environment();self.assertIsNone(missing['torch_threads']);self.assertFalse(missing['torch_runtime_measured'])

if __name__=='__main__':unittest.main()
