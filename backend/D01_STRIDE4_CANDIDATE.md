# D01 Stride4 adayı — 13 Kasım 2026

**Son durum (kullanıcı doğrulaması):** Deniz koşusu 141/168 geçerli poz,
24–83. karelerde 60/60 poz ve 98,6 sn işlem süresi; 111. karede yeniden yakalama
görsel olarak doğrulandı. 30 hedefli test geçti; telefon kontrolü bekliyor.
Bu süre telefon uçtan uca ölçümü değildir. Önceki hazırlık/engel kayıtları aşağıda korunur.

**Güncel Stride4 hedef politikası:** [tek landmark ile yeniden yakalama ve izole koşu](D01_STRIDE4_REACQUISITION.md). Varsayılan MediaPipe yolu değişmez.

## Kenar dolgusu düzeltmesi — padding v2

Önceki adaptörde `x<0 || y<0 || x+side>width || y+side>height` doğrudan
ret sebebiydi. Bu nedenle yüz noktası/kutu bulunması model kırpması oluşmasını
garantilemiyordu. Yalnız bu sınır davranışı değişti: aynı 2× karenin merkezi ve
boyutu korunur, kaynak dışında kalan yer RGB128 ile tamamlanır. İçerideki kırpma
baytları eski sürümle aynıdır. Kimlik ve başka yüz kontrolleri korunur; dolgu
poz doğruluğu onayı değildir. 10 hedefli test geçti; gerçek yeni sayılar bu
oturumda ölçülmedi (SSH/SCP engelli, uygun yerel legacy MediaPipe ortamı yok).

Değişiklik dosyaları: `stride4_tracking.py`, `test_stride4_tracking.py`,
`review_stride4_boxes.py`; ölçüm özeti `summarize_stride4_padding.py`.
Bu yeni koşu ilk bağlantının eski 148/44 test sonucuyla karıştırılmamalı.

### Yalnız yeni adaya aktarım — normal Windows PowerShell

```powershell
$target='SSH_KULLANICISI@31.77.69.171'
$code='C:\Projeler\Norogelisim\d01_stride4_candidate_530c761\research\d01'
ssh $target 'mkdir /tmp/d01-padding-v2-20261113'
if($LASTEXITCODE -ne 0){throw 'Yeni geçici klasör oluşturulamadı; üstüne yazılmadı'}
scp "$code\stride4_tracking.py" "$code\test_stride4_tracking.py" "$code\review_stride4_boxes.py" "$code\summarize_stride4_padding.py" "${target}:/tmp/d01-padding-v2-20261113/"
if($LASTEXITCODE -ne 0){throw 'Aktarım başarısız'}
```

### Tek yeniden ölçüm — önceki araştırma ortamı ayarlarının bulunduğu Linux terminali

Bu komutlar eski adayı da değiştirmez; yalnız backend/research kaynağından yeni
bir aday kopyası oluşturur. Önceki kurulumda farklı aday yolu kullanıldıysa
`old` değerini o ayrı adayın tam yoluna ayarlayın; canlı `/opt/norogelisim/app`
değerini KULLANMAYIN. Model/ses/Python ortam değişkenleri alttaki ilk kurulum
bölümündekiyle aynı olmalı. Mevcut terminalde yoksa komut açıkça durur.

```bash
set -eu
old=/opt/norogelisim/d01_stride4_candidate_530c761
candidate=/opt/norogelisim/d01_stride4_padding_v2_20261113
test "$old" != /opt/norogelisim/app
test -f "$old/backend/start_d01_candidate.js"
mkdir "$candidate"
tar -C "$old" --exclude='.env' --exclude='.env.*' --exclude=node_modules --exclude=__pycache__ --exclude='*.pyc' --exclude='*.onnx' --exclude='*.pth' -cf - backend research | tar -C "$candidate" -xf -
for name in stride4_tracking.py test_stride4_tracking.py review_stride4_boxes.py summarize_stride4_padding.py; do
  install -m 644 "/tmp/d01-padding-v2-20261113/$name" "$candidate/research/d01/$name"
done
cd "$candidate"
: "${PILOT_D01_FAST_PYTHON:?Önceki araştırma Python ayarı gerekli}"
: "${PILOT_D01_PYTHON:?Önceki 6D Python ayarı gerekli}"
: "${PILOT_D01_FACE_MODEL:?Önceki Tasks modeli gerekli}"
: "${PILOT_D01_AUDIO_MODEL:?Önceki ses modeli gerekli}"
: "${PILOT_D01_STRIDE4_SOURCE:?Önceki benchmark kaynağı gerekli}"
: "${PILOT_D01_ONNX_MODEL:?Aynı ONNX modeli gerekli}"
: "${PILOT_D01_WEIGHTS:?Önceki 6D ağırlık yolu gerekli}"
: "${PILOT_D01_OFFICIAL_SOURCE:?Önceki resmî kaynak yolu gerekli}"
export NODE_PATH=/opt/norogelisim/app/backend/node_modules
"$PILOT_D01_FAST_PYTHON" -B research/d01/check_stride4_environment.py
(cd research/d01 && "$PILOT_D01_FAST_PYTHON" -B -m unittest test_stride4_tracking -v)
runBase=$(mktemp -d "$HOME/d01-padding-v2.XXXXXXXX")
export D01_COMPARE_VIDEO=/tmp/d01-stride4-deniz.mp4
python3 - "$runBase/sources.json" <<'PY'
import json,os,sys
from pathlib import Path
data=json.loads(Path('research/d01/parameters/stride4_deniz_acceptance.json').read_text())
data[0]['video']=os.environ['D01_COMPARE_VIDEO']
Path(sys.argv[1]).write_text(json.dumps(data),encoding='utf-8')
PY
PILOT_D01_FAST_ENGINE=cascade_stride4_onnx node backend/test/real_fast_api_check.js --run --automatic-call --sources "$runBase/sources.json" --output-dir "$runBase/api"
"$PILOT_D01_FAST_PYTHON" -B research/d01/summarize_stride4_padding.py --run "$runBase/api" --output "$runBase/summary"
printf 'Sonuçlar: %s/summary\n' "$runBase"
```

Özet, padding-v2 kaydını, aynı Deniz hash/noktasını, gerçek çocuk çıkışını ve
kare başına 6D çağrıları toplamını doğrular; 22–37 dahil 16 kareyi CSV/JSON'a
yazar. Çağrı işaretleri gönderilmez, yeni iş dizini kullanılır, canlı servis
restart edilmez. Toplam yeni poz/6D sayısı ancak bu koşudan sonra bilinir.

Taban `530c761`; ayrı alan `C:\Projeler\Norogelisim\d01_stride4_candidate_530c761`.
Canlı servis ve önceki aday değiştirilmedi. Commit/push veya dağıtım yapılmadı.

## Gerçek yöntem ve uyarlama

Aktarılan `stride4_source_a636d05e045649fd8713afeb35cd656c` içindeki
`estimators/hybrid_estimator.py::CascadePnpRepNetStridedEstimator(stride=4, backend='onnx')`
doğrudan kullanılır; bağımlı estimators/common modülleri de aynı kaynaktan yüklenir.
`benchmark_runner.py` yalnız kaynak akışını anlamak için incelendi; tüm modelleri,
sabit/Gemini ROI seçimini veya benchmark'ı API isteğinde çalıştırmayız.
PnP hizalaması, ONNX CPU çapaları ve BlazeFace göreli köprüsü özgün sınıftadır.
%25 kademeli geçiş eklenmedi. Güven değerleri/klinik kararlar API'ye taşınmaz.

Telefon aynı `method=mediapipe_pnp_flow`, `targetPoint=[x,y]` isteğini gönderir.
Sunucunun `PILOT_D01_FAST_ENGINE` değeri:

- `mediapipe_pnp_flow` (varsayılan): eski MediaPipe/Tasks/PnP/optik akış yolu.
- `cascade_stride4_onnx`: aynı hedef izleyici + benchmark kaskadı. Yüz noktası zorunlu.

İkinci yöntemde videoya özel ROI yoktur. Takip edilen yüz kutusunun merkezinde,
en büyük piksel kenarın 2 katı kare alınır. Kenar taşmasında kare merkezi ve boyutu
korunur; görüntü dışındaki bölüm sabit RGB(128,128,128) ile doldurulur (padding v2).
Bu dolgunun poz doğruluğuna etkisi henüz doğrulanmış değildir. Kare kaydında
`crop_source_xywh`, `crop_status`, `crop_padding_ltrb_source_px`, `crop_padding_rgb`,
`rejection_reason` ve `repnet_calls_this_frame` bulunur. Geçersiz kutu, küçük kırpma,
kimlik/takip belirsizliği, başka yüz ve geçersiz matris farklı ret nedenleridir.
Başka bilinen yüzün merkezi kırpmaya giriyorsa ölçüm reddedilir. Hedef belirsizliği,
kayıp veya 2,5 sn sınırını aşan optik akışta 6D çalıştırılmaz. Sınır içindeki
geçerli akış kutusu Stride4 kırpmasını sağlayabilir; açı akıştan türetilmez.
Yalnız Stride4, uzun kayıptan
sonra tek konum/görünüm eşleşmesiyle yeniden yakalamayı deneyebilir; yukarıdaki güncel politika geçerlidir.
Bu kapılar çocuk kimliği veya başın tam korunması garantisi değildir; görsel kabul gerekir.
Yeni hareketli kırpma, eski sabit ROI benchmark'ının aynısı olarak sunulamaz.

Model/bağımlılık hatasında sessiz MediaPipe fallback YOKTUR. Geri dönüş,
yalnız aday süreci `PILOT_D01_FAST_ENGINE=mediapipe_pnp_flow` ile tekrar başlatmaktır.
Süren işi engine değiştirerek dönüştürmeyin. Tek iş kapasitesi/iptal/timeout korunur.
Otomatik Türkçe Deniz ASR aynı yerde çalışır; manuel alanlar verilmezse boş kalır.

## Sözleşme ve izlenebilirlik

API 1.2 ve `source.method=mediapipe_pnp_flow` eski APK'nın taşıma sözleşmesidir;
gerçek motor ayrıca `source.poseEngine` içinde döner. Backend iş, Python state ve
sonuç motorlarını eşleştirir. Ham/EMA, çağrı zamanları, kapsam, hash ve seek alanları
aynı kalır. Model/source SHA256, kırpma kuralı ve ONNX CPU 4/1 thread ayarı
`run/details/pose_engine.json` içinde; kare kutusu, kırpma ve matrisler `frames.jsonl`
içindedir. API yerel kaynak yollarını göndermez. `engineCounts.repnetCalls` gerçek
ONNX çağrılarını (ilk hizalama dahil) sayar; bilinmeyen null'dır.
`target_tracker_load_s` ve `cascade_load_s`, `model_load_s` alt kapsamlarıdır;
Python toplamına veya birbirini kapsayan API sürelerine tekrar eklenmez.

## Çalıştırılanlar ve engel

İlk bağlantıda 148 kontrollü backend ve 44 kontrollü Python testi geçti. Gerçek Stride4 çıkarımı,
API karşılaştırması ve mobil kabul henüz çalıştırılmadı. Yerel ses Python'unda
MediaPipe 1.0.1'in `solutions` arayüzü yok; aktarılan sınıf bunu gerektiriyor.
Yerel ortama paket kurulmadı. SSH/SCP bu oturumda engelli. Aşağıdaki komutlar
sunucuda çalışan benchmark'ın ayrı araştırma Python'u ile kullanıcı tarafından
çalıştırılmalıdır; ön kontrol geçmezse devam etmeyin.

## Aktarım — normal Windows PowerShell

SSH kullanıcı adını değiştirin. Bu paket yalnız backend/research kaynaklarıdır;
`.env`, bağımlılıklar, ağırlıklar ve videolar dahil değildir. Git geçmişi gerekmez.

```powershell
$candidate='C:\Projeler\Norogelisim\d01_stride4_candidate_530c761'
$target='SSH_KULLANICISI@31.77.69.171'
$bundle=Join-Path $env:TEMP ('d01-stride4-'+[guid]::NewGuid().ToString('N')+'.tar.gz')
tar.exe -czf $bundle --exclude='.env' --exclude='.env.*' --exclude=node_modules --exclude=__pycache__ --exclude='*.pyc' --exclude='*.onnx' --exclude='*.pth' -C $candidate backend research
if($LASTEXITCODE -ne 0){throw 'Paketleme başarısız'}
scp $bundle "${target}:/tmp/d01-stride4-candidate.tar.gz"
if($LASTEXITCODE -ne 0){throw 'Aktarım başarısız'}
scp 'C:\Projeler\Norogelisim\videolar\_root___context___\context___instruction___prompt_Continue_20261011025647_9.mp4' "${target}:/tmp/d01-stride4-deniz.mp4"
if($LASTEXITCODE -ne 0){throw 'Video aktarımı başarısız'}
```

## Ayrı aday ve karşılaştırma — Linux, SSH terminali

Mevcut `/opt/norogelisim/app` ve `norogelisim.service` için hiçbir komut yoktur.
Yeni aday dizini zaten varsa `mkdir` durur; üstüne yazmayın. Dört yol, canlı
servisin `.env` dosyasını açmadan mevcut araştırma ortamından seçilir. Anahtar
yalnız daha sonraki getpass adımında alınır; ortam listesi terminale dökülmez.

```bash
set -eu
candidate=/opt/norogelisim/d01_stride4_candidate_530c761
mkdir "$candidate"
tar -xzf /tmp/d01-stride4-candidate.tar.gz -C "$candidate"
cd "$candidate"
export NODE_PATH=/opt/norogelisim/app/backend/node_modules
export PILOT_D01_STRIDE4_SOURCE=/opt/norogelisim/headpose_benchmark
export PILOT_D01_ONNX_MODEL=/opt/norogelisim/araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.onnx
read -r -e -p 'Benchmark Python mutlak yolu: ' PILOT_D01_FAST_PYTHON
read -r -e -p 'Mevcut 6D Python mutlak yolu: ' PILOT_D01_PYTHON
read -r -e -p 'face_landmarker.task mutlak yolu: ' PILOT_D01_FACE_MODEL
read -r -e -p 'Hazır faster-whisper small klasörü: ' PILOT_D01_AUDIO_MODEL
export PILOT_D01_FAST_PYTHON PILOT_D01_PYTHON PILOT_D01_FACE_MODEL PILOT_D01_AUDIO_MODEL
export PILOT_D01_WEIGHTS=/opt/norogelisim/araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.pth
export PILOT_D01_OFFICIAL_SOURCE=/opt/norogelisim/dis_kaynaklar/6DRepNet360
"$PILOT_D01_FAST_PYTHON" -B research/d01/check_stride4_environment.py
# ready=false ise DURUN; canlı Python'a paket kurmayın.
export PILOT_D01_TIMEOUT_MS=900000 PILOT_D01_KILL_GRACE_MS=10000
runBase=$(mktemp -d "$HOME/d01-stride4-check.XXXXXXXX")
export D01_COMPARE_VIDEO=/tmp/d01-stride4-deniz.mp4
python3 - "$runBase/sources.json" <<'PY'
import json,os,sys
from pathlib import Path
data=json.loads(Path('research/d01/parameters/stride4_deniz_acceptance.json').read_text())
data[0]['video']=os.environ['D01_COMPARE_VIDEO']
Path(sys.argv[1]).write_text(json.dumps(data),encoding='utf-8')
PY
PILOT_D01_FAST_ENGINE=mediapipe_pnp_flow node backend/test/real_fast_api_check.js --run --automatic-call --sources "$runBase/sources.json" --output-dir "$runBase/mediapipe"
PILOT_D01_FAST_ENGINE=cascade_stride4_onnx node backend/test/real_fast_api_check.js --run --automatic-call --sources "$runBase/sources.json" --output-dir "$runBase/stride4"
"$PILOT_D01_FAST_PYTHON" -B research/d01/compare_stride4_api.py --mediapipe "$runBase/mediapipe" --stride4 "$runBase/stride4" --output "$runBase/comparison"
printf 'Rapor: %s/comparison/SUMMARY.md\n' "$runBase"
```

Betik kendi loopback backend/anahtarını kullanır, model dışında sağlayıcı çağırmaz;
iki koşu sırayla yapılır, ilki başarısızsa `set -e` ikincisini başlatmaz. Her sonuç
çocuk çıkış kodu 0 ve tamamlanmış sözleşmeyle doğrulanır. Referans Deniz hash'i
`6f127ff5…91e4c451`; tam hash ve hedef noktası parametre JSON'undadır. Nokta
`[0.4106200191390562,0.33374295794288256]`, önceki mobil iş
`83631533-2b8b-4a5a-b727-d6f5644fb56a` kaydından alınmıştır; el ile ROI değildir.
Kaynak hash'i uyuşmazsa üretim gönderilmez. Çağrı işaretleri HTTP'ye gönderilmez.

İki işte kutu/kimlik kontrolü için (çıkarım başlatmaz):

```bash
for engine in mediapipe stride4; do
  job=$(python3 -c "import json; print(json.load(open('$runBase/$engine/acceptance.json'))['runs'][0]['jobId'])")
  "$PILOT_D01_FAST_PYTHON" -B research/d01/review_stride4_boxes.py --job "$runBase/$engine/jobs/$job" --output "$runBase/${engine}_review" --stride4-source "$PILOT_D01_STRIDE4_SOURCE"
done
```

Sayfaların soldaki kaynak kutusu çocukta mı, sağdaki gerçek ön işleme yeniden
oluşturması tepe/arka baş/çeneyi koruyor mu ve yetişkin yüzü giriyor mu, insan
tarafından kontrol edilmelidir. Sayısal poz kapsamı bu onayın yerine geçmez.
ONNX çağrısı yapılmamış karede sağdaki resim yalnız olası girdidir; o karede
6D çıkarımı yapılmış olduğu anlamına gelmez. Gerçek çağrı sayısı ayrı kaydedilir.
SUMMARY tablosundaki süre API yüklemeden sonuca kadardır, telefon render süresi
değildir. Tek video/tek tekrar, sabit sıra; eski benchmark süreleriyle oran yoktur.

## D01 Test APK kabulü — canlı servisi değiştirmeden

Aynı SSH terminalinde, API karşılaştırma süreçleri kapandıktan sonra:

```bash
export PILOT_CANDIDATE_PORT=18081 PILOT_D01_FAST_ENGINE=cascade_stride4_onnx
export PILOT_D01_JOBS_DIR="$runBase/mobile_stride4_jobs"
python3 -c 'import getpass,json; print(json.dumps({"accessKey":getpass.getpass("Aday oturum ekip anahtarı: ")}))' | node backend/start_d01_candidate.js
```

Port doluysa mevcut süreç durdurulmaz. Aday yalnız 127.0.0.1:18081 dinler; terminal
açık kalır. Ayrı Windows terminali ve USB bağlı fiziksel telefon:

```powershell
ssh -N -L 127.0.0.1:18081:127.0.0.1:18081 SSH_KULLANICISI@31.77.69.171
# Başka PowerShell terminali:
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:18081 tcp:18081
```

D01 Test → Video Analizi → Deneysel D01 → gelişmiş pilot bağlantı adresi
`http://127.0.0.1:18081`; az önce verilen anahtarı oturumluk girin. Senaryo sunucusu
adresini değiştirmeyin. Aynı Deniz dosyası ve aynı çocuk yüzünü seçin, çağrı
işaretlerini boş bırakın, Başlat'a dokunun. Otomatik çağrı, kapsam, ham/EMA,
belirsiz bitiş ve adaya dokununca duraklatılmış seek/kaydırmayı kontrol edin.
Eski APK ek source.poseEngine alanını kabul eder; fakat sabit MediaPipe açıklamasını
Stride4 etiketiyle değiştiremez. Gerçek motoru API kaydı/source.poseEngine ile
doğrulayın; bu aday için yeni APK üretilmedi. Telefonun seçtiği nokta farklıysa
o koşuyu kontrollü aynı-nokta API karşılaştırmasıyla eşdeğer saymayın.

MediaPipe'a dönüş: yalnız adayı Ctrl+C ile kapatın; yeni benzersiz iş kökü seçin,
`PILOT_D01_FAST_ENGINE=mediapipe_pnp_flow` yapıp aynı başlatıcıyı çalıştırın.
Canlı servise restart veya systemd düzenlemesi gerekmez.
