# Stride4: süre sınırlı akış ve landmark ile yeniden yakalama — 13 Kasım 2026

## Son kullanıcı doğrulaması — GitHub hazırlığı

Hedefli takip/Stride4/CLI grubu: **30 test geçti**. Kullanıcının bildirdiği
Deniz koşusunda **141/168 geçerli poz**, **24–83. karelerde 60/60 poz** ve
**98,6 sn işlem süresi** alındı. **111. karede yeniden yakalama görsel olarak
doğrulandı**. Bu bildirim tek klip/koşuya aittir; genel kimlik/poz doğruluğu veya
klinik sonuç değildir. İşlem süresi telefonun video seçiminden görünür sonuca
kadar süresi olarak sunulmaz. **Telefon kontrolü bekliyor**; canlı dağıtım yok.
Ham koşu kayıtları bu GitHub hazırlığında yeniden okunmadı ve çıkarım tekrarlanmadı.
Aşağıdaki önceki “bu oturumda çalıştırılmadı” ifadeleri kod hazırlama oturumlarına aittir.

**Güncel düzeltme:** önceki yalnız-landmark kapısı, kullanıcı koşusunda 24–83.
kareleri gereksiz poz boşluğuna dönüştürmüştü. Padding-v2'nin kısa akış kırpması
geri getirildi. Akış kaynağı `optical_flow`, kimlik durumu
`pose_missing_track_unconfirmed` ve son doğrulanmış landmark yaşı sonlu,
0–2,5 sn dahil olmalıdır. Model pozu optik akıştan hesaplanmaz: akış yalnız
kırpma kutusunu sağlar, poz yine mevcut Stride4 kaskadından gelir. Güncel politika
`bounded-flow-and-unique-reacquisition-v2` olarak kayıtlıdır.

İlk hedef kurulmuşsa, son doğrulanmış landmark'tan 2,5 sn sonra da aynı arama
penceresinde aday aranır. Mevcut takip kutusuyla IoU ≥0,15 VE son doğrulanmış
görünüm histogramıyla L2 ≤0,45 sağlayan tek aday kabul edilir. Eşikler ve arama
penceresi değişmedi. Hiç kurulamayan ilk hedef sonradan otomatik seçilmez.
Uyumsuz/çoklu/boş adayda poz eksiktir. FaceTrack landmark geometrisini reddederse
yeniden yakalama kabul edilmez; önceki doğrulanmış görünüm/zaman korunur.

Süre sınırı aşılmış, kayıp veya belirsiz takipte poz boş kalır; model çalıştırılmaz.
Son doğrulama zamanı, selector ve FaceTrack zamanlarının daha eskisidir; optik
akış kareleri bunu güncellemez. Mevcut MediaPipe yolunda allow_reacquisition=False
kalır ve yalnız yeni tanılama alanları eklenmiştir; arama penceresi ve eşikler aynı.

Kare JSONL: `target_reacquired`, `reacquisition_time_s`, `reacquisition_gap_s`,
`stride4_anchors_reset`. Yeniden yakalama karesinin ilk predict çağrısından önce
rep_anchor/kp_anchor/r_align/bridge_count ve PnP/KP izleme belleği temizlenir;
ONNX oturumu yeniden yüklenmez. Bu biyometrik kimlik veya poz doğruluğu onayı değildir.

Güncel akış düzeltmesinde `test_fast_tracking`, `test_stride4_tracking` ve
`test_fast_cli` birlikte 30 test geçti. Settings kaydı da yalnız Stride4 için
yeniden yakalamaya izin verildiğini doğru yansıtır.
Bu değişiklikle gerçek analiz/sunucu koşusu yapılmadı.

## 1. Kaynak aktarımı — normal Windows PowerShell

```powershell
$target='SSH_KULLANICISI@31.77.69.171'
$code='C:\Projeler\Norogelisim\d01_stride4_candidate_530c761\research\d01'
ssh $target 'mkdir /tmp/d01-bounded-flow-20261113'
if($LASTEXITCODE -ne 0){throw 'Yeni geçici klasör oluşturulamadı'}
scp "$code\fast_tracking.py" "$code\stride4_tracking.py" "$code\fast_cli.py" "$code\test_fast_cli.py" "$code\test_fast_tracking.py" "$code\test_stride4_tracking.py" "$code\summarize_stride4_padding.py" "${target}:/tmp/d01-bounded-flow-20261113/"
if($LASTEXITCODE -ne 0){throw 'Aktarım başarısız'}
```

## 2. İzole tek koşu — Linux

Önceki araştırma Python/model/ses/süre ayarlarının bulunduğu SSH terminalinde
çalıştırın. `old` farklı bir yeniden-yakalama adayına kurulduysa yalnız o ayrı adayın
yolunu kullanın; canlı `/opt/norogelisim/app` klasörünü kullanmayın. Aşağıdaki
komut eski adayı da değiştirmez; yeni dizin varsa durur. Eksik ortam değişkeninde
durur, varsayılan başka model veya süre seçmez. Anahtarlar terminale yazılmaz.

```bash
set -euo pipefail
old=/opt/norogelisim/d01_stride4_reacquire_20261113
candidate=/opt/norogelisim/d01_stride4_bounded_flow_20261113
test "$old" != /opt/norogelisim/app
test -f "$old/backend/start_d01_candidate.js"
mkdir "$candidate"
tar -C "$old" --exclude='.env' --exclude='.env.*' --exclude=node_modules --exclude=__pycache__ --exclude='*.pyc' --exclude='*.onnx' --exclude='*.pth' -cf - backend research | tar -C "$candidate" -xf -
for name in fast_tracking.py stride4_tracking.py fast_cli.py test_fast_cli.py test_fast_tracking.py test_stride4_tracking.py summarize_stride4_padding.py; do
  install -m 644 "/tmp/d01-bounded-flow-20261113/$name" "$candidate/research/d01/$name"
done
cd "$candidate"
for setting in PILOT_D01_FAST_PYTHON PILOT_D01_PYTHON PILOT_D01_FACE_MODEL PILOT_D01_AUDIO_MODEL PILOT_D01_STRIDE4_SOURCE PILOT_D01_ONNX_MODEL PILOT_D01_WEIGHTS PILOT_D01_OFFICIAL_SOURCE PILOT_D01_TIMEOUT_MS PILOT_D01_KILL_GRACE_MS; do
  if [ -z "${!setting:-}" ]; then printf 'Eksik ayar: %s\n' "$setting"; exit 1; fi
  export "$setting"
done
"$PILOT_D01_FAST_PYTHON" -B research/d01/check_stride4_environment.py
(cd research/d01 && "$PILOT_D01_FAST_PYTHON" -B -m unittest test_fast_tracking test_stride4_tracking test_fast_cli -v)
export NODE_PATH=/opt/norogelisim/app/backend/node_modules
runBase=$(mktemp -d "$HOME/d01-bounded-flow.XXXXXXXX")
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
printf 'Rapor: %s/summary/summary.json\n' "$runBase"
```

Kaynak JSON, aynı Deniz SHA256 ve targetPoint
`[0.4106200191390562,0.33374295794288256]` değerini taşır; hash uyuşmazsa yükleme
yapılmaz. Manuel çağrı zamanları gönderilmez. Betik kendi rastgele loopback
portunu, geçici anahtarını ve yeni iş kökünü kullanır. Canlı servis restart edilmez.
Özet tüm yeniden yakalamaları, 22–37 ve 24–83. karelerin durumunu, landmark
yaşını, kırpmanın takip dayanağını ve gerçek 6D çağrılarını ayrı alanlarda verir.
`frames_24_83.csv` yeni boşluk incelemesidir. Poz kapsamı ve kimlik görsel olarak
ayrıca kontrol edilmelidir. Gerçek sunucu koşusu bu oturumda başlatılmadı.
