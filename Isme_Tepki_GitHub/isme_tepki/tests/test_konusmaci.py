from pathlib import Path
import sys
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from konusmaci import match_faces, face_regions


class SpeakerAlignmentTests(unittest.TestCase):
    def setUp(self):
        self.levels = np.array([-58, -59, -60, -56, -59, -52, -22, -20, -18, -19, -25, -23])
        self.moving = (self.levels + 60) / 300 + .015
        self.still = np.full(12, .02)
        self.regions = [('adult', 'adult_face', None, None), ('child', None, None, None)]

    def match(self, adult, child):
        return match_faces(self.levels, np.column_stack((adult, child)), self.regions, 12)

    def test_audio_matches_only_the_synchronized_face(self):
        answer = self.match(self.moving, self.still)
        self.assertEqual(answer['status'], 'matched')
        self.assertEqual(answer['target_id'], 'adult_face')

    def test_both_faces_synced_is_ambiguous(self):
        answer = self.match(self.moving, self.moving * 1.5)
        self.assertEqual(answer['status'], 'ambiguous')
        self.assertNotIn('target_id', answer)

    def test_visible_adult_is_not_assigned_from_sound_alone(self):
        self.assertEqual(self.match(self.still, self.still)['status'], 'uncertain')
        self.assertEqual(self.match(self.still, self.moving)['status'], 'untargeted_face')

    def test_insufficient_audio_cannot_select_a_face(self):
        self.levels[:] = -88
        self.assertEqual(self.match(self.moving, self.still)['status'], 'insufficient_audio')

    def test_body_and_toy_targets_are_excluded(self):
        box = [.2, .2, .4, .4]
        scene = dict(adult_head=box, adult_search_region=box, targets=[
            dict(id='body', type='person_body', track='adult', bbox=box),
            dict(id='face', type='person_face', track='adult', bbox=box),
            dict(id='toy', type='object', bbox=box),
        ])
        self.assertEqual(face_regions(scene), [('adult', 'face', box, box)])


if __name__ == '__main__':
    unittest.main()
