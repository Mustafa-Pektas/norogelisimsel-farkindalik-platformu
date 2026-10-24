# Nörogelişimsel Farkındalık Projesi — 10 Davranış Kartı

Sürüm 0.2 • 11 Ekim 2026 • Senaryo ve video etiketleme taslağı

## Sürüm değişiklikleri

- D01–D08 korundu.
- D09: Oyuncağı işlevine uygun kullanma yerine nesneyi kaba yerleştirme seçildi.
- D10: Tekrarlayan gövde sallama yerine kalemle kendiliğinden karalama seçildi.
- Eski D09/D10 etiketleri yeni kartlara otomatik taşınmaz; davranış kimliği yanında kart sürümü tutulur.
- Bu sürüm tekrarlayıcı hareketleri kapsamaz; bu alan hakkında sonuç üretmez.
- v0.1 tarihsel taslaktır; güncel uygulama dayanağı v0.2 dosyasıdır.

## Amaç ve kapsam

Bu kartlar, sentetik videolarda gözlenebilir olayları tanımlamak ve analiz prototipini geliştirmek içindir. Klinik ölçek, tanı aracı veya doğrulanmış gelişimsel puanlama sistemi değildir. Kaynaklardaki davranış örneklerinden hareketle aşağıdaki görevler ve karar kuralları proje için tasarlanmıştır; kaynakların özgün puanlaması aktarılmamıştır.

İlk teknik pilot için 30–36 aylık çocuk temsili önerilir. Bu, 12–36 aylık nihai kapsamı daraltan bir uygulama başlangıcıdır; bütün yaşlarda aynı görev, süre veya başarı beklentisi kullanılmaz. Gerçek çocuklarla çalışma için görevlerin uzman tarafından yaşa ve bireysel koşullara uyarlanması gerekir. Kaynak yaşı 'bu yaştan küçük çocuk yapamaz' sınırı değildir. Sentetik karakterin yaşı gelişimsel kanıt oluşturmaz.

## Ortak sonuç sözlüğü

| Durum | Anlam |
|---|---|
| Gözlendi | Geçerli fırsatta tanımlanan olay için yeterli görünür/işitilir kanıt var. |
| Gözlenmedi | Geçerli fırsat ve yeterli kayıt var; tanımlı gözlem penceresinde hedef olay görülmedi. Beceri yok anlamına gelmez. |
| Belirsiz | Fırsat ve kayıt var, fakat olayın türü, hedefi veya bağlamı kesin ayrıştırılamıyor. |
| Değerlendirilemedi | Fırsat oluşmadı, gerekli kayıt eksik veya görev koşulları bozuldu. |

Geçerli pencere içinde açık kanıt varsa olay kaydedilir; pencerenin kalanında kayıt kaybı varsa ayrıca belirtilir. Açık kanıt bulunmadığında temel görünürlük/uyaran eksikliği varsa 'değerlendirilemedi', esas sorun yorumun ayırt edilememesiyse 'belirsiz' seçilir. Geçersiz denemeye 'gözlenmedi' verilmez.

## İlk pilotun süre düzeni — mühendislik seçimi

- 1, 2, 6, 7 ve 8: İpucu/model tamamlandıktan sonra 10 saniyelik kesintisiz gözlem. İpucu sırasında başlayan yanıtlar da saklanır. Model kart 6'da yetişkinin hareketidir.
- 3, 4, 5, 9 ve 10: Koşullar hazır olduktan sonra 20 saniyelik gözlem fırsatı. Malzemeye ilgisizlik veya erişim sorunu ayrıca ele alınır. Daha kısa kayıt kısmi gözlem olarak saklanır; tam pencere içinde gözlenmedi gibi sunulmaz.

Bu süreler klinik gecikme veya normal/anormal sınırı değildir. Pilotun kayıtları incelendikten sonra sürüm kontrollü biçimde değiştirilebilir. 10 saniyelik pencere varsa 8 saniyelik klipten '10 saniyede gözlenmedi' sonucu üretilmez. Uyaran ile yanıt arasındaki kesmeler denemeyi bozabilir. 10 kartın bütün koşulları iki dakikalık tek kayda sığdırılmak zorunda değildir.

Tepki süresi sayısal kaydedilir; hızlı/gecikmeli gibi sınıflara gelişimsel anlam yüklenmez. İlk turda 1, 2, 6, 7 ve 8 için farklı bölümlerde iki geçerli deneme hedeflenebilir. Bu da norm veya zorunlu klinik tekrar sayısı değildir. Spontan iletişim/oyun için ayrı fırsatlar kaydedilir. Birden fazla denemede özet: geçerli deneme sayısı, gözlenen sayısı, ayrı belirsiz/değerlendirilemeyen sayıları ve tek tek sürelerdir.

## Etiketleme ve doğrulama

Her kayıtta davranış kimliği, kart sürümü, klip kimliği, yaş temsili, gerçek/sentetik bilgisi, gözlem başlangıç/bitişi, uyaran zamanı, yanıt zamanı, sonuç, alt yanıt, görünürlük ve gerekçe tutulur. Olay sınırları saniye olarak kaydedilir. Model güven skoru sonuç durumunun yerine geçmez. İnsan etiketleyiciler aynı örnekleri bağımsız inceler; görüş ayrılıkları ve nedenleri kaydedilerek kartlar düzeltilir. Bu kartlar henüz etiketleyiciler arası uyumla doğrulanmamıştır.

Üretim promptu veya senaryo düğümü hedef davranışı söyler; gerçekleşen davranışı kanıtlamaz. Uçan nesne, kendiliğinden hareket veya bozuk anatomi hedef olaya müdahale ediyorsa ilgili deneme dışlanır. Tek olay farklı kartlarla kesişirse bağlantısı kaydedilir; bağımsız risk puanları gibi toplanmaz. Otomatik sonuçlar başlangıçta insan onaylıdır. Klinik kırmızı/yeşil puan veya toplam risk puanı bu sürüme dahil değildir.

## 1. İsme tepki verme — D01

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | İlk pilotta 30–36 ay; daha küçük yaşlar için ayrı görev uyarlaması gerekir. Yaş, bu kartta klinik eşik değildir. |
| Senaryo | Çocuk oyuncağıyla ilgilenirken yetişkin, çocuğun adını bir kez doğal sesle söyler. Dokunmaz, el sallamaz veya eşzamanlı başka yönerge vermez. |
| Geçerli gözlem koşulu | Çağrı duyulur; çağıran kişinin konumu bilinir; çocuk çağrıdan önce zaten ona yönelmiş değildir. Çağrı öncesi ve sonrası kesintisiz görünür. |
| Gözlendi | Çağrı sonrasında yetişkine belirgin yönelme veya açıkça yetişkine yönelik sesli/sözel yanıt görülür. Baş yönelmesi, sesli yanıt ve yapılan işi durdurma ayrı alt alanlarda kaydedilir. Yalnızca duraklama, bağlantısı açık değilse belirsiz bırakılır. |
| Gözlenmedi | Geçerli çağrıdan sonra tanımlı pencerede belirgin yanıt görülmez. Bu sonuç yalnızca bu denemeye aittir. |
| Belirsiz | Baş döner ancak hedefin yetişkin mi başka bir uyaran mı olduğu anlaşılamaz; sesli yanıtın muhatabı belirsizdir. |
| Değerlendirilemedi | Ses yoktur/anlaşılmaz; çocuk zaten yetişkine dönüktür; çağrıyla aynı anda dokunma veya başka dikkat çekici uyaran vardır; kritik bölüm kesilmiştir. |
| Kaydedilecek ölçüler | Çağrı başlangıcı/bitişi; yanıt başlangıcı; yanıt türü; yönelme hedefi. Gecikme için referans çağrının bitişidir; adı bitmeden başlayan yanıt ayrıca işaretlenir. İlk otomatik kapsam yalnızca baş yönelmesi olabilir; bu durumda çıktı 'isme yönelme' diye adlandırılır. |
| Kaynak dayanağı | S4; görev ve karar kuralları proje tasarımıdır. |

## 2. Yetişkinin işaret ettiği hedefe yönelme — D02

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | İlk pilot 30–36 ay; daha küçük yaş uyarlamalarında hedef sayısı, uzaklık ve ipucu türü ayrı kaydedilir. |
| Senaryo | İki sabit nesne görünür. Çocuk başka yere bakarken yetişkin bunlardan birini işaret eder ve 'Bak' der; hedefin adını söylemez. İşaret+bakış ile yalnızca bakış görevleri karıştırılmaz. |
| Geçerli gözlem koşulu | Yetişkinin eli, hedef ve çocuğun yüzü/başı aynı kayıtta seçilir. Çocuk başlangıçta hedefe bakmıyordur; hedef kendiliğinden hareket etmez. |
| Gözlendi | İşaret sonrasında çocuk doğru hedefe belirgin biçimde yönelir. Yetişkine tekrar bakması zorunlu ölçüt değildir. |
| Gözlenmedi | Geçerli fırsatta hedefe yönelme görülmez; yalnızca yetişkine bakma veya başka nesneye yönelme ayrı yanıt olarak kaydedilir. |
| Belirsiz | Baş hedef tarafına döner ancak yakın duran iki nesneden hangisine yöneldiği ayırt edilemez. |
| Değerlendirilemedi | Hedef kadraj dışıdır; yetişkinin işareti görülmez; çocuk zaten hedefe bakıyordur; hedef hareket/sesle kendi başına dikkat çekmiştir. |
| Kaydedilecek ölçüler | İşaret başlangıcı; hedef kimliği; ilk yönelme hedefi; gecikme. Baş yönü ile gerçek bakış hedefi aynı değişken kabul edilmez. |
| Kaynak dayanağı | S4; görev ve karar kuralları proje tasarımıdır. |

## 3. İstemek için işaret etme — D03

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | CDC 15 ay listesinde istemek/yardım için işaret etme örneği vardır. Bu, tek denemelik başarı sınırı değildir; pilot 30–36 ay. |
| Senaryo | Güvenli oyuncak görünür fakat doğrudan erişilemez konumdadır. Çocuğun oyuncağa ilgisi gözlenir; yetişkin erişilebilir ve bekler. Yiyecek/su gibi temel ihtiyaçlar engellenmez; 'işaret et' yönergesi verilmez. |
| Geçerli gözlem koşulu | El/parmak, hedef ve yetişkin görünür; nesneye ilgi ve isteme fırsatı vardır. Çocuğun ilgilenmediği oyuncağa işaret etmemesi geçerli olumsuz deneme sayılmaz. |
| Gözlendi | Hedefe yönelik açık işaret hareketi vardır ve erişilemeyen nesne/iletişim akışı isteme yorumunu destekler. Sözel isteme olabilir; yetişkine göz teması zorunlu tutulmaz. |
| Gözlenmedi | Geçerli fırsatta işaret görülmez. Sözel isteme, açık el uzatma veya yetişkini çekme varsa 'başka isteme biçimi' kaydedilir; iletişim yok diye etiketlenmez. |
| Belirsiz | Parmak görünmez; uzanma ve işaret ayrılmaz; isteme ile paylaşma bağlamı ayrıştırılamaz. |
| Değerlendirilemedi | Nesne erişilebilirdir; çocuk ilgilenmez; el/nesne görünmez; yetişkin çocuğun elini yönlendirir. |
| Kaydedilecek ölçüler | Hedef; işaret başlangıcı; el biçimi; isteme bağlamını destekleyen olaylar; alternatif iletişim türü. Nesnenin verilmesi tek başına önceden var olan niyeti kanıtlamaz. |
| Kaynak dayanağı | S1; görev ve karar kuralları proje tasarımıdır. |

## 4. Hayali oyun — mış gibi yapma — D04

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | Basit hayali eylem ile nesneyi başka bir şey yerine kullanma ayrılır. CDC 30 ay listesinde nesne yerine koyma örneği vardır; bütün hayali oyunların başlangıç yaşı kabul edilmez. İlk pilot 30–36 ay. |
| Senaryo | Oyuncak bebek ve boş oyuncak fincan sunulur. Yetişkin aynı hareketi önceden göstermez, 'bebeğe içir' demez; çocuğun oyunu gözlenir. |
| Geçerli gözlem koşulu | Çocuğun oyuncaklara erişimi ve oyun fırsatı vardır. El, fincan ve bebeğin yüzü görünür; sahne kesintisizdir. |
| Gözlendi | Çocuk boş fincanı bebeğin ağzına götürüp içirme eylemini canlandırır. Sadece nesnelerin kısa süreli teması yetmez; eylem dizisi hayali kullanımı açıkça desteklemelidir. |
| Gözlenmedi | Geçerli oyun fırsatında tanımlanan hayali eylem görülmez. Oyuncakları keşfetmesi başka oyun olarak kaydedilir; hayali oyun becerisi yok sonucuna gidilmez. |
| Belirsiz | Fincan bebeğe yaklaşır ama bunun içirme mi rastlantısal temas mı olduğu belli değildir. |
| Değerlendirilemedi | Yetişkin aynı eylemi hemen önce modellemiştir veya açık yönerge vermiştir; kritik nesneler görünmez; kullanılabilir oyun fırsatı oluşmamıştır. |
| Kaydedilecek ölçüler | Eylem başlangıç/bitişi; nesne ve hedef; model/yönerge varlığı; basit hayali kullanım/nesne yerine koyma alt türü. Otomatik ölçüm için nesne ve el ilişkisi gerekir. |
| Kaynak dayanağı | S2, S3; görev ve karar kuralları proje tasarımıdır. |

## 5. Paylaşmak için elindeki nesneyi gösterme — D05

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | CDC 15 ay listesinde sevdiği nesneyi gösterme örneği vardır. Pilot 30–36 ay; tek video yaş normu yerine geçmez. |
| Senaryo | Çocuk kolayca kullanabildiği bir oyuncakla oynar; yetişkin yakınında ve erişilebilirdir. 'Bana göster/ver' demez; yardım gerektiren kapalı kutu kullanılmaz. |
| Geçerli gözlem koşulu | Nesne çocuğun elindedir; yetişkinin konumu bilinir; yardım veya teslim etme talebi yoktur. Kol ve nesne görünür. |
| Gözlendi | Çocuk nesneyi yetişkinin görüşüne sunar; yönelim, seslenme veya iletişim dizisi paylaşım yorumunu destekler. Nesneyi mutlaka bırakması veya göz teması kurması gerekmez. |
| Gözlenmedi | Geçerli fırsatta paylaşım amaçlı gösterme görülmez. Nesneyi yetişkine verme ayrı hareket olarak kaydedilir. |
| Belirsiz | Nesneyi kaldırır fakat muhatap belli değildir; gösterme, teslim etme ve yardım isteme ayrıştırılamaz. |
| Değerlendirilemedi | Yetişkin nesneyi istemiştir; çocuğun nesneyi tutuşu görünmez; yetişkin erişilebilir değildir; yardım gereksinimi senaryoyu baskılar. |
| Kaydedilecek ölçüler | Nesne kimliği; sunma yönü; başlangıç/bitiş; yetişkin konumu; iletişim ipuçları; nesnenin elde tutulması/teslim edilmesi. |
| Kaynak dayanağı | S1, S4; görev ve karar kuralları proje tasarımıdır. |

## 6. Basit motor hareketi taklit etme — D06

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | Pilot 30–36 ay. Seçilen model hareketinin yaşa/motor olanaklara uygunluğu ayrıca belirlenir; tüm hareketler eşdeğer sayılmaz. |
| Senaryo | Çocuk başlangıçta el çırpmıyorken yetişkin iki kez el çırpar, sonra ellerini indirip bekler. Sözel davet kullanılırsa ayrı koşul olarak kaydedilir. |
| Geçerli gözlem koşulu | Çocuğun model hareketini görebildiği anlaşılır; iki kişinin elleri görünür; çocuk aynı hareketi önceden yapmıyordur. Fiziksel yardım yoktur. |
| Gözlendi | Model hareketinden sonra çocuk aynı temel hareket yapısını üretir: ellerin birbirine yaklaşması ve görünür birleşme/temas. Hız ve tekrar sayısının birebir aynı olması gerekmez. |
| Gözlenmedi | Geçerli model sunumundan sonra eşleşen hareket görülmez; farklı hareket ayrı kaydedilir. |
| Belirsiz | Eller örtüşür; hareketin eşleşmesi belirsizdir; çocuk modelden önce de aynı hareketi yapıyor olabilir. |
| Değerlendirilemedi | Çocuk model sunumuna erişememiştir; model elleri görünmez; yetişkin çocuğun ellerini hareket ettirmiştir. |
| Kaydedilecek ölçüler | Model başlangıç/bitişi; çocuk hareketi başlangıcı; gecikme; hareket eşleşmesi; tekrar sayısı; destek türü. Poz benzerliği tek başına sosyal taklit niyetini kanıtlamaz. |
| Kaynak dayanağı | S4; görev ve karar kuralları proje tasarımıdır. |

## 7. Gülümsemeye karşılık verme — D07

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | Pilot 30–36 ay; bu kart yaşa dayalı gülümseme eşiği koymaz. |
| Senaryo | Çocuk yetişkinin yüzüne yönelmişken yetişkin doğal biçimde gülümser. Aynı anda gıdıklama, komik oyuncak, sesli şaka veya başka güçlü uyaran kullanılmaz. |
| Geçerli gözlem koşulu | Her iki yüz seçilir; çocuk yetişkinin gülümsemesini görebilir; çocuk zaten gülümsemiyordur. |
| Gözlendi | Yetişkin gülümsemesinden sonra çocukta görünür gülümseme başlangıcı vardır. 'Zaman bakımından ilişkili karşılık' kaydedilir; içsel duygusu kesin olarak çıkarılmaz. |
| Gözlenmedi | Geçerli ve görünür etkileşimde yeni gülümseme görülmez. Bu, genel sosyal tepki yok anlamına gelmez. |
| Belirsiz | Ağız hareketinin gülümseme mi konuşma mı olduğu anlaşılmaz; başka uyaranın etkisi dışlanamaz. |
| Değerlendirilemedi | Yüz profilde/örtülüdür; çocuk yetişkini görmemiştir; zaten gülümsüyordur; eşzamanlı gıdıklama gibi uyaran vardır. |
| Kaydedilecek ölçüler | Yetişkin ve çocuk gülümsemesi başlangıç/bitişi; gecikme; yüz görünürlüğü; eşzamanlı uyaran. Yalnızca ağız köşesi mesafesinden kesin etiket üretilmez. |
| Kaynak dayanağı | S4; görev ve karar kuralları proje tasarımıdır. |

## 8. Jest desteği olmadan tek basamaklı sözel yönergeyi yerine getirme — D08

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | CDC 18 ay listesinde jestsiz tek basamaklı yönerge örneği vardır. 15 ay listesindeki jest+söz göreviyle aynı koşul sayılmaz. Pilot 30–36 ay. |
| Senaryo | Araba çocuğun erişimindeyken yetişkin 'Arabayı bana ver' der. Eliyle arabayı işaret etmez, isteme için açık el uzatmaz ve hareketi modellemez. |
| Geçerli gözlem koşulu | Yönerge duyulur; dil/görev bilgisi bilinir; doğru nesne erişilebilir ve yetişkine teslim mümkündür. Çocuk zaten teslim hareketini başlatmamıştır. |
| Gözlendi | Çocuk doğru nesneyi yetişkine teslim eder. Başlama ve tamamlanma ayrı kaydedilir; nesneyi yalnızca kaldırması tamamlama sayılmaz. |
| Gözlenmedi | Geçerli yönergede hedef eylem tamamlanmaz. Yanlış nesne, yalnızca başlama veya farklı eylem ayrı yanıt olarak kaydedilir. |
| Belirsiz | Nesne kimliği ya da teslim anı görünmez; çocuğun eylemi yönergeden önce başlamış olabilir. |
| Değerlendirilemedi | Yönerge anlaşılmaz; hedef erişilemez; yetişkin işaret/model/fiziksel yardım sağlar; kayıt teslimden önce kesilir. |
| Kaydedilecek ölçüler | Yönerge bitişi; eylem başlangıcı ve tamamlanması; seçilen nesne; destek varlığı. Sonradan jest verilirse ilk jestsiz pencere kapanır ve yeni destekli koşul açılır. |
| Kaynak dayanağı | S1, S2; görev ve karar kuralları proje tasarımıdır. |

## 9. Nesneyi bir kaba yerleştirme — D09

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | CDC 12 ay listesinde bir nesneyi kaba koyma örneği vardır. Bu bir başlangıç yaşı veya tek denemelik klinik eşik değildir. İlk teknik pilot 30–36 ay; bu yaşta görevin kolay olması gelişimsel ayırt ediciliğini sınırlayabilir. |
| Senaryo | Büyük bir blok ve bloğun rahatça sığdığı geniş ağızlı, alçak bir kutu sabit yüzeyde sunulur. Yetişkin koyma hareketini önceden göstermez ve “kutunun içine koy” yönergesi vermez. |
| Geçerli gözlem koşulu | Çocuk nesneye ve kutuya erişebilir; malzemeyle etkileşim fırsatı oluşmuştur. El, blok, kutu ağzı ve sonuç konumu seçilir. Kutu boş veya yerleştirmeye uygundur. |
| Gözlendi | Çocuk bloğu eliyle kutunun ağzına taşır ve kutunun içine bırakır. El–nesne–kutu ilişkisi görünür biçimde doğrulanır. Yalnızca kutunun içinde blok görmek yeterli değildir. |
| Gözlenmedi | Geçerli fırsat ve yeterli kayıt vardır; hedef yerleştirme tamamlanmaz. Bloğu tutma, kutuya yaklaştırma veya dışarı bırakma ayrı alt eylemler olarak kaydedilir. Sonuç becerinin yokluğunu göstermez. |
| Belirsiz | Bırakma anı kısa süre örtülür veya bloğun kutunun içine mi arkasına mı düştüğü ayırt edilemez; rastlantısal düşme ile kontrollü yerleştirme ayrılmaz. |
| Değerlendirilemedi | Malzemeye erişim/ilgi ve geçerli etkileşim fırsatı yoktur; kutu uygun değildir; kritik el–nesne ilişkisi görünmez; yetişkin fiziksel yardım verir; belirgin üretim hatası vardır. Yönerge veya model verilmişse bu kartın kendiliğinden koşulu yerine ayrı destekli görev kaydedilir. |
| Kaydedilecek ölçüler | Nesneyi tutma, kutuya taşıma ve bırakma zamanları; sonuç konumu; deneme ve tamamlama sayısı; gözlenebilir süre; yönerge/model/fiziksel destek. |
| Kaynak dayanağı | S8; görev ve karar kuralları proje tasarımıdır. |

Nesneyi kaba koyma, sözel yönerge takibiyle aynı olaydan bağımsız puanlanmaz. Çocuğa “koy” denmişse desteğin türü kaydedilir; olay kendiliğinden davranış örneği sayılmaz. Tek yerleştirme, genel motor veya bilişsel beceri düzeyini kanıtlamaz.

## 10. Kalemle kendiliğinden karalama yapma — D10

| Alan | Tanım |
|---|---|
| Yaş ve kapsam | CDC 18 ay listesinde karalama yer alır. Kaynak, tek denemeden gelişimsel puan çıkarılmasını veya aşağıdaki teknik kuralları doğrulamaz. İlk teknik pilot 30–36 ay; daha küçük yaşlar için malzeme ve görev uyarlanır. |
| Senaryo | Sabit bir kâğıt ve kalın, çalışan, yaşa uygun pastel boya erişilebilir biçimde sunulur. Yetişkin çizim göstermez, çocuğun elini yönlendirmez ve “çiz” yönergesi vermez. Belirli bir şekil beklenmez. |
| Geçerli gözlem koşulu | Çocuk malzemeye erişebilir ve kâğıt/kalemle etkileşim fırsatı oluşur. El, boya ucu, kâğıt ve oluşan izler yeterince görünürdür. Kâğıt başlangıçta boş veya mevcut çizgileri bilinen durumdadır; kamera ve ışık izleri ayırt etmeye uygundur. |
| Gözlendi | Çocuk boya ucunu kâğıda temas ettirip yüzey üzerinde hareket ettirir; bu harekete bağlı yeni görünür çizgi oluşur. Tek nokta veya kalemi yalnızca tutma, bu kartın karalama ölçütünü karşılamaz. Şekil, düzenli çizgi veya belirli tutuş şartı aranmaz. |
| Gözlenmedi | Geçerli etkileşim fırsatı ve yeterli kayıt vardır; çizgi oluşturan yüzey hareketi görülmez. Kalemi tutma, nokta yapma, havada hareket ettirme ve kâğıdı inceleme ayrı kaydedilir; genel çizim becerisi yok sonucuna gidilmez. |
| Belirsiz | El ve kâğıt seçilir ancak yeni izin kalem hareketiyle ilişkisi veya izin gerçekten yeni olup olmadığı ayrıştırılamaz. Sınırlı örtülmede çizgi oluşumu kesin doğrulanamaz. |
| Değerlendirilemedi | Etkileşim fırsatı oluşmamıştır; kalem çalışmaz; kâğıt/kalem erişilemez; kritik bölge sürekli kadraj dışıdır; yetişkin fiziksel yardım verir; çizgiler kendiliğinden belirir veya kalem hareketiyle belirgin biçimde uyuşmaz. Yönerge/model varsa ayrı destekli koşul kaydedilir. |
| Kaydedilecek ölçüler | İlk temas ve ilk çizgi başlangıcı; karalama bölümlerinin başlangıç/bitişi; toplam gözlenebilir süre; yeni çizgi varlığı; el–kalem–kâğıt görünürlüğü; yönerge/model/fiziksel destek. Her nokta veya yüzey teması karalama sayılmaz. |
| Kaynak dayanağı | S2; görev, kendiliğinden koşulu ve teknik karar kuralları proje tasarımıdır. |

Karalama gözlenmesi el–kalem–kâğıt eylemi hakkında kanıttır; genel gelişim düzeyi, yaratıcılık veya tanı sonucu değildir. Önceden çizilmiş kâğıt, son karedeki çizgi veya üretim promptu tek başına yeterli kanıt olmaz. Belirgin üretim hatası ilgili denemeyi değerlendirme dışı bırakır. Otomatik ölçümün yapılabilirliği henüz doğrulanmamıştır.

## Kaynaklar ve kullanımları

Kaynaklar 11 Ekim 2026 tarihinde gözden geçirildi. Aşağıdaki kaynaklar bütün teknik kuralları veya gözlem sürelerini doğrulamaz; davranış seçimini ve görev ayrımlarını destekler.

- **S1 — CDC, 15 Months:** https://www.cdc.gov/act-early/milestones/15-months.html — Nesne gösterme, istemek için işaret etme ve jest+söz yönergesi örnekleri.
- **S2 — CDC, 18 Months:** https://www.cdc.gov/act-early/milestones/18-months.html — Jestsiz tek basamaklı yönerge ve karalama örnekleri; hayali oyunu destekleyen etkinlik önerileri.
- **S3 — CDC, 30 Months:** https://www.cdc.gov/act-early/milestones/30-months.html — Nesneyi başka bir şey yerine kullanarak hayali oyun örneği. Bu, basit hayali eylemin tek başlangıç yaşı değildir.
- **S4 — M-CHAT-R/F, Mart 2025:** https://www.mchatscreen.com/wp-content/uploads/2025/06/M-CHAT-R_F_March_2025.v2.pdf — İsme yanıt, dikkat takibi, isteme/gösterme, taklit ve karşılıklı gülümseme adayları. Ebeveyn bildirimli tarama aracının soru ve puanları bu kartlara taşınmamıştır.
- **S5 — Önceki sürümdeki kaynak:** Gövde sallama kartı v0.2 kapsamından çıkarıldı. Bu kaynak kodu yeni davranış için kullanılmaz.
- **S6 — CDC, Key Points:** https://www.cdc.gov/act-early/milestones/key-points.html — Gelişim listelerinin tarama/tanı standardı olmadığına ilişkin kullanım sınırları.
- **S7 — Mundy ve arkadaşları, 2007:** https://pubmed.ncbi.nlm.nih.gov/17517014/ — Ortak dikkati takip etme, başlatma ve davranışsal istemenin kavramsal ayrımı. İlgili tam metin: https://pmc.ncbi.nlm.nih.gov/articles/PMC2654237/

- **S8 — CDC, 1 Year:** https://www.cdc.gov/act-early/milestones/1-year.html — Nesneyi kaba koyma gelişim örneği.

## Uygulama sırası

1. D01, D06 ve D08 için gözlendi/gözlenmedi/belirsiz/değerlendirilemedi örneklerini insan tarafından etiketle.
2. Aynı olay zamanlarının farklı etiketleyicilerce anlaşılabildiğini kontrol et; kartları sürümle.
3. Baş/eller/nesneler ve ses zamanları için gerekli teknik bileşenleri bu örneklerde sına.
4. D02, D03, D05, D09 ve D10'a geç; ardından bağlam gereksinimi daha yüksek D04 ve D07'yi ele al.
5. 12–36 ay hedefi için yaşa göre ayrı senaryo düzeyleri oluştur; bir yaşın örneğini diğer yaş için klinik beklentiye dönüştürme.

