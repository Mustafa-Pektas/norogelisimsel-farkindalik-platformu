from pathlib import Path
import sys
import unittest

import numpy as np
from scipy.spatial.transform import Rotation

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bas_pozu import choose_child, direct_rotation, tracked_box


class ChildHeadTests(unittest.TestCase):
    def test_child_is_selected_even_with_higher_scoring_adult(self):
        child = dict(bbox=(.28, .30, .50, .58), confidence=.64)
        adult = dict(bbox=(.60, .08, .81, .42), confidence=.99)
        self.assertIs(choose_child([adult, child], [child['bbox']], adult['bbox'], None), child)
        self.assertIsNone(choose_child([adult], [child['bbox']], adult['bbox'], None))

    def test_two_similarly_supported_boxes_stay_unassigned(self):
        left = dict(bbox=(.3, .3, .48, .5), confidence=.8)
        right = dict(bbox=(.32, .3, .5, .5), confidence=.8)
        self.assertIsNone(choose_child([left, right], [(.31, .3, .49, .5)], None, None))

    def test_reacquisition_uses_unique_child_region(self):
        child = dict(bbox=(.3, .3, .48, .5), confidence=.8)
        self.assertIsNone(choose_child([child], [], None, None))
        self.assertIs(choose_child([child], [], None, (.2, .2, .6, .7)), child)
        self.assertIsNone(tracked_box(dict(child_track='lost', child_bbox=child['bbox']), 'child'))

    def test_full_range_wrap_is_a_small_matrix_rotation(self):
        a = direct_rotation([.5, (179 + 180) / 360, .5])
        b = direct_rotation([.5, (-179 + 180) / 360, .5])
        change = Rotation.from_matrix(a.T @ b).magnitude()
        self.assertAlmostEqual(np.degrees(change), 2.0)


if __name__ == '__main__':
    unittest.main()
