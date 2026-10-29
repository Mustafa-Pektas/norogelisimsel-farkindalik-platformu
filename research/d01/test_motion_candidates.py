"""Synthetic engineering controls, not video accuracy validation."""
import json
import math
from pathlib import Path
import unittest
import numpy as np
import motion_candidates as m

CONFIG=json.loads((Path(__file__).parent/'parameters/motion_candidates_v1.json').read_text(encoding='utf-8'))
SETTING=next(s for s in CONFIG['settings'] if s['id']=='base')

def sequence(angles):
    result=[]
    for i,angle in enumerate(angles):
        z=math.radians(angle);c,s=math.cos(z),math.sin(z)
        result.append(dict(frame_index=i,time_s=i/24,rotation_matrix=[[c,-s,0],[s,c,0],[0,0,1]],valid=True))
    return result

class MotionTests(unittest.TestCase):
    def test_stationary_has_no_candidate_and_no_initial_boundary_claim(self):
        result=m.detect(sequence([0]*60),CONFIG,SETTING)
        self.assertEqual(result['candidates'],[])
        self.assertTrue(any(u['kind']=='insufficient_or_invalid_evidence' for u in result['uncertain_intervals']))

    def test_known_ramp_dwell_has_explicit_delayed_boundaries(self):
        result=m.detect(sequence([0]*12+[3*i for i in range(1,13)]+[36]*20),CONFIG,SETTING)
        self.assertEqual(len(result['candidates']),1)
        event=result['candidates'][0]
        self.assertEqual(event['start_frame'],14)
        self.assertEqual(event['end_frame'],26)
        self.assertAlmostEqual(event['start_confirmed_s'],16/24)
        self.assertAlmostEqual(event['end_confirmed_s'],30/24)

    def test_single_bad_pose_out_and_back_is_not_sustained_motion(self):
        for setting in CONFIG['settings']:
            self.assertEqual(m.detect(sequence([0]*15+[80]+[0]*30),CONFIG,setting)['candidates'],[])

    def test_two_separated_movements_are_not_reduced_to_first(self):
        angles=[0]*12+[3*i for i in range(1,13)]+[36]*20+[36-3*i for i in range(1,13)]+[0]*20
        result=m.detect(sequence(angles),CONFIG,SETTING)
        self.assertEqual(len(result['candidates']),2)
        self.assertLess(result['candidates'][0]['end_s'],result['candidates'][1]['start_s'])

    def test_motion_at_clip_boundaries_stays_censored(self):
        result=m.detect(sequence([3*i for i in range(30)]),CONFIG,SETTING)
        self.assertEqual(len(result['candidates']),1)
        self.assertIsNone(result['candidates'][0]['start_s'])
        self.assertIsNone(result['candidates'][0]['end_s'])
        self.assertEqual(result['candidates'][0]['end_status'],'unknown_end_clip_ended')

    def test_invalid_frame_interrupts_without_filling(self):
        records=sequence([0]*12+[3*i for i in range(1,30)])
        records[22]['valid']=False;records[22]['rotation_matrix']=None
        result=m.detect(records,CONFIG,SETTING)
        self.assertIsNone(result['feature_records'][22]['median_speed_deg_s'])
        self.assertEqual(result['candidates'][0]['end_status'],'unknown_end_data_gap')
        self.assertIsNone(result['candidates'][0]['end_s'])

    def test_large_time_gap_is_not_a_contiguous_interval(self):
        records=sequence([0]*20)
        for r in records[10:]:r['time_s']+=.2
        features=m.evidence(records,CONFIG)
        self.assertEqual(features[10]['reason'],'invalid_or_large_time_gap')
        self.assertIsNone(features[10]['median_speed_deg_s'])

    def test_180_wrap_uses_short_matrix_difference(self):
        features=m.evidence(sequence([179,-179]),CONFIG)
        self.assertAlmostEqual(features[1]['speed_deg_s'],48,places=6)

    def test_transition_band_is_retained_as_uncertain(self):
        result=m.detect(sequence([0]*12+[1.25*i for i in range(1,25)]),CONFIG,SETTING)
        self.assertEqual(result['candidates'],[])
        self.assertTrue(any(u['kind']=='hysteresis_transition_band' for u in result['uncertain_intervals']))

    def test_invalid_matrix_not_silently_repaired(self):
        self.assertIsNone(m.rotation(np.eye(3)*2))

    def test_annotation_like_metadata_does_not_change_detection(self):
        records=sequence([0]*12+[3*i for i in range(1,13)]+[36]*20)
        original=m.detect(records,CONFIG,SETTING)
        for record in records:
            record['manual_start_s']=-99
            record['manual_end_s']=999
            record['response_target']='irrelevant synthetic metadata'
        self.assertEqual(m.detect(records,CONFIG,SETTING),original)

if __name__=='__main__':unittest.main()
