"""Controlled logic tests; no model/pose accuracy assertion."""
import unittest
from types import SimpleNamespace
from fast_tracking import IdentitySelection,call_phase,FastTracker


def face(box,hist=(1.,0.)):
    return dict(box=box,hist=hist)


class FastTests(unittest.TestCase):
    def test_flow_age_uses_last_confirmed_landmark_not_latest_flow_update(self):
        tracker=FastTracker.__new__(FastTracker)
        tracker.selector=SimpleNamespace(status='pose_missing_track_unconfirmed',established=True,
            provenance='manual_initial_point',last=1.)
        tracker.faces=0
        tracker.track=SimpleNamespace(last_observed=.5,update=lambda *_:dict(source='optical_flow',
            landmarks=None,flow_points=8,bbox=[.1,.1,.3,.4]))
        tracker.module=SimpleNamespace(head_pose=lambda *_:{})
        row=tracker.update(SimpleNamespace(shape=(720,1280,3)),3.)
        self.assertEqual(row['last_confirmed_landmark_time_s'],.5)
        self.assertEqual(row['landmark_age_s'],2.5)
        self.assertIsNone(row['rotation_matrix'])
    def test_stride4_reacquires_one_position_and_appearance_match_after_long_gap(self):
        child=face([.1,.1,.3,.4]);predicted=[.15,.1,.35,.4]
        moved=face(predicted)
        s=IdentitySelection([.2,.2],allow_reacquisition=True)
        self.assertIs(s.choose([child],0),child)
        self.assertIs(s.choose([moved],3.,predicted),moved)
        self.assertTrue(s.reacquired);self.assertEqual(s.reacquisition_gap_s,3.)
        self.assertEqual(s.last,3.);self.assertEqual(s.status,'face_landmarks')
        self.assertEqual(s.provenance,'manual_initial_point')
        self.assertIs(s.choose([moved],3.1,predicted),moved);self.assertFalse(s.reacquired)

    def test_stride4_wrong_box_wrong_appearance_multiple_and_no_candidate_stay_lost(self):
        child=face([.1,.1,.3,.4])
        cases=[([face([.6,.1,.9,.5])],'identity_lost_waiting_landmarks'),
               ([face(child['box'],(0.,1.))],'identity_lost_waiting_landmarks'),
               ([child,face([.11,.11,.31,.41])],'target_ambiguous'),
               ([], 'identity_lost_waiting_landmarks')]
        for candidates,status in cases:
            with self.subTest(status=status,candidates=len(candidates)):
                s=IdentitySelection([.2,.2],allow_reacquisition=True);s.choose([child],0)
                self.assertIsNone(s.choose(candidates,3.,child['box']))
                self.assertFalse(s.reacquired);self.assertEqual(s.last,0)
                self.assertEqual(s.status,status);self.assertEqual(s.hist,child['hist'])
                self.assertIs(s.choose([child],3.2,child['box']),child)
                self.assertTrue(s.reacquired)

    def test_reacquisition_cannot_establish_a_never_selected_initial_target(self):
        s=IdentitySelection([.2,.2],allow_reacquisition=True)
        self.assertIsNone(s.choose([],0));self.assertIsNone(s.choose([face([.1,.1,.3,.4])],3))
        self.assertFalse(s.established);self.assertFalse(s.reacquired)

    def test_reacquisition_requires_vendor_accepted_landmarks_and_records_media_time(self):
        child=face([.1,.1,.3,.4])
        for accepted in (True,False):
            with self.subTest(accepted=accepted):
                tracker=FastTracker.__new__(FastTracker)
                tracker.selector=IdentitySelection([.2,.2],allow_reacquisition=True)
                tracker.selector.choose([child],0);tracker.faces=1
                def update(*args):
                    tracker.selector.choose([child],3,child['box'])
                    return dict(source='landmarks' if accepted else 'optical_flow',
                        landmarks=[1] if accepted else None,flow_points=8,bbox=child['box'])
                tracker.track=SimpleNamespace(update=update)
                tracker.module=SimpleNamespace(head_pose=lambda *_:{})
                row=tracker.update(SimpleNamespace(shape=(720,1280,3)),3.)
                self.assertEqual(row['target_reacquired'],accepted)
                self.assertEqual(row['reacquisition_time_s'],3. if accepted else None)
                self.assertEqual(tracker.selector.last,3. if accepted else 0)
                if not accepted:
                    self.assertEqual(row['track_source'],'lost');self.assertFalse(row['valid'])
                    self.assertEqual(row['identity_status'],'identity_lost_waiting_landmarks')

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
