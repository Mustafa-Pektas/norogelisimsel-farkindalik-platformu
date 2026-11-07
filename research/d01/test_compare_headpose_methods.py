import unittest
import numpy as np
from compare_headpose_methods import time_sample, euler_xyz, series, phase
from motion_candidates import detect
import json
from pathlib import Path


class ComparisonTests(unittest.TestCase):
    def test_missing_decoder_time_is_not_replaced_by_nominal(self):
        for value in (None, float('nan'), 0.0):
            row = time_sample(2, 24, value, .04)
            self.assertIsNone(row['time_s'])
            self.assertEqual(row['nominal_time_s'], 2/24)
        self.assertEqual(time_sample(1, 24, 1/24, 0)['time_source'], 'OpenCV_POS_MSEC')

    def test_euler_order_matches_known_matrices(self):
        from scipy.spatial.transform import Rotation
        for angles in ([0,0,0], [20,-30,40], [-40,50,-60]):
            r = Rotation.from_euler('xyz', angles, degrees=True).as_matrix()
            np.testing.assert_allclose(euler_xyz(r), angles, atol=1e-7)

    def test_missing_pose_resets_ema_and_is_never_filled(self):
        config = json.loads((Path(__file__).parent/'parameters/motion_candidates_v1.json').read_text())
        rows = [dict(frame_index=i, time_s=i/24, valid=i!=2, rotation_matrix=np.eye(3).tolist() if i!=2 else None) for i in range(12)]
        result = series(rows,config)
        for mode in result.values():
            self.assertFalse(mode[2]['valid'])
            self.assertIsNone(mode[2]['rotation_matrix'])
            self.assertTrue(mode[3]['valid'])
        self.assertEqual(detect(result['raw'],config,config['settings'][1])['candidates'], [])

    def test_before_during_after_are_time_relations_not_response_labels(self):
        self.assertEqual(phase({'start_s':None},.4,1.15),'unknown_start')
        self.assertEqual(phase({'start_s':.3},.4,1.15),'before_call')
        self.assertEqual(phase({'start_s':.8},.4,1.15),'during_call')
        self.assertEqual(phase({'start_s':5.8},.4,1.15),'after_call')


if __name__=='__main__':unittest.main()
