"""Veri koruma ve GUI akışı testleri; gerçek kullanıcı etiketlerini değiştirmez."""
import copy
import csv
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
import uuid
import tkinter as tk
from tkinter import ttk

import d01_libvlc as m


class FakePlayer:
    length_ms = 7000
    def __init__(self):
        self._time, self._state = 0, 4
        self.attached = None
    @property
    def time_ms(self): return self._time
    @property
    def state(self): return self._state
    @property
    def seekable(self): return self._state in (3, 4)
    def attach(self, hwnd): self.attached = hwnd
    def play(self): self._state = 3
    def pause(self): self._state = 4
    def stop(self): self._state = 5
    def seek(self, value): self._time = int(value)


class DataTests(unittest.TestCase):
    def setUp(self):
        self.prefix = ".d01_test_" + uuid.uuid4().hex
        self.directory = Path(__file__).resolve().parent
        self.draft_path = self.directory / (self.prefix + ".json")
        self.csv_path = self.directory / (self.prefix + ".csv")
        self.seed = {"schema_version": 1, "video_path": str(m.DEFAULT_VIDEO),
            "behavior_id": "D01", "card_version": "0.2", "response_start_frame": 18,
            "response_start_nominal_s": .750, "fps": 24,
            "response_start_source": "manuel kullanıcı işaretlemesi",
            "candidate_status": "doğrulanmayı bekleyen aday"}
        self.seed["extra_field"] = {"keep": "korunacak"}
        self.seed["marks"] = {name: None for name in m.MARKS}
        self.draft_path.write_text(json.dumps(self.seed, ensure_ascii=False), encoding="utf-8")
        self.store = m.DraftStore(self.draft_path, m.DEFAULT_VIDEO)
        self.fields = ["video_path", "behavior_id", "card_version", "observation_start_s", "observation_end_s",
            "call_start_s", "call_end_s", "response_start_s", "latency_s", "initial_orientation",
            "response_target", "status", "window_complete", "evidence_source", "notes"]
        self.target = {k: "" for k in self.fields}
        self.target.update(video_path=str(m.DEFAULT_VIDEO), behavior_id="D01", card_version="0.2",
            window_complete="false", evidence_source="user_observation", response_target="synthetic target")
        self.target["status"] = "unchanged_status"
        self.other = dict(self.target, video_path=str(m.ROOT / "other.mp4"), notes="other row")
        with self.csv_path.open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=self.fields)
            writer.writeheader()
            writer.writerows([self.other, self.target])

    def tearDown(self):
        # Yalnızca bu testin benzersiz önekiyle oluşturduğu dosyaları sil.
        for path in self.directory.glob(self.prefix + "*"):
            if path.is_file():
                path.unlink()

    def mark(self, value):
        return {"media_time_ms": value, "time_source": m.SOURCES[1],
                "source": "manuel kullanıcı işaretlemesi", "candidate_status": "doğrulanmayı bekleyen aday"}

    def complete(self):
        for name, value in zip(m.MARKS, (100, 500, 300)):
            self.store.set_mark(name, self.mark(value))

    def test_partial_draft_reload_and_candidate_preserved(self):
        self.store.set_mark(m.MARKS[0], self.mark(100))
        loaded = m.DraftStore(self.draft_path, m.DEFAULT_VIDEO)
        self.assertEqual(loaded.data["marks"][m.MARKS[0]]["media_time_ms"], 100)
        self.assertIsNone(loaded.data["marks"][m.MARKS[1]])
        self.assertIsNone(loaded.data["marks"][m.MARKS[2]])
        self.assertEqual(loaded.data["response_start_frame"], 18)
        self.assertEqual(loaded.data["response_start_nominal_s"], .750)
        self.assertEqual(loaded.data["extra_field"], self.seed["extra_field"])
        self.assertEqual(loaded.data["response_start_source"], "manuel kullanıcı işaretlemesi")
        self.assertEqual(loaded.data["candidate_status"], "doğrulanmayı bekleyen aday")

    def test_nominal_candidate_never_substitutes_media_response(self):
        self.store.set_mark(m.MARKS[0], self.mark(100))
        self.store.set_mark(m.MARKS[1], self.mark(500))
        with self.assertRaises(ValueError):
            m.marked_times(self.store.data)

    def test_correction_clear_history(self):
        self.store.set_mark(m.MARKS[2], self.mark(750))
        self.store.set_mark(m.MARKS[2], self.mark(800))
        self.store.set_mark(m.MARKS[2], None)
        loaded = m.DraftStore(self.draft_path, m.DEFAULT_VIDEO)
        self.assertIsNone(loaded.data["marks"][m.MARKS[2]])
        self.assertEqual(loaded.data["response_start_frame"], 18)
        history = self.seed.get('mark_history', [])
        self.assertEqual(loaded.data['mark_history'][:len(history)], history)
        self.assertEqual(len(loaded.data["mark_history"]), len(history) + 3)

    def test_draft_external_edit_is_not_overwritten(self):
        changed = self.draft_path.read_bytes() + b" "
        self.draft_path.write_bytes(changed)
        with self.assertRaises(ValueError):
            self.store.set_mark(m.MARKS[0], self.mark(100))
        self.assertEqual(self.draft_path.read_bytes(), changed)

    def test_csv_backup_and_protected_fields(self):
        self.complete()
        before = self.csv_path.read_bytes()
        backup = m.save_csv(self.csv_path, m.DEFAULT_VIDEO, self.store.data, before)
        self.assertEqual(backup.read_bytes(), before)
        raw, _, fields, rows, index = m.csv_state(self.csv_path, m.DEFAULT_VIDEO)
        self.assertTrue(raw.startswith(b"\xef\xbb\xbf"))
        self.assertEqual(fields, self.fields + list(m.CSV_V2))
        self.assertEqual({key: rows[0][key] for key in self.fields}, self.other)
        self.assertEqual(rows[0]['annotation_schema_version'], '1')
        self.assertEqual(rows[index]['annotation_schema_version'], '2')
        self.assertEqual(rows[index]['response_end_s'], '')
        self.assertEqual(float(rows[index]['latency_from_call_start_s']), .200)
        self.assertEqual(float(rows[index]['latency_from_call_end_s']), -.200)
        changed_fields = {*m.MARKS, "latency_s", "evidence_source", "notes"}
        for name in self.fields:
            if name not in changed_fields:
                self.assertEqual(rows[index][name], self.target[name], name)
        self.assertEqual(float(rows[index]["latency_s"]), -.200)
        self.assertIn("negatif gecikme", rows[index]["notes"])
        self.assertIn("user_observation", rows[index]["evidence_source"])
        self.assertIn("manual_time_marking", rows[index]["evidence_source"])

    def test_optional_end_order_and_details_roundtrip(self):
        self.complete()
        self.assertIsNone(m.marked_times(self.store.data)['response_end_s'])
        before = self.draft_path.read_bytes()
        with self.assertRaises(ValueError):
            self.store.set_mark('response_end_s', self.mark(299))
        self.assertEqual(self.draft_path.read_bytes(), before)
        with self.assertRaises(ValueError):
            self.store.set_mark('call_end_s', self.mark(99))
        self.store.set_mark('response_end_s', self.mark(900))
        details = dict(zip(m.DETAILS, ['solda', 'anne olabilir', 'hedef kesin değil', 'kısa klip']))
        self.store.set_details(details)
        loaded = m.DraftStore(self.draft_path, m.DEFAULT_VIDEO)
        self.assertEqual(loaded.data['schema_version'], 2)
        self.assertEqual(loaded.data['manual_details'], details)
        self.assertEqual(m.marked_times(loaded.data)['response_end_s'], .900)
        m.save_csv(self.csv_path, m.DEFAULT_VIDEO, loaded.data, self.csv_path.read_bytes())
        _, _, fields, rows, index = m.csv_state(self.csv_path, m.DEFAULT_VIDEO)
        self.assertEqual(rows[index]['response_end_s'], '0.900000')
        self.assertEqual(rows[index]['response_target'], self.target['response_target'])
        self.assertEqual(rows[index]['manual_observed_target'], 'anne olabilir')
        self.assertEqual(json.loads(rows[index]['time_marks_json']), loaded.data['marks'])
        m.save_csv(self.csv_path, m.DEFAULT_VIDEO, loaded.data, self.csv_path.read_bytes())
        self.assertEqual(m.csv_state(self.csv_path, m.DEFAULT_VIDEO)[2], fields)

    def test_legacy_requested_marks_read_without_rewrite_but_not_exported_as_actual(self):
        seed = copy.deepcopy(self.seed)
        seed['marks'] = {name: dict(self.mark(value), time_source=m.SOURCES[0])
                         for name, value in zip(m.REQUIRED_MARKS, [0, 650, 750])}
        self.draft_path.write_text(json.dumps(seed), encoding='utf-8')
        before = self.draft_path.read_bytes()
        loaded = m.DraftStore(self.draft_path, m.DEFAULT_VIDEO)
        self.assertEqual(self.draft_path.read_bytes(), before)
        self.assertIsNone(loaded.data['marks']['response_end_s'])
        with self.assertRaisesRegex(ValueError, 'seek'):
            m.marked_times(loaded.data)
        with self.assertRaises(ValueError):
            loaded.set_mark('call_start_s', seed['marks']['call_start_s'])

    def test_reported_time_never_substitutes_requested_or_unknown(self):
        player = FakePlayer()
        player._time = 650
        with self.assertRaisesRegex(ValueError, 'seek'):
            m.capture_mark(player, 750)
        actual = m.capture_mark(player)
        self.assertEqual(actual['media_time_ms'], 650)
        self.assertIsNone(actual['requested_media_time_ms_at_mark'])
        self.assertEqual(m.capture_mark(player, 650)['requested_media_time_ms_at_mark'], 650)
        for state, value in [(3, 650), (4, -1), (4, 8000)]:
            player._state, player._time = state, value
            with self.assertRaises(ValueError): m.capture_mark(player)

    def test_original_paths_are_write_protected(self):
        for path in [m.DEFAULT_CSV, m.DEFAULT_DRAFT]:
            with self.assertRaisesRegex(ValueError, 'çalışma kopyası'):
                m.require_working_copy(path)

    def test_csv_changed_since_preview_rejected(self):
        self.complete()
        before = self.csv_path.read_bytes()
        changed = before + b"\r\n"
        self.csv_path.write_bytes(changed)
        with self.assertRaises(ValueError):
            m.save_csv(self.csv_path, m.DEFAULT_VIDEO, self.store.data, before)
        self.assertEqual(self.csv_path.read_bytes(), changed)

    def test_loop_bounds_and_end_restart(self):
        loop, player = m.SegmentLoop(), FakePlayer()
        with self.assertRaises(ValueError): loop.configure(100, 150, 7000)
        with self.assertRaises(ValueError): loop.configure(700, 100, 7000)
        loop.configure(100, 600, 7000)
        loop.enabled = True
        player._time = 650
        self.assertTrue(loop.tick(player))
        self.assertEqual(player.time_ms, 100)
        player._state = 6
        player._time = 7000
        self.assertFalse(loop.tick(player))
        self.assertTrue(loop.pending_restart)
        self.assertTrue(loop.tick(player))
        self.assertEqual(player.time_ms, 100)

    def test_gui_mark_seek_reload_loop_and_preview_cancel_confirm(self):
        root, player = tk.Tk(), FakePlayer()
        root.withdraw()
        app = None
        try:
            app = m.AnnotationApp(root, player, self.store, self.csv_path)
            root.update()
            if not app.ready:
                root.after_cancel(app.timer)
                app.poll()
            self.assertTrue(app.ready)
            self.assertIsNotNone(player.attached)
            before = self.csv_path.read_bytes()
            app.seek_candidate()
            self.assertEqual(app.requested_cursor, 750)
            self.assertIsNone(self.store.data["marks"][m.MARKS[2]])
            for key, value in (("c", 100), ("b", 500), ("r", 300)):
                app.seek(value)
                app.on_key(SimpleNamespace(keysym=key, widget=root))
            self.assertEqual(self.csv_path.read_bytes(), before)
            loaded = m.DraftStore(self.draft_path, m.DEFAULT_VIDEO)
            self.assertEqual(loaded.data["response_start_frame"], 18)
            self.assertEqual(loaded.data["marks"][m.MARKS[2]]["media_time_ms"], 300)
            self.assertEqual(loaded.data["marks"][m.MARKS[2]]["time_source"], m.SOURCES[1])
            app.seek(750)
            player._time = 300
            with self.assertRaisesRegex(ValueError, 'seek'):
                app.mark('response_start_s')
            self.assertEqual(self.store.data['marks']['response_start_s']['media_time_ms'], 300)
            self.assertIn('− çağrı başlangıcı: 0.200', app.latencies.get())
            self.assertIn('− çağrı bitişi: -0.200', app.latencies.get())
            app.seek(900)
            app.on_key(SimpleNamespace(keysym='e', widget=root))
            self.assertEqual(self.store.data['marks']['response_end_s']['media_time_ms'], 900)
            app.on_key(SimpleNamespace(keysym='4', widget=root))
            self.assertIsNone(self.store.data['marks']['response_end_s'])
            app.detail_vars['observed_target'].set('belirsiz hedef')
            app.save_draft()
            self.assertEqual(m.DraftStore(self.draft_path, m.DEFAULT_VIDEO).data['manual_details']['observed_target'], 'belirsiz hedef')
            app.loop_start.set("0.100")
            app.loop_end.set("0.600")
            app.toggle_loop()
            self.assertTrue(app.loop.enabled)
            with self.assertRaises(ValueError): app.mark(m.MARKS[0])
            app.toggle_loop()
            app.show_preview()
            root.update()
            self.assertEqual(self.csv_path.read_bytes(), before)
            buttons = [child for child in app.preview.winfo_children() if isinstance(child, ttk.Button)]
            buttons[1].invoke()
            self.assertIsNone(app.preview)
            self.assertEqual(self.csv_path.read_bytes(), before)
            app.show_preview()
            root.update()
            buttons = [child for child in app.preview.winfo_children() if isinstance(child, ttk.Button)]
            buttons[0].invoke()
            self.assertIsNone(app.preview)
            _, _, _, rows, index = m.csv_state(self.csv_path, m.DEFAULT_VIDEO)
            self.assertEqual(rows[index]["status"], "unchanged_status")
            self.assertEqual(float(rows[index]["latency_s"]), -.200)
        finally:
            if app is not None:
                app.close()
            else:
                root.destroy()


if __name__ == "__main__":
    unittest.main(verbosity=2)
