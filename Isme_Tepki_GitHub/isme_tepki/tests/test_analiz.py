import json
from pathlib import Path
import sys
import unittest
import tempfile
from unittest.mock import patch
from types import ModuleType

import numpy as np
from scipy.spatial.transform import Rotation

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from analiz import (project_paths, filtered, normalize_rows, direction, call_results, look_at_caller,
                    validate_calls, run, write, digest)
from optik_akis import measure_pair, motion_stops, parameters, pose_events

ROOT = Path(__file__).resolve().parents[2]
# Staging sirasinda gercek proje kokunu cevre degiskeniyle secmek mumkun.
import os
PROJECT_ROOT = Path(os.environ.get('ISME_TEPKI_PROJECT_ROOT', str(ROOT)))
RESEARCH = project_paths(PROJECT_ROOT)
from motion_candidates import detect

MOTION = json.loads((RESEARCH / 'parameters/motion_candidates_v1.json').read_text())
SETTING = next(s for s in MOTION['settings'] if s['id'] == 'base')


def records(degrees):
    return [dict(frame_index=i, time_s=i / 24, valid=True,
                 rotation_matrix=Rotation.from_euler('y', value, degrees=True).as_matrix().tolist())
            for i, value in enumerate(degrees)]


def sample_call(**kwargs):
    return dict(id='c1', start_s=1.5, end_s=1.8, timing_source='manual',
                speaker_target_id='adult_face', speaker_source='manual_user_verified', **kwargs)


def gazes(target, start, count):
    return [dict(time_s=start + i / 6, target=target) for i in range(count)]


class AnalysisTests(unittest.TestCase):
    def test_flow_stop_has_separate_event_and_confirmation_times(self):
        speeds = [0] * 5 + [.5] * 4 + [.05] * 5
        samples = [dict(time_s=i / 24, speed=speed) for i, speed in enumerate(speeds)]
        stop, = motion_stops(samples, parameters({}))
        self.assertEqual(stop['movement_start_s'], 5 / 24)
        self.assertEqual(stop['time_s'], 9 / 24)
        self.assertEqual(stop['confirmed_s'], 13 / 24)
        samples[10]['speed'] = None
        self.assertEqual(motion_stops(samples, parameters({})), [])

    def test_flow_subtracts_camera_motion_and_preserves_head_motion(self):
        import cv2 as cv

        rng = np.random.default_rng(42)
        image = rng.integers(0, 256, size=(360, 480), dtype=np.uint8)
        image = cv.GaussianBlur(image, (5, 5), 0)
        shift = np.float32([[1, 0, 3], [0, 1, 2]])
        translated = cv.warpAffine(image, shift, (480, 360))
        box = (160, 120, 290, 240)
        foreground = [[.29, .26, .66, .73]]
        still = measure_pair(cv, image, translated, box, box, foreground, 1 / 24)
        moved = translated.copy()
        moved[105:265, 145:315] = translated[105:265, 140:310]
        motion = measure_pair(cv, image, moved, box, box, foreground, 1 / 24)
        self.assertEqual(still[3], 'measured')
        self.assertLess(still[0], .03)
        self.assertEqual(motion[3], 'measured')
        self.assertGreater(motion[0], .30)

    def test_return_requires_sustained_departure_and_no_pose_gap(self):
        rows = records([0] * 16 + [24] * 6 + [0] * 6)
        result = pose_events(rows, 16 / 24, 27 / 24, 24, parameters({}))
        returned, = result['events']
        self.assertEqual(returned['departure_s'], 16 / 24)
        self.assertEqual(returned['time_s'], 22 / 24)
        self.assertEqual(returned['confirmed_s'], 26 / 24)
        rows[21].update(valid=False, rotation_matrix=None)
        self.assertEqual(pose_events(rows, 16 / 24, 27 / 24, 24, parameters({}))['events'], [])

    def test_look_does_not_count_a_target_run_that_started_before_the_call(self):
        before = gazes('toy', .75, 3)
        early = look_at_caller(sample_call(), before + gazes('adult_face', 1.3, 6), 3.0, 6)
        self.assertEqual(early['status'], 'already_oriented')
        after = look_at_caller(sample_call(), before + gazes('adult_face', 1.6, 6), 3.0, 6)
        self.assertEqual(after['time_s'], 1.6)

    def test_single_frame_jump_is_not_a_turn(self):
        rs = records([0] * 40 + [70] + [0] * 40)
        self.assertEqual(detect(rs, MOTION, SETTING)['candidates'], [])
        for alpha in (.5, .25):
            sm = filtered(rs, alpha, 24)
            peak = max(Rotation.from_matrix(r['rotation_matrix']).magnitude() for r in sm)
            self.assertLess(np.degrees(peak), 70)

    def test_real_turn_has_boundaries_and_later_confirmation(self):
        rs = records([0] * 40 + [i * 3.75 for i in range(1, 21)] + [75] * 40)
        c = detect(rs, MOTION, SETTING)['candidates'][0]
        self.assertLess(c['start_s'], c['end_s'])
        self.assertGreater(c['start_confirmed_s'], c['start_s'])
        self.assertGreater(c['end_confirmed_s'], c['end_s'])

    def test_clip_end_is_not_fabricated_movement_end(self):
        rs = records([0] * 40 + [i * 3.75 for i in range(1, 21)])
        self.assertIsNone(detect(rs, MOTION, SETTING)['candidates'][-1]['end_s'])

    def test_invalid_frame_and_gap_reset_ema(self):
        rs = records([0, 0, 90, 90])
        rs[1].update(valid=False, rotation_matrix=None)
        sm = filtered(rs, .5, 24)
        self.assertIsNone(sm[1]['rotation_matrix'])
        np.testing.assert_allclose(sm[2]['rotation_matrix'], rs[2]['rotation_matrix'])
        rs = records([0, 90]); rs[1]['time_s'] = 1
        np.testing.assert_allclose(filtered(rs, .5, 24)[1]['rotation_matrix'], rs[1]['rotation_matrix'])

    def test_euler_wrap_is_small_matrix_motion(self):
        rs = records([179] * 40 + [-179] * 40)
        self.assertEqual(detect(rs, MOTION, SETTING)['candidates'], [])

    def test_missing_and_invalid_measurements_stay_missing(self):
        rows = normalize_rows([dict(frame=0, time_s=0),
                               dict(frame=1, time_s=1 / 24, rotation_matrix=np.zeros((3, 3)).tolist()),
                               dict(frame=2, decoder_time_s=None, nominal_time_s=2 / 24)])
        self.assertFalse(any(r['valid'] for r in rows))
        self.assertIsNone(rows[2]['time_s'])

    def test_nonmonotonic_time_and_duplicate_frame_rejected(self):
        for rows in ([dict(frame=0, time_s=.1), dict(frame=1, time_s=.1)],
                     [dict(frame=0, time_s=0), dict(frame=0, time_s=.1)]):
            with self.assertRaises(ValueError):
                normalize_rows(rows)

    def test_caller_must_be_verified(self):
        call = sample_call(); call['speaker_source'] = 'unresolved'
        self.assertIsNone(direction(call, gazes('adult_face', 2, 6), 2, 3)['correct'])

    def test_target_transition_and_other_target(self):
        baseline = gazes('toy', .8, 4)
        self.assertTrue(direction(sample_call(), baseline + gazes('adult_face', 2, 6), 2, 3)['correct'])
        self.assertFalse(direction(sample_call(), baseline + gazes('toy', 2, 6), 2, 3)['correct'])

    def test_already_oriented_is_not_new_turn(self):
        result = direction(sample_call(), gazes('adult_face', .8, 4), 2, 3)
        self.assertEqual(result['status'], 'already_oriented')
        self.assertIsNone(result['correct'])

    def test_gaze_gap_and_missing_baseline_do_not_confirm_direction(self):
        baseline = gazes('toy', .8, 4)
        scattered = [dict(time_s=2, target='adult_face'), dict(time_s=2.8, target='adult_face')]
        self.assertIsNone(direction(sample_call(), baseline + scattered, 2, 3)['correct'])
        self.assertEqual(direction(sample_call(), gazes('adult_face', 2, 6), 2, 3)['status'], 'unknown_baseline')

    def test_precall_movement_kept_without_response_latency(self):
        rs = records([0] * 24 + [i * 3.75 for i in range(1, 25)] + [90] * 30)
        detected = {'raw': detect(rs, MOTION, SETTING)}
        event = call_results([sample_call()], detected, [], 3, 4, 6)[0]
        self.assertFalse(event['observation_complete'])
        c = event['methods']['raw'][0]
        self.assertEqual(c['relation'], 'preexisting_or_unknown_start')
        self.assertIsNone(c['latency_from_start_s'])

    def test_no_call_or_no_candidate_does_not_fabricate_response(self):
        self.assertEqual(call_results([], {}, [], 3, 4, 6), [])
        event = call_results([sample_call()], {'raw': {'candidates': []}}, [], 3, 4, 6)[0]
        self.assertEqual(event['methods']['raw'], [])

    def test_motion_lost_before_call_is_not_extended_to_later_call(self):
        candidate = dict(candidate_id='c', start_s=.5, end_s=None,
                         first_high_evidence_s=.5, last_supported_time_s=1.0)
        event = call_results([sample_call()], {'raw': {'candidates': [candidate]}}, [], 5, 4, 6)[0]
        self.assertEqual(event['methods']['raw'], [])

    def test_call_validation(self):
        for call in (dict(sample_call(), end_s=1), dict(sample_call(), id='../x'),
                     dict(sample_call(), timing_source='')):
            with self.assertRaises(ValueError):
                validate_calls([call])
        with self.assertRaises(ValueError):
            validate_calls([sample_call(), sample_call()])

    def test_manual_marks_are_posthoc_and_never_replace_detection(self):
        rs = records([0] * 40 + [i * 3.75 for i in range(1, 21)] + [75] * 40)
        detection = {'raw': detect(rs, MOTION, SETTING)}
        call = sample_call(); call['manual_movement'] = {'start_s': 1.7, 'end_s': 2.5}
        event = call_results([call], detection, [], 4, 2, 6)[0]
        candidate = event['methods']['raw'][0]
        self.assertEqual(candidate['start_s'], detection['raw']['candidates'][0]['start_s'])
        self.assertAlmostEqual(event['manual_latency_from_start_s'], .2)
        self.assertAlmostEqual(candidate['end_minus_manual_s'], candidate['end_s'] - 2.5)

    def test_recorded_report_and_no_overwrite_and_provenance_check(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / 'fixture.mp4').write_bytes(b'synthetic replay identity fixture')
            rows = records([0] * 40 + [i * 3.75 for i in range(1, 21)] + [75] * 40)
            write(base / 'frames.json', rows)
            write(base / 'meta.json', {'video': {'sha256': digest(base / 'fixture.mp4'), 'fps': 24}})
            cfg = dict(video='fixture.mp4', frames='frames.json', recorded_metadata='meta.json',
                       calls=[sample_call()])
            write(base / 'config.json', cfg)
            output = base / 'result'
            result = run(base / 'config.json', output, PROJECT_ROOT)
            self.assertEqual(result['valid_frames'], len(rows))
            self.assertEqual(json.loads((output / 'durum.json').read_text())['status'], 'completed')
            for name in ('rapor.html', 'bas_acilari.png', 'hareketler.csv', 'acilar.csv'):
                self.assertGreater((output / name).stat().st_size, 100)
            with self.assertRaises(FileExistsError):
                run(base / 'config.json', output, PROJECT_ROOT)
            write(base / 'meta.json', {'video': {'sha256': 'wrong', 'fps': 24}})
            with self.assertRaisesRegex(ValueError, 'SHA256'):
                run(base / 'config.json', base / 'wrong_video', PROJECT_ROOT)

    def test_new_video_uses_existing_pipeline(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / 'fixture.mp4').write_bytes(b'synthetic adapter fixture')
            write(base / 'scene.json', {'calls': [sample_call()], 'settings': {}})
            write(base / 'labels.json', dict(video_sha256=digest(base / 'fixture.mp4'),
                  reviewer='Synthetic fixture reviewer', reviewed=True,
                  intervals=[dict(start_s=0, end_s=3, complete=True, movements=[])]))
            write(base / 'config.json', {'video': 'fixture.mp4', 'scene_config': 'scene.json',
                                        'manual_labels': 'labels.json'})
            module = ModuleType('sesyon.pipeline')
            def existing_pipeline(scene, source, out, gaze_enabled):
                self.assertTrue(gaze_enabled)
                self.assertEqual(scene['calls'][0]['id'], 'c1')
                self.assertNotIn('manual_labels', scene)
                write(out / 'frames.json', records([0] * 72))
                write(out / 'result.json', {'video': {'fps': 24}})
                write(out / 'gaze.json', [])
            module.run = existing_pipeline
            with patch.dict(sys.modules, {'sesyon.pipeline': module}):
                result = run(base / 'config.json', base / 'result', PROJECT_ROOT)
            self.assertEqual(result['provenance']['mode'], 'video')
            self.assertEqual(result['comparison']['indicator'], 'green')
            self.assertTrue((base / 'result' / 'etiketler_kullanilan.json').exists())
            self.assertTrue((base / 'result' / 'hatalar.csv').exists())
            self.assertIn('indicator green', (base / 'result' / 'rapor.html').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
