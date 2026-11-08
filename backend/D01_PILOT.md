# Deneysel D01 analiz işi — yerel bağlantı

## Güncel yerel hızlı yol — 8 Kasım 2026, API 1.2

**Son doğrulama:** kullanıcı normal Windows PowerShell'de iki videolu gerçek hızlı API kontrolünün geçtiğini bildirdi; anne–çocuk videosunun mobil görünür sonuç süresi 19,926 sn, poz kapsamı 100/190 kare, ilk bitiş belirsizdir. Son bitiş sunumu değişikliğinde `d01_pilot_panel_test.dart` içindeki 16 test kullanıcı tarafından geçti. Aşağıdaki ilk hazırlık/başarısız deneme kayıtları tarihsel olup bu doğrulamalarla karıştırılmamalıdır; güncel tüm mobil grubun bu commit için yeniden çalıştırıldığı iddia edilmez. Kaynak atfı ve kullanıcı paylaşım izni: [vendor/README.md](../research/d01/vendor/README.md).

Mevcut POST/GET/status/result/DELETE yolları kullanılır. Multipart `method=mediapipe_pnp_flow` hızlı CPU Tasks/PnP+optik akış yolunu seçer. `video` zorunlu; `targetPoint=[x,y]` isteğe bağlı normalize ilk-kare yüz noktasıdır (0–1, dikdörtgen değildir). `callStartS`/`callEndS` birlikte isteğe bağlı, milisaniye çözünürlüğünde kullanıcı işaretleridir. Gönderilmezse çağrı ve farklar null kalır. Hareket sınırı, çalıştırılabilir yol veya ROI bu yönteme gönderilmez. 24 FPS / 30 sn / 25 MiB sınırı korunur.

Sunucuya ait mutlak `PILOT_D01_FAST_PYTHON` ve `PILOT_D01_FACE_MODEL` yolları gerekir. Yerel başlatıcı mevcut `calisma/venv_d01_hybrid_20261107_01/Scripts/python.exe` ve `calisma/Video Analizinin Feasibility Testi/face_landmarker.task` dosyasını kullanır. Yeni paket veya model indirilmedi. Bu yerel yapılandırmadır; uzak sunucu güncellenmedi. Eski yöntem alanı olmayan API1.0/1.1 istekleri ve iki hazır ROI profili aynı 6D yolunda korunur; eski yerel 4/14 thread davranışı değiştirilmedi. Mobil pilot ekranının etkin yolu hızlı yöntemdir; 6D karşılaştırması araştırma referansıdır.

`research/d01/vendor/friend_vision.py` ZIP'teki değişmemiş FaceTrack/LK/PnP kodudur. Tasks çoklu yüz araması ve muhafazakâr konum/görünüm eşleştirmesi adaptörde yapılır. Başlangıçta birden fazla olası yüz varsa seçilmez. İsteğe bağlı tek dokunuş yüzü belirtir; kişi yaşı veya çocuk kimliği otomatik doğrulanmaz. Uzun kayıptan sonra başka yüze yeniden bağlanılmaz. Optik akışta matris/açı null; PnP reddi ve takip kaybı da eksik ölçümdür. Bu mühendislik sınırları hedef kimliğinin kesin korunduğu iddiası değildir.

API1.2: kabul edilen jobId/videoHash ile eşleşen `source.type=automatic_face_tracking`, `coverage`, `missingPoseIntervals`, `manualTimes`, ham/EMA `movements`, `callPhase` ve `timings` döner. Başlangıç/bitiş/doğrulama zamanları ayrı; bilinmeyen bitiş null. Çağrıdan önce başlayan aday sonradan yeni tepki diye etiketlenmez. `settling=[]`; yerleşme veya doğru kişiye yönelme hesaplanmış gibi gösterilmez. Detay JSONL/ham hata/yerel yol API'ye verilmez.

Süre kapsamları: `upload_s` backend kabulünden yükleme bitimine; `child_process_s` çocuk başlatılmasından kapanışına; Python `total_s` kendi toplamıdır. Model, ön kontrol, takip/PnP ve son işleme süreleri Python toplamının alt kapsamlarıdır; bunlar birbiriyle toplanmaz. Ayrı optik akış süresi ölçülmedi. Mobil, açık Başlat eyleminden sonuç çizilip görünür konuma kaydırılmasına kadar oturumluk süre ölçer; ağ kesintisiyle aynı işe devam edilmesi bu süreye dahildir. Anahtar içermeyen ölçüm özeti isteğe bağlı kopyalanabilir.

**Bu tur:** 39 kontrollü backend ve 6 takip/CLI testi geçti. İki gerçek hızlı Python koşusu tamamlandı; bunlar mobil uçtan uca süre değildir. Gerçek loopback HTTP yüklemesi kabul edildi fakat alt süreç `cli_start_failed` ile başlayamadı; bu oturumda Node→Python gerçek kabulü doğrulanmadı. Test backend'i kapandı. Flutter testi çıktısız kaldı ve yalnız kendi komutu iptal edildi; doğrudan Dart analizinde telemetri dosyasına erişim engeli çıktı. Normal PowerShell doğrulaması ve son emülatör kabulü açık.

### Son yerel kabul — normal Windows PowerShell

Önce mobil kontrolleri çalıştırın:

```powershell
Set-Location C:\Projeler\Norogelisim\mobil_rag_223bc7d\mobile_skeleton
& C:\dev\flutter\bin\flutter.bat test --no-pub test/d01_fast_input_test.dart test/d01_marked_input_test.dart test/d01_pilot_service_test.dart test/d01_pilot_panel_test.dart test/video_analysis_source_test.dart
if ($LASTEXITCODE -ne 0) { throw 'Mobil testler başarısız' }
& C:\dev\flutter\bin\flutter.bat analyze --no-pub
```

Ayrı PowerShell'de yerel backend (gerçek .env okunmaz, mevcut port doluysa süreç sonlandırılmaz):

```powershell
Set-Location C:\Projeler\Norogelisim\mobil_rag_223bc7d
$pilotSecret = Read-Host 'Oturumluk ekip anahtarını girin' -AsSecureString
$pilotCredential = [System.Net.NetworkCredential]::new('', $pilotSecret)
try { @{accessKey=$pilotCredential.Password} | ConvertTo-Json -Compress | node backend/start_d01_pilot_local.js }
finally { $pilotCredential = $null; $pilotSecret = $null }
```

Diğer PowerShell:

```powershell
Set-Location C:\Projeler\Norogelisim\mobil_rag_223bc7d\mobile_skeleton
& C:\dev\flutter\bin\flutter.bat run --no-pub --dart-define=D01_PILOT_SERVER_URL=http://10.0.2.2:8000
```

Video Analizi → Deneysel D01: önce denetlenmiş `20261024200833.mp4`, sonra 595bd04e… işindeki anne/çocuk videosu. Her video için ilk karede çocuğun yüzüne tek dokunuş yapın; oynatma ilerlemişse ilk dokunuş yalnız başa alır, yüz noktasını ilk karede tekrar seçin. Çağrıyı biliyorsanız oynatıcıdan iki sınırı işaretleyin; bilmiyorsanız ikisini boş bırakın. Aynı oturum anahtarını girip açıkça Başlat'a basın. Sonuçta kapsam/kayıp ve bilinmeyen bitişi, ham/EMA adaylarını kontrol edin; adaya dokunma aynı videoyu duraklatılmış olarak görünür kılmalı. Ölçüm özetini kopyalayın. İkinci videonun manuel hareket sınırları yoktur; hata hesabı yapılamaz. Bu son adım henüz yapılmadı; süreler uydurulmadı.



## Profil dışı kullanıcı işaretli video — yerel API 1.1

Bu bölüm güncel genişletmedir; aşağıdaki iki-video/alan sınırı notları tarihsel1.0 sözleşmesini anlatır. Mobil arayüz bu adımda değiştirilmedi; yeni yolun1.1 sonucunu henüz okuyamaz.

Mevcut `POST /api/pilot-d01/jobs` ve GET durum/sonuç/DELETE yolları kullanılır. Auth, tek aktif iş (kuyruk yok), iptal/timeout,25 MiB dosya sınırı ve1 MiB genel JSON sınırı korunur. İki hazır SHA profili ROI alanı verilmeden otomatik ROI ve `d01-pilot-api-1.0` yanıtıyla çalışır. Hazır profil için ROI gönderilirse `profile_roi_fixed` döner; otomatik ROI sessizce değişmez. Profil tablosu düzenlenmedi.

Profil dışı videoda multipart alanları:

| Alan | Anlam |
|---|---|
| `video` | Tek video dosyası; en fazla25 MiB |
| `roi` | JSON metni: yalnız tamsayı `x,y,width,height`; kaynak görüntü pikselleri, sol üst başlangıç. Ekran/thumbnail koordinatı değildir. |
| `callStartS`, `callEndS` | İkisi zorunlu; sonlu, negatif olmayan ondalık saniye, en fazla milisaniye çözünürlüğü; bitiş başlangıçtan önce olamaz. |

Örnek alanlar (gerçek çağrı başlatmaz):

```text
video: <seçilen yeni dosyanın baytları>
roi: {"x":220,"y":140,"width":320,"height":320}
callStartS: 0.401
callEndS: 1.152
```

Kullanıcı ROI'si dolgusuz ve görüntünün içinde olmalı. Yeni yol **24 FPS, en fazla30 saniye/720 çözümlenmiş kare**, sabit boyut ve en fazla8388608 piksel/kare ile sınırlıdır. Bunlar kaynak kullanım sınırlarıdır; davranış/klinik eşikler değildir. Python `--user-marked` ön kontrolü tüm kısa videoyu **model yüklemeden** çözümler; gerçek kare boyutlarını, kare sayısını, OpenCV zamanlarının24 FPS çizgisiyle1ms içinde uyumunu ve çağrı aralığını doğrular. Süre, çözümlenen CFR video karelerinin kapsadığı zamandır (`count/24`); ses izi süresi, bağımsız PTS/AV senkron doğrulaması veya LibVLC zamanı değildir.24FPS dışı/uyumsuz zaman çizgisi yeniden örneklenmez, yanlış ROI kırpılarak/dolguyla düzeltilmez. Başın doğru seçildiği veya seslenmenin doğru işaretlendiği anlamsal olarak onaylanmaz.

Yükleme alanları yapısal olarak doğruysa202 döner. Bu, geometri/süre doğrulaması veya tamamlanmış analiz demek değildir. Özel video için202 ek alanları `videoHash` ve `sourceType: user_marked` içerir. Gerçek medya ön kontrolü aynı iş içinde çalışır; başarısızsa GET durumunda failed ve güvenli `invalid_roi`, `invalid_manual_times`, `unsupported_fps`, `unsupported_timeline`, `video_too_long` veya `invalid_video` kodu görülür. Model yüklenmez; slot çocuk süreç gerçekten kapanınca bırakılır. ROI verilmemiş bilinmeyen video422 `roi_required`; bozuk ROI/eksik veya ters çağrı aralığı400 olur. Multipart sınırı yalnız bu yol için1 dosya+3 kısa alan, alan başına256 bayt, parça sınırı5 oldu (Busboy sınır olayı payı dahil).

Özel sonucun yeni alanları (şema örneği; ölçülmüş analiz değildir):

```json
{
  "schemaVersion": "d01-pilot-api-1.1",
  "jobId": "<UUID>",
  "profileId": null,
  "videoHash": "<yüklenen baytların sunucuda hesaplanan SHA256 değeri>",
  "source": {
    "schemaVersion": "d01-input-source-1.0",
    "type": "user_marked",
    "roi": {"x":220,"y":140,"width":320,"height":320,"padding_ltrb_source_px":[0,0,0,0],"human_supplied":true},
    "video": {"width":1280,"height":720,"fps":24,"durationS":7,"decodedFrames":168,"durationSource":"decoded_CFR_video_frame_extent"},
    "validation": "media_bounds_only_not_content_or_ROI_quality_approval"
  }
}
```

Mevcut `manualTimes`, ham/EMA `movements`, ayrı doğrulama zamanları, sayılar ve yerleşme özetleri korunur. Manuel çağrı zamanlarının kaynağı `manual_user_input`, durum `unreviewed`; hareket işaretleri kabul edilmez/null kalır. Çağrıya göre zaman farkları negatif olabilir, davranış/tepki sınıfı değildir. `algorithmicTarget=not_determined`, `clockAlignmentVerified=false` kalır.

**Hash allowlist değildir:** backend her yüklemenin SHA'sını hesaplar; CLI sonucu/manuel dosya/ayrıntı hash'leri aynı işe bağlanır. Allowlist yalnız otomatik hazır ROI seçer; profil dışı video doğru kullanıcı girdileriyle kabul edilir.1.1 kaynağı, ROI ve çözümlenen medya bilgisi sonuçta kontrol edilerek aktarılır; yerel dosya yolu veya traceback API'ye çıkmaz. Mobil sonraki adımda1.1 kaynağını, dolu çağrı zamanlarını ve yüklenen baytlar/iş/hash ilişkisini doğrulamalıdır; mevcut1.0 profiller korunmalıdır.

Yerel kontrollü kontroller: `node --test --test-isolation=none backend/test/d01_pilot_jobs.test.js backend/test/deployment_mode.test.js` **31 geçti**; araştırma Python'uyla `python -m unittest test_pilot_cli test_pilot_metrics` **26 geçti**. Backend sahte çocuk süreç kullanır; Python kontrollü kısa video çözümlemesi, sahte runtime ve bozuk girdi kontrolleridir. Bu sonuçlar yeni gerçek videonun model doğruluğu, mobil uçtan uca kullanım veya uzak dağıtım kanıtı değildir. Gerçek model/API üretimi ve sunucu değişikliği bu adımda yapılmadı.

## Emülatör için kalıcı yerel oturum — 29 Ekim 2026 hazırlığı

Mobil pilotun22 video testi, dört dosyalık60 test grubu ve temiz Flutter analizi **kullanıcı tarafından** bildirildi; bu hazırlıkta yeniden çalıştırılmadı. Son gerçek yerel Node→Python koşusu168 geçerli/0 başarısız kareyle656.502 sn'de tamamlanmıştı; emülatör bağlantısının gerçek analiz denemesi henüz yapılmadı. Aşağıdaki eski timeout kayıtları tarihsel denemelerdir.

`start_d01_pilot_local.js` mevcut `createApp` / pilot iş yöneticisini kullanır. Otomatik `real_api_check.js` kullanılmaz: bu başlatıcı kendi POST isteğini göndermez ve completed sonrasında sunucuyu kapatmaz. Yalnız127.0.0.1:8000 dinler. Port doluysa `port_in_use` ile durur; **hiçbir mevcut süreci sonlandırmaz**, aynı portta devam etmeyi denemeyin. Her başlangıçta depo dışındaki `outputs/d01_headpose_6drepnet360/emulator_api_<UTC>_<rastgele>/jobs` yeni iş köküdür; dizin çakışırsa üzerine yazılmaz. Eski deneyler ve162 karelik kayıt kapsam dışındadır. `local_server.json` yalnız yollar/süreler içerir, anahtar içermez; mevcut24 saat/en yeni10 terminal iş saklama politikası yalnız yeni kökte sürer.

Yapılandırma doğrudan bu uygulama örneğine verilir: deployment, pilot açık, ortak Gemini kapasitesi1, analiz900000 ms, kill payı10000 ms. Python `.venv_headpose/Scripts/python.exe`; ağırlık `araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.pth`; resmî kaynak `dis_kaynaklar/6DRepNet360`; CLI `research/d01/pilot_cli.py` ve protokol `parameters/pilot_v1.json`. İlk üç yol repo üstündeki `C:\Projeler\Norogelisim` veri kökünden çözülür. Bunlar mevcut yerel Windows yollarıdır, yeni kurulum/indirme yapılmaz. Ağırlık/resmî kaynak hash ve strict yükleme kontrolleri mevcut CLI'de sürer; başlatmak modeli yüklemek değildir. `.env` çağrılmaz, kalıcı veya process ortam değişkenleri değiştirilmez; Gemini anahtarı aktarılmaz ve sağlayıcı çağrısı başlatılmaz. Eski otomatik deneme betiğinin `PILOT_CHECK_*` ayarları burada kullanılmaz; mobil istemcinin mevcut20 dk takip/30 sn HTTP sınırları korunur.

### Terminal A — normal Windows PowerShell, backend

Boşluksuz, yalnız yazdırılabilir ASCII karakterlerden oluşan **bu oturuma özel** bir ekip anahtarı seçin. Gizli isteme girin; aynı değeri mobil pilotun anahtar alanına elle girin. Aşağıdaki komut anahtarı terminale yazdırmaz, komut argümanına/dosyaya/ortama koymaz; JSON'u yalnız Node stdin'ine iletir. Kendi anahtarınızı kaynak kod örneğine eklemeyin.

```powershell
Set-Location 'C:\Projeler\Norogelisim\mobil_rag_223bc7d'
$nodeExe = (Get-Command node.exe -CommandType Application -ErrorAction Stop).Source
$pilotSecret = Read-Host 'Bu oturumun ekip anahtari (mobilde aynisini girin)' -AsSecureString
$pilotPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pilotSecret)
try {
    $pilotInput = @{ accessKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pilotPointer) } | ConvertTo-Json -Compress
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pilotPointer)
    $pilotSecret.Dispose()
}
try {
    $pilotInput | & $nodeExe '.\backend\start_d01_pilot_local.js'
    if ($LASTEXITCODE -ne 0) { throw 'Pilot baslatici hata verdi; yukaridaki guvenli kodu kontrol edin.' }
} finally {
    $pilotInput = $null
}
```

Beklenen: `[pilot-local] ready http://127.0.0.1:8000`, yeni `jobs` yolu ve `timeout=900s kill_grace=10s; no analysis submitted`. Bu terminali açık bırakın. Port doluysa burada durun; süreci öldürmeyin. İş bitince backend çalışmaya devam eder. Tercihen completed sonrasında Ctrl+C ile kapatın; çalışırken Ctrl+C mevcut pilot yöneticisi üzerinden **kendi işine** sonlandırma ister. Bu, bütün Windows süreç ağacının bağımsız OS doğrulaması değildir; genel Python/Node süreç temizliği yapmaz.

### Terminal B — normal Windows PowerShell, mevcut emülatöre dosya ve uygulama

Önce kullanıcı Android emülatörünü açmış olmalıdır; aşağıdaki komutlar yeni emülatör oluşturmaz/başlatmaz. `adb.exe` yolu SDK kaydı ve dosya varlığıyla doğrulandı; hazırlıkta adb çalıştırılmadı. Terminal A'da **ready** gördükten sonra:

```powershell
Set-Location 'C:\Projeler\Norogelisim\mobil_rag_223bc7d'
Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 10
$adb = 'C:\Users\M.T\AppData\Local\Android\sdk\platform-tools\adb.exe'
$deviceLines = & $adb devices
if ($LASTEXITCODE -ne 0) { throw 'adb devices basarisiz.' }
$emulators = @($deviceLines | ForEach-Object { if ($_ -match '^(emulator-\d+)\s+device\s*$') { $Matches[1] } })
if ($emulators.Count -eq 0) { throw 'Hazir Android emulatoru bulunamadi; kullanici emulatoru acmali.' }
$serial = $emulators[0]
if ($emulators.Count -gt 1) {
    $serial = Read-Host ('Hedef emulator seri numarasi: ' + ($emulators -join ', '))
    if ($emulators -notcontains $serial) { throw 'Listede olmayan emulator secildi.' }
}
$source = (Resolve-Path '.\mobile_skeleton\assets\videos\d01_name_turning\20261024200833.mp4').Path
$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceHash -ne 'b6e12246983f8852f2cef4397b328ec9c0412294564a17212a4021a653eaf605') { throw 'Kaynak video hash uyusmazligi.' }
$remote = '/sdcard/Download/d01_pilot_20261024200833_' + [guid]::NewGuid().ToString('N') + '.mp4'
& $adb -s $serial push $source $remote
if ($LASTEXITCODE -ne 0) { throw 'Video aktarilamadi.' }
$remoteSum = & $adb -s $serial shell toybox sha256sum $remote
if ($LASTEXITCODE -ne 0) { throw 'Cihaz hash kontrolu calismadi; eslesme varsayilmadi.' }
$remoteHash = (($remoteSum | Out-String).Trim() -split '\s+')[0]
if ($remoteHash -ne $sourceHash) { throw 'Cihaz video hash uyusmazligi; analize gecmeyin.' }
Write-Host ('SHA256 eslesti. Cihazdaki dosya: ' + $remote)
& $adb -s $serial shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d ('file://' + $remote)
if ($LASTEXITCODE -ne 0) { throw 'Medya taramasi basarisiz; dosyanin secicide gorundugunu elle kontrol edin.' }
Set-Location '.\mobile_skeleton'
& 'C:\dev\flutter\bin\flutter.bat' run --no-pub -d $serial --dart-define=D01_PILOT_SERVER_URL=http://10.0.2.2:8000
```

`adb push` yeniden kodlama/sıkıştırma yapmaz; kaynak ve cihaz SHA256 karşılaştırması bayt eşitliğini denetler. Benzersiz cihaz adı önceki videoların üzerine yazmaz. Galeri/dosya seçicisinde Download içindeki bu yeni dosyayı seçin; bir düzenleme/paylaşım uygulamasından yeniden kaydetmeyin. Medya tarama yanıtı tek başına seçicide görünürlüğün kanıtı değildir, kullanıcı kontrol eder.

**Mobil yol:** Simülasyon ve Eğitim → Hazır örnekler ve diğer araçlar → **Deneysel D01 baş hareketi analizi**. Pilot adresi **http://10.0.2.2:8000**, anahtar Terminal A'da gizli girilen aynı değerdir. Stüdyo'dan devralınan anahtar farklıysa pilot alanında değiştirin; senaryo sunucusunu değiştirmeyin. Bu komut debug uygulamayı kullanır; mevcut debug loopback HTTP izni release ayarlarını genişletmez. Anahtar yalnız oturumdadır. Videoyu seçip önizledikten sonra kullanıcı açıkça **Pilot analizi başlat** der. Sonuçta168/168/0, ham/EMA ayrı adaylar ve null çağrı zamanları beklenen önceki örnekle karşılaştırılır; gerçekleşmeden geçti sayılmaz. Mobil takip durması sunucu iptali değildir; iptal ayrı düğmedir. Bu hazırlıkta hiçbir başlatma, aktarım, health isteği veya gerçek analiz yapılmadı.

## Güncel tanılama ve ayrı süre sınırları — 29 Ekim 2026

Son gerçek HTTP denemesi tamamlanmadı: `outputs/d01_headpose_6drepnet360/api_gercek_video2_20261029T184224735Z_4855b62c` altında backend işi **interrupted / analysis_timeout**, CLI'nin son durumu **running / 162** kaldı. Diske yazılmış 162 geçerli JSONL kare (0–161) korunur; 163 PNG tamamlanmış 163 çıkarım demek değildir. Eski deneme raporundaki `job_not_completed`, deneme betiğinin genel etiketi idi; gerçek backend kodu değildi. Kayıtlar bu düzenlemeyle yeniden yazılmadı.

| Ayar | Varsayılan | Kapsam |
|---|---:|---|
| `PILOT_D01_TIMEOUT_MS` | 600000 | Backend'in çocuk süreç için bekleme sınırı; sonra SIGTERM ister. |
| `PILOT_D01_KILL_GRACE_MS` | 10000 | Gerekirse SIGKILL istemeden önceki süre; kapanış onayı değildir. |
| `PILOT_CHECK_WAIT_MS` | 600000 | Yalnız gerçek API deneme betiğinin ana gözlem süresi. |
| `PILOT_CHECK_CLOSE_GRACE_MS` | 45000 | Deneme betiğinin **ayrı ve açık** ek terminal durum gözlem payı. |

Backend'in eski 600/10 saniyelik varsayılanları değişmedi. İstemcinin ana 600 saniyesi de değişmedi; yeni kapanış payıyla varsayılan gözlem 645 saniyedir. Değerler pozitif tam sayı milisaniye, en fazla3600000; hatalı ayar açık hata verir. İstemcinin toplam gözlemi backend timeout + kill grace +35000 ms sorgu/HTTP payından kısa olamaz. Bu toplam bir işin tamamlanacağı garantisi değildir; son HTTP isteğinin kendi 30 saniyelik sınırı ve kapanış işlemleri ayrıca vardır. İş süresi sayacı Python spawn sonrasında, istemci gözlemi kabul edilmiş yükleme sonrasında başlar; farklı kapsamları performans farkı olarak yorumlamayın.

Haricî `outputs/d01_headpose_6drepnet360/api_gercek_video2_20261029T182453Z/real_api_check.js` bu ayarları `backend/pilot_timing.js` üzerinden okur, uygulamaya açıkça geçirir. Ana bekleme sınırında **yeni GET**, gerekiyorsa kapanış payında sorgulama ve sonunda **son GET** yapar. Raporun `finalStatus` / `errorCode` alanları gerçek `analysis_timeout`, `cli_failed` vb. kodları korur. Backend hâlâ terminal değilse ayrı `client_observation_expired` olur; completed sayılmaz. Her koşunun `report.json.timingLimits` alanı geçerli sınırları gösterir; kopyalanan eski `validation_plan.json` tarihsel başlangıç planıdır. Yeni deneme yalnız `--new-run` ile ayrı klasöre yapılır; burada çalıştırılmadı.

**SIGTERM ve iki kayıt:** backend `job.json` içine önce sonlandırma nedeni `cancelCode` yazar; child `close` sonrasında terminal `interrupted/analysis_timeout` yayımlar ve yuvayı serbest bırakır. CLI sinyal yakalama/checkpoint fırsatı bulamayabilir; özellikle Windows'ta zorla sonlandırma Python handler'ına ulaşmayabilir. Bu yüzden eski CLI `running` kaydı backend'in terminal kaydıyla çelişen başarı kanıtı değildir. CLI `running`, eksik sonuç ve162 ham kare birlikte **yarım çalışma** olarak korunur; backend CLI dosyasını completed olarak düzeltmez. API başarısı için mevcut sıfır çıkış + CLI completed + geçerli sonuç kontrolleri sürer. Windows venv launcher PID'si ile rapordaki Python PID'si farklı olabilir: doğrudan child close tek başına bütün alt süreç ağacının kapandığını kanıtlamaz; bu düzenleme süreç ağacı yönetimini değiştirmedi.

CLI artık gerçek Python/Torch/paket sürümlerini, Torch intra/inter-op thread sayılarını ve cihazı yerel rapora yazar; model yükleme/ön işleme/forward/kayıt/postprocess süreleri ayrı tutulur. Zaman damgalı süreç CPU/bellek örnekleri için Windows çalışma kümesi ve OS tepe çalışma kümesi; Linux'ta `/proc/self/status` içindeki Python sürecine ait `VmRSS`/`VmHWM` (KiB × 1024) kullanılır. Okunamayan/desteklenmeyen alanlar null ve `memory_status` açıklamasıyla kalır; sistem toplam RAM'i kullanılmaz. Ölçüm kapsamı için `research/d01/README.md` içindeki ölçüm bölümüne bakın. Ölçüler güvenli API projeksiyonuna eklenmez; yerel yollar mobil/API yanıtına sızmaz. Önceki yaklaşık176 sn CLI ile600 sn'de kesilen koşunun yavaşlık nedeni bu yeni ölçümlerle henüz doğrulanmadı; HTTP, donanım veya thread ayarı neden ilan edilmez.

**Bir sonraki gerçek deneme önerisi (henüz uygulanmadı):** açık tercih olarak backend `900000`, kill grace `10000`, istemci ana bekleme `900000`, kapanış payı `45000` ms (945 sn gözlem). Bu bir performans düzeltmesi veya yeterlilik garantisi değildir; mevcut yavaş koşuyu daha uzun gözleyebilmek içindir. Varsayılanlar bu öneriyle değiştirilmedi. Önce mevcut işin gerçekten kapanmış olduğu kontrol edilmeli;162 kareden devam/yeniden çıkarım bu görevde yok.

Bu tanılama düzenlemesinden sonra **107 backend testi** (sekiz dosya) ve **65 Python araştırma testi** geçti. Gerçek port, Python model çıkarımı veya sağlayıcı çağrısı yapılmadı; sahte süreç/decoder/runtime ve sentetik matrisler kullanıldı. Yeni dört zamanlama testi son GET, terminal kodların korunması, kapanış payı ve ayrı istemci aşımını; üç ölçüm testi CPU kapsamı/bilinmeyen değerler, iç içe süreler ve runtime alanlarını kapsar. Mevcut CLI testleri kalıcı ölçüm alanlarını ve değişmeyen kare forward süresini de denetler. Haricî deneme betiği yalnız `node --check` ile denetlendi. Gerçek telemetri ve uçtan uca yeni deneme doğrulanmış değildir.

Bu yol Gemini `/api/analyze-video` değildir. Varsayılan kapalıdır. Yalnız hash'i önceden denetlenmiş iki videoyu kabul eder: `resources/d01_pilot_profiles.json`. İlk video üst40px RGB128 dolgulu250,−40,440×440; ikinci video dolgusuz220,140,320×320. Profil hash'ten seçilir; istemci ROI/profil, dosya yolu, Python, ağırlık veya komut veremez. Yeni videolar için otomatik ROI/çocuk takibi yoktur.

## Yerel yapılandırma

### Açık CPU thread denemesi

`PILOT_D01_CPU_THREADS` verilmezse eski protokoldeki4 intra-op thread kullanılır. Açık değer yalnız `1`, `2` veya `4` olabilir; boş/hatalı değer backend başlangıcında hata verir. Backend bunu yalnız CLI `--cpu-threads` argümanına taşır; mobil istek bu ayarı belirleyemez. Inter-op davranışı, model, ROI, filtre/eşikler ve timeout değişmez. `parameters/pilot_v1.json` yeniden yazılmaz.

Sunucuda güncel CLI ve backend dosyaları sağlandıktan sonra, çalışan analiz tamamlanmış/kapanmış olmalı. Mevcut backend oturumunu kullanıcının kendi başlatma yöntemiyle yeniden açarken yalnız o sürece ayar verilir (burada çalıştırılmadı):

```bash
cd /opt/norogelisim/app/backend
PILOT_D01_CPU_THREADS=2 node server.js
```

Mevcut diğer ortam/anahtar/yol/timeout ayarlarını koruyun; ikinci backend başlatmayın. Bu komut kalıcı `.env` veya sistem ayarı yazmaz. Dönüşte aynı yöntemle kendi backend'inizi yeniden başlatın:

```bash
env -u PILOT_D01_CPU_THREADS node server.js
```

Bu dönüş komutu değişkenin gerçek `.env` içinde tanımlanmadığı süreçlik deneme içindir. Kalıcı dosyada önceden tanım varsa varsayılanı kullanmak için o tanımın kaldırılması gerekir; açık eski davranış için `PILOT_D01_CPU_THREADS=4 node server.js` kullanılabilir. Buradaki görev gerçek `.env` okumadı/değiştirmedi.

`job.json.requestedCpuThreads` backend seçimini; CLI `settings.json.execution` seçimi ve kaynağını, `state.json.execution` ve tamamlanmış `result.json.execution` seçilen/gerçek etkin intra-op sayılarını kaydeder. Gerçek etkin inter-op/intra-op ayrıca `runtime_environment` içindedir. Runtime sayısı seçime uymuyorsa CLI hata verir. Replay'de runtime yüklenmediği için etkin değer null kalır. Operatör kayıtlarıdır; mobil güvenli sonuç projeksiyonuna eklenmez. Bu dosyaların birlikte sunucuya aktarımı ve2-thread tam koşusu henüz yapılmadı.

Mevcut bağımlılıklar Express/multer ve Node standart kütüphaneleri yeterlidir; paket eklenmedi. Sunucu ortamında `PILOT_D01_ENABLED=true`, `TEAM_ACCESS_KEY` ve aşağıdaki **mutlak** yollar gerekir:

- `PILOT_D01_PYTHON`: mevcut uygun Python/venv yürütülebiliri.
- `PILOT_D01_WEIGHTS`: mevcut hash doğrulanan yerel ağırlık.
- `PILOT_D01_OFFICIAL_SOURCE`: mevcut resmî 6DRepNet360 checkout'u.
- `PILOT_D01_JOBS_DIR`: bu iş için ayrılmış, başlangıçta boş haricî kalıcı klasör. Node hesabının yazma yetkisi gerekir. Paylaşılan deney/etiket klasörü verilmez.

CLI/protokol depo içindeki `research/d01/pilot_cli.py` / `parameters/pilot_v1.json` dosyalarıdır. Python ortamında önceki CLI'nin kullandığı Torch/torchvision/OpenCV/NumPy/SciPy/Pillow bulunmalıdır; backend bunları kurmaz/indirmez. Anahtar yalnız backend'de doğrulanır; CLI'ye backend ortamı aktarılmaz, yalnız sınırlı işletim sistemi değişkenleri verilir. `shell:false`, bağımsız argv kullanılır.

Bu tur gerçek Node→Python işi çalıştırılmadı. Yerel gerçek deneme öncesi yollar/izinler ve mevcut Python ortamı kullanıcı tarafından doğrulanmalıdır. Ekip anahtarıyla localhost üzerinden mevcut backend başlatılıp aşağıdaki çağrılar elle yapılabilir; model maliyeti API ücreti değil yerel CPU/RAM'dir. Gerçek sırları komut çıktısına/loga koymayın. İnternete açma/HTTPS/uzak dağıtım bu kapsamda değildir.

## HTTP sözleşmesi

Development dahil tüm pilot yolları `Authorization: Bearer <oturum ekip anahtarı>` ister. Eksik/yanlış anahtar ayrıştırma/yüklemeden önce401. Anahtar yoksa etkin pilotun başlangıcı hata verir. Health anahtarsızdır; OPTIONS iş başlatmaz. Deployment allowlist'i yalnız pilot açıkken aşağıdaki yolları da kabul eder; eski `/api/analyze-video` deployment'da kapalı kalır. Mevcut üç senaryo üretim yolu korunur.

| İşlem | Yol / yanıt |
|---|---|
| Yükle | `POST /api/pilot-d01/jobs`, multipart `video`;202 `{jobId,status}`. HTTP boyunca çıkarım beklenmez. |
| Durum | `GET /api/pilot-d01/jobs/{jobId}`;200 `{jobId,status,code,profileId}`; bilinmeyen/temizlenmiş404. |
| Ana sonuç | `GET /api/pilot-d01/jobs/{jobId}/result`; tamamlandıysa200, aksi409. |
| Yerel iptal | `DELETE /api/pilot-d01/jobs/{jobId}`;202 yalnız sonlandırma isteğidir, süreç kapandı demek değildir; etkin olmayan409. |

Video sınırı **25 MiB**, disk üzerinde multer; aşım413 `video_too_large`. Tek dosya, en fazla2 kısa alan (alan başına128 bayt); multipart parça sınırı4 (Busboy sınır olayı nedeniyle üç gerçek parçaya yer sağlar); fazladan alan/dosya reddedilir. JSON sınırı deployment'da **1 MiB olarak kaldı**; bütün backend için gevşetilmedi. Yanlış/eksik yükleme400, bilinmeyen SHA256422 `unsupported_video` ve Python hiç başlamaz.

İsteğe bağlı alanlar yalnız `callStartS`, `callEndS`: 0–7 aralığında sonlu ondalık saniye, en çok milisaniye çözünürlük; ikisi verilmişse bitiş≥başlangıç. Boş/verilmeyen değer null kalır, otomatik sıfır yoktur. Bunlar manuel kullanıcı girdisidir. `responseStartS`/hareket sınırları veya başka teknik alanlar400 alır. CLI'ye verilirse yalnız çağrı işaretli ayrı `manual.json` oluşturulur; tespit sonrası rapor aşamasında okunur. Algoritma çağrıya tepki/klinik sonuç/başarı/güven/renk üretmez.

Sonuç API'si `d01-pilot-api-1.0`: iş/profil kimliği, video hash'i, manuel zamanlar ve aday durumu, ham/EMA hareket sınırları ve ayrı doğrulama zamanları, çağrıya göre farklar, dört yerleşme koşulunun sayıları, işlenen/geçerli/geçersiz sayıları. Algoritmik hedef `not_determined`; saat eşlemesi doğrulanmadı. Bu, CLI ana sözleşmesinin güvenli bir projeksiyonudur; yerel `video.path`, ROI inceleme yolu, günlük, ham traceback, büyük kare/pencere arşivi ve dosya indirme bağlantıları dönmez. Ayrıntı incelemesi yalnız operatörün disk erişimiyle yapılır.

## İş ve kaynak sahipliği

Tek Node sürecinde ve sahiplenilmiş iş klasöründe **bir pilot yükleme/analiz**; meşgulken429 `pilot_busy`, kuyruk/otomatik tekrar yok. Ayrı PID sahiplik kilidi aynı klasörü canlı başka Node sürecinin kullanmasını engeller; farklı klasörlere sahip çoklu backend'ler için dağıtık kota değildir. Gemini üretiminin mevcut ortak kapasitesi ayrı kalır. Ağ tabanlı senaryo üretimi bu CPU işi sırasında sürebilir; toplam CPU/RAM kotası sağlanmaz. CLI'nin mevcut4 iş parçacığı ve bellek ihtiyacı ayrıca ölçülüp işletim sistemi/container düzeyinde bütçelenmelidir.

İş kabulü/çıkarım durumu `uploading/running/completed/failed/interrupted`. Dosya SHA doğrulaması sonrası sunucu yapılandırmalı Python başlar. Başarı için süreç çıkışı0, CLI state completed, gerçek çıkarım işaretleri, video hash'i, işlenmiş sayılar ve sürümlü sonuç sözleşmesi doğrulanır; bozuk sonuç `invalid_cli_result`, süreç hatası `cli_failed`/`cli_start_failed`. API'ye ham hata aktarılmaz, örnek sonuç üretilmez.

10 dakika süre sınırında SIGTERM,10 saniye sonra gerekirse SIGKILL istenir; **yuva ancak child close gelince serbest kalır**. İptalden sonraki geç başarı completed olmaz. Node'un normal SIGINT/SIGTERM kapanışı çocuk süreci sonlandırmayı bekler. Zorla Node kapanırsa Python yetim kalabilir: yeniden başlangıçta canlı kayıtlı çocuk PID varsa backend pilotu başlatmaz; operatör o işe ait süreci doğrulayıp kapatmadan yeni analiz başlatılmaz. PID tekrar kullanılmışsa da otomatik öldürülmez; operatör kontrolü gerekir. Çocuk artık yoksa yarım işler `interrupted/backend_restarted` olur, otomatik devam/yeniden çıkarım yapılmaz. Bozuk sahiplik/iş kaydı startup hatasıdır; sessizce silinmez.

## Dosyalar ve saklama

Her UUID klasörü: `upload.mp4`, `job.json`, `roi.json`, gerekirse `manual.json`, en çok **64 KiB birleşik stdout/stderr** `cli.log`, `run/` CLI durum/sonuç/ayrıntıları, doğrulanmış `api_result.json`. Büyük çıktılar yalnız disktedir. Dosya/klasör izinleri Unix'te600/700 istenir; Windows ACL'si ayrıca operatör sorumluluğudur. Günlüğün sınırı aşan son kısmı yazılmaz; bu tam log arşivi değildir.

Terminal işler24 saat veya en yeni10 terminal iş sınırından hangisi önce dolarsa kendi **yükleme/log/sonuç klasörüyle birlikte** temizlenir. Temizlik başlangıçta, saatlik, yeni kabulde ve durum sorgusunda yapılır; çalışan iş silinmez. Yalnız sahiplik marker'ı olan kökte UUID+eşleşen job.json klasörleri temizlenir; kaynak video/ağırlık/etiketler kapsam dışıdır. Temizlik hatası sabit `[pilot] cleanup_failed` bildirir; sonrasında yeni istekte disk hatası güvenli500 olur. Temizlenmiş iş404 döner. Saklanması gereken raporlar bu süreden önce operatörce ayrı yedeklenmelidir; bu klasör kalıcı bilimsel arşiv değildir.

Mevcut Dockerfile **Node-only** kalır: route modülü ve profil JSON'u image'a dahil edildi; Python ortamı/ağırlık/resmî kod/araştırma klasörü image'da yoktur. Normal senaryo deployment'ı pilot kapalıyken çalışmaya devam eder. Bu image'da pilotu açmak tek başına yeterli değildir; bu görev yeni model image'ı/volume/dağıtım kurmadı.

## Kontrollü doğrulama

`node --test --test-isolation=none backend/test/d01_pilot_jobs.test.js backend/test/deployment_mode.test.js backend/test/scenario_input_generation.test.js backend/test/scenario_clip_generation.test.js`

Testler gerçek HTTP portu, Python/model veya Gemini açmaz: Express/multer zinciri, sahte çocuk süreç, geç kapanış/iptal/timeout, upload/profil/hash, auth, JSON/video boyutları, bozuk sonuç, restart ve saklama kontrolleridir. Bunlar gerçek Node→Python medya analizi kanıtı değildir. Mobil adaptör henüz bağlanmadı.

Bu tur yukarıdaki grup ile diğer mevcut backend ölçüm/karşılaştırma/çoklu senaryo testleri birlikte **103/103 geçti**;14 test pilot içindir. Bunlar kullanıcının gerçek analiz denemesi değil, bu görevde çalıştırılan kontrollü testlerdir. İlk testte sahte HTTP isteğinin tamamlanmışlık bayrağı eksikti; test düzeneği gerçek HTTP semantiğine uyarlandı. Busboy tam üç gerçek parçada `partsLimit` olayı ürettiği için limit4, bağımsız dosya1/alan2 sınırları korunarak ayarlandı; beklentiler gevşetilmedi.

## Kullanıcının sonraki yerel denemesi (bu tur çalıştırılmadı)

Depo kökünde normal Windows PowerShell. Mevcut doğru Python/venv, ağırlık ve resmî kaynak yollarını dört `PILOT_D01_*` ortam değişkenine verin; `PILOT_D01_JOBS_DIR` yeni/boş ayrı haricî klasör olmalı. `PILOT_D01_ENABLED=true` ve güvenli oturum ortamındaki `TEAM_ACCESS_KEY` gereklidir. Ortamı/anahtarı terminale dökmeyin. Backend'i kullanıcı `node backend/server.js` ile localhost'ta başlatır; burada süreç başlatılmadı. Mevcut süreç varsa üzerine ikinci sunucu başlatmadan kullanıcının uygun port/oturum seçmesi gerekir.

Yerel yükleme örneği; anahtar mevcut ortamdan okunur, URL'ye yazılmaz:

```powershell
curl.exe -sS -H "Authorization: Bearer $env:TEAM_ACCESS_KEY" -F "video=@mobile_skeleton/assets/videos/d01_name_turning/20261024200833.mp4" http://127.0.0.1:8000/api/pilot-d01/jobs
```

202'de dönen jobId ile GET durumunu sorgulayın. completed sonrası `/result` isteğini alın. İlk denemede çağrı alanlarını vermeyin; iki seride adaylar, null manuel farklar ve hedef belirlenmedi durumu beklenir. Ayrı sonraki denemede isteğe bağlı `-F "callStartS=0.401" -F "callEndS=1.152"` kullanılabilir; hareket sınırları gönderilmez. Bu komutlar gerçek model çalıştırır; mevcut103 sahte test bunların yerine geçmez. Gerçek denemede child ortamı/Python importları, yükleme→iş klasörü, completed sonuç ve yeniden başlatma davranışı ayrıca doğrulanmalı. Docker build/up veya uzak dağıtım gerekmez ve bu görevde yapılmadı.
