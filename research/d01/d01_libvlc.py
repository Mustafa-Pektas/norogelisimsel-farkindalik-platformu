"""Tek LibVLC oynatıcısıyla sesli D01 insan etiketleme; model içermez."""
from __future__ import annotations
import argparse
import copy
import csv
import ctypes as ct
from datetime import datetime, timezone
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time
import tkinter as tk
from tkinter import messagebox, ttk

ROOT = Path(os.environ.get("D01_DATA_ROOT", str(Path(__file__).resolve().parents[2]))).resolve()
DEFAULT_VIDEO = ROOT / "videolar/_root___context___/context___instruction___prompt_Continue_20261011025647_9.mp4"
DEFAULT_CSV = ROOT / "etiketler/d01_ilk_ornek.csv"
DEFAULT_DRAFT = ROOT / "etiketler/d01_ilk_ornek_taslak.json"
VLC_DIR = Path(r"C:\Program Files\VideoLAN\VLC")
REQUIRED_MARKS = ("call_start_s", "call_end_s", "response_start_s")
MARKS = (*REQUIRED_MARKS, "response_end_s")
LABELS = dict(zip(MARKS, ("Çağrı başlangıcı", "Çağrı bitişi", "Hareket başlangıcı", "Hareket bitişi (isteğe bağlı)")))
DETAILS = {"speaker_position": "Seslenen kişinin görüntüdeki konumu",
           "observed_target": "Çocuğun yöneldiği hedef (kullanıcı beyanı)",
           "uncertainty": "Belirsizlik", "review_notes": "İnceleme notu"}
CSV_V2 = ("annotation_schema_version", "response_end_s", "latency_from_call_start_s",
          "latency_from_call_end_s", "time_marks_json", *("manual_" + key for key in DETAILS))
SOURCES = ("libvlc_requested_media_position", "libvlc_reported_media_time")
NOTE_START, NOTE_END = "[D01_LIBVLC_MANUEL]", "[/D01_LIBVLC_MANUEL]"

def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")

def require_working_copy(path):
    if Path(path).resolve() in (DEFAULT_CSV.resolve(), DEFAULT_DRAFT.resolve()):
        raise ValueError("Asıl etiket dosyasına yazılamaz; ayrı çalışma kopyası kullanın (--csv / --draft).")

def validate_order(marks):
    for start, end in (("call_start_s", "call_end_s"), ("response_start_s", "response_end_s")):
        if marks.get(start) is not None and marks.get(end) is not None:
            if marks[end]["media_time_ms"] < marks[start]["media_time_ms"]:
                raise ValueError(f"{LABELS[end]} {LABELS[start].lower()}ndan önce olamaz.")

def capture_mark(player, requested_ms=None):
    reported = player.time_ms
    if player.state != 4 or type(reported) is not int or reported < 0 or player.length_ms <= 0 or reported > player.length_ms:
        raise ValueError("Güvenilir duraklatılmış medya zamanı alınamadı; oynatıp duraklatın ve yeniden deneyin.")
    if requested_ms is not None and requested_ms != reported:
        raise ValueError("İstenen seek konumu henüz bildirilmedi. Oynatıp duraklatın; bildirilen zamanı inceleyerek işaretleyin.")
    return {"media_time_ms": reported, "time_source": SOURCES[1],
            "reported_media_time_ms_at_mark": reported, "requested_media_time_ms_at_mark": requested_ms,
            "source": "manuel kullanıcı işaretlemesi", "candidate_status": "doğrulanmayı bekleyen aday"}

def atomic_write(path, payload, expected=None):
    if expected is not None and path.read_bytes() != expected:
        raise ValueError(f"Dosya dışarıdan değişti; yeniden açın: {path}")
    temp = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".d01_", suffix=".tmp", delete=False) as stream:
            temp = Path(stream.name)
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        if expected is not None and path.read_bytes() != expected:
            raise ValueError("Dosya yazma sırasında değişti; işlem iptal edildi.")
        os.replace(temp, path)
        temp = None
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)

class DraftStore:
    """İlk nominal adayı ve tanınmayan alanları korur."""
    def __init__(self, path, video):
        self.path, self.video = Path(path), Path(video).resolve()
        self.raw = self.path.read_bytes()
        self.data = json.loads(self.raw.decode("utf-8-sig"))
        if not isinstance(self.data, dict):
            raise ValueError("Taslak bir JSON nesnesi olmalı.")
        if self.data.get("schema_version", 1) not in (1, 2):
            raise ValueError("Taslak schema_version desteklenmiyor.")
        details = self.data.get("manual_details", {})
        if not isinstance(details, dict) or any(not isinstance(details.get(key, ""), str) for key in DETAILS):
            raise ValueError("manual_details alanları metin olmalı.")
        if Path(self.data.get("video_path", "")).resolve() != self.video:
            raise ValueError("Taslak farklı videoya ait; üzerine yazılmayacak.")
        if self.data.get("behavior_id") != "D01" or self.data.get("card_version") != "0.2":
            raise ValueError("Taslak D01 / kart 0.2 olmalı.")
        if not isinstance(self.data.setdefault("marks", {}), dict):
            raise ValueError("marks alanı bir nesne olmalı.")
        for name in MARKS:
            self.data["marks"].setdefault(name, None)
            mark = self.data["marks"][name]
            if mark is not None:
                validate_mark(mark)

    def commit(self, data):
        require_working_copy(self.path)
        updated = copy.deepcopy(data)
        validate_order(updated["marks"])
        updated["schema_version"] = 2
        updated["updated_at_utc"] = utc_now()
        payload = (json.dumps(updated, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        atomic_write(self.path, payload, self.raw)
        self.data, self.raw = updated, payload

    def set_mark(self, name, value):
        if name not in MARKS:
            raise ValueError("Bilinmeyen işaret.")
        if value is not None:
            validate_mark(value)
            if value["time_source"] != SOURCES[1]:
                raise ValueError("Yeni işaret yalnız oynatıcının bildirdiği medya zamanından alınabilir.")
        data = copy.deepcopy(self.data)
        data.setdefault("mark_history", []).append({
            "field": name, "previous": data["marks"][name], "new": value, "at_utc": utc_now()})
        data["marks"][name] = value
        self.commit(data)

    def set_details(self, details):
        if set(details) != set(DETAILS) or any(not isinstance(value, str) for value in details.values()):
            raise ValueError("Yön ve belirsizlik alanları kullanıcı metni olmalı.")
        data = copy.deepcopy(self.data)
        data["manual_details"] = dict(details)
        self.commit(data)

    def set_loop(self, start, end):
        data = copy.deepcopy(self.data)
        loop = data.setdefault("loop", {})
        if not isinstance(loop, dict):
            raise ValueError("loop alanı bir nesne olmalı.")
        loop.update(start_ms=start, end_ms=end)
        self.commit(data)

def validate_mark(mark):
    if not isinstance(mark, dict) or mark.get("time_source") not in SOURCES:
        raise ValueError("İşaretin medya zaman kaynağı belirsiz; otomatik dönüştürülmez.")
    if type(mark.get("media_time_ms")) is not int or mark["media_time_ms"] < 0:
        raise ValueError("İşaretin medya zamanı geçersiz.")

class LibVLCPlayer:
    """Ses ve video tek media_player nesnesinden oynatılır."""
    def __init__(self, video, vlc_dir=VLC_DIR, *, silent_check=False):
        self.instance = self.media = self.player = self.dll_directory = None
        try:
            self.dll_directory = os.add_dll_directory(str(vlc_dir))
            self.lib = ct.CDLL(str(vlc_dir / "libvlc.dll"))
            signatures = {
                "libvlc_get_version": (ct.c_char_p, []),
                "libvlc_new": (ct.c_void_p, [ct.c_int, ct.POINTER(ct.c_char_p)]),
                "libvlc_release": (None, [ct.c_void_p]),
                "libvlc_media_new_path": (ct.c_void_p, [ct.c_void_p, ct.c_char_p]),
                "libvlc_media_release": (None, [ct.c_void_p]),
                "libvlc_media_player_new_from_media": (ct.c_void_p, [ct.c_void_p]),
                "libvlc_media_player_release": (None, [ct.c_void_p]),
                "libvlc_media_player_set_hwnd": (None, [ct.c_void_p, ct.c_void_p]),
                "libvlc_media_player_play": (ct.c_int, [ct.c_void_p]),
                "libvlc_media_player_stop": (None, [ct.c_void_p]),
                "libvlc_media_player_set_pause": (None, [ct.c_void_p, ct.c_int]),
                "libvlc_media_player_get_time": (ct.c_int64, [ct.c_void_p]),
                "libvlc_media_player_set_time": (None, [ct.c_void_p, ct.c_int64]),
                "libvlc_media_player_get_length": (ct.c_int64, [ct.c_void_p]),
                "libvlc_media_player_get_state": (ct.c_int, [ct.c_void_p]),
                "libvlc_media_player_is_seekable": (ct.c_int, [ct.c_void_p]),
                "libvlc_audio_set_mute": (None, [ct.c_void_p, ct.c_int]),
                "libvlc_video_set_mouse_input": (None, [ct.c_void_p, ct.c_uint]),
                "libvlc_video_set_key_input": (None, [ct.c_void_p, ct.c_uint]),
            }
            for name, (result, arguments) in signatures.items():
                function = getattr(self.lib, name)
                function.restype, function.argtypes = result, arguments
            options = [b"--ignore-config", b"--no-plugins-cache", b"--quiet",
                       b"--no-video-title-show", b"--avcodec-hw=none"]
            if silent_check:
                options += [b"--aout=dummy", b"--vout=dummy"]
            flags = (ct.c_char_p * len(options))(*options)
            self.instance = self.lib.libvlc_new(len(flags), flags)
            if not self.instance:
                raise ValueError("LibVLC başlatılamadı.")
            self.media = self.lib.libvlc_media_new_path(self.instance, str(Path(video).resolve()).encode("utf-8"))
            if not self.media:
                raise ValueError("Medya açılamadı.")
            self.player = self.lib.libvlc_media_player_new_from_media(self.media)
            if not self.player:
                raise ValueError("Oynatıcı oluşturulamadı.")
            self.lib.libvlc_video_set_mouse_input(self.player, 0)
            self.lib.libvlc_video_set_key_input(self.player, 0)
        except BaseException:
            self.close()
            raise

    @property
    def version(self):
        return self.lib.libvlc_get_version().decode()
    @property
    def time_ms(self):
        return int(self.lib.libvlc_media_player_get_time(self.player))
    @property
    def length_ms(self):
        return int(self.lib.libvlc_media_player_get_length(self.player))
    @property
    def state(self):
        return int(self.lib.libvlc_media_player_get_state(self.player))
    @property
    def seekable(self):
        return bool(self.lib.libvlc_media_player_is_seekable(self.player))
    def attach(self, hwnd):
        self.lib.libvlc_media_player_set_hwnd(self.player, hwnd)
    def play(self):
        if self.lib.libvlc_media_player_play(self.player) != 0:
            raise ValueError("Oynatma başlatılamadı.")
    def pause(self):
        self.lib.libvlc_media_player_set_pause(self.player, 1)
    def stop(self):
        self.lib.libvlc_media_player_stop(self.player)
    def seek(self, value):
        if not self.seekable:
            raise ValueError("Medya henüz aranabilir değil.")
        self.lib.libvlc_media_player_set_time(self.player, int(value))
    def mute(self):
        self.lib.libvlc_audio_set_mute(self.player, 1)
    def close(self):
        if self.player:
            self.lib.libvlc_media_player_stop(self.player)
            self.lib.libvlc_media_player_release(self.player)
            self.player = None
        if self.media:
            self.lib.libvlc_media_release(self.media)
            self.media = None
        if self.instance:
            self.lib.libvlc_release(self.instance)
            self.instance = None
        if self.dll_directory:
            self.dll_directory.close()
            self.dll_directory = None

def csv_state(path, video):
    raw = path.read_bytes()
    encoding = "utf-8-sig" if raw.startswith(b"\xef\xbb\xbf") else "utf-8"
    reader = csv.DictReader(io.StringIO(raw.decode(encoding), newline=""))
    fields = reader.fieldnames
    required = {"video_path", "behavior_id", "card_version", *REQUIRED_MARKS, "latency_s", "status", "evidence_source", "notes"}
    if not fields or not required.issubset(fields) or len(set(fields)) != len(fields):
        raise ValueError("CSV başlıkları eksik veya yinelenmiş.")
    rows = list(reader)
    if any(None in row or any(value is None for value in row.values()) for row in rows):
        raise ValueError("CSV alan sayısı uyuşmazlığı.")
    if any(row.get("annotation_schema_version", "") not in ("", "1", "2") for row in rows):
        raise ValueError("CSV annotation_schema_version desteklenmiyor.")
    matches = []
    for index, row in enumerate(rows):
        candidate = Path(row["video_path"])
        if not candidate.is_absolute():
            candidate = ROOT / candidate
        if candidate.resolve() == video.resolve() and row["behavior_id"] == "D01" and row["card_version"] == "0.2":
            matches.append(index)
    if len(matches) != 1:
        raise ValueError("CSV'de bu video için tek bir D01/0.2 satırı olmalı.")
    return raw, encoding, fields, rows, matches[0]

def marked_times(data):
    marks = data["marks"]
    if any(marks.get(name) is None for name in REQUIRED_MARKS):
        raise ValueError("Üç medya işareti gerekli. R=18 nominal adayı medya zamanına otomatik çevrilmez.")
    for name in MARKS:
        if marks.get(name) is not None:
            validate_mark(marks[name])
            if marks[name]["time_source"] != SOURCES[1]:
                raise ValueError(f"{name}: eski istenen seek konumu doğrulanmış medya zamanı değildir; yeniden işaretleyin.")
    validate_order(marks)
    values = {name: None if marks.get(name) is None else marks[name]["media_time_ms"] / 1000 for name in MARKS}
    if values["call_start_s"] > values["call_end_s"]:
        raise ValueError("Çağrı başlangıcı bitişten sonra olamaz.")
    if values["response_start_s"] < values["call_start_s"]:
        raise ValueError("Dönüş çağrıdan önce işaretli; zamanları yeniden inceleyin.")
    values["latency_s"] = (marks["response_start_s"]["media_time_ms"] - marks["call_end_s"]["media_time_ms"]) / 1000
    values["latency_from_call_end_s"] = values["latency_s"]
    values["latency_from_call_start_s"] = (marks["response_start_s"]["media_time_ms"] - marks["call_start_s"]["media_time_ms"]) / 1000
    return values

def save_csv(path, video, data, expected):
    require_working_copy(path)
    values = marked_times(data)
    raw, encoding, fields, rows, index = csv_state(path, video)
    if raw != expected:
        raise ValueError("CSV önizlemeden sonra değişti; yeniden önizleyin.")
    row = rows[index]
    for name in CSV_V2:
        if name not in fields:
            fields.append(name)
            for old_row in rows:
                old_row[name] = "1" if name == "annotation_schema_version" else ""
    row["annotation_schema_version"] = "2"
    row["time_marks_json"] = json.dumps(data["marks"], ensure_ascii=False)
    for key in DETAILS:
        row["manual_" + key] = data.get("manual_details", {}).get(key, "")
    for name, value in values.items():
        row[name] = "" if value is None else f"{value:.6f}"
    sources = [s.strip() for s in row["evidence_source"].split(";") if s.strip()]
    for source in ("user_observation", "manual_time_marking", "libvlc_media_time"):
        if source not in sources:
            sources.append(source)
    row["evidence_source"] = ";".join(sources)
    previous = re.sub(re.escape(NOTE_START) + r".*?" + re.escape(NOTE_END), "", row["notes"], flags=re.DOTALL).strip()
    detail = "; ".join(f"{name}: {data['marks'][name]['time_source']}" for name in MARKS if data['marks'].get(name) is not None)
    timing = "Yanıt çağrı bitmeden başladı; negatif gecikme korundu." if values["latency_s"] < 0 else "Yanıt çağrı bitmeden başlamadı."
    row["notes"] = (previous + " " + NOTE_START + " " + utc_now() + "; " + detail + "; " + timing
                    + f" İlk aday: kare {data.get('response_start_frame')}, nominal {data.get('response_start_nominal_s')} s; medya/kare PTS eşleşmesi doğrulanmadı."
                    + " Manuel medya işaretleri önceki hazırlık notundaki zaman bekleme bilgisini günceller. status değiştirilmedi; insan ses-görüntü doğrulaması otomatik kabul edilmedi. " + NOTE_END).strip()
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
    backup = path.with_name(path.stem + ".yedek_" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ") + path.suffix)
    if path.read_bytes() != raw:
        raise ValueError("CSV dışarıdan değişti.")
    shutil.copy2(path, backup)
    if backup.read_bytes() != raw:
        raise ValueError("Yedek doğrulanamadı; CSV değiştirilmedi.")
    atomic_write(path, output.getvalue().encode(encoding), raw)
    return backup

def seconds_to_ms(text):
    value = float(str(text).replace(",", "."))
    if not math.isfinite(value) or value < 0:
        raise ValueError("Sonlu, negatif olmayan bir saniye değeri girin.")
    return round(value * 1000)

class SegmentLoop:
    def __init__(self):
        self.start_ms = self.end_ms = None
        self.enabled = False
        self.restarts = 0
        self.pending_restart = False
    def configure(self, start, end, length):
        if not 0 <= start < end <= length:
            raise ValueError("Tekrar: 0 ≤ başlangıç < bitiş ≤ klip süresi.")
        if end-start < 100:
            raise ValueError("Tekrar en az 0.100 s olmalı; örnek hassasiyetinde kesme yoktur.")
        self.start_ms, self.end_ms = start, end
    def tick(self, player):
        if not self.enabled:
            return False
        if self.pending_restart:
            if player.seekable:
                player.seek(self.start_ms)
                player.play()
                self.pending_restart = False
                self.restarts += 1
                return True
            return False
        if player.time_ms >= self.end_ms or player.state == 6:
            if player.seekable:
                player.seek(self.start_ms)
                player.play()
                self.restarts += 1
                return True
            self.pending_restart = True
            player.play()
        return False

class AnnotationApp:
    def __init__(self, root, player, draft, csv_path):
        self.root, self.player, self.draft, self.csv_path = root, player, draft, csv_path
        self.ready, self.paused, self.closing = False, True, False
        self.pending_seek, self.requested_cursor, self.preview = 0, None, None
        self.loop = SegmentLoop()
        root.title("D01 — Sesli manuel etiketleme / LibVLC")
        root.geometry(f"{min(1100, root.winfo_screenwidth()-60)}x{min(920, root.winfo_screenheight()-100)}")
        self.notice = tk.StringVar(value="Açılıyor; ilk karede duraklatılacak…")
        self.clock, self.candidate, self.latencies = tk.StringVar(), tk.StringVar(), tk.StringVar()
        self.detail_vars = {key: tk.StringVar(value=draft.data.get("manual_details", {}).get(key, "")) for key in DETAILS}
        self.mark_labels = {name: tk.StringVar() for name in MARKS}
        self.seek_value, self.goto_value = tk.DoubleVar(value=0), tk.StringVar(value="0.000")
        self.step_value = tk.StringVar(value="0.050")
        saved = draft.data.get("loop", {})
        self.loop_start = tk.StringVar(value="" if saved.get("start_ms") is None else f"{saved['start_ms']/1000:.3f}")
        self.loop_end = tk.StringVar(value="" if saved.get("end_ms") is None else f"{saved['end_ms']/1000:.3f}")
        ttk.Label(root, textvariable=self.candidate, wraplength=1060).pack(fill="x", padx=8, pady=5)
        self.video_frame = tk.Frame(root, bg="black", height=240, takefocus=False)
        self.video_frame.pack(fill="both", expand=True, padx=8)
        ttk.Label(root, textvariable=self.clock).pack(fill="x", padx=8, pady=4)
        ttk.Label(root, text="Milisaniye gösterimi hassasiyet garantisi değildir. Kare PTS eşleşmesi doğrulanmadı.").pack(fill="x", padx=8)
        self.slider = ttk.Scale(root, from_=0, to=7, variable=self.seek_value)
        self.slider.pack(fill="x", padx=8)
        self.dragging = False
        self.slider.bind("<ButtonPress-1>", lambda event: setattr(self, "dragging", True))
        self.slider.bind("<ButtonRelease-1>", self.slider_seek)
        row = self.row()
        self.button(row, "Oynat / duraklat [Space]", self.toggle_play)
        self.button(row, "Başa [0]", lambda: self.seek(0))
        self.button(row, "− zaman [A]", lambda: self.shift(-1))
        self.button(row, "+ zaman [D]", lambda: self.shift(1))
        ttk.Label(row, text="Adım (s):").pack(side="left")
        ttk.Entry(row, width=7, textvariable=self.step_value).pack(side="left")
        row = self.row()
        ttk.Label(row, text="Medya konumu (s):").pack(side="left")
        ttk.Entry(row, textvariable=self.goto_value, width=10).pack(side="left")
        self.button(row, "Konuma git", lambda: self.seek(seconds_to_ms(self.goto_value.get())))
        self.button(row, "R adayına yaklaşık git (nominal)", self.seek_candidate)
        ttk.Label(root, text="A/D zaman aramasıdır; hassas geri kare adımı yoktur. İlk nominal R adayı ayrı korunur.").pack(fill="x", padx=8)
        row = self.row()
        ttk.Label(row, text="Kısa tekrar (s):").pack(side="left")
        ttk.Entry(row, textvariable=self.loop_start, width=8).pack(side="left")
        ttk.Entry(row, textvariable=self.loop_end, width=8).pack(side="left")
        self.button(row, "Başlangıç ← imleç [", lambda: self.loop_boundary(True))
        self.button(row, "Bitiş ← imleç ]", lambda: self.loop_boundary(False))
        self.button(row, "Tekrar aç/kapat [L]", self.toggle_loop)
        ttk.Label(root, text="Tekrar medya saatiyle denetlenir; ses tamponları nedeniyle örnek hassasiyetinde kesme garantisi yoktur.").pack(fill="x", padx=8)
        for name, shortcut, clear in zip(MARKS, "CBRE", "1234"):
            row = self.row()
            self.button(row, f"{LABELS[name]} [{shortcut}]", lambda name=name: self.mark(name))
            self.button(row, f"Sil [{clear}]", lambda name=name: self.clear_mark(name))
            ttk.Label(row, textvariable=self.mark_labels[name]).pack(side="left", padx=8)
        ttk.Label(root, textvariable=self.latencies, wraplength=1060).pack(fill="x", padx=8)
        for key, label in DETAILS.items():
            row = self.row()
            ttk.Label(row, text=label + ":").pack(side="left")
            ttk.Entry(row, textvariable=self.detail_vars[key]).pack(side="left", fill="x", expand=True)
        _, _, _, legacy_rows, legacy_index = csv_state(csv_path, draft.video)
        ttk.Label(root, text=f"Geçmiş CSV hedefi: {legacy_rows[legacy_index].get('response_target', '')!r}; doğrulanmış sayılmaz. "
                  "Yön/not bilgileri T veya CSV önizleme ile kaydedilir.", wraplength=1060).pack(fill="x", padx=8)
        row = self.row()
        self.button(row, "Taslağı kaydet [T]", self.save_draft)
        self.button(row, "CSV önizle [S]", self.show_preview)
        self.button(row, "Kısayol odağı", root.focus_set)
        self.button(row, "Çık [Q]", self.close)
        ttk.Label(root, text="İşaretler anında çalışma taslağına kaydolur; CSV önizleme/onay ister, status korunur. "
                  "Kısa klip dışında gözlenmeyen süre için tepki yok sonucu verilmez.", wraplength=1060).pack(fill="x", padx=8)
        ttk.Label(root, textvariable=self.notice, wraplength=1060).pack(fill="x", padx=8, pady=5)
        root.bind("<KeyPress>", self.on_key)
        root.protocol("WM_DELETE_WINDOW", self.close)
        self.refresh_marks()
        root.update_idletasks()
        player.attach(self.video_frame.winfo_id())
        player.play()
        self.open_deadline = time.monotonic()+20
        self.timer = root.after(30, self.poll)

    def row(self):
        row = ttk.Frame(self.root)
        row.pack(fill="x", padx=8, pady=3)
        return row
    def button(self, parent, label, action):
        ttk.Button(parent, text=label, command=lambda: self.guard(action), takefocus=False).pack(side="left", padx=2)
    def guard(self, action):
        try:
            action()
        except (OSError, ValueError, csv.Error, json.JSONDecodeError) as exc:
            self.notice.set(f"İşlem yapılmadı: {exc}")
            print(f"HATA: {exc}", file=sys.stderr)
    def require_ready(self):
        if not self.ready:
            raise ValueError("Oynatıcı henüz hazır değil.")
        if self.preview is not None:
            raise ValueError("Önizlemeyi önce kapatın.")
    def cursor(self):
        self.require_ready()
        if not self.paused:
            raise ValueError("Önce duraklatın; oynarken tuşa basma anı işaretlenmez.")
        if self.pending_seek is not None:
            raise ValueError("Arama tamamlanmasını bekleyin.")
        value = self.requested_cursor if self.requested_cursor is not None else self.player.time_ms
        if not 0 <= value <= self.player.length_ms:
            raise ValueError("Geçerli medya saati okunamadı.")
        return value
    def slider_seek(self, event):
        value = min(self.player.length_ms-1, round(self.seek_value.get()*1000))
        self.dragging = False
        self.guard(lambda: self.seek(value))
    def seek(self, value):
        self.require_ready()
        if not 0 <= value < self.player.length_ms:
            raise ValueError("Arama konumu klibin içinde olmalı.")
        self.loop.enabled, self.loop.pending_restart = False, False
        self.paused = True
        self.player.pause()
        self.requested_cursor = int(value)
        if self.player.seekable:
            self.player.seek(value)
            self.pending_seek = None
        else:
            self.pending_seek = int(value)
            self.player.play()
        self.goto_value.set(f"{value/1000:.3f}")
        self.notice.set("İstenen medya konumu seçildi; LibVLC bildirimi ayrıca gösterilir. Kare eşitliği varsayılmaz.")
    def seek_candidate(self):
        nominal = self.draft.data.get("response_start_nominal_s")
        if nominal is None:
            raise ValueError("Nominal aday zamanı bilinmiyor; otomatik sıfır atanmaz.")
        self.seek(seconds_to_ms(nominal))
        self.notice.set("Nominal adaya yaklaşık arama yapıldı; medya/kare eşleşmesi doğrulanmadı. Yeni R işareti oluşturulmadı.")
    def shift(self, direction):
        step = seconds_to_ms(self.step_value.get())
        if step < 1:
            raise ValueError("Adım en az 0.001 s olmalı.")
        self.seek(max(0, min(self.player.length_ms-1, self.cursor()+direction*step)))
    def toggle_play(self):
        self.require_ready()
        self.loop.enabled, self.loop.pending_restart = False, False
        if self.paused:
            self.requested_cursor, self.pending_seek = None, None
            self.player.play()
            self.paused = False
        else:
            self.player.pause()
            self.paused = True
            self.requested_cursor = None
    def mark(self, name):
        self.require_ready()
        if not self.paused or self.loop.enabled or self.pending_seek is not None:
            raise ValueError("İşaretlemek için oynatmayı/tekrarı durdurun ve medya zamanını bekleyin.")
        self.draft.set_mark(name, capture_mark(self.player, self.requested_cursor))
        self.refresh_marks()
        self.notice.set("Medya işareti taslağa kaydedildi; ilk nominal R=18 korundu. CSV değişmedi.")
    def clear_mark(self, name):
        self.require_ready()
        self.draft.set_mark(name, None)
        self.refresh_marks()
        self.notice.set("Medya işareti silindi; geçmiş ve ilk nominal aday korundu.")
    def refresh_marks(self):
        data = self.draft.data
        nominal = data.get('response_start_nominal_s')
        nominal_text = 'bilinmiyor' if nominal is None else f'{nominal:.3f} s'
        self.candidate.set(
            f"Korunan R adayı: 0 tabanlı kare {data.get('response_start_frame')}; nominal "
            f"{nominal_text} / FPS {data.get('fps')}. "
            f"Kaynak: {data.get('response_start_source')}. {data.get('candidate_status')}. "
            "Medya zamanına otomatik eşitlenmez.")
        for name in MARKS:
            mark = data["marks"][name]
            self.mark_labels[name].set("Medya işareti yok" if mark is None else
                f"{mark['media_time_ms']/1000:.3f} s | {mark['time_source']}")
        try:
            values = marked_times(data)
            self.latencies.set(f"Hareket başlangıcı − çağrı başlangıcı: {values['latency_from_call_start_s']:.3f} s | "
                               f"Hareket başlangıcı − çağrı bitişi: {values['latency_from_call_end_s']:.3f} s. "
                               "Manuel aday farkları; doğrulanmış hassasiyet/klinik eşik değildir.")
        except ValueError as exc:
            self.latencies.set(f"Gecikmeler hesaplanmadı: {exc}")
    def save_draft(self):
        self.draft.set_details({key: value.get() for key, value in self.detail_vars.items()})
        self.notice.set("Taslak kaydedildi; CSV değişmedi.")
    def loop_boundary(self, start):
        value = self.cursor()
        (self.loop_start if start else self.loop_end).set(f"{value/1000:.3f}")
        self.draft.set_loop(
            None if not self.loop_start.get() else seconds_to_ms(self.loop_start.get()),
            None if not self.loop_end.get() else seconds_to_ms(self.loop_end.get()))
    def toggle_loop(self):
        self.require_ready()
        if self.loop.enabled:
            self.loop.enabled, self.loop.pending_restart = False, False
            self.player.pause()
            self.paused, self.requested_cursor = True, None
            self.notice.set("Tekrar durduruldu.")
            return
        start, end = seconds_to_ms(self.loop_start.get()), seconds_to_ms(self.loop_end.get())
        self.loop.configure(start, end, self.player.length_ms)
        self.draft.set_loop(start, end)
        self.seek(start)
        self.requested_cursor = None
        self.player.play()
        self.paused = False
        self.loop.enabled = True
        self.notice.set("Tekrar açık. İşaretlemek için durdurup zaman imlecini seçin.")
    def show_preview(self):
        self.require_ready()
        self.loop.enabled, self.loop.pending_restart = False, False
        self.player.pause()
        self.paused = True
        self.save_draft()
        data = copy.deepcopy(self.draft.data)
        values = marked_times(data)
        raw, _, _, rows, index = csv_state(self.csv_path, self.draft.video)
        dialog = tk.Toplevel(self.root)
        self.preview = dialog
        dialog.title("CSV önizlemesi — henüz yazılmadı")
        dialog.transient(self.root)
        labels = {**LABELS, "latency_s": "Eski latency_s (= çağrı bitişine göre)",
                  "latency_from_call_start_s": "Hareket başlangıcı − çağrı başlangıcı",
                  "latency_from_call_end_s": "Hareket başlangıcı − çağrı bitişi"}
        text = "\n".join(f"{labels[name]}: " + ("bilinmiyor" if value is None else f"{value:.6f} s") for name, value in values.items())
        text += "\n\n" + "\n".join(f"{name}: {data['marks'][name]['time_source']}" for name in MARKS if data['marks'].get(name) is not None)
        text += "\n" + "\n".join(f"{DETAILS[key]}: {value or 'belirtilmedi'}" for key, value in data.get('manual_details', {}).items() if key in DETAILS)
        text += "\nCSV v2: tüm başlık/satırlar birlikte yazılır; boş bitiş bilinmiyor kalır. Kısa klip dışına tepki yok sonucu çıkarılmaz."
        text += f"\n\nKorunacak status: {rows[index]['status']!r}"
        text += f"\nİlk nominal aday: kare {data.get('response_start_frame')}, {data.get('response_start_nominal_s')} s."
        text += "\nKare PTS ve insan ses-görüntü doğrulaması otomatik kabul edilmez."
        if values["latency_s"] < 0:
            text += "\nYanıt çağrı bitmeden başladı; negatif gecikme korunacak."
        ttk.Label(dialog, text=text, justify="left", padding=15).pack()
        def cancel():
            self.preview = None
            dialog.grab_release()
            dialog.destroy()
        def confirm():
            try:
                backup = save_csv(self.csv_path, self.draft.video, data, raw)
                self.notice.set(f"CSV kaydedildi; status korundu. Yedek: {backup.name}")
                print(f"CSV: {self.csv_path}\nYedek: {backup}")
                cancel()
            except (OSError, ValueError, csv.Error) as exc:
                messagebox.showerror("Kaydetme başarısız", str(exc), parent=dialog)
        ttk.Button(dialog, text="Yedek al ve CSV'ye kaydet [Enter]", command=confirm).pack(pady=4)
        ttk.Button(dialog, text="Vazgeç [Esc]", command=cancel).pack(pady=4)
        dialog.bind("<Return>", lambda event: confirm())
        dialog.bind("<Escape>", lambda event: cancel())
        dialog.protocol("WM_DELETE_WINDOW", cancel)
        dialog.grab_set()
        dialog.focus_set()
    def on_key(self, event):
        if self.preview is not None or isinstance(event.widget, (tk.Entry, ttk.Entry)):
            return
        key = event.keysym.lower()
        actions = {
            "space": self.toggle_play, "0": lambda: self.seek(0),
            "a": lambda: self.shift(-1), "d": lambda: self.shift(1),
            "c": lambda: self.mark(MARKS[0]), "b": lambda: self.mark(MARKS[1]),
            "r": lambda: self.mark(MARKS[2]),
            "e": lambda: self.mark(MARKS[3]), "4": lambda: self.clear_mark(MARKS[3]),
            "1": lambda: self.clear_mark(MARKS[0]), "2": lambda: self.clear_mark(MARKS[1]),
            "3": lambda: self.clear_mark(MARKS[2]), "t": self.save_draft,
            "s": self.show_preview, "l": self.toggle_loop,
            "bracketleft": lambda: self.loop_boundary(True),
            "bracketright": lambda: self.loop_boundary(False), "q": self.close}
        if key in actions:
            self.guard(actions[key])
            return "break"
    def poll(self):
        if self.closing:
            return
        try:
            state = self.player.state
            if state == 7:
                raise ValueError("LibVLC medya hatası; dosya ve ses aygıtını kontrol edin.")
            if not self.ready and self.player.seekable and self.player.length_ms > 0:
                self.ready = True
                self.slider.configure(to=self.player.length_ms/1000)
            if self.pending_seek is not None and self.player.seekable:
                value = self.pending_seek
                self.player.pause()
                self.player.seek(value)
                self.pending_seek = None
                self.requested_cursor, self.paused = value, True
                self.notice.set("Hazır. Ses ve video tek LibVLC oynatıcısında. İlk R adayı korunuyor.")
            if not self.ready and time.monotonic() > self.open_deadline:
                raise ValueError("Oynatıcı 20 saniyede hazır olmadı.")
            if self.ready:
                self.loop.tick(self.player)
                reported = self.player.time_ms
                if state == 6 and not self.loop.enabled:
                    self.paused = True
                cursor = max(0, reported) if self.requested_cursor is None else self.requested_cursor
                self.clock.set(
                    f"LibVLC bildirimi: {f'{reported/1000:.3f} s' if reported >= 0 else 'bilinmiyor'} | İstenen konum: "
                    f"{f'{self.requested_cursor/1000:.3f} s' if self.requested_cursor is not None else 'yok'} | "
                    f"{'DURAKLATILDI' if self.paused else 'OYNATILIYOR'} | Tekrar: {'açık' if self.loop.enabled else 'kapalı'}")
                if not self.dragging:
                    self.seek_value.set(cursor/1000)
        except (OSError, ValueError) as exc:
            self.notice.set(f"Oynatıcı hatası: {exc}")
            return
        self.timer = self.root.after(25, self.poll)
    def close(self):
        self.closing = True
        if hasattr(self, "timer"):
            self.root.after_cancel(self.timer)
        self.player.stop()
        self.root.destroy()

def check_player(player):
    """Gerçek oynatıcı; insan işaretlerine dokunmaz, dummy çıktı kullanır."""
    def wait_for(predicate, timeout=10):
        deadline = time.monotonic()+timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.025)
        raise ValueError("LibVLC kontrolünde zaman aşımı.")
    player.play()
    wait_for(lambda: player.seekable and player.length_ms > 0)
    player.pause()
    wait_for(lambda: player.state == 4)
    for value in (500, 1500, 500):
        player.seek(value)
        wait_for(lambda: abs(player.time_ms-value) <= 100)
    player.play()
    wait_for(lambda: player.state == 3 and player.time_ms > 650)
    player.pause()
    wait_for(lambda: player.state == 4)
    segment = SegmentLoop()
    segment.configure(500, 1000, player.length_ms)
    player.seek(segment.start_ms)
    player.play()
    segment.enabled = True
    wait_for(lambda: (segment.tick(player) or segment.restarts > 0) and segment.restarts > 0)
    segment.enabled = False
    player.pause()
    print(f"LIBVLC KONTROL OK: {player.version}; süre {player.length_ms/1000:.3f} s; oynatma/duraklatma/arama/kısa tekrar.")
    print("Dummy çıktı: insan dinlemesi ve ses-görüntü eşleşmesi doğrulanmadı.")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", type=Path, default=DEFAULT_VIDEO)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--draft", type=Path, default=DEFAULT_DRAFT)
    parser.add_argument("--vlc-dir", type=Path, default=VLC_DIR)
    parser.add_argument("--check", action="store_true", help="Sessiz gerçek oynatıcı kontrolü; etiket dosyalarına yazma.")
    args = parser.parse_args()
    player = None
    try:
        if not args.check:
            require_working_copy(args.csv)
            require_working_copy(args.draft)
        draft = DraftStore(args.draft, args.video)
        csv_before, draft_before = args.csv.read_bytes(), args.draft.read_bytes()
        csv_state(args.csv, args.video)
        player = LibVLCPlayer(args.video, args.vlc_dir, silent_check=args.check)
        print(f"LibVLC: {player.version}\nTaslak: {args.draft}")
        print("R nominal adayı korunur. Medya/kare zamanları ayrı kaynaklardır; status otomatik belirlenmez.")
        if args.check:
            check_player(player)
            if args.csv.read_bytes() != csv_before or args.draft.read_bytes() != draft_before:
                raise ValueError("Kontrol sırasında etiket dosyası değişti.")
            print("CSV ve taslak değişmedi.")
        else:
            root = tk.Tk()
            AnnotationApp(root, player, draft, args.csv)
            root.mainloop()
        return 0
    except (OSError, ValueError, csv.Error, json.JSONDecodeError, tk.TclError) as exc:
        print(f"HATA: {exc}", file=sys.stderr)
        return 1
    finally:
        if player is not None:
            player.close()

if __name__ == "__main__":
    raise SystemExit(main())
