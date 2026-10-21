# Senaryo içeriği → ScenarioGraph, ilk sürüm

Bu sözleşme serbest metin değil, açık alanlara ayrılmış senaryo içeriği alır.
Serbest metinden alan çıkarma veya bozuk model cevabını otomatik onarma yoktur.
Model ve dönüştürücü ekran, LLM, kalıcı kayıt, klip planı ve oynatma akışlarına
bağlı değildir. Debug geliştirici alanındaki ortak JSON ekranı bu sözleşmeyi
isteğe bağlı olarak kullanır.

## Giriş

`ScenarioInput.fromJson` / `fromJsonString` şu zorunlu alanları okur:

| Alan | Tür ve anlam |
| --- | --- |
| `schemaVersion` | Mevcut graf şeması: `1.0` |
| `scenarioId`, `title`, `language` | Senaryo kimliği, başlığı ve dili |
| `ageMonths` | Pozitif tam sayı; yaşın ay cinsinden temsili |
| `behaviorId`, `cardVersion` | Davranış ve davranış kartı sürümü |
| `source` | `manual_example`, `model_output` veya `model_output_edited` kaynak beyanı |
| `commonStart` | Ortak başlangıcın tam metni |
| `alternatives` | En az bir alternatif içeren sıralı liste |

Her alternatifte `title` (kısa başlık), `continuation` (tam devam metni),
`ending` (tam bitiş metni) zorunludur. Bütün metinler boş olmayan metinlerdir;
boşlukları temizlenmez veya içerikleri yeniden yazılmaz. Başlık uzunluğu için
keyfi bir kesme uygulanmaz; kısa başlık giriş sözleşmesinin gereğidir.

Eksik, boş veya yanlış türde alanlar ve tanımsız kaynaklar `FormatException`
üretir. Bilinmeyen alanlar da reddedilir; iç içe alternatifler veya kullanıcıdan
gelen sahne/kenar kimlikleri sessizce göz ardı edilmez. Eksik içerik tamamlanmaz.
Bu kontroller anlamsal belirsizliği, çelişkileri veya D01 uygunluğunu çözmez;
serbest metindeki belirsiz olayların insan tarafından açıklığa kavuşturulması
gerekir. Servis bunlara olay veya dal ekleyerek karar vermez.

## Dönüşüm ve sınırları

`const ScenarioGraphConverter().convert(input)` mevcut `ScenarioGraph` nesnesi
üretir ve kurucusunun bütün doğrulama kurallarından geçirir.

Yalnızca **tek dallanma düzeyi** desteklenir:

`ortak başlangıç → alternatif devam → o alternatifin bitişi`

Ortak başlangıç bir kez oluşturulur. Alternatifler birbirine bağlanmaz;
döngü, yeniden dallanma ve birleşme bu giriş sözleşmesinde yoktur. Bir, iki,
üç veya daha fazla alternatif desteklenir; tek alternatif doğrusal yol üretir.
N alternatifte 1 + 2N sahne, 2N geçiş ve N terminal bitiş oluşur.
Dalı kimin veya nasıl seçeceği bu dönüşüm tarafından belirlenmez.

Kimlikler graf içinde `start`, `alternative_1`, `ending_1`, … biçimindedir.
Aynı sıralı giriş daima aynı kimlikleri ve bağlantıları üretir; saat veya rastgele
değer kullanılmaz. Alternatiflerin sırası değişirse kimlik eşleştirmesi değişir;
bunlar içerik düzenlemeleri arasında kalıcı kimlik garantisi vermez.
Graflar arasında sahne referansı gerekiyorsa `(scenarioId, sceneId)` kullanılır.

`commonStart`, `continuation` ve `ending`, ilgili sahnelerin `description`
alanlarına birebir aktarılır; devam/bitiş metinleri geçiş açıklamalarında da
korunur. Alternatif başlıkları sahne başlığı ve dal etiketi olur.
Kaynak beyanı mevcut grafın `authoringNote` alanında korunur; yeni bir graf
şeması gerekmez. `model_output` beyanı servis tarafından bağımsız doğrulanmaz.
Hiçbir kaynak türü gözlenmiş davranış, klinik sonuç veya video kanıtı değildir.
`model_output_edited`, modelden başlayıp kullanıcı tarafından düzenlenen taslağı
belirtir. Önceki iki kaynak değeri ve JSON dosyaları okunmaya devam eder.

## Elle hazırlanmış D01 örneği

`assets/scenarios/d01_scenario_input.json` gerçek LLM cevabı değildir. Kart 0.2 D01'e
göre hazırlanmış taslaktır: çağrı öncesi oyuncakla oyun → annenin tek isim
çağrısı → anneye baş yöneltme **veya** annesine dönmeden oyuna devam → her
yolun açık bitişi. Çağrı ortak başlangıçta bir kez bulunur, dallarda tekrarlanmaz.
Bu anlatı örneği kayıt süresi, kesintisiz gözlem penceresi veya gerçekleşmiş
tepki için kanıt değildir; bunlar üretilen videoda ayrıca doğrulanmalıdır.
Mevcut D01 grafı ve klip planı bu örnekle değiştirilmez.

## Debug geliştirici arayüzü

Stüdyo → Geliştirici: Klip Üretim Planı → Senaryo / graf içe aktar ekranında
`Senaryo içeriği` seçeneğini açın. JSON metni yapıştırılabilir veya
`Elle hazırlanmış D01 örneğini yükle` ile tek kopya asset okunabilir. Örneğin
yüklenmesi dönüşüm yapmaz; `Graf oluştur` önce girdiyi doğrular, sonra mevcut
dönüştürücüyü çalıştırır. Başarılı sonuç mevcut graf ekranında açılabilir.

`Hazır graf` seçeneği mevcut graf JSON içe aktarma yoludur; doğrudan
`ScenarioGraph.fromJsonString` kullanır. İki tür birbirine otomatik çevrilmez.
Tür değişiminde her türün metni oturum içinde korunur, önceki sonuç temizlenir.
Senaryo içeriğinden oluşan graf, dönüşüm bilgisini ve girdide beyan edilen
kaynağı gösterir; kaynak alanı doğrulanmış köken kanıtı sayılmaz. Varsayılan
D01 görüntüleme ve hazır grafın kaynak etiketleri korunur.
Bu alan tekniktir; debug görünürlüğü kullanıcı yetkilendirmesi değildir.

## Yerel model → senaryo → graf demosu

Aynı ekranın `Senaryo içeriği` seçeneğinde `Qwen ile senaryo taslağı üret`
mevcut `LocalLlamaTestService`, `LlamadartTestRuntime` ve model kartını kullanır.
Ekranın açılması çıkarım başlatmaz. Yalnız kullanıcının düğmeye basmasıyla
cihazdaki Qwen dosyası yüklenir; dosya yoksa `Model indirilmedi` hatası gösterilir.
İndirici, eski model testleri, değerlendirme kayıtları ve şablon üretimi değişmez.

Modele ortak başlangıç ve iki alternatifin başlık/devam/bitiş metinleri JSON
olarak sorulur; sahne kimlikleri ve bağlantılar istenmez. Eşleşen eğitilmiş
model daha sonra aynı içerik sözleşmesini kullanabilir; yeni motor/servis
altyapısı eklenmez. Şimdiki demoda Qwen seçimi sabittir.

Uygulama `d01GraphDemoMetadata` içindeki şema, senaryo kimliği, başlık, dil,
yaş, davranış, kart sürümü ve kaynak alanlarını sağlar. Bu alanlar model yazarlığı
iddiası taşımaz; düzenlenebilir kopyada uygulama değerleri esas alınır. Modelden
yalnız `commonStart` ve alternatif başlık/devam/bitiş metinleri alınır. Ek/yanlış
graf alanları mevcut sözleşme tarafından reddedilir; eksik anlatı tamamlanmaz.
İki alternatif kontrolü yalnız bu D01 demosundadır; genel sözleşmenin değişken
sayıda alternatif desteği korunur. Yapısal doğrulama olayların D01'e anlamsal
uygunluğunu veya gerçekleşmiş davranışı doğrulamaz.

İstem doğrudan `commonStart` / `alternatives` içeren çitsiz bir JSON nesnesi
ister; `scenarioInput` sarmalayıcısı istemin parçası değildir. Model bu biçime
uymadığında demo yalnız şu **biçim normalizasyonunu** kabul eder: tüm cevabı
çevreleyen tek Markdown `json` kod çiti kaldırılır; kökün tek anahtarı
`scenarioInput` ise içindeki JSON nesnesi bir kez açılır. Bu iki dış biçim ayrı
ayrı veya birlikte kullanılabilir; çitsiz/sarmalayıcısız geçerli JSON da çalışır.
Çit öncesi/sonrası açıklama, birden fazla kod bloğu, sarmalayıcıyla aynı düzeyde
ek alanlar, iç içe sarmalayıcı ve bozuk JSON kabul edilmez. Hazır graf içe
aktarma yolu ve genel `ScenarioInput` modeli bu toleransla değiştirilmez.

Ham cevap model kartında aynen kalır. Normalizasyon editördeki kopyaya
uygulanır ve yapılan biçim işlemleri ekranda açıkça belirtilir; anlatı metinleri
boşlukları dahil korunur. Ardından mevcut metadata ekleme, `ScenarioInput`
doğrulama ve dönüştürücü yolu çalışır. Yalnız bu dış biçimlerin açılması kaynağı
`model_output_edited` yapmaz. JSON okunamıyorsa ham metin editörde kalır;
bozuk JSON onarma, içerik tamamlama, şablon cevaba geçme veya otomatik yeniden
deneme yapılmaz.
Kullanıcı JSON'u düzeltip `Graf oluştur` ile yeniden doğrulayabilir. Bir kez
düzenlenen model taslağı `model_output_edited` olarak işaretlenir; kaynak alanını
elle `model_output` yazmak bu demo içinde değiştirilmemiş cevap iddiası oluşturmaz.
Elle hazırlanmış örneği yüklemek örneğin kendi kaynak bilgisini geri getirir.

CPU, düşünme kapalı ve mevcut Qwen örneklemesi korunur. Bağlam 2048, çıktı üst
sınırı 768 token: JSON alanları ve beş anlatı metni için eski 384 sınırından daha
fazla yer ayrılır. Gerçek istek/çıktı token sayısı veya kalite burada ölçülmedi;
mevcut runtime şablonlu istek + çıktı rezervini gerçek bağlama karşı kontrol eder.
İptal, ikinci eşzamanlı çıkarımı engelleme ve kaynak kapatma mevcut servistedir.
İptal veya motor hatasında kısmi cevap korunur, otomatik grafa aktarılmaz.

Sonuç yalnız mevcut graf görüntüleyicisinde açılır. Kalıcı kayıt oluşturmaz;
sabit D01 klip planına, video eşlemelerine veya oynatmaya bağlı değildir.

Bu demo için gerçek çıkarım/Flutter testi çalıştırılmadı. Hedefli kontroller:

```powershell
cd C:\Projeler\Norogelisim\mobil_uygulama\mobile_skeleton
flutter test --no-pub test/scenario_model_demo_test.dart test/scenario_graph_converter_test.dart test/scenario_graph_import_screen_test.dart
flutter analyze --no-pub lib/models/scenario_input.dart lib/services/scenario_graph_converter.dart lib/services/local_llama_test_service.dart lib/screens/scenario_graph_import_screen.dart test/scenario_model_demo_test.dart
```

## Hedefli kontroller (normal PowerShell)

```powershell
cd C:\Projeler\Norogelisim\mobil_uygulama\mobile_skeleton
& C:\dev\flutter\bin\flutter.bat test --no-pub test/scenario_graph_converter_test.dart
& C:\dev\flutter\bin\flutter.bat test --no-pub test/scenario_graph_import_screen_test.dart test/scenario_graph_screen_test.dart test/clip_production_plan_screen_test.dart
& C:\dev\flutter\bin\flutter.bat analyze --no-pub lib/models/scenario_input.dart lib/services/scenario_graph_converter.dart test/scenario_graph_converter_test.dart
& C:\dev\flutter\bin\flutter.bat analyze --no-pub lib/screens/scenario_graph_import_screen.dart lib/screens/scenario_graph_screen.dart lib/screens/clip_production_plan_screen.dart test/scenario_graph_import_screen_test.dart
```

Bu görev sırasında Flutter testi ve SDK statik analizi çalıştırılmadı.
