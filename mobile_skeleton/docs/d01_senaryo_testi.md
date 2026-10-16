# D01 senaryo testi

> Aşama raporudur. Güncel durum ve sonraki işlem: [Devam notu](DEVAM_NOTU.md).

Stüdyodaki **D01 senaryo testi → D01 senaryosu üret** işlemi mevcut indirilmiş
GGUF'yi, mevcut llamadart 0.12.0 bağlantısı ve CPU ayarlarıyla kullanır. Yeni
paket/model, uzak sunucu, JSON/graf bağlantısı veya şablon fallback eklenmedi.
Önceki **Modeli test et** işlemi ayrı durur; 512 bağlam / 32 yeni token sınırı
ve merhaba isteği korunur. İki test aynı anda model açamaz.

Kaynak, proje üst klasöründeki
[Davranis_Kartlari_v02.md](../../../belgeler/Davranis_Kartlari_v02.md) D01 kartıdır.
Tek istek kaynağı `LocalLlamaTestRequest.d01` içindedir; ekranda **Modele
gönderilen istek** açılarak tamamı okunabilir. İstek 30 aylık Deniz'in evde
oyuncakla oynamasını, çağrı öncesi yetişkine dönük olmamasını ve yetişkinin
doğal sesle yalnızca bir kez “Deniz” demesini ister. Dokunma, ek jest ve başka
yönerge yoktur; çağrı öncesi/sonrası kesintisizdir.

Modelden toplam en fazla 80 kelimelik üç bölüm istenir: ortak başlangıç,
yetişkine baş yönelmesiyle devam ve oyuna devam. Son ikisi ayrı planlanan
alternatiflerdir. Tanı, risk puanı, klinik yorum/eşik ve uydurma tepki süresi
istenmez; taslak gözlem veya video kanıtı olarak sunulmaz.

D01 için bağlam **2048**, çıktı üst sınırı **384 yeni token** seçildi. Türkçe
koşullar, modelin sohbet şablonu ve üç kısa bölüm için önceki 512/32 sınırından
daha fazla pay gerekir. 80 kelime istek talimatıdır; 384 token motor sınırıdır.
Bu sınırlar klinik süre değildir. Model cevabı değiştirilmeden ve süreleriyle
gösterilir; içeriğin D01'e uygunluğu otomatik doğrulanmış sayılmaz. Kullanıcı
üç bölümün ve kısıtların korunup korunmadığını incelemelidir.

İptal, hata, kısmi cevap ve kaynak kapatma davranışı ortak servis üzerinden
korunur. İndirme sırasında testler, testler sırasında indirme/silme kilitlidir.
Mevcut Senaryo Üret akışı değişmedi.

Kontroller: 15 servis testi; Flutter test motorunda 8 kart, 3 yayımlanmış API
sınırı ve 13 graf ekranı testi; ayrıca 24 graf model testi geçti. API sınırı
testleri kurulu llamadart türleriyle istek, yerel yol, CPU ve token sınırlarını
kontrol eder. Kontrollü test motorları gerçek D01 model üretimi kanıtı değildir.
Değişen Dart dosyalarının statik analizi temizdir. Android APK denemesi bu
ortamda Flutter SDK `bin/cache/lockfile` erişim hatasıyla durdu; D01'in gerçek
emülatör cevabı henüz burada doğrulanmadı. Merhaba testindeki “Merhaba!” sonucu
kullanıcı tarafından bildirilmiştir.

Normal PowerShell'de, mevcut emülatör açıkken:

```powershell
Set-Location .\mobile_skeleton
flutter run --no-pub -d emulator-5554
```

Emülatör kimliği farklıysa mevcut kimliği kullanın. Zaten açık bir `flutter run`
terminali varsa `R` ile hot restart yapılabilir. Senaryo Stüdyosu'nda D01 kartına
kaydırıp **D01 senaryosu üret** düğmesine basın; ham metni, iki alternatifin
ayrılığını ve süreyi inceleyin. Cevap istenen koşulları karşılamıyorsa bu bir
model çıktısı bulgusudur; uygulama bunu bir şablonla değiştirmez.
