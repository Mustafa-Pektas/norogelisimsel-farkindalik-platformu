"""Synthetic settling logic only; no real video accuracy claims."""
import json
from pathlib import Path
import unittest
from test_motion_candidates import sequence
import settling_regions as m

CONFIG=json.loads((Path(__file__).parent/'parameters/settling_regions_v1.json').read_text(encoding='utf-8'))

def accepted(result):return [w for w in result['windows'] if w['status']=='accepted_settling_window']

class SettlingTests(unittest.TestCase):
    def scan(self,angles,radius=10):return m.scan(sequence(angles),9,radius,CONFIG)

    def test_small_oscillations_do_not_require_full_stillness(self):
        for radius in (10,15):
            r=self.scan([0]*9+[60+(-1)**i*2 for i in range(50)],radius)
            self.assertTrue(accepted(r))
            w=accepted(r)[0]
            self.assertAlmostEqual(w['confirmation_delay_from_candidate_end_s'],9/24)
            self.assertAlmostEqual(w['confirmation_delay_from_candidate_start_s'],17/24)

    def test_three_degree_alternation_exposes_medoid_phase_sensitivity(self):
        angles=[0]*9+[60+(-1)**i*3 for i in range(50)]
        narrow=self.scan(angles,10)
        self.assertFalse(accepted(narrow))
        self.assertIn('inter_center_drift_too_large',narrow['windows'][0]['reasons'])
        self.assertAlmostEqual(narrow['windows'][0]['center_distance_deg'],6,places=6)
        self.assertTrue(accepted(self.scan(angles,15)))

    def test_one_degree_per_frame_drift_rejected_by_center_change(self):
        for radius in (10,15):
            r=self.scan([0]*9+[60+i for i in range(18)],radius)
            self.assertIn('inter_center_drift_too_large',r['windows'][0]['reasons'])

    def test_very_slow_drift_can_pass_but_frozen_region_eventually_exits(self):
        r=self.scan([0]*9+[60+.2*i for i in range(100)])
        w=r['windows'][0]
        self.assertEqual(w['status'],'accepted_settling_window')
        self.assertEqual(w['departure']['status'],'confirmed_region_exit')
        self.assertGreater(w['departure']['start_s'],w['confirmation_time_s'])

    def test_two_turns_keep_both_regions_and_first_region_exit(self):
        r=self.scan([0]*9+[60]*27+[120]*30)
        ws=accepted(r)
        self.assertTrue(any(w['first_distance_from_initial_deg']<70 for w in ws))
        self.assertTrue(any(w['first_distance_from_initial_deg']>110 for w in ws))
        self.assertEqual(ws[0]['departure']['start_frame'],36)
        self.assertEqual(ws[0]['departure']['confirmed_frame'],38)

    def test_return_to_initial_is_not_new_separated_region(self):
        r=self.scan([0]*9+[60]*27+[0]*30)
        final=next(w for w in r['windows'] if w['seed_frame']==36)
        self.assertIn('first_region_not_separated_from_initial',final['reasons'])

    def test_single_spike_does_not_change_center_or_force_departure(self):
        angles=[0]*9+[60]*60;angles[12]=140;angles[35]=140
        w=self.scan(angles)['windows'][0]
        self.assertEqual(w['status'],'accepted_settling_window')
        self.assertEqual(len(w['first_support_frames']),8)
        self.assertEqual(w['departure']['status'],'no_confirmed_exit_before_clip_end')
        self.assertEqual(len(w['departure']['short_excursions']),1)

    def test_initial_orientation_cannot_be_completed_turn(self):
        r=self.scan([0]*60)
        self.assertFalse(accepted(r))
        self.assertIn('first_region_not_separated_from_initial',r['windows'][0]['reasons'])

    def test_missing_sample_is_not_imputed_even_with_eight_other_samples(self):
        records=sequence([0]*9+[60]*40);records[12]['valid']=False;records[12]['rotation_matrix']=None
        r=m.scan(records,9,10,CONFIG)
        self.assertEqual(r['windows'][0]['status'],'unconfirmed_incomplete_data')
        self.assertIn('first_block_invalid_matrix',r['windows'][0]['reasons'])

    def test_clip_end_without_nine_confirmation_samples_stays_unconfirmed(self):
        w=self.scan([0]*9+[60]*17)['windows'][0]
        self.assertEqual(w['status'],'unconfirmed_incomplete_data')
        self.assertIsNone(w['confirmation_time_s'])
        self.assertIn('insufficient_confirmation_at_clip_end',w['reasons'])

    def test_missing_initial_reference_is_explicit(self):
        r=m.scan(sequence([0]*4+[60]*40),4,10,CONFIG)
        self.assertFalse(accepted(r));self.assertIsNone(r['initial_reference'])

    def test_incomplete_departure_is_not_confirmed(self):
        r=self.scan([0]*9+[60]*30+[120]*2)
        self.assertEqual(r['windows'][0]['departure']['status'],'pending_exit_at_clip_end')
        self.assertIsNone(r['windows'][0]['departure']['start_s'])

if __name__=='__main__':unittest.main()
