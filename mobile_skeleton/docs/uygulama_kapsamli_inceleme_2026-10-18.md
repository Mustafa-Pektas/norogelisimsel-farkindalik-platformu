# Mobil uygulama — kapsamlı içerik, akış ve kullanılabilirlik incelemesi

18 Ekim 2026 · Salt okunur kaynak incelemesi · Dal: `mertcan/senaryo-grafi`

## A. Kısa durum özeti ve korunacak parçalar

### Başlangıç ve inceleme yöntemi

- Depo: `mobil_uygulama`; uygulama: `mobile_skeleton` (depoya göreli yollar kullanılır).
- Son commit: `572748fe12f355f987fc5b20d8072b9e6d123096` — `feat: senaryo girdisi, graf dönüştürücü ve ortak içe aktarma ekranı`.
- Uygulanabilir üst klasörler ve depo içindeki aramada `AGENTS.md` bulunmadı.
- Başlangıçta değişmiş yedi üretilmiş dosya vardı: `linux/flutter/generated_plugin_registrant.cc`, `generated_plugin_registrant.h`, `generated_plugins.cmake`; `macos/Flutter/GeneratedPluginRegistrant.swift`; aynı üç `windows/flutter/` dosyası. Bunlara dokunulmadı.
- Takip edilmeyen `docs/demo_2026-10-18/` klasörü korundu. İçindeki `model_ham_cevap.txt` inceleme sırasında **0 bayttı**; dolu cevap arşivi veya kurtarma kanıtı sayılmadı.
- `stash@{0}` kimliği `d2788869691dad482216f8a6f6abea8b9641578d`; stash uygulanmadı, silinmedi veya değiştirilmedi. Başlangıçta staged değişiklik yoktu.
- Kod, yapılandırma, asset, ham kayıt ve önceki belgeler değiştirilmedi. Bu incelemenin tek yeni dosyası bu rapordur. Uygulama/emülatör, test, model, çıkarım, indirme veya derleme başlatılmadı; commit/push yapılmadı.
- Önceki incelemenin aynı commit'e ait bulguları başlangıç alındı. Git durumu ile kaynakların değişmediği doğrulandı; davranış kartları, eksik ekran/kontrol ayrıntıları, iOS izin hazırlığı ve erişilebilirlik kodu ayrıca incelendi. Model kayıtları için yeni ADB taraması yapılmadı.

İnceleme üç aşamada yürütüldü: (1) kaynak ve güncel davranış eşlemesi; (2) ekran, veri akışı, kullanım ve hata incelemesi; (3) kanıt ayrımı, öncelik ve bu rapor. Her aşamada kullanıcıya kısa ilerleme özeti verildi. Bölüm sonundaki kaynak dizininde `Kxx` dayanakları dosyalara bağlanır; bunlar aşağıdaki fonksiyon adlarıyla birlikte okunmalıdır.

### Kaynak önceliği ve çelişkiler

| Öncelik | Kaynak | Bu raporda kullanımı |
|---|---|---|
| 1 | [Davranis_Kartlari_v02.md](../../../belgeler/Davranis_Kartlari_v02.md), sürüm 0.2, 11 Ekim 2026 | Güncel 10 görev, fırsat koşulları, dört sonuç durumu ve pilot pencereleri. Dosyanın tamamı okundu. Klinik doğruluğu bu incelemeyle onaylanmadı. |
| 2 | Güncel kod, `pubspec.yaml`, platform yapılandırmaları ve asset'ler | Gerçekte çağrılan yollar, metinler ve saklama davranışı. |
| 3 | Mevcut test kaynakları | Hangi beklentilerin hazır olduğu; bu görevde geçtikleri iddia edilmez. |
| 4 | [Kayıt temelli model raporu](model_degerlendirme_kanitlari.md) | Önceden incelenmiş altışar Qwen/MiniCPM kaydı ve Llama ham kayıt eksikliği. Bugün aynı kayıtlar tekrar okunmuş gibi anlatılmaz. |
| 5 | [Devam notu](DEVAM_NOTU.md) ve eski çalışma notları | Kullanıcı emülatör gözlemleri ve tarihsel durum. Güncel kodun yerine geçmez. |

Önemli düzeltmeler: Önceki salt okunur değerlendirmedeki eksik asset'lerin yeni derlemeyi kesin durdurabileceği vurgusu bu raporda kullanılmıyor. Kullanıcı, bu uyarılarla önceki test/derlemelerin tamamlandığını bildirdi; burada yalnız dosya/bildirim uyuşmazlığı doğrulandı. Model cevabının ekran kapatılınca kaybolması ise yalnız olası risk değildir: **kullanıcı tarafından yaşandığı bildirilen veri kaybıdır** ve kod bunu açıklıyor. Eski notlardaki MiniCPM çıkarımı henüz denenmedi ifadesi, daha yeni kayıt temelli raporun yerine kullanılmadı.

### Bugünkü gerçek durum

```text
Mevcut Qwen dosyası
  → gerçek yerel çıkarım → ham cevap
  → yalnız dış biçim normalizasyonu + uygulama metadata'sı
  → ScenarioInput yapısal doğrulaması
  → tek dallanma düzeyli ScenarioGraph → görüntüleyici
                                               [burada durur]

Elle hazırlanmış sabit D01 grafı + ayrı sabit klip planı
  → üretim promptunu kopyalama → dış araçta üretim [uygulama dışı]
  → galeriden video bağlama → uygulama kopyası + yerel eşleme
  → tek klip önizlemesi / kullanıcı seçimli dallı oynatma
```

İki zincir arasında yeni grafa ait klip planı/prompt üretimi ve o plana video bağlama bağlantısı yoktur. Aynı ekrandan erişilmeleri birleşmiş veri akışı anlamına gelmez. Eski şablon senaryo üretimi ve altı denemelik model değerlendirmesi de bu zincirlerin dışında kalır.

### Korunacak çalışan yapı

Buradaki çalışan sözcüğü, kodda mevcut ve ilgili kanıtı ayrılmış yapıyı belirtir; bu oturumda çalıştırıldığı anlamına gelmez.

| Parça | Korunacak davranış ve sınır | Kanıt/dayanak |
|---|---|---|
| Yerel model motoru | Mevcut dosya, CPU, temiz tek kullanıcı mesajı; hata halinde başka modele/şablona geçiş yok. | K05/K06; geçmiş emülatör gözlemi ve kayıt raporu ayrıca mevcut. |
| Girdi/dönüştürücü | İçerik alanları ile sahne/kenar kimlikleri ayrılmış. Metinler korunarak tek düzeyli graf oluşturuluyor. | K07/K08; dönüştürücü test kaynakları. |
| Ortak içe aktarma | Senaryo içeriği ve hazır graf iki seçim olarak aynı ekranda. Geçersiz içerik tamamlanmıyor. | K09; ortak ekran testleri. |
| Ham cevap/kaynak ayrımı | Ham cevap ayrı; editördeki kopya ve kullanıcı düzenlemesi ayrılıyor. Kaynak beyanının doğrulama olmadığı yazıyor. | K06/K09; demo testleri. |
| Graf görüntüleyici | Asset veya dışarıdan nesne kabul ediyor; kısa kutular, ayrıntı paneli, yakınlaştırma ve tümünü göster kontrolü var. | K10; kontrollü widget testleri. |
| Sabit D01 planı | Klip başına en fazla 8 saniye, sahne sırası, ortak sahne ve ayrı alternatifler; üretim/gözlem ayrımı açık. | K11/K12/K13; model kontrolleri. |
| Yerel video deposu | Kaynağı silmeden kopyalama, göreli yollar, hata halinde eski eşleme, plan/klip kimliğiyle kayıt. | K14; gerçek geçici dosya kontrolleri ve kullanıcı emülatör bildirimi. |
| Önizleme ve graf oynatma | Otomatik başlamayan önizleme; Başlat ile başlayan graf, gerçek video bitişiyle ilerleme, eksikte durma, çift olay koruması. | K15/K16; kontrollü oynatıcı testleri ve kullanıcı A/B yolu bildirimi. |
| Seçilen videonun sonuç güvenliği | Kullanıcı videosuna sabit örnek bulgular aktarılmıyor; tam ekran da boş bulgu listesi alıyor. | K17/K18; kaynak gösterimi testleri. |

Senaryo içeriğinin D01'e uygunluğu, video içeriği/sürekliliği ve Galaxy M21/iPhone 11 performansı bunlardan çıkarılamaz. Dönüştürücü serbest metin yorumlayıcısı veya sınırsız dallanma sistemi değildir.

## B. Güncel 10 davranışın uygulamayla eşlemesi

### Ortak karşılaştırma kuralları

Karttan çıkarılan sonuç sözlüğü: **gözlendi / gözlenmedi / belirsiz / değerlendirilemedi**. Bunlar eski `tipik / gecikmeli / atipik` ve risk renkleriyle eşdeğer değildir. Gecikmeli, belirsiz anlamına gelmez. Geçersiz fırsata gözlenmedi verilmez; açık yanıt kısa kayıtta saklanabilir, ancak tam pencere olmadan gözlenmedi denemez.

Kartın ilk pilotunda D01, D02, D06, D07 ve D08 için ipucu/model bitişinden sonra 10 saniye; D03, D04, D05, D09 ve D10 için koşullar hazırlandıktan sonra 20 saniye fırsat tanımlıdır. Bunlar mühendislik pencereleridir; klinik eşik değildir. Pilot 30–36 ay; nihai kapsam 12–36 ay olup görev uyarlaması gerektirir. Uygulamadaki eski yaş normları bu kartın onaylı karşılığı sayılmaz.

İpucu/model sırasında başlayan yanıtlar da saklanır; çağrı bitmeden başlayan D01 yanıtı ayrıca belirtilir. Böyle bir zaman ilişkisi sessizce düzeltilmez veya sırf erken başladığı için belirsiz diye sınıflandırılmaz.

Ana panel bütün eski `ScenariosRepository.allScenarios` listesini gösteriyor; `minAgeMonths/maxAgeMonths` ile listeyi süzmüyor. Ana yaş grupları 12–18 / 18–24 / 24–36; Stüdyo etiketi ayrıca 24–30 / 30–36 ayrımı yaparken şablonun dal seçimi yine üç eski grubu kullanıyor. Güncel dört sonuçlu video değerlendirme modeli uygulamaya bağlanmış değil (F01/F02).

| Güncel kod/ad ve kartın belirleyici koşulu | Uygulamadaki gerçek karşılık | Görev koşulu, yaş ve pencere farkları | Durum | Dosya/fonksiyon dayanağı |
|---|---|---|---|---|
| **D01 İsme tepki verme.** Doğal sesle tek çağrı; çağrı öncesinde yetişkine dönük olmama; temas/el sallama/ek yönerge yok. Baş yönelme, sesli yanıt ve duraklama ayrılır. Gecikme referansı çağrı bitişi; 10 saniye pencere. | Eski ONT-01; ayrıca gerçek D01 Llama/Qwen istemleri, yeni senaryo demosu, elle hazırlanmış graf/girdi/klip planı. | Eski kart 1–3 çağrı, >3 sn risk ve yaw eşikleri; şablon ikinci çağrıyı 2 sn sonra istiyor ve uyaran/yanıtı ayrı kliplerle planlıyor. Yeni D01 taslakları tek çağrı ve temassızlık bakımından daha uygun; ilk otomatik baş yönelme alt kapsamıyla sınırlı. Sabit plan çağrıyı dalın ilk klibinde, model içerik sözleşmesi ortak başlangıçta tutuyor; bunlar aynı üretim sınırı değil. Plan 10 saniyeyi videodan doğrulatıyor; LLM JSON'u bunu otomatik sağlamıyor. | **Uyumlu:** yeni taslakların açık D01 koşulları. **Eski:** ONT-01 ve şablon. **Belirsiz:** gerçek üretilen içeriğin uygunluğu ve gözlem penceresi. | K02 ONT-01; K04 `_generateScenario`; K06 `d01GraphDemo`, `d01TurkishPrompt`; K12; K17 `_clinicalCases`. |
| **D02 Yetişkinin işaret ettiği hedefe yönelme.** İki sabit nesne; yalnız Bak, hedefin adı söylenmez; el/hedef/baş görünür; başlangıçta hedefe bakmama; 10 saniye. | Eski ONT-02 ortak dikkat; yeni D02 graf/plan veya yerel LLM görevi yok. | Eski yönerge Bak ayıya/tavşana, şablon Ali bak balona diyor: hem ad hem hedef adı ekleniyor. İki sabit hedef ayrımı açık kurulmamış; yetişkine geri bakma/tebessüm eski tipik dalda ek koşul. Baş yönü ile gerçek bakış hedefi ayrımı ve dört sonuç yok. | **Eski / eksik.** Adı benzer, koşullar eşdeğer değil. | K02 ONT-02; K03 `_cleanCriteria`; K04 davranış seçimi; K20 `_getPhasesForCode` ONT-02. |
| **D03 İstemek için işaret etme.** İlgilenilen güvenli oyuncak görünür ve erişilemez; yetişkin bekler; işaret et komutu yok; göz teması zorunlu değil; 20 saniye. | En yakın aday ONT-05 İstek Bildirme. ONT-04 paylaşmak için deklaratif işarettir, bu karta eşlenmez. | ONT-05 el uzatma, ses ve göz temasını birlikte yorumluyor; Δt ≤5 sn ve yaş/risk dalları içeriyor. Gerçek parmak işareti, ilgisizlik/geçersiz fırsat, başka isteme biçimi ayrımı kartla aynı değil. D03 sürümlü görev/plan/LLM istemi yok. | **Eski / eksik.** ONT-05 yalnız içerik adayıdır; otomatik kimlik eşlemesi yapılamaz. | K02 ONT-04/05; K03 `_cleanCriteria`; K20 genel şablon dalı. |
| **D04 Hayali oyun.** Bebek ve boş fincan; yetişkin model/yönerge vermez; içirme dizisi rastlantısal temastan ayrılır; 20 saniye. | Güncel görev karşılığı bulunamadı. Genel oyun/kule/araba sahneleri bu görev değil. | Bebek–fincan eylemi, kendiliğinden koşul, model desteği ayrımı ve D04 pencere/ölçü alanları yok. İncelenen aktif katalog ve üretim yollarında bu göreve ait içerik bulunmadı. | **Eksik.** Genel oyun adıyla doldurulmadı. | K02 katalog; K20 `_buildClinicalPhases` ve `_getPhasesForCode`; K06 istemler; K12 yalnız D01 asset'leri. |
| **D05 Paylaşmak için elindeki nesneyi gösterme.** Nesne elde; yetişkin erişilebilir; Bana göster/ver yok; yardım bağlamı baskın değil; bırakma/göz teması şart değil; 20 saniye. | ONT-08 Nesne Getirme yakın adayı. ONT-03 bakış paylaşımı ve ONT-04 deklaratif işaret bu görevin karşılığı değil. | ONT-08 açık kollarla Bana getir diyor ve yaklaşma/teslim/göz teması ölçüyor; bunlar kendiliğinden eldeki nesneyi gösterme değil. Ayrıntı ekranı ONT-08'i gösterme diye sadeleştirerek görev farkını örtüyor. Daha somut hata: şablon ONT-08 için nesne getirme yerine ONT-07 ile aynı ce-e sahnesini üretiyor (F02). | **Eski / eksik; şablonda yanlış görev.** | K02 ONT-08; K03 `_cleanCriteria` ONT-08; K20 `_getPhasesForCode` ortak ONT-07/08 kolu. |
| **D06 Basit motor hareketi taklit etme.** Çocuk başlangıçta el çırpmaz; yetişkin iki kez çırpıp bekler; iki kişinin elleri görünür; fiziksel yardım yok; 10 saniye. | ONT-11 yaş metninde alkış geçiyor; bu bir taklit görevi değil. ONT-06 yetişkin elini alet olarak kullanmadır; D06 değildir. | Model hareketi başlangıç/bitişi, çocuğun modele erişimi ve aynı temel hareketin üretilmesi için ayrı görev yok. Bay-bay ve spontan alkış, yetişkinin modelini izleyen taklit diye sayılamaz. | **Eksik.** Sözcük/numara benzerliğiyle eşlenmedi. | K02 ONT-06/11; K03; K20 genel şablon; K06 yalnız D01 istemleri. |
| **D07 Gülümsemeye karşılık verme.** Çocuk yetişkine yönelmiş ve başlangıçta gülümsemiyor; yetişkin doğal gülümser; şaka/gıdıklama/oyuncak gibi ek güçlü uyaran yok; 10 saniye. | ONT-09 Duygulanım Paylaşımı; ONT-07 ce-e. Örnek analizde ONT-06 adı Sosyal Gülümseme olarak kullanılıyor. | Kule başarısı/komik olay veya ce-e sözü/örtü hareketi ek uyaran. Yeni gülümseme başlangıcı ile önceki gülümseme ayrılmıyor; eski Δt ≤2 sn/duygulanım yorumu kartın yerine geçmez. Analizde ONT-06 kodu katalogdaki el aleti göreviyle çakışıyor. | **Eski / eksik / kod anlamı tutarsız.** | K02 ONT-07/09; K20 ONT-07/08; K17 `_clinicalCases`; K03. |
| **D08 Jestsiz tek basamaklı sözel yönerge.** Erişilebilir araba için Arabayı bana ver; işaret, açık el uzatma ve model yok; eylem başlangıcı/tamamlama ayrı; 10 saniye. | ONT-10 Yönerge Takibi en yakın aday. ONT-08'in kolları açarak getirtmesi eşdeğer değil. | ONT-10 başlangıç metni jestsiz tek adım; fakat 12–18 yaş dalı jestli, 24–36 dalı al ve kutuya koy şeklinde iki adım. Eski 3.5 sn eşiği/tekrarlanan yönergeler var. Şablon yaş dalıyla bir adımlı uyaranı farklı görev yanıtıyla eşleyebilir. Tam teslim/eksik kayıt kuralları yapılandırılmış değil. | **Kısmen benzer eski görev / eksik güncel koşul.** | K02 ONT-10; K03 `_cleanCriteria`; K20 genel dal/yaş seçimi. |
| **D09 Nesneyi bir kaba yerleştirme.** Büyük blok, uygun geniş kutu; model/koy yönergesi yok; el–blok–kutu ilişkisi ve bırakma görünür; 20 saniye. | ONT-10 iki adımlı al ve kutuya koy cümlesinde benzer eylem geçiyor. ONT-06 kilitli kutu yardımı farklı görev. | Açık komutla yerleştirme kendiliğinden D09 değildir. Uygun kutu, etkileşim fırsatı ve kontrollü bırakma/görünür sonuç ayrımı yok. D09 sürümlü senaryo/graf/plan/LLM istemi bulunamadı. | **Eksik.** Eski D09 veya ONT-09 otomatik taşınamaz. | K02 ONT-06/09/10; K20; güncel kart sürüm notu. |
| **D10 Kalemle kendiliğinden karalama.** Çalışan kalın boya ve erişilebilir kâğıt; çiz yönergesi/model/fiziksel yardım yok; harekete bağlı yeni çizgi; 20 saniye. | Güncel görev karşılığı bulunamadı. ONT-10 yönerge takibidir; örnek analizdeki tekrarlayıcı hareket de D10 değildir. | El–kalem–kâğıt ve yeni iz ilişkisi, nokta/karalama ayrımı, destekli koşul ve uygun malzeme bilgisi yok. | **Eksik.** Numara veya eski sallanma/tekrarlama içeriğiyle eşlenmedi. | K02/K17/K20; K06/K12 yalnız D01; güncel kart D10. |

### Eşleme sonucunun sınırı

- D01 dışında güncel kart kimliği/sürümüyle bağlı graf/klip örneği veya yerel üretim istemi bulunmadı. Genel `ScenarioInput` başka `behaviorId` metinlerini taşıyabilir; bu, o kartların uygulandığı anlamına gelmez.
- Eski `ONT-03`, `ONT-04`, `ONT-06`, `ONT-07`, `ONT-09`, `ONT-11`, `ONT-12` ayrı eski kavramlardır; güncel D listesine sayı sırasıyla taşınamaz. D09/D10 için v0.1 içerik de otomatik devredilemez.
- Video yolları bütün bu eski eşlemeleri destekleyen kanıt değildir: tanımlı eski MP4'ler diskte yoktur. Uygulama belge dizinine bağlanan D01 videoları asset yolundan bağımsızdır.
- D01 planında 6 saniye ortak oyun, her alternatifte 8 + 8 + 2 saniyelik klipler bulunur; her yolun hedefi 24 saniyedir. Bu toplam, çağrı sonrası pencereyi otomatik kanıtlamaz. Ayrı üretim parçalarının kesintisiz gözlem olduğu yalnız prompttan çıkarılamaz.

## C. Sekme/ekran/bölüm envanteri ve gereklilik

Hedef kullanıcı sütunu görev sınıfıdır: **N** gündelik kullanım, **H** içerik hazırlama, **T** teknik deney/bakım, **K** ürün kararı henüz açık. Bunlar uygulanmış hesap/rol sistemi değildir. Normal kullanıcının üretim hakkı bu raporla kaldırılmaz. Durumlar kod bağlantısını anlatır; gerçek cihazda bu oturumda denenmişlik anlamına gelmez.

### C1. Ana gezinme ve davranış ayrıntısı

| Sekme/ekran | Bölüm/kontrol | Amaç | Hedef | Gerçek kod yolu | Durum | Gereklilik | Önerilen işlem/gerekçe |
|---|---|---|---|---|---|---|---|
| Ana kabuk | Üç alt sekme | Ana Panel / Video Analiz / Senaryo Stüdyosu | N/H/K | K01 `HomeScreen.build`, `IndexedStack` | Bağlı, ekranlar canlı kalır | Temel gezinme | **Koru/sadeleştir:** mevcut üç alan yeterli; teknik testleri yeni sekmeye dönüştürme. |
| Ana kabuk | Sistem geri: önce ana panel, sonra iki basışla çıkış | Kazara çıkışı azaltma | N | K01 `PopScope` | Bağlı; taslak alt ekranına koruma sağlamaz | Gerekli | **Koru:** model taslağının ayrı kayıp sorunuyla karıştırma. |
| Ana panel | Yaş slider'ı ve üç yaş grubu | Yaş bağlamı seçme | N/H/K | K22 `AgeSliderCard`, K01 `_currentMonth` | 12–36, oturumluk | Gerekli; anlamı içerikle uyumlu olmalı | **Yeniden adlandır:** Gelişimsel Yaş Ayarı yerine Çocuğun yaşı / örnek karakterin yaşı; norm ölçümü izlenimi azaltılır. |
| Ana panel | İki hızlı giriş kartı | Sekmelere kısa yol | N | K01 `_buildModeCard` | Bağlı; otomatik analiz vaadi eski | Gerekli | **Yeniden adlandır:** mevcut yeteneği anlat; F03. Alt sekmeyle aynı görev olması tek başına gereksizlik değil. |
| Ana panel | 12 davranış listesi, Beklenen ve Gözlem Eşiği | Bilgilendirme/ayrıntıya giriş | N/H | K01/K02 | Eski katalog; güncel 10 kart değil | Davranış bilgisi gerekli; bu içerik uygun değil | **Sadeleştir/güncelleme planla:** B tablosuna göre içerik göçü; numarayı değiştirerek eşlenmiş sayma. |
| Ana panel | Anahtar simgesi | Gemini anahtarı kaydetme | T | K22 `ApiKeyDialog.show` → K19 | Ayar kaydı bağlı, yerel demo ile ilgisiz | Bugünkü yerel hedef için gerekmiyor | **Mevcut teknik bölüme taşı:** kullanıcıya yerel üretim şartı gibi görünmesin. |
| Ana panel / Video | Kurumlar düğmesi | Yardım/iletişim bilgisi | N | K22 `InstitutionsScreen` | Sabit liste, arama/arama yapma servisi yok | İkincil bilgi olarak kalabilir | **Yeniden adlandır:** Yetkili iddiası ve güncellik doğrulanmış gibi sunulmasın; iletişimler ayrıca doğrulanmalı. |
| Davranış ayrıntısı | Kod/başlık/yaş/kategori | Hangi örneğin incelendiğini açıklama | N/H | K03 `build` | Eski ONT verisini çizer | Gerekli | **Yeniden adlandır/sadeleştir:** gündelik başlık öne; teknik kod ikincil. |
| Davranış ayrıntısı | Bu Yaşta Ne Beklenir? | Yaşa göre açıklama | N | K03/K02 `ageBreakdowns` | Eski norm iddiası | Güncel, koşullu açıklama gerekli | **Yeniden adlandır/içeriği düzelt:** tek denemeyi norm gibi sunma; F01. |
| Davranış ayrıntısı | Gözlem Eşiği, seviyeler | Risk/gelişim yorumu | N | K03 `scenario.riskThreshold`, renkli dallar | Eski, güncel hedefle çelişir | Bu sınıflama gerekli değil | **Kaldırma adayı:** klinik/risk hükmü; güncel görev koşullarıyla değiştirme ayrı içerik işi. |
| Davranış ayrıntısı | Üç Nasıl Gözlemlenir? bölümü | Hazırlık, yönerge, izlenecek noktalar | N/H | K03 `_cleanInstruction`, `_cleanCriteria` | Bağlı; bazı sadeleştirmeler anlam ekliyor | Görev koşullarını anlatmak gerekli | **Sadeleştir/güncelle:** ham içerikle ayrı friendlyMap çelişmesin; F01/F02. |
| Davranış ayrıntısı | Bu Davranış İçin Senaryo Üret | Stüdyo seçimini aktarma | H/K | K03 → K01 `onNavigateToTab(2, code)` | Eski şablon seçimine gider; Qwen demosuna aktarmaz | Üretim girişi gerekli | **Yeniden adlandır:** bugün şablon yoluna gittiğini belirt; bağlanmadan LLM hakkı/akışı varsayma. |
| Davranış ayrıntısı | Videodan Analiz Et | Video sekmesini açma | N | K03 → K01 `onNavigateToTab(1, code)` | Sekme açılır; seçilen davranış videoya/analize bağlanmaz | Video girişine erişim yararlı | **Yeniden adlandır:** Video aç/izle; analiz çalışıyor iddiasını kaldır. |

### C2. Video sekmesi ve tam ekran

| Sekme/ekran | Bölüm/kontrol | Amaç | Hedef | Gerçek kod yolu | Durum | Gereklilik | Önerilen işlem/gerekçe |
|---|---|---|---|---|---|---|---|
| Video Analiz | Video yükle/değiştir → Galeri/Kamera/Örnek | Yerel video seçme | N/H | K17 `_showVideoSourceSheet`, `_pickVideo`, `_resetToDefaultVideo` | Seçim bağlı; hata/iptal yolları farklı | Gerekli | **Koru/düzelt:** başarısız açılış önceki videoyu kaybettirmesin; F05. Kamera erişimi/iOS hazırlığı ayrıca doğrulanmalı. |
| Video Analiz | Video yüzeyi, kontrolleri gizleme | İzleme alanı | N | K17 `AspectRatio(16/9)`, timer | Bağlı; hata kalıcı spinner'a dönüşebilir | Gerekli | **Sadeleştir/düzelt:** açık hata ve gerçek en-boy oranı; F05/F12. |
| Video / tam ekran | Oynat/duraklat, ±5 sn, zaman, ses, tam ekran | Video gezinme | N | K18 `FloatingVideoControls` | Bağlı; bazı simge adları ve ses state'i eksik | Gerekli | **Koru/erişilebilirliği düzelt:** dar satır, tooltip, ses durumunu denetleyiciden okuma; F10/F12/F13. |
| Video Analiz | Seçtiğiniz video analiz edilmedi | Sonuç kaynağını açıklama | N | K17 `video-not-analyzed` | Seçilen videoda görünür; örnek bulgu çizilmez | Zorunlu doğruluk bilgisi | **Koru:** kısa açıklama yeterli; uzun yeni uyarı gerekmiyor. |
| Video Analiz | Örnek rapor, genel durum, davranış kartları, zaman işaretleri | Sabit rapor tasarımını gösterme | N/T | K17 `_clinicalCases`, K18 `ExpandableFindingCard` | Sabit örnek; otomatik analiz yok | Demo için ikincil | **Sadeleştir:** tek açık örnek bölümü; klinik/risk dili içerik incelemesinden geçmeli. Seçilen videoya taşınmaması korunmalı. |
| Video Analiz | Anahtar simgesi | Gemini ayarı | T | K22 → K19 | Video analizi motoruna bağlanmıyor | Normal izleme için gereksiz | **Tekrarıyla birleştir/mevcut teknik bölüme taşı:** ana paneldeki ayarın ikinci girişi. |
| Tam ekran video | Yatay görüntü, kontrol satırı, tam ekrandan çıkış | Aynı oynatıcıyla izleme | N | K18 `FullscreenVideoScreen` | Aynı denetleyici paylaşılır; çıkış fullscreen simgesidir | Gerekli | **Koru:** standart AppBar geri düğmesi varmış gibi test/UX varsayımı yapma. Yön/ses/erişilebilir adlar görsel kontrol bekler. |

### C3. Stüdyo, model yönetimi ve eski üretim

| Sekme/ekran | Bölüm/kontrol | Amaç | Hedef | Gerçek kod yolu | Durum | Gereklilik | Önerilen işlem/gerekçe |
|---|---|---|---|---|---|---|---|
| Stüdyo | Klinik Senaryo & Simülasyon başlığı | Ekranı tanımlama | N/H/K | K04 `build` | Eski klinik anlatım | Başlık gerekli | **Yeniden adlandır:** Senaryo Stüdyosu; klinik yetkinlik izlenimi azaltılır. |
| Stüdyo | Başlığa beş dokunuş / ADMİN / Kapat | Prompt/teknik seçenek görünürlüğü | H/T | K04 `_handleEasterEggTap`, `_isAdminMode` | Yerel bool; release için de ayrı debug şartı yok | Saklı hareket öğrenilebilir değil | **Sadeleştir:** mevcut bölümde açık İçerik hazırlama/teknik ayrıntılar kontrolü; yetkilendirme olarak adlandırma. Hak sınırı H bölümünde açık karar. |
| Stüdyo AppBar | Senaryoyu kopyala | Şablon metnini dışarı alma | H/K | K04 → K20 `exportDoctorCleanScenario` | Panoya kopyalar; dosya kaydı değil | Gerekli | **Koru/yeniden adlandır:** kaynak ve çıktı aynı şablon olarak kalsın. |
| Stüdyo AppBar, eski admin | Tüm promptları kopyala / JSON dışa aktar | Eski seans üretim verisini alma | H/T | K20 `exportEnglishPromptsOnly`, `exportGroundTruthJson` | Şablon planı; gözlem veya ScenarioInput değil | Teknik üretimde yararlı | **Mevcut hazırlama bölümünde tut/yeniden adlandır:** plan dışa aktarımı; ground truth diye kullanma. |
| Stüdyo | Senaryo Grafı | Sabit D01'i inceleme | N/H | K04 → K10 varsayılan asset | Sabit örnek | Yararlı örnek | **Yeniden adlandır:** D01 örnek akışı; üretilen grafın devamı sanılmasın. |
| Stüdyo, debug | Geliştirici: Klip Üretim Planı | Sabit plan/video alanını açma | H/T | K04 `kDebugMode` → K13 | Debug girişi; yetki sistemi yok | Hazırlama için gerekli | **Koru/amaç belirginleştir:** D01 örnek klip planı; hak yönetimi varsayma. |
| Stüdyo | Llama dosya durumu / indir / iptal / sil | Mevcut model dosyasını yönetme | H/T/K | K04 `_buildLlamaManagementCard` → K05 | Dosya yönetimi bağlı, çıkarım kanıtı değil | Model edinme için gerekli | **Sadeleştir:** indirme durumu ile üretim sonucu ayrı; silme veri kaybı etkisi açık ve kullanıcı işlemiyle. |
| Stüdyo | Llama merhaba / D01 Türkçe / D01 İngilizce | Motor ve dil karşılaştırması | T | K04 üç `LocalLlamaTestService`; K06 | Ayrı gerçek çıkarım test yolları | Teknik kanıt için gerekli | **Mevcut teknik bölümde birleştir:** gündelik senaryo üretimi gibi sunma. |
| Stüdyo | Qwen/MiniCPM seçim, durum, indir/iptal | Karşılaştırma dosyasını seçme | H/T/K | K04 `_comparisonModel`, `_buildComparisonDownloadCard`; K05 | Model seçimi yalnız ilgili karşılaştırmaya etki eder | Gerekli | **Yeniden adlandır:** Değerlendirme modeli; Qwen graf demosunun modeli sanılmasın. |
| Stüdyo | Qwen D01 karşılaştırma | Önceki üç başlıklı D01 istemi | T | K06 `d01Qwen` | Ayrı gerçek test; graf oluşturmaz | Karşılaştırma için gerekli | **Mevcut teknik bölümde tut.** |
| Stüdyo | Qwen — Ortak başlangıç testi | Yalnız iki cümle oyun ortamı | T | K06 `qwenCommonStart` | Güncel istemde yetişkin/çağrı yok | Ayrı dar deney için yararlı | **Yeniden adlandır:** Oyun ortamı testi; adı altı denemelik protokoldeki çağrılı common_start ile karışıyor. İstem/kayıtları sessizce değiştirme. |
| Stüdyo, test kartı altı | D01 değerlendirmesini başlat, durdur, kayıtları kopyala, ham kayıtlar | Sabit üç görev × iki deneme | T | K23 `D01EvaluationService`, protokol asset'i | Disk kayıtlı ayrı test yolu; eski arşiv UI'si yok | Değerlendirme için gerekli | **Mevcut teknik bölümde tut:** tekli oyun testi istemini kullandığı sanılmasın. |
| Bütün model kartları | Gönderilen istem, cevap, süre, token/örnekleme, bitiş ve çıkarım ayrıntıları | Teknik izlenebilirlik | T; ham cevap H/K | K06 `LocalLlamaTestCard` | Bağlı, bazı ayrıntılar açılır | Kanıt gerekli | **Sadeleştir/dağıt:** cevap görünür; motor ayrıntıları kapalı teknik bölümde. Ham cevabı değiştirme veya başarı etiketi ekleme. |
| Stüdyo | Hazır şablon / eski Llama seçeneği | İki eski API yolunu seçme | H/T | K04 `_buildEngineSelectorCard`; K05 `generateWithLlama` | İkisi de aynı şablon servisine gider | Ayrı motor seçimi bugün gerekmiyor | **Tekrarıyla birleştir:** tek Şablon örneği girişi; gerçek testlere dokunma. |
| Stüdyo | Yaş, çoklu davranış, ekle/değiştir/kaldır | Şablon parametreleri | H/K | K04 `_buildDoctorConfigCard`, `_showOntologyPicker` | Eski ONT verisi; Qwen demosuna aktarılmaz | Görev bağlamı gerekli | **Sadeleştir:** yalnız şablona etki ettiği açık olsun; F08/F09. Kart göçü ayrı iş. |
| Stüdyo | Gözlem Durumu: tipik/gecikmeli/atipik | Önceden yanıt varyantı seçme | H | K04 `_buildRiskChip`; K20 | Plan girdisi; gözlenmiş sonuç değil | Alternatif hazırlama gerekli, risk dili gereksiz | **Yeniden adlandır/içerik düzelt:** Planlanan devam; risk sınıflamasını yeni akışa taşımama. |
| Stüdyo | Şablondan senaryo oluştur / yükleniyor / çıktı başlığı | Hazır taslak üretme | H/K | K04 `_generateScenario` | Otomatik init/ayar değişiminde de çalışır; gerçek model değil | Eski örnek için yararlı | **Koru/ikincil yap:** kaynak etiketleri düzeltilmiş; birincil LLM üretimiyle karıştırma. |
| Stüdyo | Adım adım / tek metin, şablon adım kartları | Aynı şablonun iki sunumu | H | K04 `_buildViewModeToggle`, `_buildStepCard`, `_buildUnifiedScenarioCard` | Ortak `_session`, ayrı yeni veri değil | İhtiyaca göre iki görünüm yararlı | **Koru/sadeleştir:** farklı üretim motorları gibi sunma; görünüm değişimi veri kaybı yapmamalı. |
| Stüdyo, eski admin | Toplam seans 180/210/240 sn, klip 3/4/5/6/8/10 sn | Eski plan hedefini ayarlama | H/T | K04 `_buildAdminVideoSlicingCard`; K20 `generateSession` | 10 sn seçilebiliyor; video gerçekten kesilmiyor | Süre ayarı hazırlamada yararlı | **Yeniden adlandır/uyarla:** klip hedefi en fazla 8; toplam süre ayrı; Saniyelik dilimleme ifadesi yanlış eylem çağrıştırıyor. |
| Stüdyo, eski admin | Model doğrulaması yapılmadı kartı | Ölçülmemiş metriği sonuç diye göstermeme | H/T | K04 `_buildModelValidationCard` | Eski sahte yüzdeler kaldırılmış | Doğruluk sınırı gerekli | **Koru/kısa tut:** yeni uzun uyarı eklemek gerekmiyor. |

### C4. Ortak senaryo/graf alanı ve görüntüleyici

| Sekme/ekran | Bölüm/kontrol | Amaç | Hedef | Gerçek kod yolu | Durum | Gereklilik | Önerilen işlem/gerekçe |
|---|---|---|---|---|---|---|---|
| Ortak ekran | Senaryo içeriği / Hazır graf | İçerik sözleşmesini teknik graf JSON'undan ayırma | H/T/K | K09 `_selectType` | Ortak ekran; varsayılan Hazır graf | Gerekli | **Koru/öncelik sırasını düzenle:** hedef için senaryo içeriği öne; hazır graf ileri seçenek olarak kalabilir. |
| Ortak ekran | Qwen ile senaryo taslağı üret / iptal | Sabit D01 içerik istemi | H/K; teknik ayrıntı T | K09 `_modelDemo`; K06 `d01GraphDemo` | Gerçek motor yolu; model yoksa hata, indirme yok | Hedefin ilk adımı | **Koru/girişini sadeleştir:** normal kullanıcının bu işlemi kullanma hakkı henüz kararlaştırılmadı. |
| Ortak ekran | Ham cevap ve motor ayrıntıları | Modelin gerçekte verdiğini koruma | H/T | K06 kart; K09 `_modelChanged` | Bellekte, ayrı görünür | Gerekli | **Koru:** biçim-normalize editörle aynı kayıt sanılmasın; F04. |
| Ortak ekran | JSON metin alanı | İçerik veya hazır graf yapıştırma/düzeltme | H/T | K09 `_json`, `_edited` | Üretimde readOnly; 6–12 satır; kaydırılır | Mevcut teknik demo için gerekli | **Koru/teknik olarak etiketle:** gündelik kullanıcıdan grafik kimliği isteme; yeni form bu tur için önerilmiyor. |
| Ortak ekran | Graf oluştur / Doğrula | Seçilen sözleşmeyi kontrol etme | H/T | K09 `_validate`; K07/K08/K10 | Yapısal doğrulama, içerik onayı değil | Zorunlu | **Koru:** iki veri tipinin kurallarını tek, gevşek okuyucuda eritme. |
| Ortak ekran | Elle hazırlanmış D01 örneğini yükle | Model çalıştırmadan içerik sözleşmesi örneği | H/T | K09 `_loadExample` → tek asset | Açık kullanıcı işlemi; model fallback'i değil | Gerekli örnek | **Koru:** kullanıcı düzenlenmiş taslağı üzerine yükleyerek kaybedebilir; F04 kapsamında ele al. |
| Ortak ekran | Kimlik, alternatif/sahne/bağlantı sayısı, kaynak | Dönüşüm sonucunu özetleme | H/T | K09 summary / `_sourceText` | Metadatalı özet | Gerekli | **Sadeleştir:** yapı geçerli bilgisini koru; anlam doğrulaması gibi gösterme. |
| Ortak ekran | Biçim normalizasyonu ve hata açıklaması | Yalnız dış JSON çiti/sarmalayıcı toleransını anlatma | H/T | K09 `_demoInputJson` | Yalnız demo kökenli taslakta; genel yapıştırma yolu katı | Gerekli | **Koru/kısalt:** hangi işlem yapıldı kısa görünür, ayrıntı açılır olabilir; bozuk JSON onarma ekleme. |
| Ortak ekran | Grafı görüntüle | Doğrulanmış nesneyi açma | H/N/K | K09 `_viewGraph` → K10 | Bağlı; kalıcı kayıt/klip planı yok | Gerekli | **Koru:** sonraki eksik adımı tamamlanmış gibi sunma. |
| Graf | Kısa kutular, başlangıç/bitiş simgeleri, açıklamalı oklar | Alternatif yolları anlama | N/H | K10 `_GraphView`, `_GraphLayout` | Nesne veya D01 asset'i | Temel deneyim | **Koru:** iki satır özet ve tam ayrıntı ayrımı uygun; çok dalın görünürlüğü ayrıca sınanmalı. |
| Graf | Sahneye dokunma / alttan ayrıntı / devam açıklamaları | Tam içeriği okuma | N/H | K10 `_showScene` | Kaydırılabilir panel, açık kapatma | Gerekli | **Koru:** kısa kutu uğruna anlatı kaybolmuyor. |
| Graf | Yakınlaştır/uzaklaştır/sürükle/Tümünü göster | Küçük ekranda inceleme | N/H | K10 `_fit`, `_zoom`, `InteractiveViewer` | Bağlı, ilk sığdırma var | Gerekli | **Koru:** gerçek telefon ve büyük yazıyla görsel doğrulama gerekli. |

### C5. Klip planı, eşleme ve oynatma

| Sekme/ekran | Bölüm/kontrol | Amaç | Hedef | Gerçek kod yolu | Durum | Gereklilik | Önerilen işlem/gerekçe |
|---|---|---|---|---|---|---|---|
| Debug klip planı | El yapımı plan açıklaması / sınırlar / süreklilik açılırları | Taslağı ve süreklilik hedeflerini anlatma | H/T | K13 → K12 | Sabit D01; video kanıtı değil | Gerekli | **Koru/sadeleştir:** kısa özet + ayrıntı; normal kullanıcıya prompt gösterme. |
| Debug klip planı | Ortak sahneler ve alternatif bölümleri | Gereksiz ortak klip çoğaltmadan listeleme | H | K13 `_sections` | İlk ayrımı gösterir; D01'e göre tasarlanmış | Gerekli | **Koru:** genel çok düzeyli planlayıcı gibi sunma; sabit iki dal başlığı genelleme işi ertelenir. |
| Klip ayrıntısı | Süre/eylem/başlangıç/bitiş/tam prompt | Dış üretim hazırlığı | H | K13 `_ClipDetails` | Plan alanlarını tam gösterir | Gerekli | **Koru:** üretim hedefi ve gerçek süre farklıdır. |
| Klip ayrıntısı | Promptu kopyala | Dış platforma aktarma | H | K13 `Clipboard.setData` | Panoya kopyalama; servis entegrasyonu yok | Gerekli | **Koru:** normal graf görünümüne prompt ekleme. |
| Klip ayrıntısı | Video seç / değiştir | Galeriden kopya edinme | H | K13 `_selectVideo` → K14 `attach` | İptal eskiyi korur; kalıcı kopya | Gerekli | **Koru:** kaynak galeri videosu silinmiyor; hata halinde eski eşleme kalmalı. |
| Klip ayrıntısı | Bağlantıyı kaldır | Bu plan/klip ilişkisini kaldırma | H | K13 `_removeVideo` → K14 `remove` | İndeks sonra uygulama kopyası temizlenir | Gerekli | **Koru:** galerideki kaynağı silmediği anlaşılır olmalı. |
| Klip ayrıntısı | Dosya adı / Video bağlı-yok-bulunamadı / İncelenmedi | Dosya ve kanıt durumunu ayırma | H | K13 `_videoControls` | Bağlı; dosya varlığı kontrolü | Zorunlu | **Koru:** dosyanın varlığını içerik doğruluğuna çevirmeme. |
| Klip planı | Eşlemeleri yeniden yükle / Tekrar dene | İndeks veya asset hatasından dönüş | H/T | K13 `_load`, FutureBuilder | Açık hata; senkron setState düzeltmesi mevcut | Gerekli | **Koru:** eski başarısız callback davranışını geri getirme. |
| Klip ayrıntısı | Videoyu izle | Tek kayıtlı kopyayı açma | H/N/K | K13 → K15 | Video bağlıysa görünür | Gerekli | **Koru:** süre/içerik onayı sayılmaz. |
| Önizleme | Oynat/duraklat/başa dön, oran ve hata | Tek klibi inceleme | H/N/K | K15 `_initialize`, `_control`, `_release` | Otomatik başlamaz, oran korunur | Gerekli | **Koru:** graf akışıyla aynı oynatıcı sayılmaz; hata/kapanış kontrolleri korunmalı. |
| Klip planı, debug | Grafı dene | Sabit plan/eşlemelerle deneyim | H/T/N-K | K13 → K16 | Sabit D01 zinciri | Gerekli demo | **Yeniden adlandır:** D01 videolarını dene; yeni grafla bağlandığı sanılmasın. |
| Klip planı, debug | Senaryo / graf içe aktar | Yeni model/içe aktarma demosuna geçme | H/T/K | K13 → K09 | Başka akışa giriş | Gerekli ama konumu ters | **Mevcut girişe taşı:** hedefte senaryo önce; veri bağlantısı ayrıca eksik kalır (F06). |
| Grafı dene | Başlat, oynat/duraklat | Kullanıcı onayıyla ilk video | N/H | K16 `start`, `togglePlayback` | Gerçek bitiş olaylarıyla ilerler | Temel deneyim | **Koru:** hedef süreyle zamanlayıcı ekleme. |
| Grafı dene | Kısa dal düğmeleri / Geçiş ayrıntıları | İki alternatiften birini seçme | N/H | K16 `_choiceLabel`, `_choice`, `choose` | label → hedef başlığı → açıklama | Gerekli | **Koru:** uzun açıklama düğmeye dolmuyor, seçimi kullanıcı yapıyor. |
| Grafı dene | Tamamlandı / Baştan başlat / sahne-klip hatası | Sonu ve eksik dosyayı açıklama | N/H | K16 `_advance`, `restart`, `_fail` | Bitiş bağlı; yol kaydı/tek dosya yok | Gerekli | **Koru/düzelt:** kapanış hatasındaki restart F11; Tamamlandı içerik doğrulaması anlamına gelmez. |

### C6. Gezinmede bulunmayan veya paylaşılan eski parçalar

| Ekran/parça | Amaç ve hedef | Referans durumu / gerçek yol | Gereklilik ve önerilen işlem |
|---|---|---|---|
| `SimulationModeScreen` | Eski klinik FSM, RAG üretimi, ortam/eşya alanları; T | Normal `lib` gezinmesinde kurucu çağrısı yok; testten çağrılıyor. K19 → `LlmRagService`. | **Sonraya bırak.** Güncel yol değildir; silmek testleri ve eski demo erişimini etkileyebilir. |
| `InteractivePlayerScreen` | Eski kök/üç renkli video dalı; T | Normal ekrana kurucu çağrısı bulunmadı. **Dosyadaki `SimulationState` enum'u aktif `FullscreenVideoScreen` tarafından kullanılıyor.** | **Sonraya bırak.** Dosyanın tamamı kullanılmıyor denemez; toplu silme önerilmez. |
| `ScenarioPickerSheet` | Eski davranış seçimi; T | Yukarıdaki iki eski ekran çağırıyor; etkin katalogda ayrı Stüdyo seçicisi de var. | **Birleştirme adayı**, yalnız eski ekranların geleceği netleşince; görev benzerliği doğrudan eşdeğer davranış değildir. |
| `FloatingDecisionCard` | Eski üç renkli karar kartı; T | Sınıf tanımı bulundu; `lib` içindeki kurucu kullanımına rastlanmadı. | **Kaldırma adayı**, referans taraması/derleme ve geri dönüş değerlendirilmeden silinmez. |
| `AnalysisReport` | Eski rapor veri sınıfı | Tanımı var; aktif oluşturma/tüketim çağrısı bulunmadı. Aynı dosyada kullanılan `BehaviorFinding` ve `HealthCenter` var. | **Sonraya bırak.** Dosyanın bütünü gereksiz değildir. |
| `formatLlamaPrompt`, `getDownloadedSizeBytes` | Eski yardımcılar | K05'te tanımlı; aktif çağrı bulunmadı. Gerçek runtime ham mesajı kendisi şablonluyor. | **Kaldırma adayı**, bugünkü hedef için zorunlu temizlik değil. |
| `generateDoctorScenarioWithLlama` | Eski doktor şablonu API'si | Uygulamadan çağrı bulunmadı, kaynak gösterimi testinden çağrılıyor; içeride şablon servisi kullanıyor. | **Koru/sonraya bırak:** adı eski olsa da test edilmiş API yüzeyini bu turda kaldırma. |

Ekran sayısı veya dosya uzunluğu refactor gerekçesi yapılmadı. Girdi, graf ve plan doğrulamaları benzer yardımcılar kullansa da farklı referansları/kuralları denetler; bunları sırf benzedikleri için tekleştirmek doğru değildir.

## D. Gerçek veri akışı ve kopuk bağlantılar

### D1. Girdi, çıktı, kimlik, saklama ve sonraki adım

| Adım / bağlantı durumu | Girdi → çıktı | Gerçek çağrı | Kimlik ve saklama | Sonraki adıma bağlantı / sınır |
|---|---|---|---|---|
| **Model seçimi — ayrı test yolu** | Llama varsayılanı veya Qwen/MiniCPM karşılaştırma seçimi → dosya seçeneği | K04 `_comparisonModel`; K05 `LocalModelOption` | Depo/dosya kimliği enum'da; seçici state'i bellekte | Seçim indirme başlatmaz. Değerlendirmeyi değiştirir; graf demosu daima Qwen. |
| **İndirme — bağlı** | Kullanıcı indir eylemi → `.part` → GGUF dosyası | K05 `downloadModel`, `getModelFile` | Belge dizini `models/<fileName>`; her model ayrı ad; tercih bayrakları ayrıca yazılıyor | Qwen/MiniCPM için beklenen bayt, aktarım boyutu ve GGUF başlığı; Llama mevcut dosya kontrolü yalnız >500 MiB. Gerçek model yükleme doğrulaması ayrı. |
| **Kesilen indirme — bağlı, devam etmez** | Hata/iptal → kısmi dosya temizliği | K05 `cancelDownload`, `finally` | Tamamlanan dosyalar korunur; `.part` temizlenir | HTTP Range veya kaldığı bayttan devam yok; sonraki deneme sıfırdan. Bu rapor indirme başlatmadı. |
| **Gerçek yerel çıkarım — bağlı** | Mevcut dosya + `LocalLlamaTestRequest` → ham metin/ölçümler/hata | K06 `LocalLlamaTestService.run/_execute` → `LlamadartTestRuntime.load/generate` | İstek kimliği ve model kimliği; tekli sonuç bellekte | CPU; yeni motor ve tek user mesajı; istem manuel sohbet işaretleriyle iki kez sarılmıyor. Teknik hata model/şablon fallback'i değildir. |
| **Eski şablon — ayrı yol** | Yaş + eski ONT listesi + risk varyantı + süre → `SyntheticVideoSession` | K04 `_generateScenario`; K05 `generateWithLlama`; K20 `generateSession` | Eski `blockId`, `ontologyCode`, risk meta; `_session` bellekte | JSON dışa aktarımı `ScenarioInput` veya `ScenarioClipPlan` değildir. Gerçek LLM ve yeni grafa geçmez. |
| **Ham Qwen cevabı — bağlı** | Akış parçaları → değiştirilmemiş `state.text` | K06 `_execute`; K09 `_modelChanged` | Model/istek tanıları kartta; taslak cevabı dosyaya yazılmıyor | completed olunca editör kopyası hazırlanır. Hata/iptalde kısmi metin görünür, otomatik graf oluşturulmaz. F04. |
| **Biçim + metadata — bağlı** | Ham kopya → JSON nesnesi + uygulama alanları | K09 `_demoInputJson` | `schemaVersion=1.0`, `scenarioId=d01-qwen-yerel-demo`, başlık/dil/30 ay/D01/0.2/source | Yalnız tüm dış `json` çiti ve tek nesne değerli `scenarioInput` açılır. Ek kök alanlı sarmalayıcı, ek açıklama, bozuk JSON onarılmaz. Genel manuel giriş bu demo işaretini taşımıyorsa aynı tolerans/metadata otomatik verilmez. |
| **Kullanıcı düzenlemesi — bağlı** | Düzenlenebilir JSON → yeni taslak | K09 `_edited`, `_validate` | Demo kökeninde `model_output_edited`; ham kart cevabı değişmez | Sonuç/önceki doğrulama temizlenir. Kaynak alanını elle model_output yapmak demo içindeki düzenleme bilgisini geri almaz. |
| **ScenarioInput — bağlı** | Metadata + commonStart + alternatiflerin title/continuation/ending alanları → doğrulanmış nesne | K07 `fromJsonString/fromJson`, K09 `_validate` | `behaviorId`, `cardVersion`, `source`; bellekte | Eksik/boş/yanlış tür ve bilinmeyen alanlar reddedilir. Genel model en az bir, demo ayrıca iki alternatif ister. Dilsel anlam, tek çağrı sayısı, yaş/içerik tutarlılığı otomatik doğrulanmaz. |
| **ScenarioGraph — bağlı** | ScenarioInput → sahneler/kenarlar/bitişler | K08 `convert` → graf kurucusu `validate` | `start`, `alternative_1`, `ending_1` vb.; kaynak beyanı authoringNote'a | Tek dallanma düzeyi; metinler aynen. N alternatifte 1+2N sahne ve 2N geçiş. Bu sayılar içerik başarısı ölçüsü değil. |
| **Görüntüleme — bağlı** | Doğrulanmış nesne → etkileşimli görsel | K09 `_viewGraph` → K10 | Nesne rota belleğinde; kaynak etiketi ayrıca taşınır | Sabit asset'e dönmeden açılır. Klip planı üretimi, kalıcı kayıt veya video oynatma bu rotada yok. |
| **Yeni graf → klip planı — eksik** | Yeni graf → uygun sahne/klip/prompt yapısı | Aktif bir dönüştürücü/çağrı bulunmadı | Yeni plan kimliği/kayıt yok | Önce gerçek senaryo içeriğiyle eşleşen plan gerekir. Sadece başka ekrana yönlendirmek yeterli değil. F06. |
| **D01 planı/promptları — sabit örnek** | D01 graf asset'i + plan asset'i → yedi klip | K13 `_load`; K11 `validateAgainst` | Graf `d01-elle-hazirlanmis-taslak-001`; plan `d01-elle-hazirlanmis-klip-plani-001` | Güncel model grafı değildir; her klip sceneId ile bağlanır, sıra 1'den kesintisiz ve süre (0,8]. |
| **Dış video üretimi — uygulama dışı** | Kopyalanan prompt → dış platformda üretilen klip | K13 Clipboard; üretim çağrısı yok | Dış iş/klip kimliği uygulamada otomatik alınmıyor | Her üretim en fazla 8 saniye; toplam senaryo 8 saniye değildir. Prompt ve son kare süreklilik kanıtı değildir. |
| **Video seçme/kopyalama — bağlı, sabit plana** | Galeri `XFile` → uygulama kopyası + eşleme | K13 `_selectVideo` → K14 `attach` | `(planId, clipId)`, göreli `clip_videos/import_.../video.ext`, özgün dosya adı; `clip_video_bindings.json` | Kaynağa dokunmaz. Önce yeni kopya/indeks, sonra eski uygulama kopyasını temizleme. İptalde değişmez. Yeni grafa aktarılmaz. |
| **Önizleme — bağlı** | Kayıtlı kopya → tek video yüzeyi | K15 `_initialize/_control` | Eşlemeyi yalnız okur; kaynak kapatma ekranın işi | Otomatik başlamaz; eksik/codec/sonradan oynatma hatası gösterilir; eşleme silinmez. |
| **Dallı oynatma — bağlı, sabit plana** | D01 grafı + plan + eşlemeler → klip sırası ve kullanıcı dalı | K16 `start/_loadCurrent/_advance/choose` | Mevcut sceneId/clipIndex bellekte; rota kaydı tutulmuyor | Gerçek bitiş olayı; tek çıkış otomatik, çok çıkış kullanıcı seçimi. Eksik klip atlanmaz; önceki oynatıcı kapanmadan yenisi oluşturulmaz. |
| **Senaryo sonu — bağlı** | Terminal sahnenin son klibi biter → Senaryo tamamlandı | K16 `_stopAt(completed)` | Sonuç yalnız UI state'i | Başa dön ortak başlangıçtan başlatır; önceki seçim yolunu otomatik yeniden oynatma, yol dışa aktarımı, tek birleştirilmiş video dosyası yok. |
| **Gerçek video analizi — eksik** | Kullanıcının videosu → gözlem/ölçüm | Uygulamada analiz motoru çağrısı yok | `_clinicalCases` yalnız sabit örnek rapor | K17 seçim/izleme yapar. Masaüstündeki önceki video fizibilitesi uygulamaya bağlanmış sayılmaz. |

### D2. Metin ve kaynak bütünlüğü

- **Yeni demo:** Modelin commonStart, alternatif başlığı, continuation ve ending metinleri sessizce tamamlanmıyor veya yeniden yazılmıyor. Kod çiti/sarmalayıcı dış biçim olarak açılıyor; anlatının iç boşlukları bile korunuyor. Ham cevap serviste ayrı kalıyor. Otomatik yeniden çıkarım yok.
- **Uygulamanın ekledikleri:** K06'daki açık metadata; kaynak etiketi; dönüştürücünün Ortak başlangıç/Bitiş gibi görünüm başlıkları; sahne/kenar kimlikleri ve taslak notu. Bunlar modelin yazdığı sahne anlatısı olarak sunulmamalı. Model bir kök title yazsa bile demo metadata başlığı esas alınır; alternatif başlıkları içerik olarak korunur.
- **Manuel düzeltme:** Demo kökenli düzenleme kaynak değiştirilerek belirtiliyor. Serbest JSON içe aktarmadaki source alanı ise kullanıcının beyanıdır; uygulama modelin gerçekten çalıştığını kanıtlamaz. Hazır graf yolunda görüntüleyici Kullanıcının içe aktardığı taslak yazar; model kaynak geçmişini bağımsız doğrulamaz.
- **Örnekler:** Asset senaryo `manual_example`; sabit graf/plan el yapımı notu taşır. Bunlar gerçek model çıktısı veya gerçekleşmiş video olayı değildir. Şablon kaynak etiketleri son kodda düzeltilmiş olsa da eski export metinleri/ground truth adı ve klinik etiketler kalmıştır (F03).
- **Uyaran sınırı:** İçerik örneğinde çağrı ortak başlangıçta; üretim planında iki dalın ilk klibindedir. Planlanan eylem mantığı benzer olsa da video kesme sınırları otomatik aynı değildir. Yeni grafı eski plana yalnız sahne sayısını veya alternatif adını kullanarak bağlamak yanlış olur.
- **Kimlikler:** `d01-elle-hazirlanmis-donusum-001` örnek ScenarioInput, `d01-qwen-yerel-demo` model demosu ve `d01-elle-hazirlanmis-taslak-001` video grafı farklı kimliklerdir. Ayrıca dönüştürücü sahne kimlikleri sıraya bağlıdır; alternatiflerin yer değiştirmesi anlamı değiştirebilir. Mevcut plan doğrulamasının farklı scenarioId'yi reddetmesi korunmalıdır.

### D3. Veri yaşam süresi

| Veri | Oturum sırasında | Alt ekrandan geri dönüş | Sahibi ekran kapandığında | Uygulama yeniden açılınca | Dayanak / belirsizlik |
|---|---|---|---|---|---|
| Ana panel yaşı | Home state'inde | Home canlıysa kalır | Uygulama kabuğu bırakılırsa kaybolur | Varsayılan 18 ay | K01; kalıcı tercih yok. |
| Stüdyo yaşı/davranışları | Yerel state | **Her zaman sabit değil:** Home yeniden çizildiğinde eski initial değer yeniden uygulanabilir | Varsayılan/üstten gelen seçim | Yeniden varsayılanlar | K04 `didUpdateWidget`; F09. Önceki genel oturumda korunur ifadesinin bu istisnası var. |
| Şablon motoru, risk varyantı, süre/görünüm | Stüdyo state'inde | Aynı ekran canlıysa kalır | Kaybolur | Varsayılanlar, init'te şablon üretilir | K04; gerçek LLM otomatik çalıştırılmaz. |
| Karşılaştırma modeli | `_comparisonModel` | Aynı Stüdyo canlıysa kalır | Kaybolur | Qwen varsayılanı | K04; indirilen dosyalar ayrı olarak kalır. |
| Tekli model test cevabı | Servis state'i | Stüdyo IndexedStack'te canlıysa kalır | Servis dispose edilir, geçmiş geri yüklenmez | Cevap yok | K06; değerlendirme dosyasıyla karıştırma. |
| Qwen demo ham cevabı | Ortak ekranın servisi | Graf görüntüleyicisinden dönüşte kalır | **Kaybolur; kullanıcı bunu yaşadı** | Geri yüklenmez | K09/K06; otomatik dosya kaydı yok. |
| Düzenlenmiş JSON, tür başına taslak | `_json` ve `_drafts` | Graf ekranından dönünce kalır; tür değişiminde metin korunur, sonuç temizlenir | Kaybolur | Geri yüklenmez | K09; örnek yükleme veya yeni completed cevap da editör kopyasını değiştirir. |
| Oluşan graf ve kaynak bilgisi | `_validated`, `_scenarioInput`, rota nesnesi | Aynı ortak ekran canlıysa kalır | Kaybolur | Yalnız asset grafı tekrar okunabilir | K09/K10; dosyaya graf kaydı yok. |
| Tam indirilmiş modeller | Dosya sisteminde | Kalır | Kalır | Kalır; dosyadan durum kontrol edilir | K05; bu görev cihazdaki fiili dosyaları yeniden incelemedi. |
| Yarım indirmeler | Aktarım `.part` dosyası | İndirme/abonelik durumuna bağlı | Hata/iptal/finally temizler | Range ile devam kodu yok; süreç zorla öldürülürse finally garantisi yok, sonraki indirme sıfırdan yazabilir | K05; her koşulda kısmi dosya asla kalmaz iddiası kurulmadı. |
| Galeri kaynak videosu | Seçicinin verdiği dosya | Uygulama kaynağı silmez | Kaynak uygulamanın kontrolünde değil | Galeri sağlayıcısına bağlı | K14; kalıcı oynatma kaynak yoluna dayanmaz. |
| Kalıcı uygulama kopyası/eşleme | Belge dizininde | Kalır, yeniden okunabilir | Kalır | Yüklenir | K14; kullanıcı dosyayı dışarıdan silerse eşleme kalır ve Dosya bulunamadı gösterilir. |
| Video Analiz özel seçimi | Geçici ekran denetleyicisi ve ad | Tam ekrandan dönünce korunur | Kalıcı eşleme yok | Eski örneğe döner | K17; seçilen dosya belge dizinine kopyalanmıyor. |
| Oynatma konumu/seçilen dal | Graf denetleyicisi state'i | Ekran kapanmadan kalır; arka planda duraklatılır | Kaybolur | Baştan başlatılır | K16; yol geçmişi kaydı yok. |
| Altı denemelik değerlendirme | Plan ve denemeler diske yazılır; UI son çalışmayı tutar | Stüdyo canlıysa UI kalır | Ham dosyalar kalır, ekran belleği kaybolur | Dosyalar durur; eski run'ları okuyup listeleyen UI yok | K23; her run ayrı klasör, otomatik sonuç değiştirme yok. |

### D4. Hata, iptal ve kaynak kapatma özeti

| Yol | Korunan davranış | Somut açık / kanıt sınırı |
|---|---|---|
| Yerel çıkarım | Global tek sahip kilidi; yükleme/üretim/iptal/kapanış ayrımı; hatada ham kısmi metin korunur. | Yükleme sırasında iptal zorla motor öldürmez, güvenli bitişi bekler. Dispose başarısızsa kilit bırakılmaz ve yeniden açma mesajı verilir; bunu sessiz otomatik kurtarmaya çevirmemek gerekir. Gerçek iptal gecikmesi ölçülmedi. |
| Ortak ekran | mounted kontrolleri ve servis dispose; geç sonuç ekran kapanınca çizilmez. | Veri kaybını önleyen çıkış/geri alma veya kalıcı kayıt yok. Geç sonucu atmamak için ekranı kapalı halde güncellemek çözüm değildir (F04). |
| Klip eşleme | Seçimde iptal eski eşlemeyi korur; kopya/indeks hatasında önceki kayıt kalır; işlemler seri. | Kopya boyutu kontrolü video codec/içerik doğrulaması değildir. Temizlik hataları uyarı olarak döner. Aynı kaynak farklı kliplere bağlanırsa ayrı kopyalar oluşabilir; depolama etkisi cihazda ölçülmedi. |
| Tek klip önizleme | Geç dosya sonucu mounted ile bırakılır; hata mesajı/eşleme korunur; çıkışta dispose var. | Uygulama arka plan politikasında paket davranışı ile grafın özel politikasını eşdeğer sayamayız; bu görevde gerçek arka plan/codec ölçümü yok. |
| Graf oynatma | Epoch ile eski olayları reddetme; `_endHandled`, loading ve control kilitleri; eksik dosyada durma; lifecycle suspend/resume. | `_releasing` başarısız kalırsa restart tekrar aynı hatalı zincire takılabilir (F11). Pause/close hatası enjekte eden test bulunmadı. |
| Video Analiz | Özel videoya sabit bulgu aktarılmıyor. Tam ekran aynı denetleyiciyi kullanıyor. | Başlatma hatası görünmez/spinner; eski denetleyici başarılı yeni açılış beklenmeden bırakılabilir; bazı async setState kontrolleri eksik; tab görünürlüğüyle pause yok (F05/F10). |

## E. Öncelikli içerik, kullanılabilirlik ve teknik bulgular

Kanıt düzeyi: **KD** güncel kod/yapılandırmadan doğrulandı; **KB** kullanıcı bildirimiyle yaşanmış; **KT** kontrollü test kaynağı mevcut, bu görevde çalıştırılmadı; **KR** önceki kayıt temelli rapor; **Ç** koddan koşullu çıkarım, gerçekleşmiş cihaz olayı değil; **G** görsel/gerçek etkileşimle kontrol gerekli. Öncelik: **P0** veri kaybı/yanıltıcı sonuç/temel akış engeli; **P1** belirgin kullanım sorunu; **P2** bakım/görsel iyileştirme. Değişiklik riski, düzeltme uygulanırsa etkilenebilecek alanı anlatır.

### F01 — Güncel görevler yerine eski klinik katalog ve sonuç sözlüğü

- **Dayanak:** K02 eski 12 `ScenarioModel`, K01 `_buildDashboardTab`, K03 `_cleanCriteria/build`, K04 `_buildRiskChip`, K20 `_getPhasesForCode`; B tablosu.
- **Sorun/etki:** Kullanıcıya tek çağrı yerine tekrar çağrı, jestsiz yerine destekli/iki adımlı görev, koşulsuz göz teması, ölçülmemiş norm/başarı yüzdesi ve risk sınıflaması veriliyor. Planlanan tepki, Gözlem Durumu adıyla seçiliyor. Güncel dört sonuç ve fırsat geçerliliği ayrımı yok.
- **Kanıt:** KD; kart–kod karşılaştırması. Eski metinlerin bilimsel/klinik doğruluğu ayrıca onaylanmadı.
- **En küçük düzeltme:** Önce D01'in görünen görev ve sonuç metinlerini güncel karta göre tek bir içerik işiyle ele almak; D02–D10 göçünü ayrı tutmak. Eski alanların yalnız kodunu/başlığını değiştirerek uyum sağlanmış saymamak. Yeni klinik eşik üretmemek.
- **Öncelik / değişiklik riski:** P0 / orta-yüksek; metinler şablon, ayrıntı, yaş dalı ve export tarafından paylaşılıyor. Toplu veri silme önerilmez.

### F02 — Aynı ONT kimliği farklı olayları temsil ediyor; ONT-08 yanlış şablona gidiyor

- **Dayanak:** K02 ONT-03/06/08/12; K17 `_clinicalCases`; K03 `_cleanCriteria`; K20 `_getPhasesForCode` ONT-07 ve ONT-08 ortak case'i.
- **Sorun/etki:** Örnek analizde ONT-06 sosyal gülümseme, katalogda yetişkin elini alet kullanma; ONT-03 kısa göz teması, katalogda ortak dikkat başlatma; ONT-12 tekrarlayıcı hareket, katalogda akran ilgisi. ONT-08 Nesne Getirme seçimi ce-e üretir. Aynı koda bakıp verileri birleştirmek yanlış içerik bağlar.
- **Kanıt:** KD; örnek rapor gerçek analiz olmadığı için bu durum kullanıcı videosunda ölçülmüş yanlış sonuç olarak sunulmuyor.
- **En küçük düzeltme:** ONT-08 case'ini kendi ilan ettiği görevle eşleştirmek ve örnek raporun eski kodlarını güncel D kodlarına otomatik taşımamak. Kaynak/sürüm ayrımı belirlenmeden kimlik göçü yapmamak.
- **Öncelik / değişiklik riski:** P0 / orta; şablon ve fixture beklentileri etkilenir, ham kayıtlar yeniden etiketlenmez.

### F03 — Kalan yetenek/kaynak vaatleri birbirini tutmuyor

- **Dayanak:** K01 otomatik zaman damgalı kanıt analizi kartı; K03 Videodan Analiz Et; K22 `ApiKeyDialog.show` açıklaması; K04 admin prompt/export metinleri; K20 `exportGroundTruthJson`, `exportDoctorCleanScenario`.
- **Sorun/etki:** Ana panel otomatik analiz vaat ederken gerçek yol yalnız seçme/izleme. Gemini dialogu gerçek LLM/Veo üretimi vaat ediyor; aktif Qwen/şablon yolları bu anahtarı kullanmıyor. Plan export'unun ground truth adı ve klinik/gözlem durumu metinleri, üretim hedefini kanıt gibi çağrıştırıyor. K17'deki seçilen video analiz edilmedi koruması doğrudur ve korunmalıdır.
- **Kanıt:** KD + seçilen videoya örnek bulgu sızmaması için KT. Düğmeye basarak yeni doğrulama yapılmadı.
- **En küçük düzeltme:** Önce giriş/düğme/çıktı adlarını yapılan işe göre düzeltmek: Video aç/izle, Şablon taslağı, Üretim planı. Yeni uyarı paragrafları veya gizli yeni analiz motoru eklemek gerekmez. Eski export fonksiyon adını hemen kırmak yerine kullanıcıya görünen etiketinden başlamak mümkündür.
- **Öncelik / değişiklik riski:** P0 / düşük-orta; metin testleri ve export tüketicileri ayırt edilmeli.

### F04 — Model taslağının kaybolması yaşanmış veri kaybı

- **Dayanak:** K09 `_json/_drafts/_validated`, `dispose`, `_loadExample`, `_modelChanged`; K06 tekli servis yalnız state tutuyor. Kullanıcının bu görevdeki açık bildirimi; `docs/demo_2026-10-18/model_ham_cevap.txt` 0 bayt.
- **Sorun/etki:** Ortak ekran kapanınca ham cevap, düzenlenmiş JSON ve graf geri getirilemiyor. Kullanıcı bunu gerçekten yaşadı; yeni örnek yükleme/üretim de mevcut editör kopyasını değiştirebilir. Ekrandaki oturumluk açıklama kaybı önlemez.
- **Kanıt:** KB + KD. Süre/cevap içeriği veya kayıp denemenin ham metni bu raporda uydurulmadı.
- **En küçük düzeltme:** İlk turda dolu taslağı terk etme/değiştirme eylemine kısa koruma; mevcut geri dönüşü iptal edip aynı taslağa dönme. Bu, ekranın kazara kapanmasını azaltır; OS süreci öldürünce kurtarma veya kalıcı arşiv sağlamaz. Kalıcı saklama ayrı ve açık kaynak ayrımıyla tasarlanmalı.
- **Öncelik / değişiklik riski:** P0 / orta; geri gezinme, örnek yükleme ve çıkarım sırasında servis kapatma korunmalı. Sırf mounted kontrollerini kaldırmak çözüm değildir.

### F05 — Video açılma hatası görünmez; başarısız seçim eski videoyu bırakabiliyor

- **Dayanak:** K17 `_loadVideoForCurrentCase`, `_pickVideo`, sabit 16/9 alanındaki `isInitialized`/spinner koşulu.
- **Sorun/etki:** initialize hatası yalnız debugPrint'e gider. Yeni denetleyici başlatılamasa da eski denetleyici dispose edilip Video yüklendi mesajına ulaşılabilir. Kullanıcı bozuk/sürekli yükleniyor ekranıyla kalabilir. Await sonrasındaki bazı setState çağrılarında mounted kontrolü yok.
- **Kanıt:** KD/Ç; hata yolunun sonucu koddan açık, burada gerçek codec/izin hatası tetiklenmedi. K15 önizlemenin açık hata yolu bundan ayrıdır ve korunmalıdır.
- **En küçük düzeltme:** Yeni videoyu yerel aday denetleyicide başlatmak; yalnız başarıda seçimi değiştirmek; hata halinde adayı kapatıp eski seçimi korumak ve kısa hata göstermek. Geç sonuçlar için mounted/istek geçerliliği kontrolü. Özel videoya örnek bulgu aktarmama kuralı değişmemeli.
- **Öncelik / değişiklik riski:** P0 / orta; eski denetleyici/tam ekran sahipliği ve iptal/geri dönüş beklentileri etkilenir.

### F06 — Hedef zincirin graf → klip planı bağlantısı yok

- **Dayanak:** K09 `_viewGraph` yalnız K10'a gider; K13 `_load` iki sabit asset okur; K11/K12 kimlikleri farklı.
- **Sorun/etki:** Kullanıcı modelden oluşturduğu grafın videolarını denediğini sanabilir. Gerçekte yalnız sabit D01 video zinciri oynatılır. Uçtan uca hedef bu noktada durur; iki ayrı demo yine gösterilebilir.
- **Kanıt:** KD; ayrıca güncel devam notu bu ayrımı kabul ediyor.
- **En küçük düzeltme:** Bugün arayüz girişleri ve sunumda iki yolu doğru adlandırmak. Gerçek bağlantı için o grafa ait doğrulanabilir plan/prompt verisi ve eşleme bağlamı gerekir; yalnız yeni düğme veya sabit planın yeniden kullanımı yeterli değildir. Bu ilk küçük turda yeni dönüştürücü önerilmiyor.
- **Öncelik / değişiklik riski:** P0, hedef uçtan uca görev için / yüksek; mevcut D01 videolarını yeni içeriğe sessizce bağlama riski var. Açık kapsam boşluğu olarak korunmalı.

### F07 — Sabit/sıraya bağlı kimliklerle içerik sürümü karışabilir

- **Dayanak:** K06 `d01GraphDemoMetadata`; K08 `convert`; K11 `validateAgainst`; K14 indeks anahtarı `(planId, clipId)`.
- **Sorun/etki:** Bütün demo üretimleri aynı scenarioId'yi kullanıyor; alternatif kimliği sıraya göre. Plan/video indeksi içerik hash'i veya senaryo revizyonu taşımıyor. İçerik değişip aynı plan/klip kimlikleri korunursa eski video yanlış anlamla sunulabilir.
- **Kanıt:** KD/Ç. **Bugün bu yanlış yeni-graf/video eşlemesi gerçekleşmiyor**, çünkü bağlantı zaten yok. Mevcut `validateAgainst` farklı scenarioId'yi reddediyor.
- **En küçük düzeltme:** Kalıcı senaryo/plan bağlantısına geçmeden önce revizyon/kimlik politikasını kararlaştırmak; aynı planId ile anlam değiştirmemek. Ham geçmiş kayıtlara yeni kimlik dayatmadan yeni kayıt sürümüyle ilerlemek.
- **Öncelik / değişiklik riski:** P1 / orta-yüksek; erken kimlik değişimi mevcut video eşlemelerini görünmez hale getirebilir.

### F08 — Model/yaş seçiminin kapsamı ve test adları belirsiz

- **Dayanak:** K04 `_comparisonModel`, `_buildD01EvaluationControls`; K06 `qwenCommonStart`, `d01Qwen`, `d01GraphDemo`; K09 sabit Qwen resolver'ı; K23 protokol asset'i.
- **Sorun/etki:** MiniCPM seçimi graf demosunu değiştirmez; Stüdyo yaş/davranış seçimi D01/30 aylık demoya gitmez. Ortak başlangıç adlı tekli kart artık yalnız oyun ortamı isterken altındaki altı deneme protokolü isim çağrılı ortak başlangıç içeriyor. Aynı görev/istem çalıştırılıyor sanılabilir.
- **Kanıt:** KD; farklı protokoller ve sınırlar doğrudan kodda. Sonuçları bir araya getirerek model başarısı kıyaslanmadı.
- **En küçük düzeltme:** Değerlendirme modeli, Sabit D01/30 ay demosu, Oyun ortamı testi gibi kapsamı belirten adlar. İstemleri/ham kayıtları yeniden yazmadan teknik kontrolleri gruplamak.
- **Öncelik / değişiklik riski:** P1 / düşük; kullanıcı yetki kararı vermeden adlandırma yapılabilir.

### F09 — Sekme dönüşü Stüdyo seçimini yeniden değiştirebilir

- **Dayanak:** K01 `HomeScreen.build` her seferinde initial değerleri verir; K04 `didUpdateWidget` bunları `oldWidget` değişimi yerine güncel yerel state ile karşılaştırır.
- **Sorun/etki:** Home yaşı 18 iken Stüdyo'da 30 seçilirse Home'un sonraki yeniden çiziminde 18 geri uygulanabilir. Kullanıcının kaldırdığı initial davranış da yeniden eklenebilir. Beklenmeyen şablon yeniden üretimi olur. Bu Qwen'in sabit 30 ay isteğiyle aynı sorun değildir.
- **Kanıt:** KD/Ç; cihazda yaşandığı bildirilmedi, kod yolu bunu mümkün kılıyor.
- **En küçük düzeltme:** Dış parametre gerçekten değiştiğinde uygulamak; bunu `oldWidget` ile karşılaştırmak. Kullanıcı yerel seçimini değiştirdi diye aynı dış değeri tekrar dayatmamak.
- **Öncelik / değişiklik riski:** P1 / düşük-orta; davranış ayrıntısından Stüdyo'ya yeni seçim aktarma yolu korunmalı.

### F10 — Sekme/üst ekran görünürlüğü ile video sesi durumu ayrışıyor

- **Dayanak:** K01 `IndexedStack`; K17 görünürlük girdisi olmaması; K18 `FloatingVideoControls._isMuted`, `_toggleMute`; K16 açık lifecycle yönetimi.
- **Sorun/etki:** Video Analiz oynatıcısı sekme değişiminde dispose/pause olmuyor; ses başka alanda devam edebilir. Aynı controller ile yeni tam ekran kontrolü açıldığında yerel `_isMuted=false`, gerçek volume=0 olabilir; simge sesi yanlış yansıtabilir. Grafın tek oyuncu garantisi yalnız kendi akışını kapsar.
- **Kanıt:** KD/Ç; gizli ses veya yanlış simge bu oturumda gerçek cihazda tetiklenmedi. Uygulamanın arka plan paket davranışı ayrıca sınanmadı; grafın özel suspend/resume politikası kodda var.
- **En küçük düzeltme:** Sekme terk edilirken mevcut video denetleyicisini duraklatmak; ses görünümünü denetleyicinin gerçek değerinden üretmek. Kaynak sahipliğini birleştiren genel altyapı gerekmiyor.
- **Öncelik / değişiklik riski:** P1 / orta; tam ekran paylaşımı ve kullanıcının bilinçli yeniden oynatması korunmalı.

### F11 — Kapanış hatasından sonra grafı yeniden başlatma toparlanmıyor

- **Dayanak:** K16 `GraphPlaybackController._releasePlayer`, `_releasing.then`, `restart`, `_fail`; test fake'inde gecikmeli close var, başarısız pause/close senaryosu yok.
- **Sorun/etki:** Pause veya close hatası zincirde kalırsa sonraki yükleme/restart aynı başarısız Future'ı bekler. Baştan başlat düğmesi toparlamayabilir. Bu, normal eksik video hatasında her restart bozuk demek değildir.
- **Kanıt:** KD/Ç; gerçek motor kapanış hatası oluştuğuna dair kanıt yok.
- **En küçük düzeltme:** Kapanış sonucunu ayrıca yönetmek. Önceki kaynağın güvenle bırakıldığı biliniyorsa zinciri yeni isteğe açmak; bilinmiyorsa yeni oyuncu oluşturmadan açık durum göstermek. Kilidi sessizce kaldırmak önerilmez.
- **Öncelik / değişiklik riski:** P1 / orta; tek oyuncu ve geç olay korumaları bozulmamalı.

### F12 — Dar ekran/büyük yazı ve video oranında belirli riskler

- **Dayanak:** K22 `AgeSliderCard` başlık Row'u; K03 yaş başlığı Row'u; K04 uzun admin başlığı ve bazı küçük seçiciler; K18 `FloatingVideoControls` tek satır; K17 sabit 16/9; K10/K13 Wrap ve kaydırma korumaları.
- **Sorun/etki:** Sarılmayan başlık/kontrol satırları büyük yazıda taşabilir. Video Analiz'de portre videonun gerçek oranı kullanılmıyor. Ham model cevabının uzun gövdesi JSON/sonraki eylemi çok aşağı itiyor. Graf kutusunda iki satır kesme ise tam ayrıntı paneli bulunduğundan tek başına hata değildir.
- **Kanıt:** KD (yerleşim/ölçüler), G (gerçek taşma/okunabilirlik); ekran görüntüsü görülmedi, piksel testi çalıştırılmadı.
- **En küçük düzeltme:** Yalnız taşma doğrulanan satıra Flexible/Wrap; gerçek video oranı; ham cevap ve teknik ayrıntıları mevcut açılır düzenle dengeleme. Yazıyı küçülterek sığdırma öncelikli çözüm değil.
- **Öncelik / değişiklik riski:** P1 / düşük-orta; medya kontrollerinin erişimi ve metnin tamamına ulaşma korunmalı.

### F13 — Küçük dokunma alanları ve eksik erişilebilir ad/durumlar

- **Dayanak:** K04 seçili davranışın 14 boyutlu kaldırma simgesi + 4 padding, GestureDetector'lar; K22 yaş grubu GestureDetector; K18 oynat/ses/tam ekran IconButton'larında tooltip yok; K10 sahne Semantics ve grafik kontrol tooltip'leri mevcut.
- **Sorun/etki:** Küçük simgeye basmak zor; simge eylemleri ve bazı seçili durumlar ekran okuyucuya açık bir adla iletilmeyebilir. Kodda açık etiket bulunmaması, Flutter'ın hiçbir örtük semantiği olmadığı anlamına gelmez.
- **Kanıt:** KD/G; TalkBack/VoiceOver, klavye odak sırası ve fiziksel dokunma doğrulanmadı.
- **En küçük düzeltme:** Mevcut IconButton/ChoiceChip olanaklarıyla eylem adı, seçili durum ve daha geniş hedef sağlamak. Yeni erişilebilirlik paketi gerekmiyor.
- **Öncelik / değişiklik riski:** P1 / düşük; eylemi değiştirmeden görünür/erişilebilir kontrol düzeltmesi yapılabilir.

### F14 — Eksik eski asset'ler ve README, gerçek dosya durumunu anlatmıyor

- **Dayanak:** K21 `pubspec.yaml` ve `assets/videos/README.md`; K17 varsayılan `Deniz_Senaryo_Kurtarilan.mp4`; K02 eski videoAssets.
- **Sorun/etki:** Bildirilen 12 `ont_*` klasörü diskte yok, `assets/videos` altında yalnız README var. README ilk davranışı Hazır ve kopyalanan videoları otomatik oynar diye anlatıyor; bazı klasör adları pubspec ile farklı. Eski örnek videonun bulunmaması K17'deki yükleme sorununu görünür kılabilir.
- **Kanıt:** KD. Kullanıcı önceki uyarılarla test/derlemelerin tamamlandığını bildirdi. **Kesin derleme engeli iddiası yok**; bugün derleme yapılmadı. Cihazdaki belge dizini videoları bu asset eksikliğinden ayrı.
- **En küçük düzeltme:** Eksik eski bildirimleri ve README hazır iddiasını gerçek içerikle uyumlu hale getirmek. Yeni/sahte MP4 veya ilgisiz video eşlemesi üretmemek.
- **Öncelik / değişiklik riski:** P2, eski örnek görünürlüğü için P1 / düşük-orta; ileride eklenmesi planlanan asset yollarının tüketicileri kontrol edilmeli.

### F15 — Test beklentisi eskimiş; bazı kritik yeni hata yolları kapsanmıyor

- **Dayanak:** K24 `test/widget_test.dart`; mevcut testler ve `test/support/fake_graph_playback.dart`.
- **Sorun/etki:** Ana ekran testi ekranda bulunmayan iki eski başlığı bekliyor. Model içeriği doğruluğu, yaş/seçim geri dönüşü, görünmez sekmede ses, yanlış/başarısız video seçiminde geri alma, pause/close hatasından toparlanma ve gerçek iOS izinleri için yeterli mevcut kanıt yok. Test yeşil görünmesi gerçek cihaz kanıtı olmaz.
- **Kanıt:** KD/KT; beklenti–metin farkı doğrulandı, yeni başarısız/geçen test sayısı üretilmedi. Kapsam ayrıntısı G bölümünde.
- **En küçük düzeltme:** Ürün davranışı kararıyla uyuşan test beklentisi; sadece metin aramak yerine mevcut ilgili davranışı hedeflemek. Diğer boşluklara ancak ilgili düzeltmeyle hedefli kontrol eklemek; genel test/refactor turu açmamak.
- **Öncelik / değişiklik riski:** P1 / düşük; beklentileri gevşetmek, kaldırmak veya timeout büyütmek çözüm değil.

### F16 — Eski yollar ve iki ayrı görünürlük mekanizması bakım/keşif yükü yaratıyor

- **Dayanak:** K04 `_isAdminMode` ve `kDebugMode`, K19 eski ekranlar/servis, K18 paylaşılan `SimulationState`, C6 referans tablosu.
- **Sorun/etki:** Gizli beş dokunuşla admin adı ve debug-only geliştirici girişi iki ayrı kavram. Eski klinik ekranlar normal navigasyonda yokken paylaşılan tipleri kullanılıyor. Uçtan uca görev için kullanıcı gereksiz teknik kartlardan geçiyor.
- **Kanıt:** KD; çağrı bulunmayan sınıfın tüm dosyası gereksiz ilan edilmedi. `ScenariosRepository.addGeneratedScenario` gövdesi boş; eski RAG yolundaki listeye eklendi açıklaması kalıcı/gerçek liste kaydı değil.
- **En küçük düzeltme:** Mevcut ekranlardaki teknik kontrolleri açık bir bölümde toplamak; eski yolları yerinde bırakıp kullanım adaylarını belgelemek. Silme ancak ayrı referans/geri dönüş değerlendirmesiyle. Debug görünürlüğünü yetkilendirme diye adlandırmamak.
- **Öncelik / değişiklik riski:** P2 (keşfedilebilirlik P1) / orta; paylaşılan enum, test ve eski API'leri topluca silme riski var.

### F17 — iPhone için video seçme/çekme izin hazırlığı eksik

- **Dayanak:** K25 `ios/Runner/Info.plist`; K17 kamera/galeri ve K13 galeri çağrıları. Kurulu image_picker paketinin yerel README'si fotoğraf, kamera ve video kaydı için mikrofon kullanım açıklamalarını istiyor; requestFullMetadata istisnasını da açıklıyor. Mevcut plist'te bu üç kullanım açıklaması yok.
- **Sorun/etki:** iOS video seçme/çekme yoluna hazır olduğu iddia edilemez. Fotoğraf kitaplığı, kamera ve mikrofonun hangi görev için gerektiği belirlenmeli; yalnız gallery görevi ile kamera görevi ayrılmalı.
- **Kanıt:** KD + yerel paket dokümanı. iPhone'da çökme/izin reddi bu görevde görülmedi; kesin gerçekleşmiş olay olarak yazılmadı.
- **En küçük düzeltme:** Gerçek kullanılacak iOS eylemleri için gerekli açıklamaları eklemek; sonra hedef cihazda izin/iptal akışını doğrulamak. Android emülatör sonucu bunun yerine geçmez.
- **Öncelik / değişiklik riski:** P1, iPhone hedefi için / düşük-orta; gereksiz yetki istemek veya yeni paket eklemek önerilmiyor.

### F18 — Model kalitesi/şablon ve gerçek telefon yeterliliği hâlâ sınırlı kanıtlı

- **Dayanak:** K06 runtime ayarları; K23 kayıt servisi; [model değerlendirme kanıtları](model_degerlendirme_kanitlari.md); K25 platform kapsamı.
- **Sorun/etki:** Graf oluşması, modelin zorunlu olayları doğru kurduğu anlamına gelmez. Küçük Qwen/MiniCPM kayıt grubunda içerik ihlalleri var; Llama ham arşivi yok. RAM/tepe bellek, M21 ve iPhone 11 davranışı ölçülmedi. MiniCPM think/BOS yapısının yayıncıyla tam uyumu kayıt raporunda belirsiz bırakılmış.
- **Kanıt:** KR/KD; bu rapor eski dosyaları yeniden indirmiş veya altı yeni çıkarım yapmış değildir. Kayıtlı 160 token görevleri ile 768 token graf demosu aynı protokol sayılmaz.
- **En küçük düzeltme:** Üretim sonucu gösterimini taslak olarak korumak; insan içerik kontrolünü yapısal doğrulamadan ayırmak. Bu incelemede yeni model, yükseltme veya kapsamlı deney önerilmiyor. Telefon için daha sonra ölçüm gerekir; ağırlık dosyası boyutu RAM gereksinimi diye verilmez.
- **Öncelik / değişiklik riski:** P1 / düşük (doğru iddia), gelecekte model/çalışma ayarı değişirse orta; bugün performans garantisi verilemez.

## F. Mevcut ekranlarla sade gezinme ve içerik dağılımı

### F1. Görev yolculukları

| Görev | Bugünkü başlangıç ve sonraki adım | Kullanıcı sorunu / sonuç anlamı | Mevcut parçalarla öneri |
|---|---|---|---|
| Uygulamanın ne yaptığını anlama | Ana panel → yaş ve uzun eski 12 liste; iki hızlı kart | Otomatik analiz ve klinik norm izlenimi; ilk yapılacak iş belirsiz | İlk kartlarda bugün yapılabilen işleri söyle; ayrıntılı eski normları ana eylemin önüne koyma. Aynı alt sekmeler korunur. F01/F03. |
| Modelden senaryo → graf | Stüdyo → debug D01 klip planı → Senaryo/graf içe aktar → Senaryo içeriği → Qwen → Grafı görüntüle | Senaryo önce olmalı; kullanıcı önce başka bir üretim planına giriyor. Varsayılan Hazır graf ve teknik JSON yeni kullanıcı için ters başlangıç. | **Mevcut ortak ekranın girişini** Stüdyo'da senaryo işlemlerinin yanına almayı planla; önce mevcut debug kapsamı korunabilir. Bunun release'e/kimlere açılacağı H'de ürün kararıdır. Varsayılanı senaryo içeriği yapmak ayrı küçük tercih olabilir. Yeni ekran veya form altyapısı şart değil. |
| Hazır teknik veri deneme | Ortak ekranda senaryo JSON'u veya hazır graf | İki sözleşme aynı sanılabilir; yapıştırılan model cevabı tam metadata taşımayabilir | İki seçimi koru. Senaryo: içerik alanları; Hazır graf: sahne/kenarlar. JSON'u teknik ayrıntı olarak adlandır. Modeli çalıştırmadan sıradan yapıştırmaya model kökeni atama. |
| Üretim hazırlama | Debug D01 planı → sahne → klip → promptu kopyala → dış araç → Video seç | Kaynak grafın sabit olduğu kaçabilir; dış işin uygulamada tamamlandığı sanılabilir | Başlıkta D01 örnek klip planı; promptlar burada kalır. Yeni graf için plan yoksa eksik bağlantı açık kalmalı. Sekme/düğme toplamak gerçek plan üretimi değildir. |
| Videolu deneyim | D01 planı → Grafı dene → Başlat → dal seç → tamamlanma | Normal kullanıcı üretim/teknik alandan dolaşıyor; yayımlanacak içerik seçimi henüz yok | Mevcut oynatma ekranını koru. Bugün debug demo yolu olarak açık adlandır; normal kullanıcıya sunulacak senaryo kataloğu/erişim kararı verilmeden yeni katalog/rol inşa etme. |
| Bir videoyu izleme | Video sekmesi → galeri/kamera → oynat | Analiz bekleniyor ama yok; hata geri dönüşü zayıf | Geçici ad Video izle olabilir. Seçilen video analiz edilmedi kısa bilgisi kalır. Örnek rapor ayrı açılır bölüm olabilir; gerçek analiz gelmiş gibi davranma. |
| Model değerlendirmesi | Stüdyo içindeki tekli kartlar ve altı deneme | İstem/sürüm farkları ve karşılaştırma modeli kapsamı anlaşılmıyor | Aynı ekranda tek Teknik model denemeleri açılırı; her istem/protokol kimliği korunur. Normal senaryo üretme hakkını bu sınıflandırmaya dayanarak kaldırma. |

### F2. İçerik dağılımı — yeni sekme veya rol sistemi olmadan

- **Ana Panel:** kısa amaç, gerçek görev girişleri ve gündelik davranış açıklamaları. Güncel görev verisi hazır değilken eski 12 kartı yeni 10 kartmış gibi yeniden adlandırma. İçerik göçü ayrı kontrollü iş olmalıdır.
- **Senaryo Stüdyosu:** hedef sırayı anlatan mevcut üretim/içe aktarma girişi; sabit D01 örneği ayrı ve ikincil. Eski şablon iki motor seçimi tek şablon yolu olarak sadeleşebilir. LLM ile üretimin hangi kullanıcılara açık olacağı henüz karar değildir.
- **Mevcut teknik alan:** model indirme/durum, Llama/Qwen/MiniCPM deneyleri, motor tanıları, JSON graf içe aktarma gibi işlemler birlikte gruplanabilir. Gerçek senaryo üretimi teknik testle eşdeğer sayılmaz.
- **Mevcut içerik hazırlama alanı:** klip süreleri, promptlar, karakter/ortam sürekliliği, video kopyalama/eşleme. Promptlar normal kullanıcı grafına veya oynatmaya eklenmez. Bu düzenleme rol/yetki çözümü değildir.
- **Video sekmesi:** izleme işlevi; seçilmiş videodan sonuç üretmeyen kısa durum; sabit örnek rapor ayrı. Yeni analiz boru hattı/hesap sistemi ekleme bu planın parçası değildir.
- **Graf ve oynatma:** aynı görüntüleyici ve aynı oynatma denetleyicisi korunur. Yeni grafın eski planla aynı veriyi kullandığı izlenimi veren ortak bir Devam düğmesi, veri bağlantısı olmadan eklenmemelidir.

### F3. Dil ve etiket önerileri

Bu adlar ürün kararı gerektirmeyen açıklık adaylarıdır; bu görevde uygulanmadı. Teknik kimlikler kayıt/veri sözleşmesinde korunur.

| Bugün görünen ifade | Önerilen gündelik ifade / yer | Gerekçe ve korunacak teknik ayrıntı |
|---|---|---|
| Ontoloji / ONT-xx / Davranış Ontolojisi | Davranış; teknik kod ikincil | Katalog adının güncel olduğunu otomatik iddia etmez. Kart kimliği/sürümü hazırlama ayrıntısında kalmalı. |
| Klinik Senaryo & Simülasyon | Senaryo Stüdyosu | Klinik geçerlilik vaadi yerine gerçek işi anlatır. |
| Gelişimsel Yaş Ayarı | Çocuğun yaşı / örnek karakterin yaşı | Ölçülmüş gelişim yaşı izlenimini azaltır; gerçek/sentetik bağlam ürünce belirlenmeli. |
| Video Analiz Modu / Videodan Analiz Et | Video izle / Video aç | Gerçek analiz bağlanmadığı bugünkü aşamayı anlatır; analiz hedefi ayrı geliştirme olarak kalır. |
| Senaryo Grafı | Senaryo akışı | Graf terimi teknik aktarımda kullanılabilir; kullanıcıya dal ve devam anlaşılır. |
| Sabit Senaryo Grafı girişi | D01 örnek akışı | Bunun son üretilen senaryo olmadığı görülür. |
| Senaryo / graf içe aktar | Senaryo içeriği / Hazır akış (teknik JSON) | İki veri türü ayrımı sürer; otomatik serbest metin anlama iddiası yok. |
| GGUF / çıkarım / token | Model dosyası / modelden metin üretimi; teknik bölümde ayrıntı | GGUF, bağlam/token ve native tanılar geliştirici için gerçek adlarıyla kalır. Model indirme ile üretim ayrımı kaybolmamalı. |
| Qwen Ortak başlangıç testi (şimdiki oyun istemi) | Qwen oyun ortamı testi | İsim çağrılı sabit protokolle aynı görev sanılmasını önler; tarihsel istemi değiştirmez. |
| ADMİN / Doktor modu | İçerik hazırlama / Teknik ayrıntılar | Hesap/rol yetkisi uygulanmadığı için yetkili kişi iddiası yaratmaz. Gerçek yetki ihtiyacı H'de açık. |
| Saniyelik Klip Dilimleme | Klip süre hedefleri | Uygulama videoyu gerçekten kesmiyor; toplam süre ile tek üretim süresi farklı. |
| Gözlem Durumu: tipik/gecikmeli/atipik | Planlanan devam | Planlanan olay gözlenmiş/klinik sonuç değildir. Eski risk kategorilerini yalnız yeni ad altında sürdürmek yeterli içerik düzeltmesi sayılmaz. |
| ground truth / klinik checklist export'u | Üretim planı / planlanan olaylar | Gerçek etiket/analiz kanıtı gibi sunulmasını önler. Export şemasını kırmak gerekirse ayrıca sürüm kararı gerekir. |
| Graf yapısı geçerli | Yapı geçerli; içerik kontrol edilmedi | Bugünkü anlam zaten doğru. Yeni uzun uyarı yerine bu kısa ayrım korunabilir. |
| Tamamlandı / Senaryo tamamlandı | Teknik bağlamına göre üretim/oynatma tamamlandı | Modelin isteme uyduğu, videonun doğru olduğu veya klinik sonuç çıktığı anlamına gelmez. |

İptal, yükleniyor, kapanıyor ve hata ayrımları gerçek model kartında korunmalıdır. Şablon düğmesinde artık Şablondan senaryo oluştur, yüklemede Şablon senaryo taslağı hazırlanıyor ve çıktıda hazır şablon açıklaması var; bu düzeltmeler geri alınmamalıdır. Buna rağmen export'ta kalan Klinik gözlem/Gözlem Durumu ve ana paneldeki analiz vaadi tek bir kısa kaynak düzeltme işi olarak F03'e bağlıdır.

### F4. Birleştirilebilecekler ve ertelenebilecekler

**Mevcut bölümlerde birleştirme adayları:** aynı anahtar dialogunun iki girişi; aynı şablona çıkan iki motor seçimi; aynı Stüdyo içindeki teknik deney kartları; davranış ekle ve değiştir/ekle girişlerinin belirgin bir ortak seçiciye yönelmesi. Adım adım/tek metin iki görünümü aynı verinin farklı okunmasıdır; sırf tekrar görüldüğü için birini kaldırmak gerekmiyor.

**Korunacak ayrı sorumluluklar:** ham cevap ve düzenlenmiş kopya; ScenarioInput içerik şeması, ScenarioGraph erişilebilirlik/bitiş kuralları, ScenarioClipPlan süre/sıra/sahne kapsamı; tek klip önizleme ile graf akışı; teknik değerlendirme kaydı ile senaryo taslağı; galeri kaynağı ile uygulama kopyası. Birleştirme bunların kanıt veya kaynak anlamını silmemeli.

**Ertelenebilecekler:** yeni graf için klip planı dönüşümü, kalıcı senaryo/graf arşivi, seçilen yolun kaydı/yeniden oynatımı, tek video dosyası üretimi, tüm eski ekranların temizlenmesi, genel UI/servis altyapısı, yeni hesap/rol sistemi, model yükseltme/karşılaştırma turu. Bunların eksikliği açık kalmalı; ertelenmiş olmaları tamamlandıkları anlamına gelmez. M21/iPhone ölçümü de bu kod incelemesiyle yerine getirilmiş sayılmaz.

## G. Görsel/etkileşim kontrolü ve test/kanıt durumu

### G1. Koddan görülen görünüm ve erişilebilirlik özellikleri

Bu görevde uygulama açılmadı ve erişilmiş bir ekran görüntüsü kullanılmadı. Önceki ekranları görmüş gibi piksel, taşma veya kontrast hükmü verilmedi.

| İncelenen alan | Koddan belirlenen özellik | Kullanıcı etkisi / öneri | Gerçek kontrol ihtiyacı |
|---|---|---|---|
| Başlık/hiyerarşi | Ana panel uzun eski liste; Stüdyo'da örnek graf, debug planı ve çok sayıda test, sonra şablon üretim ayarları var | Birincil görev senaryo üretimiyse akışın başlangıcı görünmüyor; mevcut girişleri amaç sırasıyla düzenlemek gerekir | Küçük ekranda ilk görünüm ve kullanıcının ilk eylemi bulması |
| Lacivert/beyaz dil | Yeni graf/plan/oynatmada #142540 ve beyaz/açık arka plan; eski kartlarda çok sayıda klinik renk | Yeni parçaların mevcut renk dili korunabilir. Resmî kontrast oranı bu görevde ölçülmedi | Açık/gri metinler, pasif kontroller ve videonun üzerindeki yarı saydam kontroller |
| Metin ölçeği | Graf yerleşimi `TextScaler` ile hesaplanıyor; diğer bazı başlık Row'larında esneme yok | Grafik için düşünülmüş koruma var. Yaş başlığı/uzun admin başlığı/düğme satırları için F12 riski | Dar ekran + büyük sistem yazısı; düğmeye metni küçülterek sığdırmama |
| Uzun cevap ve açıklamalar | Ham cevap SelectableText olarak bütünüyle görünür; motor ayrıntıları açılır, JSON alanı max12 satır | Ham veri korunmalı; üretim/sonraki eylem çok aşağı kaçabilir. Mevcut açılır düzenle dengelemek mümkün | Uzun gerçek cevap, klavye açıkken Graf oluştur/hataya erişim |
| Seçili/pasif kontroller | ChoiceChip/Material düğmelerinde selected/onPressed var; yaş/mini kaldırma bazı GestureDetector'lar | Seçimin renk dışında okunabilir/erişilebilir durumu belirgin olmalı | TalkBack/VoiceOver selected adı, klavye odak/geri gezinme |
| Dokunma alanları | Bazı 14 simgeli küçük kaldırma eylemleri; video kontrolünde compact yoğunluk | El ile seçimi zorlaştırabilir; mevcut daha geniş Material hedefleri kullanılabilir | Gerçek parmakla yanlış dokunma ve büyük yazıda kontrol aralıkları |
| Simge adları | Graf yakınlaştırma/ayrıntı kapatma tooltip'leri ve sahne `Semantics(button:true)` var. Video oynat/ses/tam ekran simgelerinde açık tooltip eksik | İyi graf örnekleri korunmalı; video eylemleri açık adlarla tamamlanmalı | Ekran okuyucunun söylediği gerçek adlar; durum değişince güncellenmesi |
| Grafik okunabilirliği | 176 genişlikli kutular, iki satır başlık/özet, iki satır kenar etiketi; tam metin panelde | Kısaltılmış görünüm anlatı kaybı değildir; panelde tam metin var. Çok alternatifte tümünü sığdırma yazıyı küçültür | İki ve daha fazla alternatif, büyük yazı, ilk görünüm, sürükle/yakınlaştır sonrası tümünü göster |
| Grafik bağlantıları | Oklar CustomPaint; metinsel devamlar sahne ayrıntısında | Tam anlamı yalnız görsel çizgiye yüklememek için mevcut metinsel devamları koru | Ekran okuyucuyla bir sahneden devamları anlama; yeni görsel altyapı gerekmez |
| Ayrıntı panelleri | Graf `DraggableScrollableSheet` + ListView ve açık kapatma; teknik açılırlar/sahne listeleri kaydırılır | Tam açıklama ve eylemlere erişim olanağı var | Küçük ekranda panel başlığının/kapamanın görünmesi, kaydırma ve odak |
| Video oranı/kontroller | Önizleme ve graf gerçek aspectRatio; Video Analiz sabit16/9; eski kontrol satırı Wrap değil | Portre video diğer parçalarla tutarlı görünmeyebilir; tek satır dar alana sığmayabilir | Portre/yatay video ve tam ekran yön değiştirme; F12 |
| Boş/yükleniyor/hata | Yeni model/ortak ekran/önizleme/grafta durumlar var; Video Analiz init hatası yalnız log | Yeni örnekler korunmalı, sonsuz spinner F05 düzeltilmeli | Eksik dosya, izin iptali, codec hatası, üretim iptali, yeniden deneme |
| Renk anlamı | Eski risk kartları renk + etiket kullanıyor; yeni graf başlangıç/bitişi simge + metinle ayırıyor | Eski sorun yalnız renk körlüğü değil, kategorinin kapsam dışı anlamı. Yeni graf klinik sınıflama kullanmıyor | Renk olmadan başlangıç/bitiş/dal seçimi anlaşılması; risk sınıflamasını erişilebilir yapıp meşrulaştırmama |
| Klavye | Ortak ekran SingleChildScrollView/SafeArea ve çok satırlı alan; Android activity adjustResize | Klavyeye uyum için temel araçlar var; kesin sorunsuzluk iddiası yok | Klavye açık + en altta hata + Graf oluştur düğmesi; iOS klavye/geri ve uzun teknik JSON |

### G2. Sonraki görsel kontrol için kısa öncelik listesi

Bu liste bir sonraki insan kontrolü içindir; bu görevde hiçbir madde uygulama açılarak denenmedi.

1. **Ortak ekran:** gerçek uzun cevap → normalleştirilmiş kopya → hata/düzeltme; klavye açıkken doğrulama ve grafı açma; dolu taslakla geri çıkış. Kaybolma zaten bildirilmiştir, tekrar kayıp oluşturmak kontrol hedefi olmamalı.
2. **Ana panel/Stüdyo:** dar ekran ve büyük yazıda ilk eylemin bulunması, yaş başlığı ve davranış seçicisi; teknik testlerin ana görevi gölgelememesi.
3. **Video sekmesi:** eksik varsayılan video, bozuk/iptal edilen özel seçim, portre video, küçük kontrol satırı; başka sekmeye geçince ses ve tam ekranda ses simgesi.
4. **Graf:** iki alternatifin ilk açılışta görülmesi; bütün metne panelden ulaşma; büyük yazı ve çok alternatifte ok/etiket ilişkisi; Tümünü göster ve ekran okuyucu sırası.
5. **Klip planı/önizleme:** uzun promptu kopyalama; dosya yok/bulunamadı/hata; büyük yazı; video yüklenirken geri çıkış.
6. **Graf oynatma:** ilk Başlat, kısa dal düğmesi + ayrı ayrıntı, video sonu/arka plan/geri, tamamlandı ve yeniden başlat. Android emülatöründeki önceki A/B tamamlanması, iPhone/M21 kanıtı sayılmaz.

### G3. Mevcut test ve kanıt matrisi

| Kanıt grubu | Kaynak | Gerçekte hedeflenen davranış | Kanıtlamadığı / bu incelemede yapılmayan |
|---|---|---|---|
| Model/graf saf veri kontrolleri | `test/scenario_graph_converter_test.dart`, `scenario_graph_checks.dart`, `scenario_clip_plan_checks.dart` | Metin koruma, farklı alternatif sayıları, hatalı alan/bağlantılar, bitiş/erişilebilirlik, süre/sıra/sahne kapsamı, örnekten dönüşüm | Gerçek modelin anlatısı, görsel UI, dış videonun gerçek süresi/koşulu; eski `*_checks.dart` dosyaları normal `*_test.dart` keşfiyle aynı kabul edilmez |
| Ortak ekran/model demo | `test/scenario_graph_import_screen_test.dart`, `scenario_model_demo_test.dart` | Kontrollü servisle tek çağrı, ham cevap, metadata/kaynak, dış çit/sarmalayıcı, reddedilecek biçimler, hata/iptal/dispose, asset ve dış nesne yolu | Native model yükleme ve gerçek talimat takibi. Taslağı kapatıp yeniden açınca kurtarma beklentisi yok |
| Native runtime adaptörü | `test/llamadart_test_runtime_test.dart`, fixtures | Yayımlanmış paket türleriyle Fake LlamaEngine çağrılarını, CPU/örnekleme/şablon/bağlam parametrelerini denetleme | Gerçek GGUF parser/native token dizisinin doğruluğu veya MiniCPM yayıncı uyumu; fake şablon gerçek cevap değildir |
| Tekli servis/kart testleri | `local_llama_test_checks.dart`, `local_llama_test_card_test.dart`, `test/support/fake_local_llama_runtime.dart` | Durum geçişi, boş çıktı/hata, iptal/kilit/kaynak kapatma ve kart sunumu | Telefon RAM/termal/performans, gerçek native kapanış süresi, içerik uygunluğu |
| İndirici | `test/local_model_download_test.dart` | Kontrollü HTTP ile ayrı dosya, tamamlanmayan aktarım, iptal, başlık/boyut, ortak kilit ve mevcut dosyayı koruma | Gerçek ağda kesinti davranışının ölçümü, resume özelliği veya indirilen ağırlığın anlamsal kalite kanıtı |
| Altı deneme kaydı | `test/d01_evaluation_test.dart` | Test double ile sabit planın önce yazılması; altı bağımsız görev, ham metin/süre/token/hata/kaynak alanları, boş insan değerlendirmesi, iptal | Gerçek model başarı oranı; kayıt alanlarının dolması içerik onayı değildir |
| Video deposu — gerçek dosya sistemi | `test/clip_video_store_checks.dart`; binding testinin DiskStore bölümü | Yalnız teste ait geçici dosyalarda kopya/indeks, göreli yollar, yeniden yükleme, kayıp dosya ve hata halinde önceki kayıt | Galeri sağlayıcısı, codec, gerçek cihaz izinleri. Fixture baytları video çözümü değildir. runAsync/Completer düzeltmeleri korunmalı |
| Video deposu/önizleme — kontrollü platform | `clip_video_binding_screen_test.dart`, `clip_video_preview_screen_test.dart`, `clip_production_plan_screen_test.dart` | Sahte seçici/platform ve kontrollü store ile UI durumu, seçme/değiştirme/iptal, olay sırası, hata, oran, dispose | Gerçek Android/iOS video çözme, bellek ve cihaz dosyalarının varlığı |
| Graf oynatma | `graph_playback_controller_test.dart`, `graph_playback_screen_test.dart`, `support/fake_graph_playback.dart` | Fake oyuncu ile sıra, iki dal, bitiş, eksik video, double end, eski olay, tek canlı oyuncu, suspend/resume, yükleme sırasında çıkış; kısa label fallback'i ve büyük yazı | Gerçek medya bitiş bildiriminin platform davranışı; başarısız pause/close'tan restart toparlanması. Fake close geciktiriliyor ama başarısız olmuyor |
| Kaynak/doğruluk metinleri | `video_analysis_source_test.dart`, `template_source_labels_test.dart` | Kullanıcı videosuna örnek bulgu taşınmaması; tam ekrandan gerçek çıkış kontrolü; şablon etiketleri ve sahte yüzdelerin kaldırılması | Ana panelde kalan yanlış vaatler, tüm eski klinik içeriğin güncelliği, sekme sesi/yaş geri dönüşü ve bozuk video rollback'i |
| Ana ekran smoke | `test/widget_test.dart` | Ana başlık ve temel girişlerin varlığını hedefliyor | İki eski başlık beklentisi güncel UI ile uyuşmuyor (F15). Çalıştırmadan sonuç/başarısız sayısı verilmedi |
| Kayıtlı gerçek model kanıtı | `docs/model_degerlendirme_kanitlari.md` | Önceden erişilmiş Qwen ve MiniCPM için altışar ham kayıt; sabit protokol/süre/token/bitiş/ham cevap ve içerik ihlalleri | Llama için ham kayıt yok; yeni graf demosunun tam ham arşivi yok; genel model başarı oranı ve telefon performansı çıkarılamaz |
| Kullanıcı emülatör gözlemi | Kullanıcının bildirimi ve `docs/DEVAM_NOTU.md` | Modelden grafın gösterilmesi; video bağlama, yeniden açma, önizleme ve A/B yolları; aynı test videosu tekrar kullanılmış | Video içeriği/sürekliliği ve yeni grafın bu videolara bağlandığı kanıtı değil; tüm testlerin geçtiği anlamına gelmez |
| Yaşanmış taslak kaybı | Kullanıcının bu görevdeki açık bildirimi + K09 | Ekran kapanınca cevap kaybı; KD ile neden açıklanıyor | Kaybolan ham cevabın metni/süresi yeniden üretilmedi; boş yerel TXT arşiv sayılmadı |
| Gerçek telefon/iOS | Bu incelemede yeni kanıt yok | Hedef cihazlar M21 4 GB/Exynos 9611 ve iPhone 11 olarak kayıtlı | RAM/tepe RAM, performans, iOS izin/video/native motor davranışı ve fiziksel kullanım ölçülmedi |

Genel bir test turu, yeni hepsi geçti sonucu veya bu görev için statik analiz temizliği iddiası yoktur. Önceki kullanıcı test çıktılarının tamamını kapsayan son commit'e ait tek bir güncel test raporu bu incelemede doğrulanmadı. Sonraki testler yalnız uygulanmasına karar verilen küçük değişikliğin anlamını doğrulamalı; mevcut beklentiler kaldırılarak/süre artırılarak yeşile çevrilmemeli.

### G4. Tamamlanmayan ve tamamlandı sayılmayan kontroller

- Uygulamanın canlı açılışı, ekran görüntüsü/piksel ve gerçek klavye etkileşimi; kontrast oranı ve TalkBack/VoiceOver.
- Yeni Flutter/Dart test, statik analiz veya Android/iOS derleme sonucu. Eksik asset uyarılarının bu ortamda yeni derlemeye etkisi denenmedi.
- Gerçek codec/galeri/kamera ve arka plan/ses davranışının cihazda yeniden üretimi; graf kapanış hatasının gerçek native oyuncuda tetiklenmesi.
- Qwen demo cevabının yeni ham arşivden içerik denetimi; boş TXT bunu sağlamıyor. Önceki 12 model kaydı yeniden cihazdan okunmadı; rapor kanıtı olarak açıkça ayrı tutuldu.
- Native motora giden tam token dizisinin bağımsız dökümü, MiniCPM şablonunun yayıncıyla tam eşleşmesi; bu belirsizliği çözmek için yeni ağ/çıkarım araştırması yapılmadı.
- M21/iPhone 11 RAM, tepe bellek, hız, ısınma ve uzun oturum kararlılığı; kurulu model boyutundan bu değerler hesaplanmadı.
- Sabit kurum listesinin dış kaynaktan güncellik/yetki ve telefon/adres teyidi; kurumlar kullanıcının videosunun analiz sonucu olarak önerilmemeli.
- Normal kullanıcı üretim hakkı, hazırlama/yayınlama yetkisi ve arşiv politikası; bunlar H'deki açık ürün kararlarıdır.

## H. Hocayla netleşmesi gereken ürün kararları

| Karar | Neden gerekli / sabit sınır | Karar verilene kadar korunacak yaklaşım |
|---|---|---|
| Normal kullanıcı senaryo üretebilir mi, yoksa hazırlanan senaryoyu mu deneyimler? | Birincil eylemi ve teknik JSON'un kimde kalacağını belirler. Kullanıcı profesyonel olmak zorunda değil. | Üretim hakkı varsayılarak kaldırılmaz; teknik testlerin gruplandırılması bu yetki kararı değildir. Yeni hesap/rol sistemi kurulmaz. |
| İçerik hazırlayan kişi hangi işlemleri yapar; gözden geçirme/yayınlama sorumluluğu nedir? | Promptlar normal kullanıcıya gösterilmeyecek; debug ve beş dokunuş gerçek yetkilendirme değil. | Mevcut debug kapsamı açık adlandırılır; promptlar hazırlama alanında kalır. Gerçek erişim sistemi ancak somut gereksinimle ele alınır. |
| İlk içerik sürümü yalnız D01 pilotu mu, yoksa 10 kartın tümü mü? | Bugün yalnız D01 için güncel taslak/graf/plan hattı var; eski 12 listeyi yeni 10 saymak yanlış. | Desteklenen kapsam açık söylenir; D02–D10 için eksik koşullar uydurulmaz. Güncel kart listesi kaynak kabul edilir. |
| Yaş seçimi farkındalık açıklaması mı, üretilecek sentetik karakter mi? | Ana panel ve Stüdyo değerleri kısmen bağlı, model demosu sabit30; 12–36 hedef ile 30–36 teknik pilot farklı. | Yaş etiketi klinik beklenti ölçümü diye sunulmaz; bütün yaşlara aynı görev/başarı şartı verilmez. |
| Yapısal geçerli taslağın içerik uygunluğunu kim, hangi kısa ölçütle kontrol eder? | Tek çağrı, ek uyaran yokluğu, alternatiflerin ayrılığı JSON doğrulamasından çıkmaz. | Yapı geçerli sonucu korunur; içerik doğrulandı denmez. Yeni onay ekranı veya otomatik anlamsal puan bu turda zorunlu değil. |
| Geçici taslağın yaşam süresi ve saklama rızası ne olmalı? | Gerçek veri kaybı yaşandı; ham cevap, düzenlenmiş içerik ve graf farklı sürümlerdir. | İlk küçük önlem kazara terk etmeyi engeller. Kalıcı arşiv ihtiyacı ayrıca kararlaştırılır; ham kayıtlar üzerine yazılmaz. |
| Yeni senaryo için klip planı kim tarafından ve nasıl hazırlanacak? | Graf tek başına üretim promptu/süreklilik/klip sırası sağlamaz; dış platform her üretimde en fazla8 sn. | Elle hazırlanmış D01 planı örnek kalır. Yeni grafı eski videolara otomatik bağlama yok. Plan hedefi ile gerçek pencere/süre ayrı doğrulanır. |
| Gösterimin kabul ölçütü nedir? | İki ayrı demo mu, aynı senaryonun videolu uçtan uca deneyimi mi? Cihaz hedefi de kabulü etkiler. | Bugün iki zincir açıkça ayrı sunulur; M21/iPhone doğrulaması iddia edilmez. Dalı mevcut oynatma ekranında kullanıcı seçer; bu karar yeniden belirsizleştirilmez. |

Klinik tanı, risk sınıflandırması ve klinik geçerlilik iddiası eklenmemesi; promptların normal kullanıcıya gösterilmemesi; önce senaryo sonra graf; tek düzeyli dönüştürücü ve dış video üretimi bu karar tablosunda yeniden tartışmaya açılan seçenekler değildir, görevin sabit sınırlarıdır.

## I. En fazla üç küçük değişiklik içeren ilk uygulama turu

Bu rapor düzeltme yetkisi olarak kullanılmadı; aşağıdakiler yalnız öneridir. Üç iş bağımsız ve gözden geçirilebilir tutulmalı; genel refactor, paket/model değişimi, yeni ekran veya veri göçü gerektirmemeli.

| Sıra / bulgu | Küçük değişiklik | Korunacaklar ve hedefli kabul kontrolü | Risk / açık kalan |
|---|---|---|---|
| **1 — F04 / P0** | Mevcut ortak ekranda dolu taslağı kazara terk etmeye karşı geri çıkış koruması. İlk kapsam ekranı kapatma ile sınırlı tutulabilir. | Vazgeçince aynı ham cevap, düzenlenmiş JSON ve doğrulanmış nesne kalır; bilinçli çıkışta servis güvenle iptal/kapatılır. Mevcut sahte servisle hedefli gezinme kontrolü hazırlanmalı. | Orta. OS süreci ölünce kurtarma, kalıcı arşiv ve yeni üretim/örnekle bilinçli değiştirme ayrı kalır; tam veri koruma çözüldü denmez. |
| **2 — F03 / P0, F15** | Ana panelin iki giriş kartını bugünkü işe göre adlandırmak: seçme/izleme ve senaryo taslağı. İlgili ana ekran testinin eski başlık beklentisini gerçek giriş davranışıyla güncellemek. | Gezinme ve gerçek model testleri değişmez. Kullanıcıya otomatik analiz yapıldığı vaat edilmez. Test yalnız yeni metni arayan gevşek bir beklentiye indirgenmemeli; doğru sekmeye giriş korunmalı. | Düşük. Eski 12 davranış içeriği/risk metinleri bu küçük metin turuyla güncel hale gelmez; F01/F02 ayrı P0 içerik işi olarak açık kalır. |
| **3 — F05 / P0** | Video Analiz'de yeni oynatıcı açılışını başarıya kadar aday olarak tutmak; kısa hata durumu ve geç sonuç koruması. | İptal/bozuk video eski seçimi korur; başarısız aday kapanır; özel videoya örnek bulgu verilmez; tam ekran aynı çalışan denetleyiciyi kullanır. Kontrol gerçek video motoru yerine kontrollü platformla yapılmalı. | Orta. Yeni analiz, yeni oynatıcı paketi veya kalıcı eşleme eklenmez. Sekme sesi, iOS izinleri ve gerçek codec testi ayrıca kalır. |

Bu üç işten sonra sıradaki dar içerik işi F01/F02'deki D01 ve ONT-08 anlam uyuşmazlığını ele almaktır; 10 davranışın tamamını tek değişiklikte yeniden yazmak önerilmiyor. F06'daki gerçek graf→klip planı bağlantısı daha büyük ve ürün kararı gerektiren iştir. F09 yaş/seçim ve F11 kapanış hatası gibi belirli teknik yollar ayrı küçük düzeltmeler olabilir; asset/README bakımı F14, önceki uyarıları kesin derleme engeli saymadan yapılabilir.

### Kaynak dizini

Aşağıdaki yollar uygulama köküne göredir. Dosya adının ardından verilen fonksiyonlar, tablolardaki `Kxx` dayanaklarını somutlaştırır. İncelenen içerikler bu rapora taşınarak kod/veri dosyaları değiştirilmedi.

| Kod | Dosya ve başlıca dayanak |
|---|---|
| K01 | [main.dart](../lib/main.dart), [home_screen.dart](../lib/screens/home_screen.dart): `HomeScreen.build`, `PopScope`, `IndexedStack`, `_buildDashboardTab`, `_currentMonth`, `onNavigateToTab`. |
| K02 | [scenarios_data.dart](../lib/models/scenarios_data.dart): `ScenarioModel`, `ScenarioBranchModel`, `ScenariosRepository.allScenarios`, boş `addGeneratedScenario`, ONT-01…12/ageBreakdowns/videoAssets. |
| K03 | [ontology_detail_screen.dart](../lib/screens/ontology_detail_screen.dart): `build`, `_cleanInstruction`, `_cleanCriteria`, Stüdyo/Video eylemleri. |
| K04 | [synthetic_video_studio_screen.dart](../lib/screens/synthetic_video_studio_screen.dart): `initState`, `didUpdateWidget`, `_generateScenario`, `_handleEasterEggTap`, model kartları, `_buildDoctorConfigCard`, `_showOntologyPicker`, `_buildAdminVideoSlicingCard`, `_buildD01EvaluationControls`, export/clipboard. |
| K05 | [llama_model_service.dart](../lib/services/llama_model_service.dart), [local_model_option.dart](../lib/models/local_model_option.dart): `getModelFile`, `isModelDownloaded`, `downloadModel`, `cancelDownload`, `deleteModel`, `generateWithLlama`, model dosya kimlikleri. |
| K06 | [local_llama_test_service.dart](../lib/services/local_llama_test_service.dart), [llamadart_test_runtime.dart](../lib/services/llamadart_test_runtime.dart), [local_llama_test_card.dart](../lib/widgets/local_llama_test_card.dart): istekler/metadata, `run/_execute/cancel/dispose`, `load/generate`, kart durumları ve tanıları. |
| K07 | [scenario_input.dart](../lib/models/scenario_input.dart): `ScenarioInput.fromJson/fromJsonString`, `ScenarioInputAlternative`, `ScenarioInputSource`, `_onlyFields`. |
| K08 | [scenario_graph_converter.dart](../lib/services/scenario_graph_converter.dart): `convert`; [scenario_graph.dart](../lib/models/scenario_graph.dart): kurucu, `validate`, erişilebilirlik ve terminal sahneler. |
| K09 | [scenario_graph_import_screen.dart](../lib/screens/scenario_graph_import_screen.dart): `_modelChanged`, `_demoInputJson`, `_selectType`, `_edited`, `_validate`, `_loadExample`, `_viewGraph`, `_sourceText`, `dispose`. |
| K10 | [scenario_graph_screen.dart](../lib/screens/scenario_graph_screen.dart): asset/nesne `_load`, kaynak etiketi, `_GraphLayout`, `_GraphView`, `_showScene`, `_fit/_zoom`. |
| K11 | [scenario_clip_plan.dart](../lib/models/scenario_clip_plan.dart): `PlannedClip`, süre/sıra kontrolleri, `clipsForScene`, `validateAgainst`. |
| K12 | [D01 senaryo içeriği](../assets/scenarios/d01_scenario_input.json), [D01 grafı](../assets/scenarios/d01_scenario_graph.json), [D01 klip planı](../assets/scenarios/d01_clip_plan.json): ayrı kimlikler ve el yapımı plan koşulları. |
| K13 | [clip_production_plan_screen.dart](../lib/screens/clip_production_plan_screen.dart): `_load`, `_sections`, `_ClipDetails`, `_selectVideo`, `_removeVideo`, `_videoControls`, debug girişleri ve yeniden yükleme. |
| K14 | [clip_video_store.dart](../lib/services/clip_video_store.dart): `ClipVideoBinding`, göreli yol kontrolü, `_serial`, `_read/_save`, `attach/remove`, `fileFor/fileExists`. |
| K15 | [clip_video_preview_screen.dart](../lib/screens/clip_video_preview_screen.dart): `_initialize`, `_control`, `_release`, `dispose`, `ValueListenableBuilder` hata yolu. |
| K16 | [graph_playback_controller.dart](../lib/services/graph_playback_controller.dart), [graph_playback_screen.dart](../lib/screens/graph_playback_screen.dart): `_NativeClipPlayer`, `_choiceLabel`, `start/choose/_loadCurrent/_advance/_releasePlayer/restart/suspend/resume/close`. |
| K17 | [video_analysis_screen.dart](../lib/screens/video_analysis_screen.dart): `_clinicalCases`, `_loadVideoForCurrentCase`, `_pickVideo`, `_onVideoTick`, `_openFullscreen`, örnek/özel video koşulları ve hata UI'si. |
| K18 | [floating_video_controls.dart](../lib/widgets/floating_video_controls.dart), [fullscreen_video_screen.dart](../lib/widgets/fullscreen_video_screen.dart), [expandable_finding_card.dart](../lib/widgets/expandable_finding_card.dart), [finding_notification_pill.dart](../lib/widgets/finding_notification_pill.dart), [models.dart](../lib/models/models.dart): kontroller, paylaşılan controller ve eski örnek rapor tipleri. |
| K19 | [simulation_mode_screen.dart](../lib/screens/simulation_mode_screen.dart), [interactive_player_screen.dart](../lib/screens/interactive_player_screen.dart), [llm_rag_service.dart](../lib/services/llm_rag_service.dart), [scenario_picker_sheet.dart](../lib/widgets/scenario_picker_sheet.dart), [floating_decision_sheet.dart](../lib/widgets/floating_decision_sheet.dart): eski ekranlar, paylaşılan SimulationState, Gemini/fallback yolu. |
| K20 | [synthetic_video_service.dart](../lib/services/synthetic_video_service.dart): `generateSession`, `_buildClinicalPhases`, `_getPhasesForCode`, `SyntheticVideoSession` export'ları, eski doktor şablonu. |
| K21 | [pubspec.yaml](../pubspec.yaml), [video README](../assets/videos/README.md): paket/asset bildirimleri, eski klasör ve hazır video iddiaları. |
| K22 | [age_slider_card.dart](../lib/widgets/age_slider_card.dart), [api_key_dialog.dart](../lib/widgets/api_key_dialog.dart), [institutions_screen.dart](../lib/screens/institutions_screen.dart): yaş seçimi, anahtar ayarı ve statik kurum listesi. |
| K23 | [d01_evaluation_service.dart](../lib/services/d01_evaluation_service.dart), [d01_qwen_v1.json](../assets/evaluations/d01_qwen_v1.json): sabit üç görev, iki tekrar, model/ayar/ham kayıt, boş insan alanları ve safe export. |
| K24 | [test dizini](../test/): G3'te adı verilen kontrol kaynakları; özellikle [widget_test.dart](../test/widget_test.dart), [scenario_model_demo_test.dart](../test/scenario_model_demo_test.dart), [fake_graph_playback.dart](../test/support/fake_graph_playback.dart). |
| K25 | [iOS Info.plist](../ios/Runner/Info.plist), [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml), [Android build.gradle.kts](../android/app/build.gradle.kts): platform hazırlığı. Kurulu image_picker yerel README'sinin iOS bölümü ayrıca okundu; kişisel cache yolu rapora alınmadı. |

### Rapor bütünlüğü ve son sınır

Bu belge bir uygulama/cihaz çalışma raporu değil; kaynak, test beklentisi, kayıt raporu ve açık kullanıcı bildirimini ayıran analizdir. Önceki belgeler silinmedi/değiştirilmedi. Kapsamı tamamlamak için test/çıkarım/uygulama başlatma yoluna gidilmedi. G4'teki kontroller açık bırakıldı; tamamlandı sayılmadı. Düzeltmeye başlanmadı.

Rapor tamamlanırken A–I bölümlerinin ve yerel kaynak bağlantılarının varlığı kontrol edildi; eksik yerel bağlantı bulunmadı. Başlangıçtaki yedi platform değişikliği ve kullanıcı demo klasörü korundu; Git durumuna eklenen tek dosya bu rapordur. Staged içerik ve stash değişmedi. Bu belge tutarlılığı kontrolü uygulama testi/derleme sonucu değildir.
