from pathlib import Path
import json
import unittest
import numpy as np
from selective_6d_replay import select_windows


class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.motion=json.loads((Path(__file__).parent/'parameters/motion_candidates_v1.json').read_text())
        self.policy=json.loads((Path(__file__).parent/'parameters/selective_6d_v1.json').read_text())
        self.six=[dict(frame_index=i,time_s=i/24,valid=True,rotation_matrix=np.eye(3).tolist()) for i in range(80)]
        self.pnp=[dict(r) for r in self.six]

    def test_no_gap_selects_no_6d(self):
        self.assertEqual(select_windows(self.six,self.pnp,self.motion,self.policy,'raw')['selected_unique_frames'],0)

    def test_selection_uses_validity_not_pnp_rotations_and_never_merges(self):
        self.pnp[30]['valid']=False
        a=select_windows(self.six,self.pnp,self.motion,self.policy,'raw')
        for r in self.pnp:r['rotation_matrix']=[[-999]*3]*3
        b=select_windows(self.six,self.pnp,self.motion,self.policy,'raw')
        self.assertEqual(a,b)
        self.assertEqual(a['triggered_windows'][0]['first_selected_frame'],6)
        self.assertEqual(a['triggered_windows'][0]['last_selected_frame'],40)
        self.assertEqual(a['triggered_windows'][0]['candidates'],[])

    def test_unrecovered_gap_keeps_window_to_clip_end(self):
        for r in self.pnp[30:]:r['valid']=False
        a=select_windows(self.six,self.pnp,self.motion,self.policy,'ema_050')
        self.assertEqual(a['triggered_windows'][0]['last_selected_frame'],79)
        self.assertEqual(a['triggered_windows'][0]['close_reason'],'clip_ended')

    def test_time_mismatch_is_not_filled(self):
        self.pnp[10]['time_s']=None
        with self.assertRaises(ValueError):select_windows(self.six,self.pnp,self.motion,self.policy,'raw')


if __name__=='__main__':unittest.main()
