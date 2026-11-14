# Fast D01 integration inventory — 8 November 2026

Source: user-supplied `Isme_Tepki.zip`, SHA256 `2b7cb0df7e5571e228d3e96174048fc197173bb0f29f66e805a2fb1720c1e4fa`.

Attribution and the user's explicit permission for this GitHub sharing scope:
[vendor/README.md](vendor/README.md). The original vendor file is unchanged.

Current mobile display separates the start from the low-speed endpoint candidate;
missing ends say "Bitiş belirlenemedi" and confirmation times remain separate.
This endpoint need not match visual completion of the main turn. The user
reported all16 `d01_pilot_panel_test.dart` tests passing in normal Windows
PowerShell after this change. Earlier acceptance notes below are historical.

| ZIP / existing file | Current use / reusable part | Missing / action |
|---|---|---|
| `ses_yonelme/sesyon/vision.py` | Already used by compare_headpose_methods; generic SQPnP+LM and forward/backward Lucas–Kanade flow | Original FaceTrack assumes manually assigned person/search ROI; add conservative automatic association before passing landmarks. Preserve original in vendor/friend_vision.py (SHA4fbe1f9049ccacef00fdfd73028b5a697e57978abdb05de950f9e51012c8a9e4). |
| `ses_yonelme/sesyon/pipeline.py` | Frame processing, separate tracking/pose/gaze concepts, report timing | Depends on manual child/adult search regions; not an automatic identity solution. Do not adopt gaze model, decision confidence or response classification. |
| `isme_tepki/analiz.py` | normalize_rows, existing SO(3) EMA/motion detector; preserves preexisting/unknown-start movements in call_results | Repo already has the shared detector. Adapt temporal call phases only; no target/clinical inference, no ASR dependency. |
| `isme_tepki/karsilastir.py` | One-to-one temporal matching and explicit coverage/unknowns | Use manual labels only in posthoc evaluation; do not reuse agreement colors as clinical colors. |
| ZIP rapor/sonuc.json, karsilastirma.json, acilar.csv | Packaged example evidence only | Different source video; not a new run or current-video ground truth. |
| research/d01/official_runtime.py, recorded 6D JSONL | Existing reference matrices | Do not rerun full6D for these videos. Reference axes have no calibrated common neutral with PnP. |
| backend/d01_pilot_jobs.js | Upload/jobId/status/result/cancel/auth/timeout/storage | Add opt-in fast method with configured Tasks CPU runtime; preserve legacy1.0/1.1. |
| mobile D01PilotPanel/service/result model | Existing preview, polling/resume, seek/scroll and source binding | Fast1.2 coverage/identity gaps/call phases and visible-result client timing. |

Identity is a conservative association of a face track, not age recognition or biometric proof. Multiple ambiguous faces cause missing measurements. Optional initial point is a human target indication, not a drawn ROI. Flow-only frames never provide absolute roll/pitch/yaw. No clinical label, calibrated confidence or correct-speaker decision is added.

## Implemented boundary and acceptance

- Fast method uses the existing job endpoint and single slot, session Bearer key,25MiB upload, timeout/cancel/late-close protections. API1.2 is explicit; no method preserves legacy1.0/1.1 and both6D profiles.
- FastTracker uses unchanged ZIP LK/PnP, local Tasks CPU multi-face detection with scaled search and conservative position/appearance association. Initial human point is optional; ambiguity produces missing data. It does not identify children or the speaker. Long loss never reacquires whichever adult remains.
- Per-frame JSONL contains measurement status, decoder/nominal time, full-frame RGB hash and null angles for flow-only/lost frames. Same V1 detector and EMA.5 are reused without interpolation, ASR, confidence or clinical labels.
- New measured Python runs are outside Git: `outputs/d01_headpose_method_compare/fast_acceptance_20261108_01/video_0` and `video_1`; comparison_0/1 have all candidates and native_angles_and_gaps.png.168frames43pose and190frames100pose; first ends unknown in both. No6D rerun, and no historical server speed ratio.
-39 controlled backend tests and6 controlled Python logic/orchestration tests passed. Flutter tests were stopped after no output; direct Dart analysis was blocked by telemetry-file access. Formatting parsed the Dart source before the access error; that is not type analysis.
- Actual local HTTP upload accepted, but child launch failed with cli_start_failed. Underlying error was not recorded; do not assert a specific OS cause. Own backend closed. No mobile-visible real duration yet. Normal PowerShell commands and final two-video emulator acceptance are in backend/D01_PILOT.md.
