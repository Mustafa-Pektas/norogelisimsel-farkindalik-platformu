# İsme Tepki Analizi

24 FPS videolarda seslenmeye yönelme, baş hareketinin durması ve başın
başlangıç pozuna dönmesi için olay adayları çıkarır. Video raporunda baş
kutusu, baş yönü, hedef tahmini ve olay zamanları gösterilir.

## Kurulum

Windows ve 64 bit Python 3.9 ile PowerShell örneği:

```powershell
python -m venv .venv
& '.\.venv\Scripts\python.exe' -m pip install -r requirements.txt
```

Baş pozu modelleri CUDA destekli PyTorch ve TorchVision ile GPU’da
çalışabilir. Çalıştırma sırasında `--head-pose-device cuda` veya
`--head-pose-device cpu` seçilebilir. [PyTorch sürümleri](https://pytorch.org/get-started/previous-versions/)

## Model dosyalarını hazırlama

`optik_akis.ornek.json`, DirectMHP ve isteğe bağlı 6DRepNet360
karşılaştırmasının dosya yollarını tanımlar.

1. DirectMHP-S CMU-HPE ağırlığını ve belirtilen kaynak sürümünü indir.
   Depo kökünde `third_party/` altında tutabilirsin. [Resmî DirectMHP kaynağı](https://github.com/hnuzhy/DirectMHP/tree/a51b06bc34ed4202a9e9d1aad1c1cac9b6de05d0) · [CMU-HPE ağırlığı](https://huggingface.co/HoyerChou/DirectMHP/blob/main/cmu_s_1280_e200_t40_lw010_best.pt)
2. Ağırlığı analiz biçimine aktar. Örnekte kaynak klasörünün adı `DirectMHP`.

   ```powershell
   & '.\.venv\Scripts\python.exe' -m pip install pandas==2.2.3 seaborn==0.13.2 'setuptools<81'
   & '.\.venv\Scripts\python.exe' -B scripts/export_directmhp.py --source third_party/DirectMHP --weights third_party/cmu_s_1280_e200_t40_lw010_best.pt
   ```

3. 6DRepNet360 karşılaştırması için Full Rotation ağırlığını
   `6drepnet360_denemesi/` klasörüne koy. Yalnız DirectMHP kullanacaksan ayar
   dosyasından `head_pose.repnet360` satırını çıkar. [6DRepNet360 model kaynağı](https://github.com/thohemp/6DRepNet360)

Gaze-LLE ve DINOv2 ağırlıkları ilk görüntü ölçümünde model yükleyicisi
tarafından alınır. [Model kaynakları](ses_yonelme/THIRD_PARTY.md)

## Kendi videonu analiz etme

Depo köküne `video.mp4` koy. Aşağıdaki çağrı zamanlarını ve ismi kendi videona
göre düzenle. İlk komut sahne bölgelerini seçmeni ister. İkinci komut her
çalıştırmada ayrı bir rapor ve `isaretli_video.mp4` üretir.

```powershell
& '.\.venv\Scripts\python.exe' -B ses_yonelme/select_regions.py --video video.mp4 --output isme_tepki/sahne.json --call-start 1.0 --call-end 1.8 --name Deniz
& '.\.venv\Scripts\python.exe' -B isme_tepki/analiz.py --config isme_tepki/optik_akis.ornek.json
```

İsim zamanlarını Faster-Whisper ile aramak için `audio_label_tool/requirements.txt`
bağımlılıklarını kur ve analiz ayarına `"calls": []` ile birlikte
`"audio": {"name": "Deniz", "language": "tr", "model": "small"}` ekle.

## Testler

```powershell
& '.\.venv\Scripts\python.exe' -B -m unittest discover -s isme_tepki/tests -q
```
