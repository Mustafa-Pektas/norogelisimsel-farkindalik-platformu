# Güncel üretim sözleşmesi — 28 Ekim 2026

Tekrarlanabilir ilk uzak kurulum dosyaları ve işletim adımları için
[`SUNUCU_KURULUM.md`](SUNUCU_KURULUM.md) belgesine bakın. Bu dosyalar hazırlıktır;
sunucu, DNS veya sertifika henüz kurulmuş değildir.

Stüdyo tek formu normal üretime ve A/B/C’ye taşır. Eski tek kartlı ve `requestVersion:2.0` çoklu istekler tam ay metadata’sıyla geriye uyumludur. Yeni üretim `requestVersion:3.0` ile bütün kartların `behaviors:[{behaviorId,cardVersion}]` referanslarını, `ageGroup:{contractVersion:"1.0",id}` alanını ve isteğe bağlı `production` ayarını taşır. Yaş grubu kimlikleri yalnız `12_18`, `18_24`, `24_36` olabilir; yeni istek `ageMonths` alanını kabul etmez. Ortam zorunlu, ek yönerge isteğe bağlıdır.
`production` structure=branched/linear26, targetDurationS, maxClipDurationS≤8
ve doğrusal düzende targetSceneCount=26 içerir. Bunlar hedeflerdir, video ölçümü değil.

Yaş grubu sözleşmesi aralıkları 12≤ay<18, 18≤ay<24 ve 24≤ay≤36 olarak tanımlar. Eski ay değerleri kayıtlarda aynen korunur; yalnız eski taslaktan yeni istek hazırlanırken eşlenebilir. Geçersiz/eksik yaşa varsayılan atanmaz. İstem grubu aralık olarak iletir, temsilî tek ay uydurmaz. Grup seçimi yaşa göre içerik/klinik desteğinin doğrulandığı anlamına gelmez.

Etkin istek sözleşmesi `requestVersion:3.0`; anlatı protokolü **scenario-input-narrative-v4**:
- Alternatifli çıktı commonStart/commonBehaviorIds, structure=branched ve
  alternatives[{title,continuation,ending,behaviorIds}] kullanır.
- linear26 çıktısı commonStart genel anlatı, alternatives=[], linearScenes
  içinde tam 26 title/description/behaviorIds içerir. Kendiliğinden dal eklenmez.
- Eski tek kartlı v1 ve requestVersion 2.0 istekleri eski ay metadata’sıyla geriye uyumlu kalır; yeni grup sözleşmesine dönüştürülmez.
- Aynı isteğin normal ve A/B/C üretimi aynı narrativeSchemaFor/validateNarrative,
  SCENARIO_INPUT_MODEL ve temperature=0.2/topP=0.95/maxOutputTokens=16384 kullanır.
  Yalnız kaynak miktarı değişir. İstek/şema/kaynak/ayarlar protokol hash’ine bağlıdır;
  eski protokol aktif yeni deneye katılamaz. Eski v2 tek kart sonucu yalnız kayıt uyumluluğudur.

`loadCard` tek kanonik dosyadan seçilen bütün kartları bir kez yükler. Kaynak ve
ölçüm metadata’sı bütün referansları taşır; embedding veya ikinci katalog yoktur.
Yaş gruplu anlatı/graf 1.2 sürümlü ageGroup ve sahnelerde behaviorIds taşır. Klip planı 1.1 ageGroup değerini aynen taşıyıp grafla eşleşmelidir. Eski graf 1.0/1.1 ve plan 1.0 ageMonths değerleriyle açılmaya devam eder. Klipler davranış ilişkisini sceneId üzerinden korur. `/api/generate-clip-plan` eski ve yeni grafı doğrular; ilgili D01 yollarının
pilot penceresini kontrol eder, başka kartı klinik eşikle değerlendirmez.

Mobilde gerçek sonuç seçimi yeni çağrı yapmaz; düzenleme/graf sonrası klip planı
ayrı açık çağrıdır. Mevcut plan ekranı prompt/süreklilik/seslendirme/export’u gösterir.
Genel yeni plan-video eşlemesi hâlâ yoktur. Eski 26 sahne endpoint’i/kodu korunur,
yeni anlatı diye yeniden etiketlenmez; deployment’ta eski endpoint’ler kapalı kalır.
Erişim, gövde, kapasite, timeout ve güvenli ölçüm korumaları değiştirilmedi.

Kullanım: `../mobile_skeleton/docs/KULLANIM_REHBERI.md`. Aşağıdaki eski tek davranış/v2
notları tarihsel bağlamdır; güncel sürüm ve çoklu seçim için bu bölüm önceliklidir.
Bu değişikliklerin testleri/analizi ve gerçek sağlayıcı çağrısı bu turda çalıştırılmadı.

# Backend kart kaynağı ve kurulum

Güncel tek Markdown kaynağı `resources/Davranis_Kartlari_v02.md` dosyasıdır.
Proje üstündeki eski `belgeler/Davranis_Kartlari_v02.md` dosyası bu konuma
içeriği değiştirilmeden taşınmıştır. Kart değişikliklerini yalnız burada yapın;
başka bir bağımsız kart kopyası oluşturmayın. Backend klasörü dağıtılırken
`resources/` klasörü de pakette bulunmalıdır.

Her iki üretim endpoint'i (`/api/generate-scenario-input` ve
`/api/generate-clip-plan`) aynı `loadCard` fonksiyonunu kullanır. Varsayılan yol
`__dirname` üzerinden çözülür; uygulamanın başlatıldığı çalışma dizinine bağlı
değildir. Eksik kaynak veya bozuk kart kimliği/biçimi hata verir; istek sürümü
kaynak sürümüyle uyuşmazsa istek reddedilir. Kaynağın SHA256 değeri mevcut
üretim yanıtının `behaviorSource` alanında korunur; bu içerik doğruluğu kanıtı
değildir.

## Tek anlatı sözleşmesinde A/B/C

Kaynak 223bc7d’nin karşılaştırma arayüzü/önizleme/kollar/ham çıktı ve ölçüm
araçları korunur; aktif protokol **scenario-input-narrative-v2** sürümündedir.
Stüdyo’da tek güncel davranış, 12–36 ay yaş, ortam ve ek yönerge doğrulanır.
Normal üretim ve karşılaştırma bu aynı isteği alır; editörde ikinci üretim yoktur.

1. A/B/C veya ALL seçimi, gerçek istemleri/kaynağı inceleyen önizleme ve ayrı
   açık başlatma kullanılır. Önizleme model/kapasite tüketmez. Seçilen her kol
   için bir sağlayıcı çağrısı vardır; otomatik tekrar veya benchmark yoktur.
2. `/api/compare-scenario`: `{request,arm,action}`; generate için önizlemeden
   `protocolId` zorunludur. Kaynak/model/girdi/şema/ayar değişirse 409 verilir.
3. A ek kart metni kullanmaz; B ortak kurallar+seçili kartı, C tek kanonik
   Markdown’ın tamamını kullanır. Temel görev/çıktı şeması/ayarlar aynıdır.
   Embedding/vector retrieval yoktur; klinik ikinci bir kaynak eklenmez.
4. Normal üretim ve bütün kollar aynı `SCENARIO_INPUT_MODEL`, temperature 0.2,
   topP 0.95, maxOutputTokens 16384 kullanır. Normal üretimin eski 4096 sınırı
   bu ortak protokole geçerken 16384 olmuştur. Normal üretimin önceki 0.7 sıcaklığı da ortak 0.2 değerine getirilmiş, topP 0.95 açıkça belirlenmiştir. Model seçimi değiştirilmez.
5. Bütün kollar `validateNarrative` ile doğrulanır. Eksik/bozuk/26 sahneli
   çıktı örnekle tamamlanmaz. Ham metin aynen korunur. Yapısal geçerlilik
   anlamsal içerik onayı, klinik skor veya gerçek video ölçümü değildir.
6. Her başarılı sonuç için “Bu senaryoyla devam et” kimliği ve tam kaynağı
   editöre taşır. Dolu taslakta aktarım onayı gerekir. Seçilen sonuç açık
   kaydetmeyle yeniden açılabilir; her denemenin kimliği ayrıdır. Tüm deney
   kayıtları ve hatalar karşılaştırma kopyalama aracıyla erişilebilir kalır.

Eski 26 sahne çıktıları yeni protokol sonucu olarak kabul edilmez; legacy
şema/yardımcılar ve development endpoint’i geçmiş kullanım için korunur.
Yeni anlatıdan grafı mevcut mobil dönüştürücü kurar; klip/prompt/seslendirme
planı ayrı mevcut endpoint’ten gelir. Plan ve üretim kaynağı dışa aktarılır;
genel yeni plan-video eşlemesi bu kapsamda yoktur. Test/API çalıştırılmadı.

Yeni yol da deployment Bearer kontrolü, 1 MiB, ortak sağlayıcı kapasitesi ve
timeout/geç cevap sınırlarından geçer. Eski `/api/generate-scenario` ve analiz
endpoint'i deployment'ta kapalı kalır. Gerçek anahtar internet üzerinde yalnız
HTTPS ile kullanılmalıdır. Bu görevde test/API/uygulama çalıştırılmadı.
**Ayrı açık iş:** modelin `d01CallTiming` alanını ortak çağrı klibi için tekrar etmesi
istem yönergesi/schema açıklamasıyla önlendi; yeni sözleşmeyle gerçek sağlayıcı çıktısı
henüz doğrulanmadı.

## Ortam ve kurulum

### Seçici retrieval ve ölçüm entegrasyonu

Kaynak yaklaşım: arkadaş dalındaki `da96695..223bc7d`, özellikle
`rag/retriever.js` ve `services/benchmark_service.js`/sağlayıcı ölçüm kodu.
Bu seçici kaynak uyarlamasıdır; Git merge yapılmış veya arkadaş dalının tamamı
alınmış değildir.

Mevcut `loadCard` iki güncel endpoint'in ortak **kurallı kart seçimi** olarak
korunur; ikinci retrieval çağrısı veya istemde ikinci kart kopyası yoktur.
Davranış/sürüm/12–36 tam ay doğrulaması değişmez. Yaş istek ve istem içinde
taşınır; yeni yaş bandı/klinik eşik üretilmez. Bu embedding/vector arama değildir.
Tek kaynak hâlâ `resources/Davranis_Kartlari_v02.md`; response `behaviorSource`
alanına dosya yolunu açığa çıkarmayan `sourceId` eklenmiştir; sürüm ve SHA256
aynı kanonik dosyadan gelir.

İki endpoint'in başarı ve hata JSON'larına güvenli `measurement` metadatası
eklenir. Ham cevap ayrı ve aynı kalır. Alanların anlamı:

- `requestId`: backend'in ürettiği istek/iş kimliği. Terminal sonuç aynı kimlikle
  yalnız bir kez oluşturulur; geç sağlayıcı sonucu ikinci kayda dönüşmez.
- `endpoint`: senaryo, klip planı veya karşılaştırma endpoint kimliği.
- `retrievalDurationMs`: tek kart okuma/doğrulama/seçim süresi.
- `providerDurationMs`: sağlayıcı adaptörüne çağrıdan Promise'ın sonlanmasına
  kadar geçen süre; SDK çağrısı ve metin/usage çıkarımı dahildir, kart seçimi ve
  çıktı doğrulaması hariçtir. Yalnız ağ gidiş-dönüş ölçümü değildir.
- `endpointDurationMs`: handler girişinden terminal sonucun hazır olmasına kadar
  geçen süre; kart/sağlayıcı/çıktı doğrulaması dahildir. Daha önceki Bearer/gövde
  middleware'i, ağ aktarımı ve istemci çizimi dahil değildir.
- `providerStarted`, `providerFinished`: timeout/kapanış sırasında model işi
  gerçekten tamamlandı mı ayrımını korur. Henüz bitmemiş işte sağlayıcı süresi
  ve tokenlar `null` olabilir; HTTP timeout süresi sağlayıcı süresi gibi yazılmaz.
- `promptTokens`, `outputTokens`: varsa SDK usageMetadata sayacı, yoksa/geçersizse
  `null`. Gerçek `0`, bilinmiyor ile karıştırılmaz.
- `behaviorSource`: yalnız kaynak kimliği, davranış kimliği, kart sürümü ve hash.
- `outcome`: `success`, `validation_error` (model çıktısı), `provider_error`,
  `timeout`, `disconnected`, `capacity_rejected`, `configuration_error`,
  `invalid_request` veya `internal_error`; model çağırmayan karşılaştırma önizlemesi `preview` olur.

Otomatik başarı oranı hesaplanmaz. Preview model denemesi paydasına girmez.
İleride oran hesaplanırsa yalnız başarılı
kayıtlar seçilmemeli; payda, dahil edilen hata/timeout/iptal türleriyle
tanımlanmalıdır. Bu ölçüm handler'a ulaşan istekleri kapsar; auth/body sınırında
reddedilen 401/413 ve kapalı endpoint'ler bu ölçüm kümesinde değildir.

`createApp({reportMeasurement})` veya doğrudan ortak handler'ın aynı isteğe
özel bildirim noktası, terminal metadatayı kontrollü alıcıya aktarabilir.
Varsayılan kalıcı kayıt, log, kuyruk, bellek arşivi veya yeni istatistik endpoint'i
**yoktur**; dosya yolu/saklama süresi/boyut limiti gerektiren yeni JSONL deposu
eklenmedi. İleride bir alıcı kayıt eklerse kendi sınırlı saklama politikasını
tanımlamalıdır. Disconnect yanıt göndermez; varsa alıcıya tek terminal kayıt
bildirilir. Timeout sonrası geç sonucu güncellemek yerine terminal snapshot
korunur; bu nedenle geç tamamlanmış işin tam süresi bu sürümde alınmaz.

Metadatada anahtar, başlık, mutlak dosya yolu, istem/ham cevap, çocuk adı veya
bağlam yoktur. Saat/usage okuma ve senkron/asenkron ölçüm alıcısı hataları yanıtı
başarı/hata bakımından değiştirmez; bilinmeyen ölçüler `null` kalır.

İlk seçici uyarlamada alınmayan parçalar: bağımsız `clinical_knowledge_base.json` ve diğer Markdown
kopyası (tek kaynağı ve görev koşullarını bozar), yaşa bağlı tipik/atipik eşikler,
doğrusal 26 sahne FSM'i (dallı graf sözleşmesi değildir), sınırsız JSONL yazımı ve
tam dosyayı okuyan istatistikler, benchmark koşucusu/endpoint'i. Deployment,
Bearer, gövde, ortak kapasite ve D01 zamanlama korumaları korunur. Mevcut eski
26 sahne route'u değişmedi ve deployment modunda kapalıdır. Aşağıdaki yeni görev,
yalnız metinsel FSM ve A/B/C dialogunu ayrı deney yolunda uyarlamıştır; bu ilk
kart/ölçüm uyarlamasının tamamlanmış karşılaştırma olmadığı kaydı korunur.

### Çalışma modu

`BACKEND_MODE` verilmezse veya boşsa `development` kullanılır. Bu mod mevcut
yerel 26 sahne/video analiz yollarını ve 50 MB gövde sınırını korur. `development`
ve `deployment` dışında bir değer başlangıçta hata verir; sessizce geliştirme
moduna geçilmez.

İlk uzak dağıtım için `BACKEND_MODE=deployment` seçin. Bu modda yalnız:

- `GET /health` (HEAD da desteklenir),
- `POST /api/generate-scenario-input`,
- `POST /api/generate-clip-plan`

- `POST /api/compare-scenario` — aşağıdaki ekip karşılaştırma uyarlaması

açıktır; bu adreslerin CORS preflight OPTIONS istekleri de desteklenir.
Eski `/api/analyze-video`, `/api/generate-scenario`, diğer adresler ve izin
verilmeyen metotlar JSON 404 ile, gövde ayrıştırma/video yükleme ve sağlayıcı
çağrısından önce reddedilir. Eski route kodları silinmemiştir.

Deployment JSON gövde sınırı **1 MiB = 1.048.576 bayt**tır; JSON anahtarları,
metadata ve bütün graf metni dahildir. Sınır UTF-8 baytlarına uygulanır; Türkçe
karakterler birden çok bayt olabilir. Bu, senaryo/istek ve graf taşıyan plan
JSON'ları için ilk dağıtımın taşıma sınırıdır; sözleşmedeki sınırsız metin/şema
geçerliliği boyut sınırını aşma hakkı vermez. Sınır aşılırsa sağlayıcıya
gidilmeden `{success:false,error:...}` JSON'u ile **413**, bozuk JSON'da **400**
döner. URL-encoded gövdelerde de modun aynı boyut sınırı kullanılır. Gövde
sessizce kırpılmaz, graf/istem tamamlanmaz. Gerçek kullanım boyutları bu limitin
uygunluğunu ayrıca doğrulamalıdır; performans ölçümü yapılmış değildir.

Deployment health yalnız `status`, `service`, `timestamp` alanlarını verir;
anahtar/model yapılandırmasını, yerel yolu veya model erişimi doğrulamasını
bildirmez. HTTP 200, Gemini erişimi ya da içerik doğruluğu kanıtı değildir.

PowerShell kullanım örneği (önceden yapılandırılmış sunucu ortamında):

```powershell
$env:BACKEND_MODE = 'deployment'
node backend/server.js
```

Yerel akış için değeri `development` yapın veya kaldırın. Deployment modu endpoint
kapsamını, gövde boyutunu, geçici ekip Bearer anahtarını ve aşağıdaki süreç içi
üretim kapasitesini sınırlar; bu, kişi/rol hesabı veya istek hızı sınırı değildir.
CORS kimlik doğrulaması değildir. Caddy/Compose HTTPS yapılandırması eklendi ancak
gerçek DNS, sertifika ve dış erişim kabulü yapılmadı. Mobil uygulamaya sabit gizli
anahtar eklenmez.

### Geçici ekip erişimi

Deployment başlangıcında `TEAM_ACCESS_KEY` sunucu ortamında tanımlanmış olmalıdır.
Eksik/boş veya boşluk içeren değer başlangıç hatasıdır; yazdırılabilir boşluksuz
ASCII kullanılır. Gerçek değer `.env.example`, kaynak kod, Git, URL veya APK
içine yazılmaz; sunucu ortamında gizli ayar olarak sağlanır. Bu, Gemini sağlayıcı
anahtarından ayrı bir ekip erişim anahtarıdır.

Güncel üretim ve karşılaştırma endpoint'leri `Authorization: Bearer` başlığında bu anahtarı gerektirir.
Kontrol, JSON ayrıştırma ve kapasite kullanımından öncedir. Eksik/yanlış anahtar
**401**, `team_access_required` kodu ve sabit erişim açıklaması verir; anahtarı
veya gönderilen başlığı geri yansıtmaz. Karşılaştırma sabit boyutlu SHA256
özetleri üzerinde `timingSafeEqual` ile yapılır. Health/HEAD ve ilgili OPTIONS
anahtar gerektirmez; üretim başlatmaz. Development modu anahtar gerektirmez.

Mobil debug ekip çalışma alanındaki **Ekip erişim anahtarı** gizli alanına elle
girilir. Aynı ekran oturumundaki senaryo ve klip planı HTTP istekleri kullanır;
anahtar yalnız başlığa eklenir, JSON/URL'ye girmez. Taslak veya preferences'a
kaydedilmez, ekran yeniden açıldığında boştur. Temizleme eylemi vardır; devam
eden işi değiştirmemek için üretim sırasında alan kilitlidir. Başlamış bir
istek başlama anındaki anahtarı kullanır; temizleme sunucudaki işi iptal etmez.
401, sağlayıcı/model hatası yerine anlaşılır ekip erişim hatası olarak gösterilir.

Bu **geçici ortak ekip erişimi** kullanıcı kimliği, rol, kişi bazında anahtar
iptali veya kalıcı oturum sistemi değildir. **HTTPS sağlanmadan internet
üzerinde gerçek ekip anahtarıyla kullanılmamalıdır.** HTTP, anahtarı korumaz.
Gerçek anahtarı loglamayın; sunucu/ters proxy loglarında Authorization başlığı
bulunmamalıdır. Anahtarın uygulama kaynaklarına veya build parametrelerine
sabitlenmesi önerilmez.

### Ortak üretim kapasitesi

Deployment modunda `GENERATION_MAX_CONCURRENT` güncel üretim ve karşılaştırma endpoint'lerinin
aynı Node sürecindeki ortak sağlayıcı iş sınırıdır. Verilmezse **1** kullanılır;
verilirse ondalık, işaret veya boşluk içermeyen pozitif, güvenli tam sayı olmalıdır.
Boş, sıfır, negatif, ondalıklı veya hatalı değer başlangıcı durdurur. Development
modunda bu sınır uygulanmaz ve ayar dikkate alınmaz; mevcut yerel akış korunur.

Kapasite doluyken geçerli yeni istek sağlayıcıya gönderilmeden **429** ile
`{success:false, code:"local_capacity_exceeded", error:...}` döner. Bu, Gemini
kotası veya sağlayıcı 429'u değildir; kuyruk, `Retry-After` vaadi ve otomatik
tekrar oluşturulmaz. Health ve OPTIONS slot tüketmez. Sınır istek boyutu,
geçerlilik ve kart kaynağı kontrollerinden sonra sağlayıcı çağrısı öncesinde
alınır; istemci bağlantısı ve body ayrıştırma sayısını sınırlamaz.

Slot, sağlayıcı Promise'ı başarıyla veya hatayla sonlandığında tam bir kez
bırakılır. HTTP timeout/istemci bağlantısının kapanması yalnız beklemeyi bitirir;
sağlayıcı iptali doğrulanmadığı için slot erken bırakılmaz ve geç cevap
uygulanmaz. Sağlayıcı Promise'ı hiç sonlanmazsa slot dolu kalabilir; timeout'un
dolması model işi durdu anlamına gelmez. Otomatik TTL ile kapasite açılmaz.

Bu sınır **tek Node süreci/uygulama örneği** içindir. Çoklu worker, sunucu veya
yeniden başlatma arasında paylaşılan sayaç/kota sağlamaz. Çoklu süreçte gerçek
toplam yük ayrıca kontrol edilmelidir; bu bir saniyelik hız limiti veya dağıtık
sağlayıcı kota koruması değildir.

Backend bağımlılıkları `package-lock.json` ile kurulmalıdır. Yerel geliştirme ve
deployment değişkenleri (`BACKEND_MODE`, `TEAM_ACCESS_KEY`,
`GENERATION_MAX_CONCURRENT`, `PUBLIC_DOMAIN`, `PORT`, `GEMINI_API_KEY`,
`SCENARIO_INPUT_MODEL`, `BEHAVIOR_CARDS_PATH`) `.env.example` içinde açıklanır;
Compose deployment örneği ve HTTPS kurulum adımları `SUNUCU_KURULUM.md` içindedir.
Gerçek anahtarı Git'e veya mobil uygulamaya eklemeyin. Backend'i `npm start` veya başka bir dizinden
`node /mutlak/depo/backend/server.js` ile başlatmak kart yolunu değiştirmez.

`BEHAVIOR_CARDS_PATH` boşsa paket içindeki kaynak kullanılır. Açıkça bir yol
verilmişse yalnız o dosya okunur; hatalı yol için paket kaynağına sessiz geçiş
yoktur. Başka çalışma dizinlerinden başlatılacaksa açık ayarda mutlak yol
kullanın; göreli açık yol Node çalışma dizinine göredir. Override bir kaynak
seçimidir; dosyanın ikinci bir düzenlenen kopyasını yönetme gereği doğurmaz.

Kontrollü kaynak/yol ve iki endpoint testleri (gerçek API çağrısı içermez):

```powershell
node --test backend/test/scenario_comparison.test.js backend/test/generation_measurement.test.js backend/test/deployment_mode.test.js backend/test/scenario_input_generation.test.js backend/test/scenario_clip_generation.test.js
```

Komut depo kökünden çalıştırılır. Bu değişiklik sırasında paket/test/sunucu
veya API çalıştırılmadı. HTTPS, erişim kontrolü ve uzak dağıtım kabulü ayrıca
tamamlanmalıdır.

Mod testleri `createApp` üzerinden Express'in gerçek middleware/route zincirini
bellekteki HTTP mesajlarıyla sınar; port açmaz ve sahte sağlayıcı kullanır.
`require('./server')` ortam dosyalarını yüklemez veya sunucu başlatmaz; normal
komut satırı başlangıcı bu davranışları korur.

Mobil hedefli doğrulama (`mobile_skeleton` dizininde; burada çalıştırılmadı):

```powershell
& 'C:\dev\flutter\bin\flutter.bat' test --no-pub test/scenario_comparison_test.dart test/http_scenario_generation_service_test.dart test/scenario_workspace_draft_test.dart test/scenario_graph_import_screen_test.dart
& 'C:\dev\flutter\bin\flutter.bat' analyze --no-pub
```

Yerel gösterim sırası: özel sunucu ortamında mevcut Gemini modeli/anahtarı ve
deployment ekip erişimi ayarlı olsun; `node backend/server.js` ile kullanıcı
başlatsın. Android emülatör uygulamasında mevcut sunucu ayarı
`http://10.0.2.2:8000` olabilir (yalnız yerel deney; internet için HTTPS gerekir).
Debug ekip formunda anahtarı elle girin, davranış/yaş/bağlamı doğrulayın,
karşılaştırmayı açın, A/B/C sistem istemlerini inceleyin, çağrı sayısını görüp
Başlat'a basın. Hoca için aynı girdiyi/model ayarını, üç ham çıktıyı, hataları ve
bilinmeyen tokenları ayrı gösterin; sonuçları kapatmadan kopyalayın. Bu belgedeki
başlatma adımları asistan tarafından çalıştırılmadı.

# Deneysel yerel D01 iş API'si

Varsayılan kapalı, ekip anahtarlı yükleme→iş kimliği→durum→ana sonuç bağlantısı eklendi. Mevcut senaryo endpoint'lerinden ve eski Gemini video analizinden ayrıdır. Yalnız iki denetlenmiş video hash'i ve kayıtlı ROI kabul edilir. Python/model Node Docker image'ına eklenmedi; gerçek Node→CLI koşusu henüz denenmedi. Yapılandırma, sözleşme,25 MiB sınırı, tek CPU işi, kesinti ve24 saat/en yeni10 iş saklama politikası: [D01_PILOT.md](D01_PILOT.md).
