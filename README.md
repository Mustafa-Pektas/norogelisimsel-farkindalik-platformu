# Nörogelişimsel Farkındalık İçin Simülasyon Platformu

Çocukların sosyal iletişim davranışlarını konu alan sentetik senaryolar hazırlamak, bu senaryoları graf ve klip planlarına dönüştürmek, dallanmalı videolarla eğitim ve farkındalık deneyimleri sunmak amacıyla geliştirilen üniversite tasarım projesi.

**Bursa Uludağ Üniversitesi · Bilgisayar Mühendisliği · Tasarım Projesi**

> Proje geliştirme ve araştırma aşamasındadır. Klinik tanı koyan veya doğrulanmış bir otizm risk puanı veren bir ürün değildir. Üretilen senaryolar planlanan olaylardır; gerçek çocuk gözlemi, etiketlenmiş kanıt veya onaylanmış içerik olarak kabul edilmez.

## Güncel kod ve belgeler

| Konum | Amaç |
|---|---|
| [entegrasyon dalı](https://github.com/Mustafa-Pektas/norogelisimsel-farkindalik-platformu/tree/entegrasyon) | Güncel ortak mobil uygulama ve backend geliştirmesi |
| [Kullanım rehberi](https://github.com/Mustafa-Pektas/norogelisimsel-farkindalik-platformu/blob/entegrasyon/mobile_skeleton/docs/KULLANIM_REHBERI.md) | Ekranların amacı, kullanım akışları ve mevcut sınırlar |
| [Backend kurulum belgesi](https://github.com/Mustafa-Pektas/norogelisimsel-farkindalik-platformu/blob/entegrasyon/backend/README.md) | Ortam ayarları, çalışma modları, kaynak ve erişim yönetimi |
| [Geliştirme ve devam notları](https://github.com/Mustafa-Pektas/norogelisimsel-farkindalik-platformu/blob/entegrasyon/mobile_skeleton/docs/DEVAM_NOTU.md) | Güncel yol haritası ve tarihsel geliştirme kayıtları |
| [Literatür taraması](literatur/README.md) | Kaynaklar, tıklanabilir bağlantılar ve projeyle ilişkileri |

Bu README, **24 Ekim 2026** itibarıyla ortak geliştirme durumunu açıklar. `main` dalındaki bu belgenin varlığı, `entegrasyon` dalındaki uygulama kodunun `main` dalına birleştirildiği anlamına gelmez. Belgelerde bağlantılı dal zaman içinde ilerleyebilir.

## Amaç ve kapsam

Proje iki ana çalışma alanını bir araya getirir:

1. **Simülasyon ve eğitim:** Davranış kartlarından yararlanarak senaryo üretme, alternatifleri karşılaştırma, olay akışını grafa dönüştürme, görsel/sesli üretim yönergeleri hazırlama ve dallanmalı video oynatma.
2. **Video analizi araştırması:** İlk olarak isme tepki davranışında seslenme anı, baş yönelmesi ve yönelmenin hedefini inceleme; insan etiketleriyle karşılaştırılabilir bir analiz yöntemi geliştirme.

Senaryo formunda 12–36 ay aralığı kullanılabilir. Bu aralığın seçilebilir olması, her davranış görevinin bütün yaşlarda bilimsel veya teknik olarak doğrulandığını göstermez. Davranış kartlarındaki pilot kapsam ve görev koşulları ayrıca incelenir.

İsme tepki verme, yetişkinin işaret ettiği hedefe yönelme ve istemek için işaret etme gibi görevler D01–D10 davranış kimlikleriyle ele alınır. Tam tanımların tek kaynak dosyası: [Davranış Kartları v0.2](https://github.com/Mustafa-Pektas/norogelisimsel-farkindalik-platformu/blob/entegrasyon/backend/resources/Davranis_Kartlari_v02.md).

## Mevcut özellikler

| Alan | Mevcut durum |
|---|---|
| Mobil uygulama | Flutter tabanlı ana panel, video analizi ve simülasyon/eğitim alanları |
| Senaryo üretimi | Tek formdan yaş, bir veya birden fazla davranış, ortam ve ek yönergeyle backend üzerinden üretim |
| Senaryo düzeni | Alternatifli anlatı veya 26 sahnelik doğrusal anlatı |
| RAG karşılaştırması | Aynı model ve girdide A/B/C kaynak bağlamı deneyi; ham sonuçlar, süreler ve varsa token sayaçları |
| Senaryo çalışma alanı | Sonucu açık onayla editöre aktarma, düzenleme, doğrulama ve cihazda senaryo taslağı kaydetme |
| Graf | Senaryodan deterministik dönüşüm; sahne, geçiş, bitiş ve davranış ilişkileri |
| Klip planı | Grafın sahnelerine bağlı eylem, başlangıç/bitiş durumu, hedef süre, görsel prompt ve ayrı seslendirme yönergeleri |
| Dışa aktarma | Ham üretim/kaynak bilgileri, plan JSON'u ve prompt metinlerini kopyalama |
| Hazır D01 örneği | Video eşleme ve dallanmalı oynatma; tamamlanan seçili yolu baştan tekrar oynatma |
| Klip geçişleri | Kesin olarak bilinen tek sonraki klibi önceden hazırlama; en fazla aktif ve hazırlanmış iki oynatıcı |
| Backend korumaları | Deployment modunda sınırlı endpoint kapsamı, gövde sınırı, ekip anahtarı, ortak üretim kapasitesi ve bekleme süresi yönetimi |

Klip planı üretmek video üretmek değildir. Genel bir yeni plan için video sağlayıcısına otomatik gönderim, bütün yeni planlara video eşleme ve gerçek ses üretimi henüz tamamlanmış değildir. Hazır D01 videoları yeni senaryolara otomatik uygulanmaz.

## Mimari

| Bileşen | Sorumluluk | Mevcut konum |
|---|---|---|
| Flutter istemci | Formlar, sonuç inceleme, editör, taslak, graf dönüşümü/görünümü ve oynatma | Mobil cihaz |
| Node.js / Express | İstek doğrulama, kaynak seçimi, istem hazırlama, üretim ve plan doğrulama | Yerel backend; uzak dağıtım planlanıyor |
| Kanonik Markdown kaynağı | Davranış görevleri ve ortak kurallar | Backend paketi |
| Gemini API | Senaryo ve klip planı için metin üretimi | Haricî sağlayıcı |
| Video ve ses üretimi | Sentetik klipler, seslendirme ve zaman eşleme | Entegrasyon aşaması bekliyor |
| Davranış analizi | Yönelme hedefi ve kanıt temelli değerlendirme | Araştırma aşaması |

**Mevcut üretim akışı:** Stüdyo formu → normal üretim veya A/B/C → sonucu inceleme/seçme → açık editör aktarımı → doğrulama → graf → klip/prompt planı → insan incelemesi ve dışa aktarma.

Graf dönüşümü şu anda mobilde yapılır; graf işlemlerinin sunucuya taşınması gelecek iştir. Kendi büyük dil modelimizi çalıştıran bir sunucu henüz kurulmuş değildir.

## RAG ve karşılaştırma deneyi

Buradaki RAG, istekle seçilen davranış kimliklerine göre güvenilir kaynak metnini getirip LLM üretimine bağlayan **kurallı retrieval** yaklaşımıdır. Embedding, anlamsal arama veya vektör veritabanı kullanılmaz. Literatür klasörü otomatik RAG veri tabanı değildir; çalışan kaynak davranış kartları dosyasıdır.

| Kol | Modele sağlanan bağlam |
|---|---|
| A — ek kart bağlamı yok | Davranış adları, ortak görev/güvenlik ve üretim talimatları; getirilen kart metni verilmez |
| B — seçili kaynak | Ortak talimatlar ve seçilen davranış kartlarının metinleri |
| C — geniş bağlam | Ortak talimatlar ve kanonik kart dosyasının tamamı |

A kolu tamamen kuralsız bir model değildir; ortak istemde D01'e özel görev ayrıntıları da bulunur. Deneyin karşılaştırdığı değişken **ek kart bağlamıdır**. Bu kollar senaryo dalları veya farklı modeller değildir.

Önizleme model çağrısı yapmaz. Üretim açıkça başlatılır; A/B/C birlikte çalıştırıldığında en fazla üç sağlayıcı çağrısı yapılır. Sonuç seçmek ve grafa dönüştürmek kendiliğinden yeni model çağrısı başlatmaz.

### İlk gerçek deneme

30 ay, D01/D02/D03, evde blok oyunu ve 26 doğrusal sahne isteği; bütün kollarda `gemini-3.5-flash-lite`, temperature `0.2`, topP `0.95`, maxOutputTokens `16384`.

| Kol | Sağlayıcı bekleme süresi | Girdi tokenı | Çıktı tokenı |
|---|---:|---:|---:|
| A | 5,03 sn | 1.213 | 1.125 |
| B | 4,58 sn | 3.804 | 1.141 |
| C | 6,20 sn | 8.031 | 1.842 |

Üç çıktı da yapısal kontrolden geçti. Bu tek örneğin insan incelemesinde A'nın D02 anlatısında iki sabit nesne ve “Bak” yönergesi eksikken B ve C'de bu ayrıntılar yer aldı. C, hedef nesneyi araba olarak daha açık tanımladı.

Bulgular tek denemeye aittir; istatistiksel başarı değerlendirmesi, klinik doğruluk veya RAG'nin her zaman hız kazandırdığı iddiası değildir. Süreler video üretimini veya mobil uçtan uca gecikmeyi göstermez. Eksik token bilgisi varsa `null`/“Bilinmiyor” olarak korunur.

## Graf ve süre kavramları

- Alternatifli anlatı dallanan bir graf, doğrusal anlatı ise 26 sahneli tek bir yol oluşturur.
- Sahne sayısı ile klip sayısı farklıdır. Bir sahne birden fazla klip gerektirebilir.
- Toplam süre bir üretim hedefidir; klip başına belirlenen sınır zorunlu üst sınırdır. Mevcut plan sözleşmesinde klip süresi en fazla 8 saniyedir; istek daha küçük sınır seçebilir.
- Örneğin 210 saniyelik hedef için 26 adet 8 saniyelik klip en fazla 208 saniye eder. Hedefe erişmek için en az 27 klip gerekir; hedefin gerçekten karşılanıp karşılanmadığı ayrıca gösterilir.
- Dallı grafın alternatif yolları tek video süresi gibi toplanmaz; süreler yol bazında ele alınır.
- D01 çağrı zamanlaması ve planlanan gözlem süresi yapısal olarak denetlenir. Bu kontrol gerçek videoda ses–görüntü uyumunu veya kesintisiz gözlemi kanıtlamaz.

## Yerel kurulum ve çalıştırma

Aşağıdaki adımlar **entegrasyon dalındaki kod** içindir. Git, Node.js/npm, Flutter/Dart ve Android denemesi için Android SDK/emülatör gerekir. Paket sürümleri depo tanımlarından alınmalıdır.

### 1. Kodu edinme

```bash
git clone --branch entegrasyon https://github.com/Mustafa-Pektas/norogelisimsel-farkindalik-platformu.git
cd norogelisimsel-farkindalik-platformu
```

Mevcut geliştirme dizininde kaydedilmemiş değişiklikler varsa bu komutları o dizini değiştirmek için kullanmayın; temiz bir dizine klonlayın.

### 2. Backend

```powershell
cd backend
npm ci
Copy-Item .env.example .env
```

`.env` dosyasını yerelde düzenleyin. Sağlayıcı anahtarı ve `SCENARIO_INPUT_MODEL` gibi gerekli ayarlar için [backend belgesini](https://github.com/Mustafa-Pektas/norogelisimsel-farkindalik-platformu/blob/entegrasyon/backend/README.md) izleyin. Gerçek anahtarları Git'e eklemeyin.

```powershell
npm start
```

Yerel backend varsayılan adresi `http://localhost:8000`, Android emülatörü üzerinden erişim adresi `http://10.0.2.2:8000` biçimindedir. `/health` yanıtı sunucunun erişilebilirliğini gösterir; sağlayıcı anahtarının/kotasının çalıştığını tek başına kanıtlamaz.

### 3. Mobil uygulama

Ayrı terminalde, depo kökünden:

```powershell
cd mobile_skeleton
flutter pub get
flutter devices
flutter run -d <cihaz-kimligi> --dart-define=SCENARIO_SERVER_URL=http://10.0.2.2:8000
```

`<cihaz-kimligi>` yerine `flutter devices` çıktısındaki kimliği yazın. Bu adres Android emülatörü içindir; gerçek cihaz için erişilebilir sunucu adresi kullanılmalıdır. Uygulamada daha önce kaydedilmiş sunucu adresi varsa onu da kontrol edin.

### 4. İlk kullanım

1. Simülasyon ve Eğitim / Stüdyo alanını açın ve sunucu motorunu seçin.
2. Yaş, davranışlar, ortam ve senaryo düzenini belirleyin.
3. Normal üretimi başlatın veya karşılaştırma istemlerini önizleyip A/B/C deneyini açıkça çalıştırın.
4. Sonucu inceleyin ve kullanmak istediğiniz sonucu çalışma alanına taşıyın.
5. JSON editörüne aktarımı onaylayın; graf oluşturup görüntüleyin.
6. Klip/prompt planı hazırlayın; süre, eylem, görsel ve ses yönergelerini inceleyip dışa aktarın.

Ekran bazındaki ayrıntılar ve hazır D01 araçları için [Kullanım Rehberi](https://github.com/Mustafa-Pektas/norogelisimsel-farkindalik-platformu/blob/entegrasyon/mobile_skeleton/docs/KULLANIM_REHBERI.md) okunmalıdır. Senaryo taslağı kaydı, üretilen klip planının kalıcı olarak kaydedildiği anlamına gelmez; planı oturumdan çıkmadan dışa aktarın.

## Test ve doğrulama

Depo kökünden PowerShell:

```powershell
$backendTests = @(Get-ChildItem .\backend\test\*.test.js -File |
    ForEach-Object { $_.FullName })
node --test @backendTests

cd mobile_skeleton
flutter analyze --no-pub
flutter test --no-pub
```

Bağımlılıklar önce kurulmuş olmalıdır. Kontrollü testler gerçek sağlayıcı üretiminin, cihaz kabulünün veya içerik doğruluğunun yerine geçmez.

24 Ekim 2026 tarihli kullanıcı tarafından çalıştırılan son kontrol:

- Statik analiz: temiz.
- Backend: 86 test başarılı.
- Mobil toplu çalışma: 319 başarılı, 1 eski metin beklentisi başarısız.
- Yalnız bu beklenti güncellendikten sonra ilgili `scenario_graph_import_screen_test.dart` dosyasındaki 23 test başarılı.

Son test düzeltmesinden sonra bütün mobil paketin yeniden çalıştırıldığı iddia edilmez. Güncel test sayıları sonraki geliştirmelerde değişebilir.

## Erişim ve uzak dağıtım

- `development` yerel geliştirme modudur; internete açık kurulum için doğrudan kullanılmamalıdır.
- `deployment` modunda güncel üretim yolları sınırlanır; ekip anahtarı, gövde boyutu ve ortak üretim kapasitesi kontrolleri uygulanır.
- Ekip anahtarı Gemini anahtarı değildir. Ortak ekip erişimi sağlar; kişi/rol bazlı hesap sistemi değildir.
- Mobil anahtar ilgili ekran oturumunda tutulur; taslağa kaydedilmez.
- Timeout veya istemcinin bağlantıyı kapatması sağlayıcı işinin durduğunu göstermez. Kapasite sağlayıcı işi bitene kadar tutulur.
- HTTPS, ağ erişimi, istek hızı sınırları, yedekleme ve saklama politikası uzak kurulum sırasında tamamlanmalıdır. Arayüzdeki admin/debug görünürlüğü sunucu yetkilendirmesi değildir.

Sunucu sağlayıcısı henüz kesinleştirilmemiştir. API kullanımı, yerel model çalıştırma, video işleme ve depolama maliyetleri ayrı değerlendirilir. Kurulum adımları başka sunucuya taşınabilir biçimde belgelenecektir.

## Literatür taraması

Tam kaynakça ve açıklamalar: **[literatur/README.md](literatur/README.md)**.

| Konu | Başlıca kaynaklar |
|---|---|
| İsme tepki ve bilgisayarlı görü | [Campbell ve ark., 2019](https://pubmed.ncbi.nlm.nih.gov/29595333/) · [Miller ve ark., 2017](https://pubmed.ncbi.nlm.nih.gov/28162768/) · [Nadig ve ark., 2007](https://pubmed.ncbi.nlm.nih.gov/17404135/) |
| Bakışın hedefi | [Deng ve ark., AAAI 2026](https://ojs.aaai.org/index.php/AAAI/article/view/41177) |
| Ev videosundan analiz | [Kim ve ark., 2025](https://www.nature.com/articles/s41746-025-01993-5) |
| Ortak dikkat ve iletişim | [Mundy ve ark., 2007](https://pubmed.ncbi.nlm.nih.gov/17517014/) · [CSBS DP yayınevi belgesi](https://brookespublishing.com/wp-content/uploads/2012/06/csbs-dp-itc.pdf) |
| Gelişimsel çerçeve ve tarama sınırları | [CDC](https://www.cdc.gov/act-early/milestones/index.html) · [M-CHAT-R/F resmî sitesi](https://www.mchatscreen.com/) · [Robins ve ark., 2014](https://pmc.ncbi.nlm.nih.gov/articles/PMC3876182/) |
| Sentetik insan hareketi videosu | [Knapp ve Bohacek, 2025](https://arxiv.org/abs/2506.09411) |
| LLM ile dallanmalı anlatı | [GENEVA, 2024 sürümü](https://arxiv.org/abs/2311.09213) |

Robotik batarya sökümü üzerine paylaşılan Symmetry makalesi doğrudan çocuk davranışı kaynağı olarak gösterilmez; izlenebilirlik için ayrıntılı literatür belgesinde ayrı tutulur. Bu liste sistematik literatür taraması iddiası taşımaz.

## Haftalık çalışma planı ve açık işler

| İş | Durum / sonraki adım |
|---|---|
| RAG kullanımı ve süre karşılaştırması | İlk gerçek A/B/C denemesi tamamlandı; sonuçların tekrarlı değerlendirmesi ayrı çalışma |
| Sunucu seçimi | Bellek, depolama, API/yerel model ve toplam maliyet karşılaştırması; ardından kurulum |
| Uzak senaryo ve graf işlemleri | Yerel backend çalışıyor; uzak dağıtım ve graf dönüşümünün sunucuya taşınması bekliyor |
| Daha büyük modeller | DeepSeek başta olmak üzere aynı girdilerle model denemeleri bekliyor |
| Yeni sentetik video | Hazır senaryo/klip planından gerçek klip üretimi ve insan incelemesi |
| Sonradan ses ve farklı diller | Soniox'un hedeflenen işe uygunluğunu doğrulama; uygun ses aracıyla üretim ve zaman eşleme deneyi |
| D01 video analizi | Çağıran kişiye yönelme ile başka yöne dönmeyi ayırma; güven değerinin dayanağını araştırma |
| Seçili yolun kesintisiz izlenmesi | Oturum içinde tekrar oynatma mevcut; tek MP4 gerekirse sunucuda birleştirme ve maliyet deneyi |
| Literatür ve tekrar kurulabilirlik | Kaynakça ve mevcut belgeler hazır; gerçek uzak kurulum adımları uygulama sırasında kaydedilecek |

Yanlış üretilen videolar, uygun olmayan model cevapları ve hatalı analizler de nedenleri ve deney koşullarıyla kaydedilmelidir. Planlanan işler tamamlanmış özellik olarak sunulmaz.

## Ekip çalışması ve katkı

Güncel ortak geliştirme temeli `entegrasyon` dalıdır. Diğer dal ve eski çalışma alanlarından doğrudan dosya kopyalamak yerine değişiklikler Git üzerinden karşılaştırılarak alınmalıdır. Katkıda ilgili davranış/kullanım akışı, değişen sözleşme, çalıştırılan testler ve bilinen sınırlar açıklanmalıdır.

API anahtarları, gerçek `.env` dosyaları, kişisel/çocuk verileri, yerel video kayıtları ve build/cache çıktıları kaynak kod deposuna eklenmemelidir. Makale bağlantısı vermek, tam metni veya ölçek formunu yeniden dağıtma izni anlamına gelmez.
