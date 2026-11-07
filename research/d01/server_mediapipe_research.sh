#!/usr/bin/env bash
# Research bundle only. No dotenv, package install, service, Torch or 6D inference.
set -eu
if [ "$#" -ne 2 ]; then
  printf 'Usage: bash server_mediapipe_research.sh /absolute/research/python --check-only|--measure\n' >&2
  exit 2
fi
py="$1"
mode="$2"
case "$py" in /*) ;; *) printf 'Absolute research Python path required\n' >&2; exit 2 ;; esac
case "$mode" in --check-only|--measure) ;; *) printf 'Invalid mode\n' >&2; exit 2 ;; esac
if [ ! -x "$py" ]; then
  printf 'Research Python missing or not executable. Nothing installed or started.\n' >&2
  exit 2
fi
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$root"
if [ "$mode" = '--measure' ] && [ -e measurement ]; then
  printf 'Measurement directory already exists; use a separate new bundle directory.\n' >&2
  exit 2
fi
"$py" -B - "$mode" <<'PY'
import sys, json, pathlib, hashlib, platform, os, importlib.metadata
root=pathlib.Path.cwd()
manifest=json.loads((root/'bundle_manifest.json').read_text())
for name,expected in manifest['files_sha256'].items():
    file=(root/name).resolve()
    if root not in file.parents or hashlib.sha256(file.read_bytes()).hexdigest()!=expected:
        raise SystemExit('Bundle checksum/path failure')
try:
    import numpy as np, cv2, mediapipe as mp
    from mediapipe.tasks.python import BaseOptions
    from mediapipe.tasks.python.vision import FaceLandmarker, FaceLandmarkerOptions, RunningMode
    assert hasattr(BaseOptions.Delegate,'CPU')
except (ImportError, AttributeError, AssertionError) as error:
    print(json.dumps({'research_environment_ready':False,'error_type':type(error).__name__,
        'required':'Existing NumPy, OpenCV, MediaPipe Tasks CPU/IMAGE. No install performed.'}))
    raise SystemExit(2)
record=json.loads((root/'reference_run/result.json').read_text())
settings=json.loads((root/'reference_run/settings.json').read_text())
video_sha=hashlib.sha256((root/'video.mp4').read_bytes()).hexdigest()
if video_sha!=manifest['video_sha256'] or video_sha!=record['video']['sha256'] or settings['roi']!=manifest['roi']:
    raise SystemExit('Video/reference/ROI mismatch')
if hashlib.sha256((root/'face_landmarker.task').read_bytes()).hexdigest()!=manifest['face_task_sha256']:
    raise SystemExit('Task model mismatch')
environment={'research_environment_ready':True,'location':'remote_research_cpu',
    'platform':platform.platform(),'python':sys.version,'executable':sys.executable,
    'numpy':np.__version__,'opencv':cv2.__version__,'mediapipe':mp.__version__,
    'cpu_count':os.cpu_count(),'affinity_cpu_count':len(os.sched_getaffinity(0)) if hasattr(os,'sched_getaffinity') else None,
    'tflite_effective_threads':None,'no_model_loaded_during_check':True,
    'same_task_model_and_roi':True,'video_sha256':video_sha,
    'runtime_version_equality_not_assumed':True}
print(json.dumps(environment))
if sys.argv[1]=='--measure':
    with (root/'server_environment.json').open('x') as f:json.dump(environment,f,indent=2)
PY
if [ "$mode" = '--check-only' ]; then exit 0; fi
# Conservative guard: do not compete with an already running Python analysis.
# No process is killed and no service setting is read or changed.
if ps -eo comm= | grep -Eq '^python([0-9]+([.][0-9]+)*)?$'; then
  printf 'An existing Python process is present; inspect its purpose before measuring. No model started.\n' >&2
  exit 3
fi
"$py" -B -X utf8 compare_headpose_methods.py measure \
  --video video.mp4 --package Isme_Tepki.zip --face-model face_landmarker.task \
  --recorded-run reference_run --output measurement --max-seconds 120
"$py" -B - <<'PY'
import json,pathlib
state=json.loads(pathlib.Path('measurement/state.json').read_text())
metrics=json.loads(pathlib.Path('measurement/measurement.json').read_text())
if state['status']!='completed' or metrics['decoded_frames']!=168:raise SystemExit('Incomplete server measurement; preserve partial results')
print(json.dumps({'location':'remote_research_cpu','measurement':metrics}))
PY
