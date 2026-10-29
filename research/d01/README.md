# D01 manuel etiketleme ve baş pozu deney kodları

## CLI ölçüm kapsamı — 29 Ekim 2026 tanılama güncellemesi

Model/ROI/protokol/filtre/eşik değişmedi; bu güncellemede gerçek çıkarım yapılmadı. `pilot_metrics.py` ile `state.json.runtime_environment`, `result.json.runtime_environment` ve `details/performance.json` gerçek Python sürümü/yürütülebilirini, paket dağıtım sürümlerini, PID/parent PID'yi, yüklenmiş Torch sürümünü, etkin intra/inter-op thread sayılarını ve model parametresinin cihazını kaydeder. Yüklü olmayan paket, ölçülmeyen thread veya replay'de yüklenmemiş runtime bilgisi null kalır; sadece kurulu paket sürümü Torch'un bu koşuda yüklendiğinin kanıtı değildir. Yerel ortam yolları operatör raporudur; backend'in güvenli ana sonuç projeksiyonuna girmez.

- Mevcut kare başı `inference_s` **forward duvar saati** olarak aynen kalır. Yeni `decode_s`, `preprocess_s` (RGB/ROI + resmî dönüşümler), `input_save_s` (PNG yazma), `model_attempt_wall_s` (forward + sonuç kontrolleri) ayrı alanlardır. Kayıt tekrarı eski forward değerlerini yeni performans ölçümü olarak toplamaz.
- `state.json.measurements.timings_s`: `runtime_initialization_s` içinde `model_load_s`; `raw_phase_s` içinde decode/ön işleme/PNG/prediction/JSONL/state işlemleri; `prediction_call_s` içinde `forward_s` bulunur. `raw_jsonl_write_s` JSONL serialize+flush+fsync; `state_checkpoint_write_s` atomik durum yazıları; `postprocess_detail_write_s` EMA/özellik/pencere/index yazılarının yardımcı gövdeleri; `report_files_write_s` ana JSON/özet/koruma raporu yazılarıdır. Bunlar tüm dosya sistemi etkinliğinin eksiksiz ayrıştırılması değildir.
- `postprocess_s` sabit EMA/hareket/yerleşme işlemleri **ve içindeki ayrıntı yazılarını** kapsar. İç içe süreler **toplanmaz**. Toplam için ayrıca `elapsed_s` kullanılır. `details/performance.json` ana sonuç yayımlanmadan önceki ölçüm anıdır; son değerler `state.json` içindedir ve son checkpoint kendi yazma maliyetini içermez. Hiç ölçülmemiş süre null kalır; eksik kareye süre uydurulmaz.
- Her tamamlanan ham karede `memory_current_run` UTC zaman damgası, monoton geçen süre, Python sürecinin birikimli CPU zamanı ve önceki örneğe göre CPU yüzdesi taşır. State ayrıca son kaynak örneğini içerir. Yüzde100 **bir CPU çekirdeğidir**, çok iş parçacığında100'ü aşabilir; bütün makine kullanımı değildir. Windows çalışma kümesi ve OS tepe çalışma kümesi ölçülür; mevcut yöntem desteklenmiyorsa bellek null + `memory_status` açıklaması olur. İlk CPU oranı null'dır; CUDA/GPU kullanımı, diğer süreçlerin yükü ve scheduler/termal durumu ölçülmez. Örnekler sürekli profiler değildir; yavaşlık nedenini tek başına ispatlamaz.

SIGTERM/OS zorla sonlandırmasında son CLI `running` kaydı kalabilir. Backend'in terminal `job.json` kaydı ile CLI dosyası farklı katmanları anlatır; yarım çıktı completed değildir. Ayrıntı ve ayrı süre sınırları: `backend/D01_PILOT.md`. Kesilen162 karelik eski kayıt, video ve manuel etiketler bu güncellemeyle değiştirilmez.

## Ortak pilot CLI — önerilen giriş

**29 Ekim 2026 — sonraki gerçek-model doğrulaması:** ikinci video ortak CLI ile `--manual` ve `--recorded-raw` verilmeden tamamlandı:168 çözümlenen/işlenen/geçerli,0 başarısız kare. Denetlenmiş RGB/tensör hash'leri168/168 eşleşti. Önceden belirtilen1e-6 eleman /0.001° SO(3) toleransları altında ham ve EMA farkları **tam0.0**; bütün aday/belirsizlik kayıtları ve630 yerleşme penceresi aynı. Manuel zamanlar ve çağrıya göre farklar null; state completed ve ayrıntı referansları/hash'leri doğrulandı. Yerel forward163.829 sn / CLI176.358 sn (iç içe); ham aşamada örneklenen Python OS tepe626.594 MiB, son postprocess tepe örneği yok. Kayıt: haricî `outputs/d01_headpose_6drepnet360/cli_gercek_video2_20261029T165724Z/INCELEME_SONUCU.md` ve `validation_result.json`; ana sonuç `run/result.json`. Bu kanıt aşağıdaki önceki birleştirme turunun “gerçek model yolu çalıştırılmadı” durumunu günceller; poz/ davranış doğruluğu veya genellenebilir performans kanıtı değildir. Kod/protokol değişikliği gerekmedi, tam çıkarım tekrar edilmedi.

`pilot_cli.py` video, insanın açıkça verdiği ROI/dolgu, yerel ağırlık, sabit protokol ve yeni haricî çıktı klasörüyle çalışır. İlk/ikinci video yolu, 168 kare veya manuel olay zamanları bu akışın kodunda sabit değildir. Eski deney betikleri ve sonuçlar korunur; yeni CLI geçmiş deney klasörü düzenini zorunlu tutmaz. `source_manifest.json` önceki kopyalama anının tarihsel hash kaydıdır; güncel ortak akış, çalıştırdığı kod ve parametrelerin hash'lerini kendi `settings.json` / `source_preservation.json` dosyalarına kaydeder.

Sıra: **CPU ham çıkarım (veya kayıtlı matrisleri yeniden kullanma) → nedensel SO(3) EMA .50 → mevcut V1 ana ayarı → bütün ham/EMA ×10°/15° yerleşme taramaları → isteğe bağlı manuel girdilerle sonradan pilot rapor**. `motion_candidates.detect`, `settling_regions.scan` ve `pilot_time_relations.build_report` yeniden kullanılır. Ortak EMA `rotation_processing.py`; resmî ön işleme/strict model yükleme `official_runtime.py` içindedir. Eski yumuşatma ve C çıkarım betikleri de bu ortak yardımcıları kullanır. Eşikler/model değişmedi. Eksik decoder zamanının hata vermesi engellendi; mevcut geçerli kayıtların hesapları değişmedi.

Sabit protokol `parameters/pilot_v1.json`, iki mevcut kural dosyasına içerik hash'iyle bağlıdır. Şu an **24 FPS** kare pencerelerini korur; başka FPS açık hata verir, yeniden örnekleme/uyarlama yapılmaz. Her videonun FPS, çözünürlük ve bildirilen kare sayısı videodan okunur; gerçek çözümleme/işlenen sayısı ayrıca tutulur. Bu sınır genel FPS desteği sağlandığı iddiası değildir.

ROI JSON örneği (yalnız örnek koordinatlar; her video için insan incelemesi gerekir):

```json
{"x":220,"y":140,"width":320,"height":320,"padding_ltrb_source_px":[0,0,0,0],"human_supplied":true}
```

Kaynak dışına taşan ROI için tam dolgu miktarı ve `padding_rgb` açık olmalıdır. Örneğin x250,y−40,440×440,1280×720 görüntüde `[0,40,0,0]` ve `[128,128,128]` gerekir. Sessiz kırpma/dolgu yoktur. İnsan ROI'si otomatik çocuk takibi veya model doğruluğu kanıtı değildir. Resmî Resize256/CenterCrop224/Normalize korunur.

Depo kökünde Windows PowerShell, **gelecekte yetkilendirilen yeni CPU koşusu için** tek komut biçimi (bu geliştirmede çalıştırılmadı):

```powershell
& '<MEVCUT_PYTHON_EXE>' -X utf8 -B research/d01/pilot_cli.py --video '<VIDEO.mp4>' --weights '<YEREL_AGIRLIK.pth>' --roi '<ROI.json>' --protocol research/d01/parameters/pilot_v1.json --official-source '<MEVCUT_RESMI_6DREPNET360_KLASORU>' --output-dir '<YENI_HARICI_DENEY_KLASORU>'
```

Manuel çağrı/baş hareketi girdisi istenirse `--manual '<LIBVLC_TASLAK.json>'` eklenir. Mevcut aracın `marks` biçimi kullanılır; yalnız çağrı işaretleri de verilebilir. `media_time_ms` ve `time_source` korunur. Parametre verilmezse manuel zamanlar ve çağrıya göre farklar **null** kalır; sıfır veya otomatik ses tespiti varsayılmaz. Manuel dosya yalnız tespit sabitlendikten sonra ayrıştırılır; hareket sınırları tespit kuralına girmez. Ayrı kullanıcı gözlemi dosyası `--user-review '<INCELEME.json>'` ile eklenebilir (tekrarlanabilir); hedef bilgisi yalnız kullanıcı gözlemidir.

**Model yüklemeden kayıtlı sonuç tekrarı:** aynı komutta `--official-source` yerine `--recorded-raw '<kareler.jsonl>' --recorded-report '<report.json>'` kullanılır. Video/ağırlık/ROI/protokol yine açık parametredir. Kaynak video, ağırlık, resmî kaynak provenance ve ROI eşleşmesi denetlenir; kaynak kayıtların zaman/ham matrisleri korunur. Bu modun çalışma süresi yeni çıkarım süresi değildir; ham kayıtlardaki eski `inference_s` kaynak ölçümdür.

### Küçük sonuç sözleşmesi

- `result.json`: **`schema_version:d01-pilot-result-1.0`**, protokol sürümü, video kimliği/hash'i, ROI/kaynak, manuel aday ve zaman eşleme sınırları; ham/EMA **bütün ana adayları**, ayrı başlangıç/bitiş/doğrulama zamanları ve çağrıya göre aritmetik farklar; koşul bazında yerleşme sayıları ve ayrıntı referansları. Algoritmik hedef belirlenmedi. Kaynak gözlemi ile algoritma/inceleme durumu ayrı kalır.
- `detail_files`: göreli dosya yolu + SHA256. `details/raw_frames.jsonl`, `ema_frames.jsonl`, `features_raw.jsonl`, `features_ema_050.jsonl`, `motion.json`, `settling_windows.jsonl`, `settling_index.json` büyük kare/pencere ve belirsizlik kayıtlarını taşır. Yerleşme bitişi hareket bitişi sayılmaz.
- `state.json`: running/completed/interrupted/failed, aşama, işlenen/geçerli/geçersiz sayıları, yerel süre; `result.json` ancak **state completed** ise tamamlanmış rapor olarak kullanılmalı. Her kare ve pencere flush/fsync ile yazılır. Ctrl+C/SIGBREAK/uygulanabilir SIGTERM kesintisi kaydedilir; OS zorla sonlandırmasında son running kaydı kalabilir ve tamamlandı sayılmaz. Otomatik devam/üzerine yazma yok; yeni klasör gerekir.
- Eksik kayıt kareleri, decoder durduktan sonraki bildirilen fakat çözümlenemeyen kareler ve geçersiz matrisler silinmez. Decoder zamanı bilinmiyorsa null; nominal frame/FPS ayrı. OpenCV EOF/bozulmayı her durumda ayıramaz. Sayısal olarak geçersiz kaynak matris orijinaliyle korunup analiz için geçersiz işaretlenir; doldurma yok. Veri/zaman kopmasında EMA referansı sıfırlanır, boşluk üzerinden filtreleme yapılmaz. Sabit geçerli koşullarda önceki EMA ile aynıdır.

### Bu tur doğrulama ve kalan sınırlar

İki kaydın yeniden kullanımı `outputs/d01_headpose_6drepnet360/ortak_cli_kontrol_20261029T164036Z` altında `video1_final/result.json` / `video2_final/result.json` dosyalarındadır; **yeni model çıkarımı yapılmadı**. İki videoda da EMA eleman farkı 0.0, V1 ana adayları/belirsizlikleri aynı; bütün **594 / 630** yerleşme penceresi birebir aynı. Ana JSON'lar 12,324 / 18,586 bayt. `regression_checks_final.json` son karşılaştırmayı kaydeder; önceki kontrol çıktıları silinmedi. İlk videonun eski ±%20 denemeleri kendi arşivinde kalır; ortak CLI yalnız sabit ana ayarı yeniden uygular, yeni parametre aramaz. Bu tur araştırma test grubunda **62 test geçti** (6.188 sn); gerçek model/medya doğruluğu değil. Kontrollü kesinti/yazma, eksik alan/zaman/matris, açık dolgu, farklı kare sayısı, manuel girdinin tespiti etkilememesi ve eski davranış testleri kapsandı. Yeni gerçek model çıkarım yolu çalıştırılmadı.

İnsan ROI seçimi/tüm-kare görsel kabulü, manuel seslenme/olay işaretleme, bağımsız LibVLC–decoder senkron doğrulaması ve bilimsel/klinik doğruluk değerlendirmesi otomatikleşmedi. Ortak CLI yeni çizelge/eksen sayfası üretmez; önceki grafik araçları/çıktıları korunur. Yeni ortak **gerçek model çalıştırma yolu henüz uçtan uca çalıştırılmadı**; kayıt tekrarı ve kontrollü testler gerçek model doğrulaması yerine geçmez. Başka FPS/model yeni protokol kararı gerektirir. Backend/mobil entegrasyonu yoktur.

```powershell
& '<MEVCUT_PYTHON_EXE>' -X utf8 -B -m unittest discover -s research/d01 -p 'test_*.py' -v
```

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

## İlk deneysel hareket adayı taraması

Bu V1 korunur. Ayrı yönelim bölgesine yerleşme deneyi aşağıdaki bölümde tanımlanmıştır; V1 başlangıçlarını veya bitişlerini değiştirmez.

`motion_candidates.py` yalnız kayıtlı ham ve nedensel EMA 0.50 matrislerini tarar; model veya manuel etiket almaz. `parameters/motion_candidates_v1.json` önceden sabitlenmiş 5 aralıklı nedensel medyanı, 3 başlangıç/5 bitiş doğrulama örneğini ve 36/16, 45/20, 54/24 °/sn mühendislik eşiklerini kaydeder. Bunlar tahmin matrislerinin hareketliliğidir, klinik eşik veya fiziksel poz doğruluğu değildir. Bilinmeyen başlangıç/bitiş null kalır; boşluk doldurulmaz. Geçersiz/zamanı kopuk veriler kesinti olarak saklanır. Tüm adaylar, kısa doğrulanmamış koşular ve histerezis aralıkları `detection.json` içindedir.

Manuel karşılaştırma ayrı `compare_motion_candidates.py` komutudur; mevcut `detection.json` üzerinde değişiklik yapmaz. Bütün adayları tek manuel adayla aritmetik olarak karşılaştırır; en iyi eşleşme seçmez. Diğer adayların bağımsız etiketi yoktur; kendiliğinden yanlış pozitif sayılmaz. Zaman farkları doğrulanmamış LibVLC/decoder eşlemesine dayanır, kesin milisaniye hatası değildir.

```powershell
& $python -X utf8 -B -m unittest discover -s research/d01 -p test_motion_candidates.py -v
& $python -X utf8 -B research/d01/motion_candidates.py --raw-dir '<MEVCUT_CPU_KLASORU>' --smoothed-dir '<MEVCUT_YUMUSATMA_KLASORU>' --output-dir '<YENI_HARICI_ADAY_KLASORU>'
& $python -X utf8 -B research/d01/compare_motion_candidates.py --detection-dir '<YENI_HARICI_ADAY_KLASORU>' --manual-json '<MANUEL_CALISMA_KOPYASI_JSON>'
```

29 Ekim ilk taramasında ana ayar hamda yaklaşık 0.79–5.21 sn, EMA'da 0.83–5.29 sn tek aday verdi. İlk hareketin yaklaşık 1.40 sn manuel bitişi **ayrılamadı**; sonraki değişimler ve tahmin titreşimi birleşiyor. EMA'nın +%20 eşiğinde iki aday oluşması parametre duyarlılığıdır, en iyi ayar kanıtı değildir. Sonuçlar ayrı yerel `motion_candidates_20261029T123326Z` klasöründedir; ham kayıtlar değiştirilmedi. 36. kare kullanıcı incelemesiyle yalnız model kararsızlığı adayıdır, kesin hata etiketi değildir.

## Yönelim bölgesine yerleşme deneyi

`settling_regions.py` yalnız kayıtlı ham/EMA .50 matrislerini kullanır; model veya manuel etiket okumaz. İşlemden önce kaydedilen `parameters/settling_regions_v1.json`: 10°/15° SO(3) yarıçap, 9 karede 8 destek, ilk medoid sabit tutularak sonraki çakışmayan 9 karede 8 destek ve merkezler arasında en fazla yarıçap/2. Başlangıç referansı V1 ana başlangıcından önceki 9 geçerli kesintisiz kare medoididir; iki yeni merkez de referanstan 2×yarıçaptan uzak olmalıdır. Bu referans doğrulanmış nötr poz değildir. Parametreler manuel bitişe uydurulmadı.

V1 başlangıçları sabit kalır; V1 bitişi taramayı kesmez. Her olası pencere, ret nedenleri ve klip sonunda doğrulanamama korunur. Aday ilk blok aralığı, ikinci bloğun sonunda kullanılabilir doğrulama zamanı ve üç ardışık dış örnekle doğrulanan sonraki ayrılma ayrıdır. 24 FPS örneklerinde doğrulama ilk blok bitiminden 0.375 sn sonradır; geçmiş pencere anında tespit edilmiş sayılmaz. Komşu kabul pencereleri bağımsız hareket veya tek sabit merkezli uzun bölge değildir.

```powershell
& $python -X utf8 -B -m unittest discover -s research/d01 -p test_settling_regions.py -v
& $python -X utf8 -B research/d01/settling_regions.py --raw-dir '<MEVCUT_CPU_KLASORU>' --smoothed-dir '<MEVCUT_YUMUSATMA_KLASORU>' --v1-dir '<MEVCUT_V1_KLASORU>' --output-dir '<YENI_HARICI_YERLESME_KLASORU>'
& $python -X utf8 -B research/d01/compare_settling_regions.py --experiment-dir '<YENI_HARICI_YERLESME_KLASORU>' --manual-json '<MANUEL_CALISMA_KOPYASI_JSON>'
```

29 Ekim koşusu: 12 sentetik kontrol geçti; 594 pencereden ham10/ham15/EMA10/EMA15 için 24/18/27/23 kabul. Tüm kabul/retler, sonraki ayrılmalar, manuel adayla **sonradan** karşılaştırma ve sınırlar ayrı yerel `settling_regions_20261029T132523Z/INCELEME_SONUCU.md` dosyasındadır. Çok yavaş sürüklenme kabul edilebilir; medoid fazı küçük salınımı reddedebilir. Yarıçap artışı ayrılma şartını da değiştirir; sonuçlar monoton değildir. İlk fiziksel dönüşün yaklaşık manuel bitişi ayrılmış sayılmaz. Baş pozu bölgesi, hedefe bakış/isme tepki veya doğruluk artışı değildir. Model yeniden çalıştırılmadı, etiketler değiştirilmedi/onaylanmadı.
