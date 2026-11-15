from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from isaretli_video import event_label, event_panels


class VideoTimelineTests(unittest.TestCase):
    def test_event_before_boundary_candidate_and_confirmation(self):
        samples = [dict(time_s=4.041667, confirmed_s=4.208333)]
        self.assertEqual(event_label(samples, 4, 'Bekleniyor')[:2], ('Bekleniyor', ''))
        self.assertEqual(event_label(samples, 4.041667, 'Bekleniyor')[:2],
                         ('4,042 sn', 'Aday · doğrulama bekleniyor'))
        self.assertEqual(event_label(samples, 4.208333, 'Bekleniyor')[:2],
                         ('4,042 sn', 'Doğrulama 4,208 sn'))

    def test_late_return_is_marked_outside_window(self):
        event = {'observation_end_s': 5.65, 'optical_flow': {
            'look': {'status': 'observed', 'time_s': 3.666667, 'confirmed_s': 4},
            'stop': {'status': 'unconfirmed', 'events': []},
            'return_to_baseline': {'status': 'unconfirmed', 'events': []},
            'return_after_window': [{'time_s': 6.958333, 'confirmed_s': 7.125}],
        }}
        self.assertEqual(dict(event_panels(event, 6))['Geri döndü'][0], 'Gözlemde doğrulanmadı')
        self.assertEqual(dict(event_panels(event, 7.125))['Geri döndü'][:2],
                         ('Pencere dışı · 6,958 sn', 'Doğrulama 7,125 sn'))


if __name__ == '__main__':
    unittest.main()
