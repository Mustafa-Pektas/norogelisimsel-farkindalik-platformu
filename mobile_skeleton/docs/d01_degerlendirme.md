# Küçük Qwen D01 değerlendirmesi

Sabit plan: [d01_qwen_v1.json](../assets/evaluations/d01_qwen_v1.json). Tam istemlerin tek değerlendirme kaynağı bu asset'tir. Ortak başlangıç, yönelme ve oyuna devam görevleri sırasıyla **ikişer kez** çalışır: `common_start_1`, `common_start_2`, `turn_to_mother_1`, `turn_to_mother_2`, `continue_playing_1`, `continue_playing_2`.

Alternatiflerin istemlerinde aynı sabit başlangıç bağlam olarak verilir; önceki model cevabı sonraki isteme eklenmez. Başlangıç çıktısındaki bir eksiklik sonraki denemelerin girdisini değiştirmez. Her görev 2–3 kısa Türkçe cümle ister; başlık, JSON ve açıklama istemez. Alternatiflerde yeni çağrı/uyaran yasaktır. Denemeler arasında istem değiştirilmez, model cevabı düzeltilmez veya yenisiyle değiştirilmez. İki tekrar önceden planlıdır; hata üzerine retry değildir.

Mevcut Qwen dosyası ve `LlamadartTestRuntime` kullanılır. Her denemeye ayrı `LocalLlamaTestService` ve yeni native motor açılır; önceki motor kapatılmadan sonraki açılmaz. Aynı CPU ayarları, 2048 bağlam, 160 yeni token üst sınırı, düşünme kapalı, sıcaklık 0.7, top-P 0.8, top-K 20, min-P 0, tekrar cezası 1.0 ve presence cezası 0 korunur. Seed belirtilmez; native motorun seçtiği kesin seed raporlanmaz. Her deneme tek user mesajıyla başlar.

## Kayıt

Uygulamanın mevcut belge dizini API'si, Dart dosya yazımı ve panoya kopyalama işlemi kullanılır. Yeni paket, paylaşım servisi veya sunucu eklenmedi. Değerlendirme başlatılınca ayrı `evaluations/d01_qwen/run_...` klasörü oluşturulur:

- İlk model açılmadan `protocol.json` tam istemleri, sıralamayı, model kimliğini ve istenen ayarları sabitler. Altı ayrı kayıt önce `pending` olarak yazılır.
- Her denemenin kendi JSON dosyası; görev/deneme ve çalışma kimliği, tam istem, model deposu/dosya adı, ayarlar, ham API içerik cevabı, başlangıç/bitiş tarihi, toplam/üretim süresi, varsa native istek/çıktı/önbellek token sayıları ve API bitiş nedenini içerir. Şablonlu token sayımı native üretim sayımından ayrı tutulur. Raporlanmayan sayı ve neden `null` kalır.
- Raporlanan örnekleme, bağlam kapasitesi ve son prompt önizlemesi de saklanır. Genel runtime teşhis haritası dışa aktarılmaz; kişisel model/kayıt yolları kayda alınmaz. Hata metinlerinden yerel yollar çıkarılır. Model ağırlığı hiçbir kayda kopyalanmaz.
- `run_summary.json` yalnızca çalıştırma/iptal/hata özetidir. `semantic_verdict=null` kalır. Yeni çalıştırma yeni klasör kullanır; önceki kayıtlar üzerine yazılmaz.

Her denemede `human_evaluation` içindeki şu beş alan **null/boş** bırakılır: Anlaşılır Türkçe; Zorunlu olayların bulunması; Doğru olay sırası; Yasaklanan ek olayların bulunmaması; İstenen çıktı biçimi. Anlamsal başarı kararı, kelime araması, modelin kendine verdiği puan veya davranış sonucu üretilmez. `execution_status=completed` yalnızca çıkarım işleminin sonlandığı anlamına gelir.

Bir deneme teknik hata verirse kısmi ham cevap ve hata kendi kaydında tutulur; kaynaklar kapatılabildiyse planlı sıraya devam edilir. Kaynak kapatma hatasında kalan denemeler çalıştırılmaz. İptalde biten/kısmi kayıtlar korunur; başlanmayan kayıtların `raw_response=null`, durumu `pending` kalır. Plan diske yazılamazsa model çıkarımı başlamaz.

## Kullanım ve gerçek çalıştırma sınırı

Yeni ekran, test kartı, onay/düzenleme formu veya graf bağlantısı eklenmedi. Mevcut **Qwen — Ortak başlangıç testi** kartının altındaki **D01 değerlendirmesini başlat (6 deneme)** tek giriş noktasıdır. Değerlendirme boyunca tekli model testleri ve model yönetimi kilitlenir. Ham kayıtlar mevcut alanda salt okunur gösterilir; **Değerlendirme kayıtlarını kopyala** tam JSON'u panoya alır.

Emülatöre ADB erişimi doğrulandı; mevcut Llama ve Qwen dosyaları yerinde. Ancak yeni Android derlemesi Flutter SDK `bin/cache/lockfile` erişim hatasıyla durdu. **Bu değerlendirmede altı gerçek model çıkarımı çalıştırılmadı.** SDK izinleri/ağ ayarları değiştirilmedi; model veya paket indirilmedi. Kontrollü test kayıtları `execution_source=test_double` olarak işaretlenir ve gerçek model sonucu sayılmaz.

Normal PowerShell'de uygulama klasöründen güncel kodu açmak için:

```powershell
flutter run --no-pub -d emulator-5554
```

Uygulamada tek işlem: **Stüdyo → Qwen — Ortak başlangıç testi → D01 değerlendirmesini başlat (6 deneme)**. Başlatılan üretimlerin içerik değerlendirmesi daha sonra insan tarafından yapılır.

## Yazılım kontrolleri

56/56 Flutter kontrolü geçti; bunların 7 tanesi yeni değerlendirme hizmetini, 3 ek API kontrolü de üç görevin aynı Qwen/CPU/2048/160 ayarlarıyla aktarılmasını sınar. Mevcut servis kontrolleri 18/18 geçti. İlgili altı Dart dosyasında statik analiz temizdir. Testlerdeki üretilmiş cevaplar kontrollü test verisidir; altı gerçek model sonucu değildir.
