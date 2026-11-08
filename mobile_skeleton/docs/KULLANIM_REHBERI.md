# Kullanım rehberi

## Hızlı D01 baş hareketi — yerel deneysel yol, 8 Kasım

Video Analizi → Deneysel D01. Galeriden kısa24FPS video seçin; aynı önizleme/controller kullanılır. Yeni yöntem MediaPipe/PnP ve optik akıştır;6D araştırma referansıdır. Çok yüzlü görüntüde **Hedef yüzü belirt** seçeneğini açın, videonun ilk karesinde çocuğun yüzüne bir kez dokunun. Baş çevresine kutu çizilmez. İlerideki bir karede dokunursanız oynatıcı önce başa gelir; ilk karede tekrar belirtin. Tek yüz bulunması çocuk yaşını/kimliğini doğrulamaz. Hedef seçilemezse veya takip kaybolursa eksik poz açık gösterilir.

Çağrı başlangıç/bitişini yalnız duyup işaretleyebiliyorsanız iki ayrı düğmeyle alın. İkisini boş bırakmak geçerlidir; tek işaret bırakmak geçerli değildir. Otomatik ses algılama yapılmaz. Pilot sunucu adresi ve oturumluk ekip anahtarını girip **Pilot analizi başlat** deyin; adres senaryo sunucusu tercihini değiştirmez. Hızlı runtime yerelde yapılandırılmalı; uzak sunucuya bu değişiklik dağıtılmadı.

Tamamlanınca sonuç görünür alana kayar. Poz/akış/kayıp/belirsiz kapsamı, poz ölçülemeyen zaman aralıkları, ham ve EMA adayları ayrı gösterilir. Akışta mutlak açı yoktur; null bitiş tamamlanmış dönüş değildir. Çağrı varsa yalnız önce/sıra/sonra ilişkisi vardır; çağrı öncesi hareket sonradan yeni tepki sayılmaz. Çağrı bilinmiyorsa yalnız hareket sonucu gösterilir. Adayın bilinen başlangıcına dokunma aynı videoyu duraklatılmış olarak görünür kılar; yeni video açmaz. Ölçüm süreleri → ölçüm özetini kopyala ile anahtar içermeyen yerel kabul kaydı alınabilir.

Yeni yerel Python ölçümlerinde iki videoda da başlangıç bulunmasına rağmen ilk bitiş eksik kaldı; bu sınırlama gizlenmez. Bunlar klinik/isme tepki/doğru kişiye yönelme sonuçları değildir. Eski6D/API1.0/1.1 profil ve işaretli istek desteği backend/serviste korunur; aşağıdaki önceki ROI yönergeleri o araştırma yoluna aittir. Yeni mobil arayüz henüz normal PowerShell testleri ve son emülatör kabulüyle doğrulanmadı. Kesin yerel başlatma/kabul komutları backend/D01_PILOT.md başındadır.

## Yeni kullanıcı işaretli D01 videosu — API 1.1 yerel bağlantısı

Video Analizi → Deneysel D01 baş hareketi analizi ekranında galeriden videoyu seçin. İki hazır örnek için **Yeni video için işaretleme** kapalı kalsın; sunucu mevcut otomatik ROI/API1.0 yolunu kullanır. Profil dışı video için bu anahtarı açın. Önizlemede çocuğun başını ve çevresindeki payı kapsayan bir dikdörtgen çizin; görüntü boşlukları ROI'ye dahil edilmez. Çizim videoyu duraklatır. ROI'nin doğru çocuğu/başın tamamını kapsadığını insan kontrol eder; uygulama otomatik kişi takibi veya anlamsal onay yapmaz.

Mevcut zaman kontrolleriyle çağrı başlangıcına gidip **Bu konumu çağrı başlangıcı yap**, sonra bitişe gidip **Bu konumu çağrı bitişi yap** düğmelerini kullanın. Bunlar oynatıcının o anki konumudur; gerçek kare PTS'si veya bağımsız AV senkron doğrulaması değildir. Video değişince ROI, çağrı işaretleri ve önceki sonuç temizlenir; seçimin iptali/açılış hatası mevcut videoyu korur. Eksik/ters veya video süresinin dışındaki işaretlerle yeni analiz düğmesi etkinleşmez.

Pilot adresini ve yalnız oturumluk ekip anahtarını girip açıkça başlatın. Özel yol24FPS/en fazla30sn/25MiB sınırındadır; sunucu gerçek video boyutunu ve süre/zaman çizgisini modelden önce denetler.202 iş kabulüdür, başarı değildir. Sonraki FPS/ROI/çağrı aralığı hatası aynı iş üzerinde gösterilir; otomatik yeni yükleme yapılmaz. Bağlantı kesilirse aynı iş kimliğini yeniden takip edin; bu sunucu işinin iptali değildir. Gerçek sunucuda bu yolun kullanılabilmesi için backend/Python API1.1 değişikliklerinin ayrıca bulunması gerekir; bu görev uzak dağıtım yapmaz.

Sonuçta analiz edilen ROI/çağrı işaretleri, ham ve EMA adayları, çağrı başlangıcı/bitişine göre zaman farkları gösterilir. Negatif fark hata veya klinik sonuç değildir. Adaya dokunmak aynı videoda başlangıca gider, duraklatmayı korur ve önizlemeye kaydırır. Aday bulunmayan completed sonuç desteklenir; “tepki yok” sınıfı değildir. İş/hash, kaynak ve işaretler sözleşmeyle uyuşmazsa sonuç uygulanmaz.

Yerel kabul denemesi: önce hedefli test/analizi normal PowerShell'de çalıştırın; ardından API1.1 backend ile daha önce profillenmemiş kısa24FPS videoda ROI ve iki çağrı işareti →202 → durum takibi → completed/boş aday veya aday sonucu → adaya git/duraklat/kaydır akışını kontrol edin. Sonra iki hazır örneği otomatik modda açın. Bu yeni mobil yol gerçek videoyla henüz doğrulanmadı; bu oturumda Flutter komutları çıktı vermeden bekledi ve yalnız başlatılan komutlar iptal edildi.

Bu uygulamanın iki ana alanı **Video Analizi** ve **Simülasyon ve Eğitim**’dir.
Senaryo/prompt hazırlama ve model karşılaştırması proje ekibinin araçlarıdır.
Üretilen anlatı ve planlar taslaktır; tanı, klinik puan veya gözlenmiş davranış değildir.


Bu uygulamanın iki ana alanı **Video Analizi** ve **Simülasyon ve Eğitim**’dir.
Senaryo/prompt hazırlama ve model karşılaştırması proje ekibinin araçlarıdır.
Üretilen anlatı ve planlar taslaktır; tanı, klinik puan veya gözlenmiş davranış değildir.

## Deneysel D01 baş hareketi analizi — ekip pilotu

**Menü:** Video Analizi → Deneysel D01 baş hareketi analizi. Bu araç genel Video Analizi/Gemini analizi değildir. Yalnız backend'in `d01-first-reviewed` ve `d01-second-reviewed` hash profilleri desteklenir; diğer videolara otomatik ROI uygulanmaz. Paketli D01 videolarının tamamı destekleniyor sanılmamalıdır; ikinci denetlenmiş video `assets/videos/d01_name_turning/20261024200833.mp4` dosyasıdır.

1. Yerel backend'i `backend/D01_PILOT.md` içindeki Python/ağırlık/resmî kaynak ayarlarıyla, `PILOT_D01_ENABLED=true`, oturumluk `TEAM_ACCESS_KEY` ve bu denemeye ayrılmış yeni iş köküyle hazırlayın. Önceki650 sn gerçek koşu nedeniyle bu denemede açık `PILOT_D01_TIMEOUT_MS=900000`, `PILOT_D01_KILL_GRACE_MS=10000` kullanın; .env/varsayılanları değiştirmeyin. Bu backend CPU işi ve Python ortamı gerektirir; mevcut Node-only Docker imajı tek başına yeterli değildir. Tamamlanmış doğrulama betiği kendi backend'ini kapatır; mobil deneme için dinleyen yerel backend ayrıca gerekir. Bu tur backend/model başlatılmadı.
2. Denetlenmiş videoyu emülatörün galerisinden seçilebilir şekilde cihaza aktarın; uygulama paketindeki assetler kendiliğinden galeride görünmez. “Video seç” ile açın, önizleyin. Açılış hatası veya seçim iptali önceki çalışan videoyu/sonucu korur; başarılı değişim eski sonucu ve yalnız istemci takibini temizler.
3. Pilot adresine Android emülatörde `http://10.0.2.2:8000` (backend farklı porttaysa o port), ekip anahtarına aynı backend oturumunun anahtarını elle girin. İkisi de bu ekran oturumundadır; senaryo sunucusunun adresi/tercihleri değişmez. Debug derlemede emülatör/loopback HTTP izinlidir; release izinleri genişletilmedi. Bu düz HTTP erişimi yerel ekip denemesi içindir; internet üzerinde gerçek anahtarla kullanılacak HTTPS kurulumu yerine geçmez.
4. **Pilot analizi başlat** düğmesi multipart yükler,202 ile iş kimliği alır;5 saniye aralıklarla önceki sorgu bittikten sonra durum sorar. Birkaç dakika sürebilir. Sunucu kare ilerlemesi bildirmiyorsa yüzde/zaman tahmini yapılmaz. İşlem başına HTTP beklemesi30 sn; istemci takip sınırı20 dk. Bağlantı hatasında yeni analiz otomatik başlamaz; iş kimliği varsa **Aynı işi yeniden takip et** yalnız GET takibini sürdürür.
5. Completed sonrasında ham ve EMA α=.50 adaylarını ayrı inceleyin. **Aday aralığı** ve daha sonraki **doğrulama zamanı** farklıdır. Adaya dokunmak aynı videoda başlangıca gider ve duraklatır; oynatma kendi kontrolünüzdedir. Eksik/ters/süre dışı aralıkta kısayol kapalıdır. Hareket adayları isme tepki veya doğru hedef sınıflandırması değildir. Çağrı zamanları gönderilmez; bilinmeyen değerler sıfır/tepki yok sayılmaz. Yerleşme sonuçları fiziksel hareket bitişini kanıtlamaz.
6. **Sunucudaki işi iptal et** ayrı DELETE isteğidir;202 yalnız isteğin kabulüdür, kapanış durumu ayrıca beklenir. Ekrandan çıkmak/video değiştirmek sunucu işini iptal etmez. İş kimliğini operatör incelemesi için saklayın; bu tur iş geçmişi/analiz sonucu kalıcılığı eklenmedi. Anahtar kaydedilmez, dışa aktarılmaz veya loglanmaz.

Normal Windows PowerShell'de, `mobile_skeleton` dizininde (bu tur ortam engeli nedeniyle çalıştırılarak doğrulanmadı):

```powershell
& 'C:\dev\flutter\bin\flutter.bat' analyze --no-pub
& 'C:\dev\flutter\bin\flutter.bat' test --no-pub test/d01_pilot_service_test.dart test/d01_pilot_panel_test.dart test/video_analysis_source_test.dart test/studio_sections_test.dart
# Kontroller geçtikten ve yerel backend hazırlandıktan sonra kullanıcı başlatır:
& 'C:\dev\flutter\bin\flutter.bat' run --no-pub --dart-define=D01_PILOT_SERVER_URL=http://10.0.2.2:8000
```

İlk cihaz kontrolünde yeni iş kimliği/gerçek yükleme, completed sayımları, ham/EMA ayrı listeler, duraklatılmış zaman kısayolu ve video değiştirme kontrol edilir. İptal/ekran kapanışı sunucuya iptal gönderme bakımından ayrı sınanmalıdır. Önceki gerçek yerel API koşusu yeni mobil arayüzün çalıştırıldığı anlamına gelmez.

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
| Stüdyo: **1. Hazırla** | Tek form: bir veya daha çok güncel davranış, 12–18 / 18–24 / 24–36 ay gruplarından biri, ortam ve isteğe bağlı ek yönerge. | Sunucu motorunu seçin; yaş grubunu açıkça seçin, kartları kontrol edin ve ortamı yazın. Düzeni seçip isteği doğrulayın. | Değişmez istek; normal üretim ve A/B/C bunu aynı şekilde kullanır. |
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

Yaş grubu kimlikleri sürümlü sözleşmedir: `12_18` = 12 ≤ ay < 18, `18_24` = 18 ≤ ay < 24, `24_36` = 24 ≤ ay ≤ 36. Yeni üretimde tek bir ay değeri gönderilmez ve grup seçimi zorunludur. Eski taslaktaki geçerli ay yalnız yeni istek hazırlanırken bu aralıklara eşlenir; taslaktaki tarihsel ay, ham cevap ve anlatı değiştirilmez. Eksik/geçersiz eski yaşta kullanıcı grup seçer. Bu gruplar klinik yaş uygunluğu veya her kart için üretim desteği kanıtı değildir.

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
