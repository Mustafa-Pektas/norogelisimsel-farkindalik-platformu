#!/usr/bin/env bash
set -e

BENCH_DIR="/opt/norogelisim/headpose_benchmark"
VENV_DIR="/opt/norogelisim/venv_headpose"
PY="$VENV_DIR/bin/python"
VIDEO_ARG="${1:-$BENCH_DIR/sample_videos/video_2026-11-07_17-13-48.mp4}"
OUTPUT_DIR="${2:-$BENCH_DIR/outputs_deniz}"
ONNX_MODEL="/opt/norogelisim/araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.onnx"
TORCH_WEIGHTS="/opt/norogelisim/araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.pth"
EXPORT_DEPS="$BENCH_DIR/.onnx_export_deps"
CONSTRAINTS="$BENCH_DIR/.pip_constraints.txt"

cd "$BENCH_DIR"
mkdir -p "$OUTPUT_DIR"

# Mevcut çekirdek paket sürümlerini SABİTLE: yeni paket kurulumları mediapipe'i bozamaz
# (mediapipe 0.10.x protobuf<5 ister; yeni mediapipe'te mp.solutions yok).
"$PY" -m pip freeze 2>/dev/null \
  | grep -iE '^(numpy|protobuf|mediapipe|torch|torchvision|opencv-python|opencv-contrib-python|opencv-python-headless|scipy)==' \
  > "$CONSTRAINTS" || true

# Konsolide raporlar (PDF / Excel / HTML) için gerekli paketler; eksikse kurulur.
if ! "$PY" -c "import matplotlib, openpyxl, PIL" 2>/dev/null; then
  echo "--> Rapor bağımlılıkları kuruluyor (matplotlib, openpyxl, pillow)..."
  "$PY" -m pip install -q -c "$CONSTRAINTS" "matplotlib>=3.5" "openpyxl>=3.0" "pillow>=9.0"
fi

# 6DRepNet360 ONNX çalışma zamanı (Cascade_PnP_to_6DRepNet360_Stride4_ONNX için)
if ! "$PY" -c "import onnxruntime" 2>/dev/null; then
  echo "--> onnxruntime kuruluyor (mevcut protobuf/numpy/mediapipe sürümleri sabit)..."
  "$PY" -m pip install -q -c "$CONSTRAINTS" onnxruntime || echo "[UYARI] onnxruntime kurulamadı; ONNX modeli UNAVAILABLE olacak."
fi

# ONNX modeli yoksa bir kez dışa aktar + PyTorch ile doğrula (onnx/protobuf>=5 ayrı klasöre, ana venv'e değil)
if [ ! -f "$ONNX_MODEL" ] && [ -f "$TORCH_WEIGHTS" ]; then
  echo "--> 6DRepNet360 ONNX modeli bulunamadı; dışa aktarılıyor ve doğrulanıyor (tek seferlik)..."
  if [ ! -d "$EXPORT_DEPS/onnx" ]; then
    "$PY" -m pip install -q --target "$EXPORT_DEPS" --no-deps onnx protobuf ml_dtypes typing_extensions \
      || echo "[UYARI] Dışa aktarma bağımlılıkları kurulamadı."
  fi
  OMP_NUM_THREADS=4 "$PY" -u tools/export_6drepnet_onnx.py --video "$VIDEO_ARG" --deps-dir "$EXPORT_DEPS" \
    || echo "[UYARI] ONNX dışa aktarma/doğrulama başarısız; Stride4_ONNX UNAVAILABLE olacak (PyTorch modelleri etkilenmez)."
fi

export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4

echo "--> Karsilastirma, Sesli Video ve Rapor Uretimi Baslatiliyor (Xeon 4 Cekirdek, Canli Cikti)..."
"$PY" -u benchmark_runner.py \
  --video "$VIDEO_ARG" \
  --warmup 20 \
  --output-dir "$OUTPUT_DIR" \
  --out "$OUTPUT_DIR/benchmark_results.json"

echo ""
echo "=========================================================="
echo " ANALIZ, SESLI VIDEO VE RAPOR CIKTILARI TAMAMLANDI!"
echo " Raporlar: tum_modeller_raporu.pdf | karsilastirma_tablosu.xlsx | tum_modeller_raporu.html"
echo " Ciktilar surada olusturuldu ($OUTPUT_DIR):"
ls -lh "$OUTPUT_DIR"
echo "=========================================================="
