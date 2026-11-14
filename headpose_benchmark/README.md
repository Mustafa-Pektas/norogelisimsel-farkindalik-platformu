# D01 Baş Yönü ve Bakış Tahmini Kıyaslama Paketi (Independent Benchmark)

Bu dizin ana platformdan (`backend/`, `mobile_skeleton/`) **tamamen bağımsız ve izole** bir araştırma modülüdür. 
Gerektiğinde hem yerel ortamdan hem de sunucudan (`/opt/norogelisim/headpose_benchmark/`) tek bir komutla silinebilir:
```bash
rm -rf headpose_benchmark/
```

---

## 1. Kıyaslanan Yöntemler

1. **`mediapipe_pnp`:** MediaPipe FaceMesh (6 nokta) + OpenCV `solvePnP`
2. **`mediapipe_pnp_1euro`:** MediaPipe + SolvePnP + 1-Euro Filtresi (Jitter engelleme)
3. **`mediapipe_pnp_kalman`:** MediaPipe + SolvePnP + Kalman Filtresi
4. **`optical_flow`:** Lucas-Kanade Optik Akış (Diferansiyel piksel takibi)
5. **`Hybrid_PnP_KP_Step5`:** Hibrit (5 karede bir MediaPipe FaceMesh çapası + aradaki kareler ve profil dönüşleri BlazeFace 6 anahtar nokta köprüsü). Eski `Hybrid_PnP_LK_Step5` kaldırıldı: LK piksel kayması kafa ötelemesini (2–4 px/kare) dönme sanıyor ve FaceMesh kaybolan anahtar karelerde SO(3) dizisinde boşluk bırakıyordu (`unknown_end_data_gap`).
6. **`mediapipe_iris`:** MediaPipe Iris (Göz bebeği bakış tahmini)
7. **`sixdrepnet360`:** 6DRepNet360 (Ağır derin öğrenme referansı - varsa ağırlıklarla)
8. **`Cascade_PnP_to_BlazeFaceKP`:** Her karede FaceMesh; FaceMesh kaybolduğunda veya profil (|yaw| ≥ 62°) başladığında ~2 ms'lik BlazeFace anahtar nokta köprüsü (`estimators/blazeface_kp.py`). Göz arası/yüz yüksekliği oranından |yaw|, kulak→burun eğiminden profil pitch'i; açılar son güvenilir FaceMesh karesine göre göreli hesaplanır, SO(3) dizisi kesintisizdir.
9. **`Cascade_PnP_to_6DRepNet360_Stride4`:** Profil/kayıp aralığında 6DRepNet360 yalnız her 4. karede mutlak çapa; aradaki kareler KP göreli dönüşüyle (6DRepNet çağrısı ≈4 kat azalır). 6DRepNet ağırlıkları gerekir.

**Profil köprüsü tüm FaceMesh modellerinde:** `MediaPipe_SolvePnP_Raw/1Euro/Kalman`, `MediaPipe_Iris_Gaze` ve `MediaPipe_PnP_LK_Tracker` FaceMesh kaybolduğunda veya |yaw| ≥ 62° olduğunda BlazeFace KP köprüsüne geçer (kayıp kare 0). 1-Euro / Kalman filtreleri FaceMesh + köprü birleşik açı akışına kesintisiz uygulanır. `Cascade_PnP_to_BlazeFaceKP` artık `MediaPipe_SolvePnP_Raw` ile aynı olduğu için listeden çıkarıldı (sınıf ortak göz takibinde kullanılır).

Deniz videosu (referans 6DRepNet360: 3.42 → 3.96 sn): Raw / LK_Tracker / Iris 3.46 → 3.92 sn, 1Euro 3.50 → 4.04 sn, Kalman 3.50 → 4.08 sn, Hybrid_KP 3.50 → 3.92 sn.

## 6DRepNet360 ONNX (Stride4_ONNX)

`Cascade_PnP_to_6DRepNet360_Stride4_ONNX`, Stride4 kaskadının 6DRepNet360'ı ONNX Runtime ile çalıştıran sürümüdür (PyTorch gerekmez). Model bir kez `tools/export_6drepnet_onnx.py` ile dışa aktarılır. Araç PyTorch ve ONNX çıktılarını videodaki ROI karelerinde karşılaştırır (maks geodezik fark > 0.5° ise dosyayı yazmaz) ve 1/2/4 iş parçacığıyla gecikme tablosu basar. `run_server_benchmark.sh`, `.onnx` yoksa bunu otomatik yapar; doğrulama raporu `<model>.onnx.verify.json`.

Bağımlılık notu: `onnx` paketi protobuf ≥ 5 ister, mediapipe 0.10.x protobuf < 5 ister. Bu yüzden `onnx` yalnız `.onnx_export_deps/` klasörüne (`pip install --target`) kurulur ve sadece dışa aktarma sürecinde yüklenir; ana venv'e yalnız `onnxruntime` eklenir.

## Konsolide Raporlar

Her koşu `--output-dir` içine üç tek dosyalık rapor yazar (ayrık `bas_acilari_*.png` yazılmaz, eskileri silinir):
* `tum_modeller_raporu.pdf` — A3 yatay: 1) genel tablo, 2) çok modelli Yaw/Pitch/Sapma bindirmesi (6DRepNet360 referansına karşı), 3..N) her model ayrı sayfa (metrik bloğu + 5 panel: Yaw, Pitch, Roll, Baştan Sapma, ω).
* `karsilastirma_tablosu.xlsx` — `Genel_Kiyaslama` (tablo + gömülü bindirme grafiği), `Tum_Modeller_Yan_Yana` (kare kare tüm modeller), her model ayrı sayfa (özet + gömülü grafik + kare verisi).
* `tum_modeller_raporu.html` — tek, çevrimdışı dosya; sekmeler + "Tümünü Göster", gömülü grafikler.

Bayraklar: `--no-report` (raporları kapatır), `--reference-model AD` (uyum ölçütü referansı; varsayılan `6DRepNet360_Heavy_Reference`, yoksa `Cascade_PnP_to_6DRepNet360`). Bağımlılıklar: `matplotlib`, `openpyxl`, `pillow` (`run_server_benchmark.sh` eksikse kurar).

---

## 2. Kurulum ve Çalıştırma

### Bağımlılıklar:
```bash
pip install opencv-python mediapipe numpy
# (İsteğe bağlı 6DRepNet için: torch torchvision)
```

### Kıyaslamayı Çalıştırma:
```bash
python benchmark_runner.py --video test_video.mp4 --warmup 50 --out benchmark_sonuc.json
```

---

## 3. Ölçülen Metrikler (Celil'in Ölçüm İlkeleri)
* **İlk 50 kare ısınma (warmup):** İlk çağrıdaki bellek ayırma ve grafik optimizasyonu süreyi saptırmasın diye atılır.
* **Medyan ve p95 gecikme (ms):** Saf ortalama yerine p95 ve medyan raporlanır.
* **Yüz Kaybı İstatistiği:** Toplam kare, yüz bulunan kare, tespit oranı (%), yüzün kaybolduğu kare indeksleri.
* **Açısal Tutarlılık:** Geodezik uzaklık (derece) ile yöntemler arası uyum.
