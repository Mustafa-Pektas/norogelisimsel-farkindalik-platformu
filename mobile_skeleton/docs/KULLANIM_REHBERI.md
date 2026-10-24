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
| Süreklilik | Karakter, yaş, kıyafet, ortam, nesne, kamera ve klip başlangıç/bitişlerinin tutarlılığı. Üretim istemi genel süreklilik ister; sabit açı ile D02 nesne/konum/hedef eşleşmesi otomatik olarak güvence altında değildir ve insan incelemesi gerekir. Gerçek videoda ayrıca kontrol edilir. |
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
| A/B/C karşılaştırması | Aynı formun kaynak bağlamı deneyi. | Kol/ALL seçin, istemleri inceleyin, çağrı sayısını görün, ayrıca Başlat’a basın. | Her kolun ham cevabı, hata/durum, varsa süre/token bilgisi. Başarılı sonucu seçmek yeni çağrı yapmaz. |
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
| Sunucu/oturum ayarı | Adres ve geçici ekip erişimi. | Sunucu motorundaki ayarı kullanın; gerekiyorsa ekip anahtarını girin, iş bitince temizleyin. | Adresin bulunması model erişiminin kanıtı değildir. Anahtar yalnız bellekte tutulur; internette gerçek anahtar için HTTPS gerekir. |
| Kurum bilgi listesi | Mevcut kurum/bağlantı bilgilerine bakma. | Bilgiyi inceleyip mevcut bağlantının hedefini kontrol edin. | Klinik onay, yetkilendirme veya en iyi kurum sıralaması değildir; güncellik ayrıca doğrulanmalıdır. |

## A/B/C kaynakları ve sonuçları

- **A:** Aynı temel görev ve davranış adları; ilave kart metni yok.
- **B:** Ortak kurallar ve seçilen **bütün** kartların tam metni.
- **C:** Kanonik kart Markdown’ının tamamı.

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
