# Süre sınırlı CPU tanılaması

Bu hazırlıkta deney çalıştırılmadı. Önce kayıtlı koşuların ve CPU raporunun incelenmesi gerekir. Canlı backend boşken kullanıcı tarafından ayrı bir deney olarak başlatılır; çalışan analizle aynı anda çalıştırmak karşılaştırmayı etkiler. Backend, sistem affinity'si ve pilot protokolü değiştirilmez.

Linux sunucuda, betik dosyası sağlandıktan sonra depo kökünde:

```bash
cd /opt/norogelisim/app
read -r -p 'Kayitli runtime python_executable yolu: ' DIAG_PYTHON
"$DIAG_PYTHON" -B research/d01/cpu_diagnostic.py --inspect-cpu
```

Bu ilk komut model yüklemez. Mantıksal CPU, süreç affinity'si, cgroup v2 yolu ve üst gruplardaki cpu.max/cpu.stat/cpuset.cpus.effective, yalnız ilgili thread ortam ayarları yazdırılır. cpu.max içindeki kota/periyot oranı CPU kapasitesidir; affinity CPU kimlikleri başka bir sınırdır. cgroup yolu/mount çözümlemesi eksikse veya v1 ise kota bilinmiyor kalır; host CPU sayısı kullanılabilir kapasite diye kabul edilmez. Node/Python farklı cgroup/affinity ile başlatılıyorsa bu shell raporu backend'in koşullarını kanıtlamaz; ilgili süreçlerin Cpus_allowed_list ve /proc/PID/cgroup kayıtları ayrıca karşılaştırılmalıdır. cpu.stat önce/sonra farkları grup ölçümüdür; başka süreçler de bu farklara katkı yapabilir.

Kota/affinity en az4 CPU'ya izin veriyorsa1/2/4 intra-op karşılaştırması uygundur. Daha azsa4 thread aşırı abonelik deneyi olur; üretim için öneri sayılmaz. CPU raporu bilinmeden koşul seçimi veya protokol değişikliği yapılmaz. Deney, önce4 referansı sonra1/2 ölçer; sıra/yük etkileri nedeniyle tek turdan en iyi ayar seçilmez. Inter-op4 sabittir.

CPU raporu incelendikten sonra, yalnız kullanıcı açıkça çalıştıracaksa:

```bash
read -r -p 'Tamamlanmis denetlenmis is run klasoru: ' DIAG_RUN
read -r -p 'Mevcut agirlik dosyasi: ' DIAG_WEIGHTS
read -r -p 'Resmi 6DRepNet360 kaynak klasoru: ' DIAG_SOURCE
"$DIAG_PYTHON" -B research/d01/cpu_diagnostic.py \
  --recorded-run "$DIAG_RUN" --weights "$DIAG_WEIGHTS" \
  --official-source "$DIAG_SOURCE" \
  --output-dir "/opt/norogelisim/experiments/cpu_diag_$(date -u +%Y%m%dT%H%M%S)_$$"
```

Yalnız0/36/72 kareleri kullanılır; video çözülmez. Kaydedilmiş RGB224×224 görüntülerinin ve resmî normalizasyonla elde edilen tensörlerin SHA256 değerleri eski raw_frames kayıtlarıyla karşılaştırılır. Resize/CenterCrop zaten kaydedilmiş girdilere uygulanmıştır; tekrar uygulanmaz. Ağırlık ve resmî kaynak hash'leri ve strict runtime/matris kontrolleri korunur. Her koşulda ayrı Python süreci ve tek model yüklemesi, bir ısınma çağrısı ve üç ölçüm vardır: en fazla12 forward. İlk ölçümden önceki ısınma da kaydedilir; ölçüm ortalamasına katılmaz.

Toplam iş süresi180 sn; yalnız kendi alt sürecini kapatmak için en fazla5 sn ek pay. Süre sonu interrupted, alt süreç hatası failed; eski kayıtlar üzerine yazılmaz. Her sonuç JSONL'ye flush/fsync ile yazılır. report.json kısmi koşulları ve matris farklarını taşır; eksik koşul başarılı sayılmaz. Runtime yüklemesinin wall/CPU süreleri, her tahminin forward ve çevre kontrollerini kapsayan prediction wall/CPU süreleri ayrıdır. Matrisler hem eski aynı kareyle hem4-thread referansıyla1e-6 mutlak eleman toleransında karşılaştırılır; eşleşme davranış/poz doğruluğu değildir.

Bu dosya ve cpu_diagnostic.py yerel depoda hazırlanmıştır; sunucuya aktarılmış veya çalıştırılmış sayılmaz. Ortam/anahtar dosyaları okunmaz, API çağrısı yapılmaz. Çıktı arşivi ölçüm kapsamıyla birlikte saklanmalıdır.
