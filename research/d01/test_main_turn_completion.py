import math
import unittest
from main_turn_completion import main_turn_region


def row(i, degrees):
    a=math.radians(degrees)
    return dict(frame_index=i,time_s=i/24,valid=True,rotation_matrix=[[math.cos(a),0,math.sin(a)],[0,1,0],[-math.sin(a),0,math.cos(a)]])


class RegionTests(unittest.TestCase):
    def test_turn_into_new_region(self):
        rows=[row(i,0 if i<12 else 40) for i in range(40)]
        r=main_turn_region(rows,dict(start_frame=12,start_s=.5))
        self.assertEqual(r['candidate']['frame_index'],12)
        self.assertEqual(r['candidate']['confirmed_frame'],29)

    def test_initial_region_not_a_turn(self):
        r=main_turn_region([row(i,0) for i in range(40)],dict(start_frame=12,start_s=.5))
        self.assertIsNone(r['candidate'])

    def test_missing_or_unknown_baseline(self):
        rr=[row(i,0) for i in range(40)]
        self.assertEqual(main_turn_region(rr,dict(start_s=None))['reason'],'unknown_start')
        self.assertEqual(main_turn_region(rr,dict(start_frame=2,start_s=2/24))['reason'],'missing_pre_start_context')

    def test_short_target_not_confirmed(self):
        rr=[row(i,0 if i<12 else 40) for i in range(29)]
        self.assertIsNone(main_turn_region(rr,dict(start_frame=12,start_s=.5))['candidate'])


if __name__=='__main__':unittest.main()
