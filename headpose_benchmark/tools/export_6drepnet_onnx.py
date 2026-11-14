"""
6DRepNet360 -> ONNX dışa aktarma + doğrulama + hız ölçümü (sunucuda bir kez çalıştırılır).

Ne yapar:
  1) Resmi PyTorch modelini (repnet360.py ile aynı yükleme) ONNX'e aktarır. Önce tam modeli (6D -> 3x3
     rotasyon dahil) dener; ONNX'e çevrilemeyen bir işlem varsa 6D çıktılı başı aktarır, 6D -> 3x3
     dönüşümü çalışma zamanında NumPy ile yapılır (repnet360.ortho6d_to_rotation_matrix).
  2) Videodan alınan çocuk ROI kareleri üzerinde PyTorch ve ONNX Runtime çıktılarını karşılaştırır
     (geodezik fark, derece). Maks fark --max-diff-deg (varsayılan 0.5°) üstündeyse ONNX dosyası
     YAZILMAZ ve çıkış kodu 1 olur.
  3) 1/2/4 iş parçacığıyla PyTorch ve ONNX Runtime kare başı gecikmesini ölçer (ön-işleme dahil).

Bağımlılık yalıtımı: PyTorch'un ONNX dışa aktarıcısı `onnx` paketini ister; `onnx` ise protobuf ≥ 5
gerektirir ve mediapipe 0.10.x'in protobuf < 5 kısıtıyla çakışır. Bu yüzden `onnx` + yeni protobuf ana
venv'e KURULMAZ; `--deps-dir` (varsayılan: headpose_benchmark/.onnx_export_deps) klasörüne
`pip install --target ... --no-deps onnx protobuf ml_dtypes typing_extensions` ile kurulur ve yalnız bu
süreçte sys.path'in başına eklenir. Bu süreç mediapipe'i hiç yüklemez. Çalışma zamanında (benchmark)
yalnız onnxruntime gerekir.

Kullanım (sunucu):
  /opt/norogelisim/venv_headpose/bin/python tools/export_6drepnet_onnx.py \
      --video sample_videos/video_2026-11-07_17-13-48.mp4
"""
import os
import sys

_BENCH_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _prepend_deps_dir(argv):
    """--deps-dir'i protobuf/onnx içe aktarılmadan ÖNCE sys.path başına ekler."""
    deps = os.path.join(_BENCH_DIR, ".onnx_export_deps")
    for i, a in enumerate(argv):
        if a == "--deps-dir" and i + 1 < len(argv):
            deps = argv[i + 1]
        elif a.startswith("--deps-dir="):
            deps = a.split("=", 1)[1]
    if os.path.isdir(deps):
        sys.path.insert(0, deps)
    return deps


_DEPS_DIR = _prepend_deps_dir(sys.argv)

import argparse  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
import time  # noqa: E402
from typing import List  # noqa: E402

import numpy as np  # noqa: E402
import cv2  # noqa: E402

sys.path.insert(0, _BENCH_DIR)
from common.roi import resolve_video_roi, crop_roi_bgr  # noqa: E402
from estimators.repnet360 import (  # noqa: E402
    SixDRepNet360Estimator, DEFAULT_ONNX, preprocess_numpy,
)


def geodesic_deg(a: np.ndarray, b: np.ndarray) -> float:
    return math.degrees(math.acos(float(np.clip((np.trace(a.T @ b) - 1.0) / 2.0, -1.0, 1.0))))


def sample_rois(video: str, n: int) -> List[np.ndarray]:
    roi, _ = resolve_video_roi(video)
    cap = cv2.VideoCapture(video)
    frames = []
    while True:
        ok, fr = cap.read()
        if not ok:
            break
        frames.append(crop_roi_bgr(fr, roi))
    cap.release()
    if not frames:
        raise RuntimeError(f"Videodan kare okunamadı: {video}")
    idx = np.linspace(0, len(frames) - 1, min(n, len(frames))).round().astype(int)
    return [frames[i] for i in sorted(set(idx.tolist()))]


def export(est: SixDRepNet360Estimator, path: str, opset: int) -> str:
    import torch

    dummy = torch.randn(1, 3, 224, 224)

    def _do(model):
        kwargs = dict(input_names=["input"], output_names=["output"], opset_version=opset,
                      do_constant_folding=True, dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}})
        try:
            torch.onnx.export(model, (dummy,), path, dynamo=False, **kwargs)
        except TypeError:  # dynamo parametresi olmayan eski torch
            torch.onnx.export(model, (dummy,), path, **kwargs)

    try:
        _do(est.model)
        return "rotation_matrix_3x3"
    except Exception as exc:
        print(f"    Tam model aktarılamadı ({type(exc).__name__}: {exc}); 6D çıktılı baş aktarılıyor...")

    fn_name = "compute_rotation_matrix_from_ortho6d"
    patched = []
    for mod in (est.utils, getattr(est, "test_module", None)):
        if mod is not None and hasattr(mod, fn_name):
            patched.append((mod, getattr(mod, fn_name)))
            setattr(mod, fn_name, lambda x: x)
    try:
        _do(est.model)
    finally:
        for mod, fn in patched:
            setattr(mod, fn_name, fn)
    return "ortho6d"


def time_ms(fn, rois, repeats: int = 20) -> float:
    for r in rois[:3]:
        fn(r)
    ts = []
    for i in range(repeats):
        r = rois[i % len(rois)]
        t0 = time.perf_counter()
        fn(r)
        ts.append((time.perf_counter() - t0) * 1000.0)
    return float(np.median(ts))


def main():
    ap = argparse.ArgumentParser(description="6DRepNet360 -> ONNX dışa aktarma ve doğrulama")
    ap.add_argument("--video", required=True, help="Doğrulama karelerinin alınacağı video")
    ap.add_argument("--weights", default=None, help=".pth yolu (varsayılan: repnet360 arama yolları)")
    ap.add_argument("--source", default=None, help="Resmi 6DRepNet360 kaynak dizini")
    ap.add_argument("--out", default=None, help=f"ONNX çıktı yolu (varsayılan: {DEFAULT_ONNX[0]})")
    ap.add_argument("--frames", type=int, default=48, help="Doğrulama kare sayısı")
    ap.add_argument("--opset", type=int, default=17)
    ap.add_argument("--threads", default="1,2,4", help="Hız ölçümü iş parçacığı listesi")
    ap.add_argument("--max-diff-deg", type=float, default=0.5)
    ap.add_argument("--deps-dir", default=_DEPS_DIR, help="Yalnız dışa aktarma için onnx/protobuf klasörü")
    args = ap.parse_args()
    try:
        import onnx  # noqa: F401
    except Exception as exc:
        print(f"[HATA] 'onnx' paketi yüklenemedi ({exc}). Kurulum:\n"
              f"  python -m pip install --target {args.deps_dir} --no-deps onnx protobuf ml_dtypes typing_extensions")
        sys.exit(4)

    out = args.out or os.environ.get("REPNET360_ONNX") or DEFAULT_ONNX[0]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    tmp = out + ".tmp.onnx"

    print("--> PyTorch modeli yükleniyor...", flush=True)
    est_t = SixDRepNet360Estimator(args.weights, args.source, cpu_threads=4, backend="torch")
    if not est_t.setup():
        print("[HATA] PyTorch 6DRepNet360 yüklenemedi (ağırlık/kaynak yolu?).")
        sys.exit(2)

    print(f"--> ONNX'e aktarılıyor (opset {args.opset})...", flush=True)
    kind = export(est_t, tmp, args.opset)
    print(f"    Aktarılan çıktı türü: {kind}")

    est_o = SixDRepNet360Estimator(cpu_threads=4, backend="onnx", onnx_path=tmp)
    if not est_o.setup():
        print("[HATA] ONNX Runtime oturumu açılamadı.")
        sys.exit(3)

    rois = sample_rois(args.video, args.frames)
    print(f"--> Doğrulama: {len(rois)} ROI karesi", flush=True)

    # Ön-işleme eşdeğerliği (torchvision vs NumPy)
    from PIL import Image
    pre_diffs = []
    for r in rois[:8]:
        tv = est_t.normalize(est_t.crop(est_t.resize(Image.fromarray(cv2.cvtColor(r, cv2.COLOR_BGR2RGB))))).numpy()
        pre_diffs.append(float(np.max(np.abs(tv - preprocess_numpy(r)[0]))))

    diffs = [geodesic_deg(est_t.infer_rotation(r), est_o.infer_rotation(r)) for r in rois]
    report = {
        "onnx_path": out,
        "output_kind": kind,
        "frames_checked": len(rois),
        "preprocess_max_abs_diff": max(pre_diffs),
        "rotation_diff_deg": {"max": max(diffs), "median": float(np.median(diffs)), "mean": float(np.mean(diffs))},
        "latency_ms_median": {},
    }

    import torch
    for t in [int(x) for x in args.threads.split(",") if x.strip()]:
        torch.set_num_threads(t)
        est_ot = SixDRepNet360Estimator(cpu_threads=t, backend="onnx", onnx_path=tmp)
        est_ot.setup()
        report["latency_ms_median"][f"threads_{t}"] = {
            "torch": round(time_ms(est_t.infer_rotation, rois), 2),
            "onnxruntime": round(time_ms(est_ot.infer_rotation, rois), 2),
        }

    ok = report["rotation_diff_deg"]["max"] <= args.max_diff_deg
    report["passed"] = ok
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print("\n| İş parçacığı | PyTorch (ms) | ONNX Runtime (ms) | Hızlanma |")
    print("| :--- | ---: | ---: | ---: |")
    for k, v in report["latency_ms_median"].items():
        sp = v["torch"] / v["onnxruntime"] if v["onnxruntime"] > 0 else float("nan")
        print(f"| {k.split('_')[1]} | {v['torch']:.1f} | {v['onnxruntime']:.1f} | {sp:.2f}x |")

    if not ok:
        os.remove(tmp)
        print(f"\n[HATA] ONNX çıktısı PyTorch'tan {report['rotation_diff_deg']['max']:.3f}° sapıyor "
              f"(sınır {args.max_diff_deg}°). ONNX dosyası YAZILMADI.")
        sys.exit(1)
    os.replace(tmp, out)
    with open(out + ".verify.json", "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    print(f"\n[OK] ONNX modeli doğrulandı ve kaydedildi: {out}")


if __name__ == "__main__":
    main()
