"""Controlled logic tests; no model/pose accuracy assertion."""
import unittest
from types import SimpleNamespace
from fast_tracking import IdentitySelection,call_phase,FastTracker


def face(box,hist=(1.,0.)):
    return dict(box=box,hist=hist)


class FastTests(unittest.TestCase):
    def test_ambiguous_scene_never_silently_selects_adult(self):
        child=face([.1,.1,.3,.4]);adult=face([.6,.1,.9,.5])
        s=IdentitySelection()
        self.assertIsNone(s.choose([child,adult],0))
        self.assertIsNone(s.choose([adult],.1))
        self.assertEqual(s.provenance,'not_determined')

    def test_point_association_and_no_reacquisition_after_long_loss(self):
        child=face([.1,.1,.3,.4]);adult=face([.6,.1,.9,.5])
        s=IdentitySelection([.2,.2])
        self.assertIs(s.choose([adult,child],0),child)
        self.assertIsNone(s.choose([adult],.1))
        self.assertIsNone(s.choose([face(child['box'],(0.,1.))],.15))
        self.assertIsNone(s.choose([child,face([.11,.11,.31,.41])],.18))
        self.assertIs(s.choose([child,adult],.2),child)
        self.assertIsNone(s.choose([child],3))
        self.assertIsNone(s.choose([child],3.1))

    def test_preexisting_motion_does_not_become_postcall_response(self):
        self.assertEqual(call_phase(.1,.4,1.2),'before_call')
        self.assertEqual(call_phase(.8,.4,1.2),'during_call')
        self.assertEqual(call_phase(1.3,.4,1.2),'after_call')
        self.assertEqual(call_phase(1,None,None),'call_unknown')
        self.assertEqual(call_phase(None,.4,1.2),'unknown_movement_start')

    def test_flow_only_never_provides_angles(self):
        t=FastTracker.__new__(FastTracker)
        t.selector=SimpleNamespace(status='pose_missing_track_unconfirmed',established=True,provenance='manual_initial_point')
        t.faces=0
        t.track=SimpleNamespace(update=lambda *_:dict(source='optical_flow',landmarks=None,flow_points=8,bbox=[.1,.1,.3,.4]))
        t.module=SimpleNamespace(head_pose=lambda *_:{})
        frame=SimpleNamespace(shape=(720,1280,3))
        r=t.update(frame,.5)
        self.assertFalse(r['valid']);self.assertIsNone(r['rotation_matrix'])
        for key in ['pitch_deg','yaw_deg','roll_deg']:self.assertIsNone(r[key])
        self.assertEqual(r['measurement_status'],'optical_flow_only')


if __name__=='__main__':unittest.main()
