"""Controlled selector checks only; these tests never load either model."""
from pathlib import Path
import json
import unittest
import numpy as np
from real_hybrid_benchmark import BufferedWindows
from selective_6d_replay import select_windows


class BufferedTests(unittest.TestCase):
    def setUp(self):
        params=Path(__file__).parent/'parameters'
        self.motion=json.loads((params/'motion_candidates_v1.json').read_text())
        self.policy=json.loads((params/'selective_6d_v1.json').read_text())
        self.six=[dict(frame_index=i,time_s=i/24,valid=True,rotation_matrix=np.eye(3).tolist()) for i in range(80)]

    def online(self, pnp, mode):
        selector=BufferedWindows(self.motion,self.policy,mode)
        cache={};calls=[]
        for i,r in enumerate(pnp):
            for j in selector.request(r):
                if j not in cache:
                    self.assertGreaterEqual(j,max(0,i-24))
                    self.assertLessEqual(j,i)
                    calls.append(j);cache[j]=self.six[j]
            selector.observe(r,cache)
        selector.observe(pnp[-1],cache,final=True)
        return selector,calls

    def test_buffered_selection_matches_original_replay(self):
        for mode in self.policy['methods']:
            for loss in ([30],list(range(30,80))):
                pnp=[dict(r,valid=i not in loss,rotation_matrix=None) for i,r in enumerate(self.six)]
                replay=select_windows(self.six,pnp,self.motion,self.policy,mode)
                actual,calls=self.online(pnp,mode)
                self.assertEqual(calls,replay['selected_frame_indices'])
                self.assertEqual(actual.windows,replay['triggered_windows'])
                self.assertEqual(len(calls),len(set(calls)))

    def test_no_pose_loss_never_requests_6d(self):
        for mode in self.policy['methods']:
            selector,calls=self.online(self.six,mode)
            self.assertEqual(calls,[])
            self.assertEqual(selector.windows,[])

    def test_invalid_sixd_keeps_unknown_endpoint(self):
        for r in self.six[40:]:r.update(valid=False,rotation_matrix=None)
        pnp=[dict(r,valid=i<30,rotation_matrix=None) for i,r in enumerate(self.six)]
        actual,calls=self.online(pnp,'raw')
        self.assertEqual(calls,list(range(6,80)))
        self.assertEqual(actual.windows[0]['close_reason'],'clip_ended')
        self.assertEqual(actual.windows[0]['candidates'],[])


if __name__=='__main__':unittest.main()
