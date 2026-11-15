"""Create reviewable audio annotation drafts; never mark them as ground-truth."""
import argparse
import csv
import hashlib
import json
import re
import sys
import unicodedata
from datetime import datetime, timezone
from pathlib import Path


# === AYARLAR: Yalnizca bu bolumu degistirmeniz yeterli ===
VIDEO_KLASORU = ".."
ISLEME_MODU = "tek"
TEK_VIDEO_ADI = "video.mp4"  # "tek" modunda dosyanin tam adi
COCUK_ADI = None           # Aranacak isim veya None
KONUSMA_DILI = "tr"        # Turkce: "tr", Ingilizce: "en", otomatik: None
CIKTI_KLASORU = "outputs"  # Python dosyasinin yaninda otomatik olusturulur
MODEL_ADI = "small"
CIHAZ = "cpu"
HESAPLAMA_TIPI = "int8"
VAD_KULLAN = True
# === AYARLAR SONU ===

KOD_DIZINI = Path(__file__).resolve().parent
VIDEO_UZANTILARI = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v"}


def kod_yolu(value):
    """Resolve config paths relative to the script, not the terminal."""
    path = Path(value).expanduser()
    return path if path.is_absolute() else KOD_DIZINI / path


def secilen_videolar():
    klasor = kod_yolu(VIDEO_KLASORU)
    if not klasor.is_dir():
        raise ValueError(f"Video klasoru bulunamadi: {klasor}. VIDEO_KLASORU ayarini kontrol edin.")
    if ISLEME_MODU == "tek":
        if not TEK_VIDEO_ADI or Path(TEK_VIDEO_ADI).name != TEK_VIDEO_ADI:
            raise ValueError("TEK_VIDEO_ADI yalnizca dosya adi olmali (ornegin video_01.mp4).")
        video = klasor / TEK_VIDEO_ADI
        if not video.is_file():
            raise ValueError(f"Video bulunamadi: {video}. TEK_VIDEO_ADI ayarini kontrol edin.")
        if video.suffix.lower() not in VIDEO_UZANTILARI:
            raise ValueError(f"Desteklenmeyen video uzantisi: {video.suffix}")
        return [video]
    if ISLEME_MODU == "klasor":
        videolar = sorted((p for p in klasor.iterdir()
                           if p.is_file() and p.suffix.lower() in VIDEO_UZANTILARI),
                          key=lambda p: (p.name.casefold(), p.name))
        if not videolar:
            raise ValueError(f"Klasorde desteklenen video bulunamadi: {klasor}")
        return videolar
    raise ValueError('ISLEME_MODU "tek" veya "klasor" olmali.')


def normalize(text):
    text = unicodedata.normalize("NFC", text).replace("İ", "i").replace("I", "ı")
    return re.sub(r"[^\w]", "", text.casefold())


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def make_draft(path, segments, info, args):
    words, transcript = [], []
    for segment in segments:
        transcript.append({"start_s": segment.start, "end_s": segment.end,
                           "text": segment.text})
        for word in segment.words or []:
            words.append({"text": word.word.strip(), "start_s": word.start,
                          "end_s": word.end, "model_probability": word.probability})
    target = normalize(args.name) if args.name else None
    candidates = [dict(word, event="possible_name_call", speaker="unknown",
                       review_status="pending") for word in words
                  if target and normalize(word["text"]) == target]
    return {
        "schema_version": "1.0", "annotation_status": "draft_unreviewed",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source": {"filename": path.name, "sha256": sha256(path),
                   "audio_duration_s": info.duration,
                   "time_origin": "start_of_input_file", "clip_offset_s": 0.0},
        "scenario": {"child_name": args.name, "age_group": None},
        "automatic_proposals": {
            "model": args.model, "language": info.language,
            "language_probability": info.language_probability,
            "vad_filter": not args.no_vad,
            "transcript_segments": transcript, "words": words,
            "name_call_candidates": candidates,
            "notes": [
                "Word times are estimates; listen and correct before accepting.",
                "A name occurrence does not establish a call or identify its speaker.",
                "No candidate does not establish absence of a call.",
                "Model probabilities are not validated behavioral confidence scores.",
            ],
        },
        "ground_truth": {
            "reviewed": False, "reviewer": None,
            "call_status": "not_reviewed",
            "calls": [], "visual_events": [], "unusable_intervals": [],
            "notes": "Fill by listening/viewing; do not automatically copy proposals.",
        },
    }


def write_outputs(draft, destination):
    destination.mkdir(parents=True, exist_ok=False)
    (destination / "annotation_draft.json").write_text(
        json.dumps(draft, ensure_ascii=False, indent=2), encoding="utf-8")
    fields = ["text", "start_s", "end_s", "model_probability"]
    with (destination / "words.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(draft["automatic_proposals"]["words"])


def main():
    parser = argparse.ArgumentParser(description="Videodan ses etiket taslagi olusturur.")
    parser.add_argument("videos", nargs="*", type=Path,
                        help="Opsiyonel; verilmezse kodun basindaki ayarlar kullanilir")
    parser.add_argument("--name", default=COCUK_ADI, help="Aranacak cocuk adi")
    parser.add_argument("--language", default=KONUSMA_DILI, help="tr, en vb.")
    parser.add_argument("--model", default=MODEL_ADI)
    parser.add_argument("--device", default=CIHAZ, choices=["cpu", "cuda"])
    parser.add_argument("--compute-type", default=HESAPLAMA_TIPI)
    parser.add_argument("--no-vad", action="store_true", default=not VAD_KULLAN,
                        help="Konusma filtresini kapatir; kisa cagri atlanirsa karsilastirin")
    parser.add_argument("--output", type=Path, default=kod_yolu(CIKTI_KLASORU))
    args = parser.parse_args()
    if not args.videos:
        try:
            args.videos = secilen_videolar()
        except ValueError as exc:
            parser.error(str(exc))
    missing = [str(path) for path in args.videos if not path.is_file()]
    if missing:
        parser.error("Dosya bulunamadi: " + ", ".join(missing))
    if args.name is not None and not normalize(args.name):
        parser.error("--name bos veya yalnizca noktalama olamaz")
    print(f"Islenecek video sayisi: {len(args.videos)}")
    for path in args.videos:
        print(f"  {path.resolve()}")
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        print("Once: python -m pip install -r requirements.txt", file=sys.stderr)
        return 1
    try:
        model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)
    except Exception as exc:
        print(f"Model yuklenemedi: {exc}", file=sys.stderr)
        return 1
    run = args.output / datetime.now().astimezone().strftime("%Y-%m-%d_%H-%M-%S_%f")
    failures = 0
    for index, path in enumerate(args.videos, 1):
        try:
            segments, info = model.transcribe(
                str(path), language=args.language, task="transcribe",
                word_timestamps=True, vad_filter=not args.no_vad,
                condition_on_previous_text=False)
            # Inference runs while this generator is consumed.
            draft = make_draft(path, segments, info, args)
            folder = run / f"{index:03d}_{path.stem}"
            write_outputs(draft, folder)
            print(f"Ciktilar: {folder.resolve()}")
            count = len(draft["automatic_proposals"]["name_call_candidates"])
            print(f"{path.name}: {count} isim adayi; taslak: {folder}")
            if not draft["automatic_proposals"]["words"]:
                print("  Kelime taninamadi; sesi elle kontrol edin.")
        except Exception as exc:
            failures += 1
            print(f"{path.name}: analiz basarisiz: {exc}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
