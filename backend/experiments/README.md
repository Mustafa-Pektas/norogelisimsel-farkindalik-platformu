# 24 üretimlik karşılaştırma — comparison-24-v1

## Yalnız yedi kota hatasını tamamlama — 7 Kasım 2026

`backend/run_comparison_completion.js`, özgün `comparison24_20261107_010505` manifest'i ve24 kaydı salt okunur yükler; yalnız failed+sağlayıcı kota hatası olan7 kaydı seçer.17 completed yeniden çağrılmaz. Yeni denemelerin UUID'si ayrıdır; `originalTrialId`, özgün kayıt SHA256'sı ve kaynak deney yolu yeni kayıtta durur. Eski başarısız kayıtlar silinmez/başarılıya çevrilmez. Ek koşular farklı tarihteki telafi örnekleridir; ilk koşunun sıra/kota/zaman etkisi ortadan kalkmış sayılmaz.

Önizlemede özgün istek (yaş/bağlam/yönergeler dahil), kol, model, üretim ayarları, çıktı sözleşmesi, deney/protokol kimliği, kaynak metadata/hash ve tam sistem/kullanıcı istemleri karşılaştırılır. Fark varsa o üretim gönderilmez ve kalan çalışma durur. Özgün kaynaklar bu sırada değiştirilmez; örneğin JSON eşiklerini düzeltip aynı protokol deneyi gibi tamamlamak uygun değildir. Backend kaynaklarını/modelini değiştirmeyin.

`--interval-ms` her HTTP isteğinin bitişi ile sonraki isteğin başlangıcı arasındaki asgari aralıktır; önizlemeleri de kapsar.1000..3600000 ms, aşağıdaki örnek30000 ms'dir. Kota açılma garantisi sağlamaz. Her yeni deneme en fazla bir üretim gönderir;429/kota, timeout/bağlantı belirsizliği ve yerel kapasite doluluğunda mevcut ortak durdurma devrededir. Otomatik tekrar yoktur. Aynı ek koşu klasörüyle yeniden açılışta tamamlanmış/başarısız ek deneme tekrarlanmaz; belirsiz/kotalı durdurma kendiliğinden kaldırılmaz. Kaynak/hash/ayar değişiminde yeni üretim yoktur. Kaynak24 kayıt ve yeni çıktı klasörü kesinlikle farklı olmalıdır. Yerel backend veya ikinci servis başlatılmaz.

Yalnız planlama (ağ ve sağlayıcı çağrısı yok):

```powershell
Set-Location C:\Projeler\Norogelisim\mobil_rag_223bc7d
node backend/run_comparison_completion.js --plan --source C:\Projeler\Norogelisim\calisma\comparison24_20261107_010505
```

Kullanıcı açıkça çalıştırdığında en fazla7 ücretli üretim; gerçek kota uygunluğu önceden bilinmez:

```powershell
Set-Location C:\Projeler\Norogelisim\mobil_rag_223bc7d
$source = 'C:\Projeler\Norogelisim\calisma\comparison24_20261107_010505'
$server = Read-Host 'Mevcut sunucu API adresi'
$output = Join-Path 'C:\Projeler\Norogelisim\calisma' ('comparison7_completion_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$secure = Read-Host 'Oturumluk ekip anahtarı' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $sessionKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  @{accessKey=$sessionKey} | ConvertTo-Json -Compress | node backend/run_comparison_completion.js --execute --source $source --server $server --output $output --interval-ms 30000
  if ($LASTEXITCODE -ne 0) { Write-Warning 'Çalışma durdu. Kayıtları inceleyin; komutu otomatik tekrarlamayın.' }
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
  Remove-Variable sessionKey,secure -ErrorAction SilentlyContinue
}
```

Ekip anahtarı stdin/oturum belleğindedir; .env veya çıktı dosyasına yazılmaz. Devam ettirme gerekiyorsa aynı `$output` kullanılır; tarihli yeni klasör açarak başarısız ek denemeler sessizce yeniden gönderilmez. Kilitli/kotalı/belirsiz işi operatör incelemeden yeniden çağırmayın.

17 yanıtın ön incelemesi ayrı klasörde: `C:\Projeler\Norogelisim\calisma\comparison24_20261107_010505_content_review_20261107_01/CONTENT_REVIEW.md`; yapısal `preliminary_review.json` ve82 alıntının varlığını kontrol eden `evidence_check.json`. Her yanıtta görev, tepki tutarlılığı, yaşa uyarlama ve sorunlar ayrı; yalnız iki yanıtı bulunan7 koşulun tekrarı karşılaştırıldı. Bu asistanın metinsel ön incelemesidir, uzman/klinik onay veya gerçek video davranış ölçümü değildir. Eski17 not_reviewed insan formunun durumu değiştirilmedi.

Başlıca bulgular: D01/A tekrar2 ay yerine yaş yazıyor; D01/D tekrar1 tek çağrıya ikinci çağrı ekliyor, tekrar2 göz teması ekliyor; D01/D ve D02/D sayısal gecikme sınıfları kullanıyor, D02/D istekte olmayan3m mesafe ekliyor. D04 başlıkları gelişim seyri çağrışımı yapıyor. Bazı diğer yanıtlarda uzman uyarlaması gereği açıkken somut uyarlama belirsiz. Bu tur kaynak/istemler değiştirilmedi; tamamlayıcı deney özgün koşulları koruyacak.

Kontrollü kontroller:
```powershell
node --test --test-isolation=none backend/test/comparison_completion.test.js backend/test/comparison_experiment.test.js backend/test/comparison_summary.test.js backend/test/scenario_comparison.test.js backend/test/generation_measurement.test.js
```

`comparison_24.json`: üç sabit girdi, A/B/C/D, iki tekrar. D01 (12–18), D02 (18–24), D04 (24–36); her biri tek davranışlı, dallı anlatı görevidir. Kart sürümü 0.2. Üç yaş grubu, uzman onaylı yaş desteği değildir: özellikle D01/D02 kartının ilk pilot kapsamı 30–36 aydır; küçük yaş uyarlaması insan incelemesinde değerlendirilir. Kart metinleri kopyalanmaz; mevcut endpoint kaynak yükleyicilerini kullanır.

A: ortak görev/güvenlik talimatları, ek kart metni yok. B: seçilen Markdown kartı ve ortak kurallar. C: bütün Markdown kaynağı. D: seçilen davranış/yaş için JSON'un TIPIK/ATIPIK/SINIRDA profilleri birlikte. Bu, seçilebilir bir kullanıcı profili veya yalnız atipik üretim deneyi değildir. Normal üretim düğmesi B benzeri seçili Markdown bağlamı kullanır; A'yı normal düğmeyle eşdeğer raporlamayın.

Yalnız `/api/compare-scenario` kullanılır. Her üretimden önce ücretsiz istem önizlemesi alınır; model, ayarlar, protokol ve kaynak kimlikleri dosyaya yazılır. Aynı girdinin bütün kolları/tekrarları aynı model/ayar/protokole kilitlenir. Sunucunun model ayarı değiştirilmez. Önizleme hash'i kaynak değişince üretimi reddeder. 24 üretim sıralıdır: girdi sırası, tekrar 1 A→D, tekrar 2 A→D. Sıra etkisi/tek model ve iki tekrar sınırlamalarını raporlayın; 24 planlı deneme 24 başarılı sonuç garantisi değildir.

## Kayıt ve devam ettirme

**7 Kasım gerçek deney sonrası kota koruması:** sağlayıcının429/kota kodu, backend'in HTTP502 hata sarmalayıcısındaki `providerError` içinden de tanınır. Daha önce sağlayıcı Promise'ı bitmiş sayıldığı için sonraki kol başlıyordu. Artık `provider_quota_rejected` nedeniyle manifest durdurulur; hata kaydı ve null tokenlar korunur, sonraki çağrı yapılmaz. Eski kota kayıtlarıyla yeniden başlatmak da otomatik devam etmez. Bu durum, timeout'taki bilinmeyen sağlayıcı sonucundan ayrıdır; `remoteOutcomeUncertain` sırf kota reddi nedeniyle true yapılmaz.

Yeni, tercihen depo dışı boş klasör kullanın. `manifest.json` planı ve UUID'leri sabitler. Her UUID JSON'u çağrıdan önce `running` yazılır, sonra `completed/failed`; ham metin boşlukları korunur. Başarılı ve başarısız kayıtlar tekrar çağrılmaz. İstemci kapanırsa uzaktaki sağlayıcı işi sürebilir. **504/timeout, gönderim sonrası bağlantı hatası, yerel kapasite doluluğu veya bitişi doğrulanmamış sağlayıcı işi deneyin tamamını durdurur.** Terminal kayıt ve `manifest.halted` diske yazılır; sonraki kola geçilmez. Yeniden çalıştırma da bu kilidi otomatik kaldırmaz. Eski çalıştırıcının belirsiz hata kayıtları ve running→interrupted dönüşü de durdurma sebebidir. Otomatik tekrar veya kuyruk yoktur. Sunucudaki işin durumu operatör tarafından değerlendirilmeden yeniden başlatmayın; CLI kasıtlı olarak bu durdurmayı aşan bir seçenek sunmaz. İç API'deki açık operatör onayı geçmişe kaydedilir, başarısız çağrıyı tekrar etmez; bu onay kendi başına sağlayıcının işi bitirdiğinin kanıtı değildir.

`runner.lock` aynı klasörde iki çalıştırıcıyı engeller. Zorla kapanışta kilit kalabilir: PID'nin bu deneye ait sürecinin artık çalışmadığını ve sunucudaki işi insan kontrolüyle doğrulamadan kilidi kaldırmayın. Sonra yalnız o klasördeki runner.lock kaldırılarak aynı komutla devam edilebilir. Kaynak/model/protokol veya Git durumunu değiştirmeyin; farklı koşul için yeni klasör kullanın. Dosyalar yereldir, süresiz otomatik arşiv/temizlik servisi yoktur; kullanıcı saklama/silme ve disk alanından sorumludur. Sırlar stdin'den alınır, kayda/export'a girmez. Ham içerikli deney klasörlerini herkese açık paylaşmadan inceleyin.

`measurement.promptTokens/outputTokens` sağlayıcının bildirdiği değerlerdir; eksikse null. Cached/reasoning/maliyet mevcut endpoint'te sunulmadığından null. `providerDurationMs` backend'in sağlayıcı çağrısı bekleme süresi; `endpointDurationMs` retrieval ve sağlayıcıyı kapsar; `clientDurationMs` HTTP gidiş-dönüştür (mobil kullanıcı süresi değildir). İç içe süreleri toplamayın. Timeout sağlayıcı süresini tamamlamamış olabilir; bu ölçümü tamamlanmış API süresi saymayın. Başarı oranının paydası başarısız/kesilmiş kayıtları da kapsamalı; içerik değerlendirmesi ayrı yapılır.

Backend karşılaştırma sınırı 120 sn, mobil ve bu çalıştırıcı HTTP sınırı 150 sn (30 sn terminal yanıt/taşıma payı). Backend işinin kesin iptali iddia edilmez. Proxy sınırı da 150 sn'den kısa olmamalıdır; ağ/uzak kurulum bu hazırlıkta doğrulanmadı. Bu araç otomatik sağlayıcı yeniden denemesi yapmaz.

Her UUID için `evaluation_template.json` kopyasını ayrı inceleme dosyası olarak doldurun. Şema durumu ile tepki tutarlılığı, yaşa uyarlama ve içerik incelemesini ayırın; kanıt cümlelerini belirtin. İki tekrar üzerinden genellenebilir klinik kalite veya başarı sonucu çıkarmayın.

Git bilgisi çalıştırıcının yerel HEAD'idir; `dirty` çalışma ağacı durumunun parmak izidir, commitlenmemiş kodun tam arşivi değildir. Sunucu Git HEAD'i API'de verilmediğinden `serverGitRevision=null`; deney öncesi sunucudaki commit/kaynak sürümünü ayrıca kaydedin. Bir önceki sunucu ölçümünü yeni protokol ölçümü olarak kullanmayın. Proxy ve sunucu sürümü bu araçla dağıtılmaz veya doğrulanmış sayılmaz.

## Mevcut uzak servis — önce salt okunur kontrol

**Sonraki kullanıcı doğrulaması:** sunucunun da73d30 güncellemesi,49 geçen sunucu testi ve12 başarılı önizleme bildirildi. Aşağıdaki456dec0/kısmi güncelleme açıklaması önceki kontrol hazırlığının tarihsel durumudur. Gerçek deney kaydı `comparison24_20261107_010505`:17 completed,7 sağlayıcı429/QUOTA_EXCEEDED. Bu yeni kota koruması o deneyde etkin değildi; geçmiş kayıtlar değiştirilmedi.

Deney Windows'tan mevcut uzak API'ye bağlanacak; yerel backend/ikinci servis başlatılmaz. Sunucuda `norogelisim.service` zaten çalışıyor. Son bildirilen taban HEAD456dec0, metrik dosyaları41fc83f'ten, pilot backend/CLI dosyaları3073332'den kısmi alınmış; canlı sayaç değişikliği ve izlenmeyen compose.http.yaml kaydı var. Bunlar tarihsel kullanıcı bildirimidir, bugünkü sunucu durumu değildir. Aşağıdaki kontrol çıktısı görülmeden pull/reset/clean, dosya aktarımı veya restart yapılmaz.

Windows PowerShell'de yalnız şu blok çalıştırılır (bu hazırlıkta çalıştırılmadı). Kimlik doğrulama kişisel SSH anahtarıyla; sudo yetkisi yoksa ilgili satır salt okunur eksiklik bildirir. Gerçek .env, systemd Environment/ExecStart değerleri, süreç komut argümanları ve ham günlükler yazdırılmaz.

```powershell
$target = 'mertcan@SUNUCU_IP'
$checks = @'
set -eu
cd /opt/norogelisim/app
printf '\n--- Git ---\n'
git branch --show-current
git log -1 --format='%H %cs'
git status --short
git diff --name-status
git diff --cached --name-status
printf '\n--- Source fingerprints (no secrets) ---\n'
for f in backend/server.js backend/scenario_input_generation.js backend/scenario_age_group.js backend/scenario_comparison.js backend/generation_capacity.js backend/generation_measurement.js backend/rag/retriever.js backend/rag/clinical_knowledge_base.json backend/resources/Davranis_Kartlari_v02.md backend/d01_pilot_jobs.js research/d01/pilot_cli.py research/d01/pilot_metrics.py; do
  if [ -f "$f" ]; then sha256sum -- "$f"; else printf 'MISSING: %s\n' "$f"; fi
done
printf '\n--- Service (no environment or raw logs) ---\n'
systemctl show norogelisim.service -p ActiveState -p SubState -p MainPID -p ExecMainStartTimestamp -p FragmentPath -p DropInPaths -p EnvironmentFiles
pid=$(systemctl show norogelisim.service -p MainPID --value)
if [ "$pid" -gt 0 ]; then
  ps -p "$pid" -o pid,ppid,comm,etimes,pcpu,rss
  sudo -n readlink -f "/proc/$pid/cwd" || printf 'Service cwd unavailable without sudo\n'
  printf '\n--- Direct service children (no argv) ---\n'
  ps --ppid "$pid" -o pid,ppid,comm,etimes,pcpu,rss || true
fi
printf '\n--- Python/Node processes (no argv) ---\n'
ps -eo pid,ppid,comm,etimes,pcpu,rss | awk 'NR==1 || $3 ~ /^(node|nodejs|python|python3|python3\.[0-9]+)$/'
printf '\n--- Port 8000 connections/listener ---\n'
sudo -n ss -Hntp '( sport = :8000 )' || printf 'Connection inspection unavailable\n'
sudo -n ss -Hlntp '( sport = :8000 )' || printf 'Listener inspection unavailable\n'
# Optional: enter the ALREADY KNOWN pilot job root, not an inferred/default path.
pilot_root=''
if [ -n "$pilot_root" ]; then
  sudo -n python3 - "$pilot_root" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = sorted(root.glob('*/job.json'))
print('pilot_job_files=', len(files), 'inspected_limit=200')
for file in files[:200]:
    try:
        if file.stat().st_size > 65536:
            print('job_metadata_too_large'); continue
        job = json.loads(file.read_text())
        if job.get('status') not in ('completed', 'failed', 'interrupted'):
            # IDs/status only; no errors, video paths, request text or headers.
            print(json.dumps({k: job.get(k) for k in ('jobId', 'status', 'childPid', 'updatedAt')}))
    except (OSError, ValueError):
        print('job_metadata_unreadable')
PY
else
  printf 'Pilot job root not supplied; persistent active-job records NOT checked.\n'
fi
printf '\nIN-FLIGHT GENERATION IS NOT PROVEN IDLE: capacity is in Node memory; no read-only active-generation API exists.\n'
'@
($checks -replace "`r", '') | ssh $target 'bash -s'
```

Pilot kayıt kökü biliniyorsa `pilot_root` satırı doğru mevcut dizine ayarlanabilir; .env okunarak otomatik çıkarılmaz.200 kayıt sınırı ve bulunamayan izin/kök açık kontrol eksikliğidir. Aktif Python süreci, pilot kaydı ve port bağlantısı faydalı ipuçlarıdır; dış sağlayıcıya sürmekte olan senaryo isteği bunlardan kesin çıkarılamaz. Health200 de model/kapasite boşluğu kanıtı değildir. Kontrol çıktısını birlikte değerlendirdikten sonra, yerel commitlenmemiş RAG/graf farkları ve sunucudaki özel pilot düzeltmeleri için dosya bazlı güncelleme planı belirlenecek; bu aşamada dağıtım komutu verilmez.

Sabit sıra (girdi1→2→3, her tekrarda A→B→C→D) kol ile deneme sırasını karıştırır: sağlayıcı yükü, ısınma/cache, günün saati ve kota değişimi süre/token karşılaştırmasını etkileyebilir. Sıra bu protokolde değiştirilmedi; zaman damgalarıyla birlikte raporlanmalı ve kol farkının tek nedeni RAG kabul edilmemelidir. İki tekrar genelleme için sınırlıdır.

## Windows PowerShell — ancak sunucu kontrolünden sonra

Önce sunucunun bu kaynak/protokol sürümünde olduğunu kontrol edin; çalıştırıcı dağıtım yapmaz. `--plan` ağ çağrısı yapmaz. `--execute` **24'e kadar ücretli çağrıyı açıkça başlatır**; bu hazırlık sırasında kullanılmadı.

```powershell
Set-Location C:\Projeler\Norogelisim\mobil_rag_223bc7d
node backend/run_comparison_24.js --plan
# Gerçek deney için adresi girin; HTTPS veya güvenli SSH tüneli kullanın.
$server = Read-Host 'Karşılaştırma sunucu adresi'
$output = Join-Path 'C:\Projeler\Norogelisim\calisma' ('comparison24_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$secure = Read-Host 'Oturumluk ekip anahtarı' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $sessionKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  @{accessKey=$sessionKey} | ConvertTo-Json -Compress | node backend/run_comparison_24.js --execute --server $server --output $output
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
  Remove-Variable sessionKey,secure -ErrorAction SilentlyContinue
}
```

Devam ettirmede `$output` mevcut aynı klasör olmalıdır; yeni tarihli klasör oluşturmayın. Sunucu/anahtar komut geçmişine yazılmaz; terminal oturumu belleğinde kullanılır. Gerçek `.env` okunmaz.

Kontrollü doğrulama (ücretli çağrı yok):
```powershell
node --test --test-isolation=none backend/test/comparison_experiment.test.js backend/test/scenario_comparison.test.js backend/test/generation_measurement.test.js
```

## Çevrimdışı özet ve insan incelemesi

`summarize_comparison_24.js` yalnız dosya okur; sağlayıcı/API bağlantısı kurmaz. Yeni bir çıktı klasörü gerektirir, orijinal klasör içine yazmaz.25 JSON'un (manifest+24 kayıt) SHA256 değerleri önce/sonra karşılaştırılır. `trials.csv` her girdi/kol/tekrarı; `summary.json` yalnız completed kayıtların alan bazında n/ortalama/min/max değerlerini; `SUMMARY.md` okunabilir tabloyu; `missing_successful_outputs.json` üretilemeyen yanıtları taşır. Kota reddi süreleri ayrı tutulur; null CSV hücreleri boştur, sıfır değildir. `reviews/` altında yalnız tamamlanan yanıtlar için mevcut şablon, özgün istek/ham yanıt/anlatı ile hazırlanır; bütün değerlendirmeler not_reviewed/null kalır.

```powershell
node backend/summarize_comparison_24.js C:\Projeler\Norogelisim\calisma\comparison24_20261107_010505 C:\Projeler\Norogelisim\calisma\YENI_OZET_KLASORU
node --test --test-isolation=none backend/test/comparison_experiment.test.js backend/test/comparison_summary.test.js backend/test/scenario_comparison.test.js backend/test/generation_measurement.test.js
```

İlk özet: `C:\Projeler\Norogelisim\calisma\comparison24_20261107_010505_summary_20261107_01`. Sabit sıra/kota nedeniyle başarı sayıları eşit değildir; tüm kolları farklı girdi bileşimleriyle havuzlayarak nedensel RAG etkisi çıkarmayın. İçerik ve yaşa uygunluk incelemesi henüz yapılmadı.
