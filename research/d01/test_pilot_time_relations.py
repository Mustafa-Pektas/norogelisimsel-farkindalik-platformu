"""Synthetic saved-record checks only; no model, real labels, or media required."""
import copy
import json
import unittest

from pilot_time_relations import build_report, readable

class PilotTimeRelationsTests(unittest.TestCase):
    def setUp(self):
        self.annotation=dict(video_path='fixture.mp4',candidate_status='candidate',
            marks={k:dict(media_time_ms=v,time_source='libvlc_reported_media_time') for k,v in
                [('call_start_s',401),('call_end_s',1152),('response_start_s',1401),('response_end_s',2402)]},
            manual_details=dict(observed_target='User-observed adult',uncertainty='Approximate end'))
        event=dict(candidate_id='candidate_001',start_s=1.5416666666666665,end_s=2.458333333333333,
            start_confirmed_s=1.625,end_confirmed_s=2.625,start_status='observed_rule_boundary',end_status='observed_rule_boundary')
        self.detection=dict(results={m:dict(base=dict(candidates=[copy.deepcopy(event)],uncertain_intervals=[dict(kind='saved_ambiguity')])) for m in ('raw','ema_050')})
        self.settling=dict(protocol='fixture',results=dict(raw={'10':dict(radius_deg=10,fixed_v1_start_frame=37,
            windows=[dict(status='accepted_settling_window',candidate_interval_s=[1.9,2.23],confirmation_time_s=2.605,
                departure=dict(start_s=3.0,confirmed_s=3.083))],overlapping_groups=[])}))

    def report(self):
        return build_report('fixture','hash',self.annotation,self.detection,self.settling)

    def candidate(self, report=None):
        return (report or self.report())['movement_results']['raw']['settings']['base']['candidates'][0]

    def test_two_call_offsets_and_confirmations_are_separate(self):
        c=self.candidate()
        self.assertAlmostEqual(c['start_minus_manual_call_start_s'],1.1406666666666665)
        self.assertAlmostEqual(c['start_minus_manual_call_end_s'],.3896666666666666)
        self.assertEqual(c['movement_start_s'],1.5416666666666665)
        self.assertEqual(c['start_confirmation_time_s'],1.625)
        self.assertAlmostEqual(c['end_confirmation_delay_s'],1/6)

    def test_subsequent_candidates_and_existing_settings_not_filtered(self):
        for method in self.detection['results']:
            self.detection['results'][method]['base']['candidates'].append(dict(candidate_id='candidate_002',start_s=5.875,end_s=6.583333333333333,
                start_confirmed_s=5.958333333333333,end_confirmed_s=6.75))
        self.detection['results']['raw']['higher_20pct']=copy.deepcopy(self.detection['results']['raw']['base'])
        r=self.report();cs=r['movement_results']['raw']['settings']['base']['candidates']
        self.assertEqual(len(cs),2)
        self.assertAlmostEqual(cs[1]['start_minus_manual_call_start_s'],5.474)
        self.assertEqual(cs[1]['reference_call_association'],'arithmetic_reference_only_not_a_response_assignment')
        self.assertEqual(r['movement_results']['raw']['settings']['higher_20pct']['role'],'previously_recorded_sensitivity_only')

    def test_missing_call_time_is_unknown_not_zero(self):
        self.annotation['marks']['call_start_s']=None
        c=self.candidate();self.assertIsNone(c['start_minus_manual_call_start_s'])
        self.assertIsNotNone(c['start_minus_manual_call_end_s'])
        self.assertEqual(self.report()['manual']['marks']['call_start_s']['record_status'],'missing')

    def test_explicit_zero_call_start_is_preserved(self):
        self.annotation['marks']['call_start_s']['media_time_ms']=0
        self.assertEqual(self.report()['manual']['marks']['call_start_s']['time_s'],0)
        self.assertEqual(self.candidate()['start_minus_manual_call_start_s'],self.candidate()['movement_start_s'])

    def test_missing_start_or_end_not_replaced_by_evidence_or_settling(self):
        c=self.detection['results']['raw']['base']['candidates'][0]
        c.update(start_s=None,end_s=None,first_high_evidence_s=.5,end_status='unknown_end_clip_ended')
        result=self.candidate()
        self.assertIsNone(result['movement_start_s']);self.assertIsNone(result['movement_end_s'])
        self.assertIsNone(result['boundary_span_s']);self.assertIsNone(result['start_minus_manual_call_end_s'])
        self.assertEqual(result['end_status'],'unknown_end_clip_ended')
        self.assertIn('bilinmiyor',readable(self.report()))

    def test_long_first_video_candidate_is_not_trimmed(self):
        self.detection['results']['raw']['base']['candidates'][0].update(start_s=.7916666666666666,end_s=5.208333333333333,
            start_confirmed_s=.875,end_confirmed_s=5.375)
        self.assertAlmostEqual(self.candidate()['boundary_span_s'],4.416666666666667)
        self.assertFalse(self.candidate()['end_is_confirmed_physical_endpoint'])

    def test_negative_relative_time_not_turned_into_class(self):
        c=self.detection['results']['raw']['base']['candidates'][0];c.update(start_s=.5,start_confirmed_s=.6)
        self.assertAlmostEqual(self.candidate()['start_minus_manual_call_end_s'],-.652)
        self.assertNotIn('response_class',self.candidate())

    def test_settling_both_archive_shapes_preserve_all_statuses(self):
        original=self.settling['results']['raw']['10']
        original['windows'].append(dict(status='unconfirmed_incomplete_data',candidate_interval_s=None,confirmation_time_s=None,reasons=['missing_tail']))
        self.settling['results']['ema_050']={'15':dict(scans=[dict(source_candidate_id='candidate_002',**copy.deepcopy(original))],unassessable_starts=[dict(reason='unknown_start')])}
        r=self.report();regions=r['settling']['regions']
        self.assertEqual(len(regions),2);self.assertFalse(r['settling']['is_movement_end'])
        self.assertEqual(regions[0]['windows'][0]['confirmation_time_s'],2.605)
        self.assertIsNone(regions[1]['windows'][1]['confirmation_time_s'])
        self.assertEqual(regions[1]['windows'][1]['reasons'],['missing_tail'])

    def test_sources_not_mutated_target_is_only_user_observation(self):
        originals=copy.deepcopy([self.annotation,self.detection,self.settling]);r=self.report()
        self.assertEqual([self.annotation,self.detection,self.settling],originals)
        self.assertEqual(r['algorithmic_target']['status'],'not_determined')
        self.assertEqual(r['manual']['target_and_direction']['source'],'user_observation_only')
        self.assertIsNone(r['manual']['approval_field_in_source'])
        self.assertFalse(r['manual']['report_grants_approval'])
        self.assertFalse(r['limitations']==[])
        json.dumps(r,allow_nan=False)

    def test_invalid_times_rejected_not_silently_filled(self):
        for value in (-1,True,float('nan'),'401'):
            with self.subTest(value=value):
                self.annotation['marks']['call_start_s']['media_time_ms']=value
                with self.assertRaises(ValueError):self.report()

    def test_missing_method_and_empty_candidates_are_explicit(self):
        del self.detection['results']['ema_050']
        self.detection['results']['raw']['base']['candidates']=[]
        r=self.report()
        self.assertEqual(r['movement_results']['ema_050']['status'],'not_recorded')
        self.assertEqual(r['movement_results']['raw']['settings']['base']['candidates'],[])
        self.assertFalse(r['movement_results']['raw']['settings']['base']['no_candidates_means_no_response'])

if __name__=='__main__': unittest.main()
