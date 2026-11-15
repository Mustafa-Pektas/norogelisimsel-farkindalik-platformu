import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from karsilastir import evaluate, match, DEFAULT_RULES


def manual(start=1, end=1.6, **extra):
    return dict(id='m1', start_s=start, end_s=end, **extra)


def candidate(start=1, end=1.6, identity='c1'):
    return dict(candidate_id=identity, start_s=start, end_s=end,
                first_high_evidence_s=start if start is not None else .8,
                last_supported_time_s=end if end is not None else 3)


def labels(movements=None):
    return dict(video_sha256='video', reviewed=True, reviewer='Test inceleyen',
                intervals=[dict(start_s=0, end_s=4, complete=True,
                                movements=[manual()] if movements is None else movements)])


def assess(annotation, candidates, bad_frames=(), result=None):
    rows = [dict(frame_index=i, time_s=i / 24, valid=i not in bad_frames) for i in range(96)]
    result = result or dict(video={'sha256': 'video', 'fps': 24}, selected_method='ema_050', calls=[])
    detection = {'ema_050': {'candidates': candidates}}
    return evaluate(annotation, result, detection, rows, 4)


class ComparisonTests(unittest.TestCase):
    def test_agreement_is_green(self):
        result = assess(labels(), [candidate(1.05, 1.65)])
        self.assertEqual(result['indicator'], 'green')
        self.assertEqual(result['methods']['ema_050']['counts']['matched'], 1)

    def test_unreviewed_and_partial_windows_are_yellow(self):
        self.assertEqual(assess(None, [])['indicator'], 'yellow')
        annotation = labels(); annotation['reviewed'] = False
        self.assertEqual(assess(annotation, [candidate()])['methods']['ema_050']['records'], [])
        annotation = labels(); annotation['intervals'][0]['complete'] = False
        self.assertEqual(assess(annotation, [candidate()])['indicator'], 'yellow')
        annotation = labels([]); annotation['intervals'][0]['end_s'] = 1
        summary = assess(annotation, [candidate(2, 3)])['methods']['ema_050']
        self.assertEqual(summary['counts']['extra'], 0)
        self.assertEqual(summary['color'], 'yellow')

    def test_wrong_video_or_missing_reviewer_rejected(self):
        for change in ({'video_sha256': 'other'}, {'reviewer': ''}):
            annotation = labels(); annotation.update(change)
            with self.assertRaises(ValueError):
                assess(annotation, [])

    def test_missed_extra_and_timing_mismatch_red(self):
        self.assertEqual(assess(labels(), [])['methods']['ema_050']['counts']['missed'], 1)
        result = assess(labels([]), [candidate()])
        self.assertEqual(result['indicator'], 'red')
        self.assertEqual(result['methods']['ema_050']['counts']['extra'], 1)
        result = assess(labels(), [candidate(1.3, 1.9)])
        self.assertEqual(result['indicator'], 'red')
        self.assertEqual(result['methods']['ema_050']['timing_errors'], 1)

    def test_exact_tolerance_is_accepted(self):
        self.assertEqual(assess(labels(), [candidate(1.2, 1.8)])['indicator'], 'green')

    def test_duplicate_candidate_cannot_match_same_label(self):
        result = assess(labels(), [candidate(), candidate(1.1, 1.7, 'c2')])
        summary = result['methods']['ema_050']
        self.assertEqual(summary['paired_count'], 1)
        self.assertEqual(summary['counts']['extra'], 1)

    def test_matching_maximizes_pairs_before_minimizing_distance(self):
        ms = [manual(1, 1.2), dict(manual(1.5, 1.7), id='m2')]
        cs = [candidate(1.15, 1.6), candidate(.7, 1.1, 'c2')]
        self.assertEqual(set(match(ms, cs, DEFAULT_RULES)), {(0, 1), (1, 0)})

    def test_disjoint_far_candidate_is_not_arbitrarily_paired(self):
        result = assess(labels(), [candidate(2.5, 3)])['methods']['ema_050']
        self.assertEqual(result['paired_count'], 0)
        self.assertEqual(result['counts']['extra'], 1)
        self.assertEqual(result['counts']['missed'], 1)

    def test_low_quality_miss_and_extra_remain_uncertain(self):
        bad = range(24, 40)
        for annotation, candidates in [(labels(), []), (labels([]), [candidate()])]:
            summary = assess(annotation, candidates, bad)['methods']['ema_050']
            self.assertEqual(summary['counts']['missed'], 0)
            self.assertEqual(summary['counts']['extra'], 0)
            self.assertEqual(summary['color'], 'yellow')

    def test_good_local_match_but_global_gap_stays_yellow(self):
        result = assess(labels(), [candidate()], range(55, 75))
        self.assertEqual(result['indicator'], 'yellow')

    def test_missing_end_or_unknown_onset_not_a_confirmed_failure(self):
        self.assertEqual(assess(labels(), [candidate(1, None)])['indicator'], 'yellow')
        summary = assess(labels(), [candidate(None, 1.6)])['methods']['ema_050']
        self.assertEqual(summary['counts']['missed'], 0)
        self.assertEqual(summary['counts']['extra'], 0)
        self.assertEqual(summary['color'], 'yellow')

    def test_verified_empty_reference_can_agree_without_inventing_accuracy(self):
        result = assess(labels([]), [])
        self.assertEqual(result['indicator'], 'green')
        self.assertEqual(result['methods']['ema_050']['paired_count'], 0)
        self.assertNotIn('accuracy', result)

    def test_direction_mismatch_and_unknown_are_distinct(self):
        annotation = labels([manual(call_id='call', direction_correct=True)])
        result = dict(video={'sha256': 'video', 'fps': 24}, selected_method='ema_050',
                      calls=[dict(call={'id': 'call'}, methods={'ema_050': [
                          dict(candidate_id='c1', direction={'correct': False})]})])
        checked = assess(annotation, [candidate()], result=result)
        self.assertEqual(checked['indicator'], 'red')
        self.assertEqual(checked['methods']['ema_050']['direction_errors'], 1)
        result['calls'][0]['methods']['ema_050'][0]['direction']['correct'] = None
        checked = assess(annotation, [candidate()], result=result)
        self.assertEqual(checked['indicator'], 'yellow')
        self.assertEqual(checked['methods']['ema_050']['direction_errors'], 0)

    def test_direction_requires_call_and_boolean(self):
        for movement in (manual(direction_correct=True), manual(direction_correct='yes')):
            with self.assertRaises(ValueError):
                assess(labels([movement]), [])

    def test_overlapping_review_intervals_and_movements_rejected(self):
        annotation = labels()
        annotation['intervals'].append(copy.deepcopy(annotation['intervals'][0]))
        with self.assertRaises(ValueError):
            assess(annotation, [])
        with self.assertRaises(ValueError):
            assess(labels([manual(), dict(manual(1.5, 2), id='m2')]), [])

    def test_rules_invalid_and_inputs_unchanged(self):
        annotation = labels(); detections = [candidate()]
        original = copy.deepcopy((annotation, detections))
        assess(annotation, detections)
        self.assertEqual((annotation, detections), original)
        rows = [dict(time_s=i / 24, valid=True) for i in range(96)]
        result = dict(video={'sha256': 'video', 'fps': 24}, selected_method='ema_050', calls=[])
        with self.assertRaises(ValueError):
            evaluate(annotation, result, {'ema_050': {'candidates': []}}, rows, 4, {'min_coverage': 1.1})


if __name__ == '__main__':
    unittest.main()
