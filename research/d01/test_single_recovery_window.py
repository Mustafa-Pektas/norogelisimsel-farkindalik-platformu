import copy
import unittest
from single_recovery_window import gap_groups, select


class WindowTests(unittest.TestCase):
    def inputs(self, recovery=1):
        rows = [dict(frame_index=i, time_s=i/24, valid=True) for i in range(168)]
        for i in [40, 41] + list(range(42+recovery, 48+recovery)):
            rows[i]['valid'] = False
        c = dict(start_s=21/24, start_frame=21, end_s=None,
                 end_status='unknown_end_data_gap', last_supported_time_s=39/24)
        return rows, dict(raw=dict(candidates=[c]), ema_050=dict(candidates=[]))

    def test_one_recovery_retained_and_first_gap_anchor(self):
        rows, d = self.inputs()
        before = copy.deepcopy((rows, d))
        s = select(rows, d, 24)['selected']
        self.assertEqual((s['gap_start_frame'], s['gap_end_frame']), (40, 48))
        self.assertEqual(s['bridge_valid_frames'], [42])
        self.assertEqual((s['start_frame'], s['end_frame_inclusive']), (0, 75))
        self.assertEqual((rows, d), before)

    def test_two_or_more_recovery_frames_remain_separate(self):
        for count in (2, 3, 8):
            with self.subTest(count=count):
                rows, d = self.inputs(count)
                self.assertEqual(len(gap_groups(rows)), 2)
                self.assertIsNone(select(rows, d, 24)['selected'])

    def test_short_gap_alone_rejected(self):
        rows, d = self.inputs()
        for row in rows[42:]:
            row['valid'] = True
        self.assertIsNone(select(rows, d, 24)['selected'])

    def test_window_cap_preserved(self):
        rows, d = self.inputs()
        for row in rows:
            row['valid'] = row['frame_index'] < 150
        d['raw']['candidates'][0]['last_supported_time_s'] = 149/24
        s = select(rows, d, 24)['selected']
        self.assertEqual(s['frames'], 96)
        self.assertTrue(s['post_context_clipped'])


if __name__ == '__main__':
    unittest.main()
