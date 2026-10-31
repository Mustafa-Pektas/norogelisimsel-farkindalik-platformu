import unittest
from unittest.mock import patch
from types import SimpleNamespace
from pathlib import Path
from tempfile import TemporaryDirectory
from pilot_metrics import Metrics, environment, memory, _linux_proc_memory

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

    def test_linux_proc_rss_and_peak_are_converted_from_kibibytes_to_bytes(self):
        with TemporaryDirectory() as root:
            status=Path(root)/'status'
            status.write_text('Name:\tpython\nVmHWM:\t2345 kB\nVmRSS:\t1234 kB\n',encoding='ascii')
            result=_linux_proc_memory(status)
        self.assertEqual(result['working_set_bytes'],1234*1024)
        self.assertEqual(result['os_peak_working_set_bytes'],2345*1024)
        self.assertEqual(result['memory_status'],'measured_linux_proc_status')

    def test_linux_proc_missing_or_unreadable_values_stay_null(self):
        with TemporaryDirectory() as root:
            status=Path(root)/'status'
            status.write_text('VmRSS: 1234 kB\nVmHWM: unavailable\n',encoding='ascii')
            partial=_linux_proc_memory(status)
            unreadable=_linux_proc_memory(Path(root)/'missing')
        self.assertEqual(partial['working_set_bytes'],1234*1024)
        self.assertIsNone(partial['os_peak_working_set_bytes'])
        self.assertIn('partial_linux_proc_status',partial['memory_status'])
        self.assertIsNone(unreadable['working_set_bytes'])
        self.assertIsNone(unreadable['os_peak_working_set_bytes'])
        self.assertEqual(unreadable['memory_status'],'unavailable_linux_proc_status_unreadable')

    def test_platform_dispatch_preserves_windows_measurement_path(self):
        expected=dict(working_set_bytes=10,os_peak_working_set_bytes=20,memory_status='measured_windows_process')
        with patch('pilot_metrics.platform.system',return_value='Windows'), patch('pilot_metrics._windows_memory',return_value=expected) as windows:
            self.assertEqual(memory(),expected)
            windows.assert_called_once_with()
        linux_expected=dict(working_set_bytes=30,os_peak_working_set_bytes=40,memory_status='measured_linux_proc_status')
        with patch('pilot_metrics.platform.system',return_value='Linux'), patch('pilot_metrics._linux_proc_memory',return_value=linux_expected) as linux:
            self.assertEqual(memory(),linux_expected)
            linux.assert_called_once_with()
        with patch('pilot_metrics.platform.system',return_value='Plan9'):
            unsupported=memory()
        self.assertIsNone(unsupported['working_set_bytes'])
        self.assertIsNone(unsupported['os_peak_working_set_bytes'])
        self.assertEqual(unsupported['memory_status'],'unavailable_unsupported_platform')

if __name__=='__main__':unittest.main()
