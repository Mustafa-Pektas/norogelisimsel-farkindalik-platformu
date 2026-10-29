# D01 manuel etiketleme ve baş pozu deney kodları

Bu klasör mevcut bağımsız çalışmanın **kod kopyalarını**, önceden belirlenmiş parametrelerini ve kısa sonucunu Git ile korur. Mobil/backend analiz entegrasyonu değildir. Özgün `araclar/`, `etiketler/`, `calisma/`, `outputs/`, video, sanal ortam ve resmî model deposu mobil Git deposunun dışındadır; taşınmadı. Ham veriler ve büyük deney arşivi GitHub'a eklenmedi. **Temiz checkout tek başına deneyi yeniden üretmeye yetmez**; aşağıdaki haricî girdiler de korunmalıdır.

## İçerik ve taşınabilirlik

| Kod | Görev | Gereken mevcut girdiler |
|---|---|---|
| `d01_etiketleme.py`, `d01_libvlc.py` | Var olan LibVLC/Tkinter manuel işaretleme | Kaynak video, ayrı CSV/JSON çalışma kopyaları, Windows x64 VLC |
| `roi_review.py` | A/B/C ROI, resmî ön işleme ve bütün-kare görselleri; model çıkarımı yok | Önceki ROI/zaman raporu, yerel video/ağırlık hashleri, resmî kod |
| `infer_c_cpu.py` | C için 168 karelik CPU çıkarımı; her kare JSONL + fsync, atomik durum kaydı | Denetlenmiş C girdileri, `kareler.csv`, `ayarlar.json`, `roi_oneri.json`, `gorsel_inceleme.json`, önceki provenance, yerel ağırlık/resmî kod, manuel aday JSON |
| `smooth_rotations.py` | Kayıtlı matrisleri karşılaştırma; model yüklemez | Tamamlanmış CPU kayıtları, denetlenmiş C görüntüleri, resmî `utils.py`, aday etiket klasörü |

`source_manifest.json` özgün kaynakların göreli adlarını/hashlerini ve depoya uyarlanmış kopyaların hashlerini ayırır. Uyarlamalar: açık `--data-root` / `--output-dir`, isteğe bağlı video/ağırlık/resmî kod/girdi dizini yolları, başka makinenin mutlak yollarını içeren eski koruma manifesti yerine mevcut girdilerden yeni manifest, sabit sanal ortam klasör adına bağımlılığın kaldırılması. Ağırlık/kaynak/video hash, strict yükleme ve matris kontrolleri korunur. Çıktı klasörü yeni olmalı ve **Git checkout'u dışında**, veri kökü altında bulunmalıdır. Özgün deneyler düzenlenmez. LibVLC için `D01_DATA_ROOT` yalnız mevcut oturumda haricî veri kökünü belirtir.

Betikler mevcut deney veri düzenini kullanır; genel veri indirme/kurma sistemi değildir. Haricî kökte şunlar beklenir: `videolar/`, `araclar/` altındaki mevcut `.pth`, `dis_kaynaklar/6DRepNet360`, `etiketler/`, `calisma/` ve `outputs/d01_headpose_6drepnet360/` altındaki tarihli deney girdileri. Başka makinede `--video`, `--weights`, `--official-source`, `--annotations`, `--roi-dir`, `--raw-dir` ile yollar açıkça verilir. Video/etiket kimliği ve hashleri uyuşmazsa kayıt sessizce değiştirilmez; deney durur. ROI inceleme betiği görsel kabul veya `roi_oneri.json` oluşturup onaylamaz; mevcut insan inceleme kararı ayrıca gereklidir.

Ortam referansı: Python 3.11.9, CPU Torch 2.14.1+cpu, torchvision 0.29.1+cpu, OpenCV 5.0.0, Pillow 12.3.0 ve mevcut NumPy/SciPy/Matplotlib. Bunlar bu kapanışta kurulmadı veya indirilmedi; bağımlılık paketi ya da ağırlık vendoring yapılmadı. İşletim sistemi/CPU ve kütüphane farklılıklarında aynı sayısal çıktı garanti edilmez. Resmî kaynak commit'i/hashleri ve ağırlık hash'i denetlenir; kendiliğinden indirme yok.

## Windows PowerShell — kontroller (çıkarım başlatmaz)

Depo kökünde; `$python` mevcut uygun Python ortamının yürütülebiliridir:

```powershell
$python = '<MEVCUT_PYTHON_EXE>'
& $python -X utf8 -B -m unittest discover -s research/d01 -p 'test_*.py' -v
& $python -X utf8 -B research/d01/infer_c_cpu.py --help
```

Etiketleme testleri gerçek kayıtlar yerine sentetik fixture kullanır. Tkinter arayüz akışı gizli pencere ve fake oynatıcı ile sınanır; gerçek VLC, ses, video veya insan doğrulaması değildir. CLI kontrolleri çıktı oluşturmadığını ve checkout içine deney yazılmadığını sınar. Bu kopyaların tam ROI/çıkarım/yumuşatma koşuları kapanışta tekrar çalıştırılmadı.

## Windows PowerShell — manuel çalışma kopyalarıyla açma

Yeni kopya oluşturmak için haricî veri kökü ve **mevcut videonun gerçek yolu** kullanıcı tarafından verilir. Hiçbir değer kaynak videodan tahmin edilmez. JSON içindeki video referansı eşleşmelidir:

```powershell
$env:D01_DATA_ROOT = '<HARICI_VERI_KOKU>'
$python = '<MEVCUT_PYTHON_EXE>'
$video = '<MEVCUT_KAYNAK_VIDEO>'
$work = Join-Path $env:D01_DATA_ROOT ('calisma/d01_' + (Get-Date -Format yyyyMMddTHHmmss) + '_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -ErrorAction Stop | Out-Null
Copy-Item -LiteralPath (Join-Path $env:D01_DATA_ROOT 'etiketler/d01_ilk_ornek.csv') -Destination (Join-Path $work 'd01_ilk_ornek.csv') -ErrorAction Stop
Copy-Item -LiteralPath (Join-Path $env:D01_DATA_ROOT 'etiketler/d01_ilk_ornek_taslak.json') -Destination (Join-Path $work 'd01_ilk_ornek_taslak.json') -ErrorAction Stop
& $python -X utf8 -B research/d01/d01_etiketleme.py --video $video --csv (Join-Path $work 'd01_ilk_ornek.csv') --draft (Join-Path $work 'd01_ilk_ornek_taslak.json')
```

Var olan çalışmaya devam ederken yeni kopya üretmeyin; aynı çalışma CSV/JSON yollarını açıkça verin. C/B/R çağrı başlangıcı/bitişi ve hareket başlangıcı; E isteğe bağlı hareket bitişi. Giriş kutularındayken kısayollar çalışmaz; düğmeler kullanılabilir. Seslenen kişinin konumu, hedef, belirsizlik ve not kullanıcı beyanıdır. S önizleme; onaylı CSV yazımı öncesi yedek, iptalde CSV korunur. T ayrıntıları çalışma JSON'una kaydeder. İlk nominal aday ve değişiklik geçmişi korunur.

İşaretler yalnız duraklatılmış oynatıcının **bildirdiği** geçerli medya zamanından alınır; istenen seek ile uyuşmazsa reddedilir. Nominal FPS zamanı gerçek kare PTS'si değildir. `response_start-call_start` ile `response_start-call_end` ayrıdır; ikincisi negatif olabilir. Çağrı ve hareket bitişleri başlangıçlarından önce olamaz. Bilinmeyen zaman boş kalır; kayıt otomatik onaylanmaz. CSV/JSON v1 okunur, yeni yazımlar v2'dir; eski CSV başlıklarının altına farklı sütunlu satır eklenmez. Kısa klipte görülmeyen süre için “tepki yok” üretilmez.

## Sonraki yetkili deney için komut biçimleri — bu kapanışta çalıştırılmadı

`--output-dir` her seferinde haricî kök altında yeni bir klasör olmalı. Önce insan tarafından C koşulunun kabulü gerekir. Parametre ekleme komutu otomatik üretim başlatmaz; aşağıdaki çıkarım komutu ancak açık deney kararıyla çalıştırılmalıdır:

```powershell
& $python -X utf8 -B research/d01/roi_review.py --data-root '<HARICI_VERI_KOKU>' --output-dir '<HARICI_VERI_KOKU>/outputs/YENI_ROI_KLASORU'
& $python -X utf8 -B research/d01/infer_c_cpu.py --data-root '<HARICI_VERI_KOKU>' --roi-dir '<DENETLENMIS_C_KLASORU>' --output-dir '<HARICI_VERI_KOKU>/outputs/YENI_CPU_KLASORU'
& $python -X utf8 -B research/d01/smooth_rotations.py --data-root '<HARICI_VERI_KOKU>' --raw-dir '<TAMAMLANMIS_CPU_KLASORU>' --roi-dir '<DENETLENMIS_C_KLASORU>' --output-dir '<HARICI_VERI_KOKU>/outputs/YENI_YUMUSATMA_KLASORU'
```

Şu an ilk iş bu komutları tekrar çalıştırmak değil, var olan grafik/eksen sayfalarını birlikte incelemektir. `results/2026-10-29_summary.md` kısa sonuç ve sınırları içerir. Tam ham deney arşivi yalnız yereldedir ve ayrıca yedeklenmelidir; kodun GitHub'da olması deney verisinin yedeği değildir.
