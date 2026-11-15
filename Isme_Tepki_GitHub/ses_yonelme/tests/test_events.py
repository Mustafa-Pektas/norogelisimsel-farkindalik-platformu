import json
import unittest
from pathlib import Path
from sesyon.events import evaluate,sustained


CONFIG=json.loads((Path(__file__).resolve().parents[1]/"config"/"deniz.json").read_text(encoding="utf-8"))


class EventTests(unittest.TestCase):
    def fixture(self):
        call={"id":"test_call", "name":"Test", "start_s":2., "end_s":2.5,
              "timing_source":"synthetic_test", "speaker_target_id":None,
              "speaker_source":"unresolved"}
        rows=[{"time_s":i/24,"rotation_vector":[0,0,0],"pose_change_deg":0 if i/24<3 else 20} for i in range(192)]
        gaze=[{"time_s":i/6,"target":"toy" if i/6<3.34 else "adult_face"} for i in range(48)]
        return call,rows,gaze

    def decide(self,call,rows,gaze):
        return evaluate(call,rows,gaze,CONFIG["settings"],24,8)

    def test_unknown_speaker_is_not_caller(self):
        c,r,g=self.fixture();out=self.decide(c,r,g)
        self.assertEqual(out["status"],"toward_visible_adult")
        self.assertIsNone(out["confidence_probability"])
        self.assertAlmostEqual(out["movement_latency_from_start_s"],1.)

    def test_verified_speaker(self):
        c,r,g=self.fixture();c["speaker_target_id"]="adult_face"
        self.assertEqual(self.decide(c,r,g)["status"],"toward_caller")

    def test_missing_data_never_means_no_response(self):
        c,r,g=self.fixture()
        for x in r: x["rotation_vector"]=None;x["pose_change_deg"]=None
        for x in g: x["target"]="unavailable"
        self.assertEqual(self.decide(c,r,g)["status"],"not_evaluable")

    def test_already_oriented(self):
        c,r,g=self.fixture()
        for x in g:x["target"]="adult_face"
        self.assertEqual(self.decide(c,r,g)["status"],"already_oriented")

    def test_clear_no_movement(self):
        c,r,g=self.fixture()
        for x in r:x["pose_change_deg"]=0
        for x in g:x["target"]="toy"
        self.assertEqual(self.decide(c,r,g)["status"],"no_orientation_observed")

    def test_movement_before_call_not_new_response(self):
        c,r,g=self.fixture()
        for x in r:x["pose_change_deg"]=20 if x["time_s"]>=1.75 else 0
        # Gaze can support an adult target candidate independently, but a
        # pre-call head change must not be reported as response latency.
        self.assertIsNone(self.decide(c,r,g)["movement"])

    def test_early_unrelated_motion_does_not_become_response_latency(self):
        c,r,g=self.fixture()
        for x in r:x["pose_change_deg"]=20 if x["time_s"]>=2.1 else 0
        for x in g:x["target"]="toy" if x["time_s"]<4 else "adult_face"
        out=self.decide(c,r,g)
        self.assertIsNotNone(out["first_pose_deviation"])
        self.assertIsNone(out["movement"])
        self.assertIsNone(out["movement_latency_from_start_s"])

    def test_gaps_do_not_form_a_sustained_run(self):
        self.assertIsNone(sustained([{"time_s":0,"ok":True},{"time_s":.5,"ok":True}],lambda x:x["ok"],.3,.2))

    def test_ambiguous_gaze_cannot_support_positive(self):
        c,r,g=self.fixture()
        for x in g:x["target"]="ambiguous"
        self.assertNotIn(self.decide(c,r,g)["status"],("toward_caller","toward_visible_adult"))


if __name__=="__main__":
    unittest.main()
