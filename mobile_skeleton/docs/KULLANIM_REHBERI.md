# Kullanım rehberi

Bu uygulamanın iki ana alanı **Video Analizi** ve **Simülasyon ve Eğitim**’dir.
Senaryo/prompt hazırlama ve model karşılaştırması proje ekibinin araçlarıdır.
Üretilen anlatı ve planlar taslaktır; tanı, klinik puan veya gözlenmiş davranış değildir.

## Hangi kavram ne demek?

| Kavram | Anlamı |
|---|---|
| Senaryo / anlatı | Karakterin bulunduğu ortamı ve planlanan olayları anlatan metin. |
| Alternatif yol | Ortak başlangıcın birbirinden ayrı devamlarından biri; bütün alternatifler aynı anda gerçekleşmez. |
| Doğrusal 26 sahne | Aynı senaryonun sırayla ilerleyen 26 anlatı sahnesi; kendiliğinden alternatif içermez. |
| Sahne | Anlatının bir bölümü. Sahne adedi klip adedi değildir; bir sahnede birden fazla üretim klibi bulunabilir. |
| Graf | Sahnelerin hangi sırada ve hangi alternatif bağlantılarla ilerlediğini gösterir. |
| Klip | Dış video aracında tek üretimde hazırlanacak, en fazla 8 saniyelik parça. Toplam senaryo süresi 8 saniye değildir. |
| Prompt | Dış video aracına verilecek görsel üretim yönergesi. Anlatı veya gerçek video değildir. |
| Süreklilik | Karakter, yaş, kıyafet, ortam, nesne, kamera ve klip başlangıç/bitişlerinin tutarlılığı. İstek sabit açı/kadraj belirtiyorsa istem ilgili kliplerde bunu korumayı ister. D02 için iki nesnenin kimliği/konumu ve işaret hedefinin kliplerde tutarlı taşınması istenir; kaynakta eksik ayrıntılar doğrulanmış bilgi değil, açıkça etiketli öneridir. Bunlar anlamsal doğrulama değildir; insan incelemesi ve gerçek videoda kontrol gerekir. |
| Seslendirme | Görsel prompttan ayrı söylenecek söz/sessizlik yönergesi. Uygulama henüz ses üretmez. |
| A/B/C | Aynı isteği aynı görev/çıktı/ayarlarla farklı kaynak miktarları kullanarak karşılaştırma. |
| Hazır D01 | Elle hazırlanmış sabit graf/plan ve cihazda ayrıca bağlanan videolar. Yeni üretimin otomatik video kütüphanesi değildir. |
| Video eşleme | Belirli planId/clipId için galeriden seçilen videonun uygulama kopyasını bağlama. İçerik onayı değildir. |
| Video üretimi | Plan/promptlarla dış araçta gerçek dosyaları oluşturma. Bu uygulama video render etmez. |
| Video analizi | Gerçek videodan davranış ve zaman kanıtı çıkarma. Güncel, doğrulanmış genel analiz hattı henüz tamamlanmadı. |

## Ekranlar ve araçlar

| Giriş / araç | Amacı ve girdisi | Kullanım adımları | Çıktısı / sonraki adım |
|---|---|---|---|
| Ana Panel | İki ana işleve ve güncel D01–D10 bilgi kartlarına erişim. | Video Analizi, Simülasyon ve Eğitim veya bir davranış seçin. | İlgili ekran. Kartların bulunması on analiz modelinin hazır olduğu anlamına gelmez. |
| Davranış ayrıntısı | Davranışın amacını, hazırlığını ve uygulama koşullarını tanıtır. | Temel metni okuyun; ekip ayrıntıları varsa açın. | Bilgilendirme; yaş normu veya klinik yorum değildir. |
| Video Analizi | Video seçme/değiştirme, önizleme ve mevcut analiz durumlarını görme. | Video seçin; varsa yaş bilgisini yalnız 12–36 tam ay olarak girin veya boş bırakın. | Seçilen video; gerçek hizmet bağlı değilse analiz sonucu oluşmaz. Sabit örnek raporu kendi videonuzun sonucu saymayın. |
| Tam ekran video | Aynı videoyu daha büyük izleme. | Tam ekranı açın; oynat/duraklat ve çıkış kontrolünü kullanın. | Aynı oynatıcı ve konuma dönüş. Sekmeden ayrılınca duraklar; dönüşte kendiliğinden başlamaz. |
| Stüdyo: **1. Hazırla** | Tek form: bir veya daha çok güncel davranış, 12–36 tam ay, ortam, isteğe bağlı ek yönerge. | Sunucu motorunu seçin, kartları/yaşı kontrol edin, ortamı yazın. Düzeni seçin ve isteği doğrulayın. | Değişmez istek; normal üretim ve A/B/C bunu aynı şekilde kullanır. |
| Alternatifli anlatı | Ortak başlangıç ve bağımsız devam/bitişler. | Düzen olarak Alternatifli anlatı seçin, Senaryo üret’e basın. | Okunabilir anlatı/sahne kartları; ardından “Bu senaryoyla devam et”. |
| 26 sahnelik doğrusal anlatı | Eski 26 sahne hazırlama ihtiyacının aynı formdaki açık düzeni. | 26 sahnelik doğrusal anlatı seçin. Süre/klip hedeflerini kontrol edip üretin. | 26 sıralı anlatı sahnesi; dönüştürücü tek yol kurar. Eski 26 sahne JSON’ları yeni grafmış gibi yeniden etiketlenmez. |
| Süre ve klip hedefleri | İsteğe bağlı toplam süre hedefi ve klip başına zorunlu üst sınır (en fazla 8 saniye). | Ayrıntıyı açın. Hedef süreyi ve klip üst sınırını seçin. 26 sahne için birer klip varsayımı hedefe yetmiyorsa form gerekli asgari klip sayısını bildirir; klip sayısı sabit değildir. | Plan ekranı sahne ve klip adetlerini ayırır; her dallı yolun planlanan toplamını, hedefe farkını ayrı gösterir. Dallar toplanmaz. Bunlar video ölçümü değildir. |
| A/B/C karşılaştırması | Aynı formdaki bütün seçili davranış, yaş, ortam, senaryo düzeni ve ek yönergeyi kullanan kaynak bağlamı deneyi. | Kol/ALL seçin, istek özetini ve kaynak farkını inceleyin, istemleri/çağrı sayısını görün, ayrıca Başlat’a basın. Dar ekranda sonuç özetlerini kaydırarak okuyun. | Her kolun ham cevabı, hata/durum, varsa sağlayıcı ve toplam istek süresi ile girdi/çıktı tokenı. Bilinmeyen ölçüm “Bilinmiyor” kalır; sıfır yalnız ölçülen sıfırdır. Başarılı sonucu seçmek yeni çağrı yapmaz. |
| Stüdyo: **2. İncele** | Üretilen gerçek cevabın okunabilir anlatı ve sahneleri. | Sahne kartlarını açın. Kaynak/ham cevap ayrıntısını gerekirse inceleyip kopyalayın. | İncelenmemiş taslak; “Bu senaryoyla devam et” ile çalışma alanı. |
| Senaryo çalışma alanı | Sonuç inceleme, ayrı JSON içe aktarma, düzenleme ve doğrulama. İkinci üretim formu değildir. | Gelen sonucu açıkça aktarın. Dolu taslakta onay verin veya koruyun. JSON’u düzenleyip Graf oluştur/Doğrula seçin. | Yapısal olarak doğrulanmış graf. İçerik doğruluğu ayrıca insan incelemesi gerektirir. |
| Taslağı kaydet / yeniden aç | Ham cevap ve düzenlenmiş metni ayrı saklama. | Çalışma alanında Taslağı kaydet’i seçin. Sonraki açılışta kayıt yüklenir. | İstek/kimlik/kaynak ve metinler geri gelir; graf yeniden doğrulanır. Çalışan iş yeniden başlatılmaz. |
| Grafı görüntüle | Sahneleri/alternatifleri görsel inceleme. | Kaydırın/yakınlaştırın, Tümünü göster’i kullanın, sahneye dokunup ayrıntısını açın. | Çalışma alanına aynı taslakla dönüş; video oynatma veya içerik onayı değildir. |
| **3. Üretime hazırla** | Aynı istek ve doğrulanmış graf için klip/prompt planı. | Klip ve prompt planı hazırla eylemini açıkça başlatın; sonuçta Klip planını incele’ye geçin. | Mevcut plan ekranında süre, amaç, başlangıç/bitiş, prompt, süreklilik ve ayrı seslendirme yönergeleri. Bu ikinci sağlayıcı çağrısıdır; anlatı seçimi çağrı yapmaz. |
| Klip planı / export | Dış üretim için tam plan. | Sahne ve klip kartlarını açın. Tek prompt, bütün promptlar, plan JSON’u veya kaynak paketini kopyalayın. | Dış araçta kullanılacak metinler. JSON/kaynak paketinde oturum anahtarı bulunmaz. |
| Hazır D01 grafı / klip planı | Sabit elle hazırlanmış örnek. | Stüdyo’daki hazır D01 girişlerini açın. | Örnek graf ve ayrı plan; yeni senaryo sonuçlarından bağımsızdır. |
| Hazır D01 video eşleme | Sabit örneğin kliplerine cihazdan video bağlama. | Plan kartında Video seç; dosyayı değiştir veya bağlantıyı kaldır. | Uygulama belge dizinindeki kopya ve göreli yol eşlemesi. Galeri kaynağı silinmez. |
| Tek klip önizleme | Bağlanan uygulama kopyasını izleme. | Videoyu izle’yi seçip ayrıca oynatın; duraklat/başa dön kullanın. | İncelenmemiş video; açılabilmesi süreklilik/olay doğrulaması değildir. |
| D01 videolu örnek / Grafı dene | Hazır klipleri graf sırasıyla oynatma. | Başlat’a basın, ayrımda devamı seçin. Bitişte seçtiğiniz yolu tekrar oynatın veya yeniden seçimle başlatın. | Tamamlanmış seçili yolun oturum içi tekrarı. MP4 birleştirme veya boşluksuz geçiş garantisi yoktur. |
| Admin ve çevrimdışı şablon | Eski şablon, tür/süre ayarları, ayrıntılı prompt/kopyalama/export ve ölçülmedi doğrulama kartı. | Stüdyo başlığına beş kez dokunun. Yerel motorla şablon araçlarını kullanın. | Hazır şablon; yerel LLM çıkarımı değildir. Gizli giriş kimlik doğrulaması değildir. Eski klinik/norm metinleri gerçek ölçüm değildir. |
| Sunucu/oturum ayarı | Uygulamanın sunucu adresi ve geçici ekip erişimi. | Uygulama varsayılan sunucu adresini kullanır. Yalnız farklı bir sunucu kullanmanız gerekiyorsa Stüdyo → **Gelişmiş bağlantı ayarları** bölümünden adresi kaydedin; gerekiyorsa ekip anahtarını oturum alanına girin. | Adres `custom_server_base_url` tercihi olarak saklanır; tanınan eski emülatör/tünel adresleri bir defa yeni varsayılana taşınır, diğer özel adresler korunur. `SCENARIO_SERVER_URL` derleme sırasında varsayılanı belirleyebilir. Health yalnız sunucu yanıtını gösterir. Ekip anahtarı yalnız bellekte kalır. |
| Kurum bilgi listesi | Mevcut kurum/bağlantı bilgilerine bakma. | Bilgiyi inceleyip mevcut bağlantının hedefini kontrol edin. | Klinik onay, yetkilendirme veya en iyi kurum sıralaması değildir; güncellik ayrıca doğrulanmalıdır. |

## Yeni kısa videolu örnekler

Menü yolu: **Simülasyon ve Eğitim → Stüdyo → Hazır örnekler ve diğer araçlar**. Eski **Hazır D01 örneği: videolu dallı oynatma** girişi korunmuştur. Yanındaki **D01 örneği: İsme yönelme** ve **D02 örneği: İşaret yönü** girişleri aynı graf tabanlı oynatıcıyı açar. Video ilk kez kullanılırken paket içindeki dosyalar uygulamanın mevcut yerel video deposuna kopyalanır; kaynak dosyalar değiştirilmez. Var olan eşlemeler kullanılır, eksik kayıtlı kopya sessizce başka videoyla değiştirilmez.

Yeni D01/D02 graf örneklerindeki `ageMonths: 36`, kurmaca karakter için hazırlanmış graf metadata değeridir; videodan yaş doğrulanmamıştır. D01’de baş/bakış yönelmesi göz temasından ve tüm bedenin dönmesinden ayrıdır; varsa sesli yanıt da ayrı olay olarak ele alınır.

| Örnek / yol | Klip sırası (dosya adındaki zaman damgası) |
|---|---|
| D01 ortak başlangıç | `20261024200425.mp4` |
| D01 — Anne yönüne dönme | `20261024200833.mp4` → `20261024204922.mp4` |
| D01 — Oyuna devam | `20261024201633.mp4` → `20261024202154.mp4` |
| D01 — Başka yöne dönme | `20261024202847.mp4` → `20261024203806.mp4` |
| D02 ortak başlangıç | `20261024214654.mp4` |
| D02 — Raf yönüne dönme | `20261024220131.mp4` → `20261024225140.mp4` |
| D02 — Masaya bakmayı sürdürme | `20261024222918.mp4` → `20261024224133.mp4` |

Başlat’a dokununca ortak klip oynar. Gerçek video bitişinden sonra bir alternatif seçilir; o dalın iki klibi sırayla oynar ve ikinci klipten sonra tekrar seçim istenmez. Yol tamamlanınca **Seçtiğim yolu tekrar oynat** aynı başlangıç ve seçilmiş dalı kullanır. Dosya adına göre sıra/olay çıkarılmaz; yukarıdaki eşleme ve graf verisi kullanılır. Bunlar insan incelemesiyle hazırlanmış kısa sentetik oynatma örnekleridir, otomatik analiz sonucu değildir ve 2–3 dakikalık tamamlanmış senaryo değildir. Kesin tepki zamanı, tam gözlem penceresi veya klipler arası içerik/süreklilik doğrulanmış değildir. D02’de **Raf yönüne dönme**, doğru nesneye bakışın doğrulandığı anlamına gelmez.

## A/B/C kaynakları ve sonuçları

- **A:** Ek kart metni yoktur; ortak görev ve güvenlik talimatları ile seçili davranış adları korunur.
- **B:** Ortak kart kuralları ve seçilen **bütün** davranış kartlarının metni kullanılır.
- **C:** Kanonik davranış kartı Markdown dosyasının tüm içeriği kullanılır.

Üç kol aynı istek, görev, anlatı sözleşmesi, model ve ayarları kullanır; yalnız kaynak bağlamının miktarı değişir. Sabit istek özeti bütün davranışları, yaş ve senaryo düzenini gösterir.

Bu kurallı kaynak seçimidir; embedding/vector arama diye sunulmaz.
Model/istem/şema/ayar/kaynak değişirse önizleme yenilenir. Protokol v3’tür;
eski protokol yeni karşılaştırmaya sessizce katılmaz. Eski tek davranışlı v2
kaydı okunabilir; çoklu/26 düzeni olarak yeniden etiketlenmez.
Başarısız kollar gizlenmez. Ölçüm yoksa bilinmiyor kalır; sıfır olduğu varsayılmaz.
Üretim, JSON doğrulama ve metinsel uyum gerçek videoda başarı kanıtı değildir.

## Kısa baştan sona örnek

1. Stüdyo’da Sunucu motorunu seçin. D01 ve gerekiyorsa D02’yi seçin;
   31 ay ve “Evde oyuncaklarla oyun; çağıran yetişkin kamera kadrajında” bağlamını girin.
   Kart koşulları çelişiyorsa ek yönergeyle geçersiz kılmayın; üretilen taslağı inceleyin.
2. Alternatifli anlatıyı veya 26 sahnelik doğrusal düzeni seçin. Normal üretimi
   **ya da** aynı formdan A/B/C karşılaştırmasını açıkça başlatın.
3. Gerçek cevabı inceleyin; uygun sonuçta **Bu senaryoyla devam et** seçin.
   Bu seçim çağrı yapmaz. Çalışma alanında aktarımı onaylayın; ham cevap ayrı kalır.
4. Metni gerekiyorsa düzenleyin, taslağı kaydedin, grafı oluşturup inceleyin.
   Aynı sonuç aynı scenarioId’yi korur; başka bir üretim farklı kimlik alır.
5. Klip/prompt planını ayrıca isteyin. Her sahnenin kliplerini, çağrı sayısını,
   kart ilişkilerini, süre hedeflerini, başlangıç/bitişleri ve ayrı seslendirmeyi kontrol edin.
6. Plan/prompt/kaynak paketini kopyalayıp videoları **dış araçta** üretin.
   **Burada güncel bağlantı sınırı vardır:** yeni genel plan için video eşleme/oynatma
   henüz bağlı değildir. Yeni planı hazır D01 videolarına bağlanmış saymayın.
   Video eşleme/oynatmayı bugün ayrı hazır D01 örneğinde deneyebilirsiniz.

Süre örneği: 210 saniye bir hedef, klip başına 8 saniye ise zorunlu üst sınırdır.
26 sahneye birer klip verildiğinde 26 klibin üst sınırı 208 saniye olur; hedefe
ulaşmak için en az 27 klip gerekir ve bazı sahnelerde birden fazla klip planlanabilir.
Plan ekranı her izlenebilir dalı ayrı toplar. Örneğin bir yol 202 saniyeyse hedefe
farkı −8 saniyedir; başka dalların süresi buna eklenmez. Bu hesaplanan plan süresidir,
üretilmiş videonun gerçek süresi değildir.

## Veri, iptal ve bilinen sınırlar

- Ekrandan kazara çıkışta taslak koruması vardır; cihazdaki kalıcılık için açık
  **Taslağı kaydet** gerekir. Kaydedilmemiş Stüdyo formu otomatik kurtarılmaz.
- Senaryo içeriği ve hazır graf editörleri ayrı tutulur. Ham cevap, düzenlenmiş
  JSON ve kaynak kimliği birbirine karıştırılmaz. Dolu taslağa aktarım onay ister.
- Klip planı mevcut oturumdadır; plan JSON’u ve kaynak paketini dışa aktarın.
  Senaryo taslağı kaydı üretilmiş planı veya çalışan işi yeniden yüklemez.
- Mobil ve backend aynı güncel sözleşmeyle çalışmalıdır. Eski çalışan backend
  yeni istemciye uygun yanıt vermeyebilir; protokol uyuşmazlığı açık hata verir.
- İptal yerel beklemeyi durdurur; sunucudaki model işinin gerçekten iptal edildiği
  doğrulanmış sayılmaz. Ücret/kota kullanımı sürebilir. Otomatik tekrar yoktur.
- D01 pilot gözlem süresi klinik tepki eşiği değildir. Kliplerde hesaplanan süre,
  gerçek videonun kesintisiz gözlem veya doğru hedefe yönelme kanıtı değildir.
- Kartlar seçilebilir; her yaş/davranış için doğrulanmış üretim/analiz desteği
  bulunduğu anlamına gelmez. Çıktının anlamsal incelemesi proje ekibindedir.
- Gerçek video/ses üretimi, genel yeni plan-video eşlemesi, doğrulanmış gerçek
  video analizi ve gerçek telefon/iOS kabulü bu mobil hazırlıkla tamamlanmış olmaz.
- Backend deployment erişim/boyut/kapasite/timeout korumaları internet dağıtımı
  tamamlandı demek değildir. Sunucu dağıtımı ve HTTPS ayrıca hazırlanmalıdır.

**Kanıt:** Kullanıcı bu turdan önce 309 mobil test, 79 backend testi ve temiz analiz
bildirdi. Bu rehberle birlikte yapılan yeni değişikliklerin testleri bu turda çalıştırılmadı.
