"""Synthetic/recorded processing checks, no model or API calls."""
import json
from pathlib import Path
import unittest
from sampling12_review import sampled_rows, match_candidates


def candidate(start,end):
    return dict(start_s=start,end_s=end,end_confirmed_s=None if end is None else end+1/6)


class SamplingTests(unittest.TestCase):
    def test_sampling_preserves_source_time_and_missing_indices(self):
        rows=[dict(frame_index=i,time_s=i/24) for i in [0,1,2,3,6,7]]
        selected=sampled_rows(rows,0)
        self.assertEqual([r['source_frame_index'] for r in selected],[0,2,6])
        self.assertEqual([r['frame_index'] for r in selected],[0,1,3])
        self.assertEqual([r['time_s'] for r in selected],[0,2/24,6/24])
        self.assertEqual([r['frame_index'] for r in rows],[0,1,2,3,6,7])

    def test_gate_does_not_accept_early_boundary_or_hide_extra_candidates(self):
        ref=[candidate(1,2)]
        self.assertTrue(match_candidates(ref,[candidate(1,2)])['eligible'])
        self.assertFalse(match_candidates(ref,[candidate(1,2-1/6)])['eligible'])
        report=match_candidates(ref,[candidate(1,2),candidate(3,4)])
        self.assertEqual(report['extra_or_unmatched'],[1]);self.assertFalse(report['eligible'])

    def test_unknown_boundary_is_unassessable_not_imputed(self):
        r=match_candidates([candidate(1,None)],[candidate(1,None)])
        self.assertFalse(r['eligible'])
        self.assertEqual(r['missing_or_unknown'][0]['reason'],'reference_boundary_unknown')
        # "extra_or_unmatched" is deliberately not an automatic extra-event label.
        self.assertEqual(r['extra_or_unmatched'],[0])

    def test_declared_time_scales_and_alpha_are_not_label_tuned(self):
        protocol=json.loads((Path(__file__).parent/'parameters/sampling12_v1.json').read_text())
        self.assertEqual(protocol['phases'],[0,1]);self.assertEqual(protocol['median_intervals'],[3,2])
        self.assertEqual((protocol['start_confirmation_samples']-1)/12,(3-1)/24)
        self.assertEqual((protocol['stop_confirmation_samples']-1)/12,(5-1)/24)
        self.assertEqual(protocol['ema_alpha'],1-(1-.5)**2)
        self.assertLess(2/12,5/24);self.assertGreater(3/12,5/24)


if __name__=='__main__':unittest.main()
