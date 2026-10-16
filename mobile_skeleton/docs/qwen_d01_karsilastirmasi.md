# Qwen3 D01 karşılaştırması — 16 Ekim 2026

> Aşama raporudur. Güncel durum ve sonraki işlem: [Devam notu](DEVAM_NOTU.md).

Qwen ayrı bir karşılaştırma seçeneğidir. Mevcut Senaryo Üret akışı veya grafla bağlantısı yoktur. Llama Türkçe/İngilizce testleri ve indirilen Llama dosyası korunur. Paket yükseltilmedi; llamadart **0.12.0** kullanılmaya devam eder.

## Destek ve doğrulama sınırı

- Kurulu `llamadart-0.12.0` paketinin `lib/src/core/template/handlers/hermes_handler.dart` dosyası Qwen 3'ü kapsar. Render bağlamına gerçek `enable_thinking` değişkenini aktarır; paketin desteklenen Dart parametresi `enableThinking:false` kullanılır.
- Mevcut Android x64 native hook çıktısı **llamadart-native v0.6.0-2** paketinin önbellekten kullanıldığını gösterir. Yerel `libllama.so` içinde `qwen3`, `qwen3moe` ve `Q4_K` tanımları bulundu. Bu, dosyanın başarıyla yüklenmesinin yerine geçmez.
- [Native sürümün kaydı](https://github.com/leehack/llamadart-native/releases/tag/v0.6.0-2), llama.cpp commit'ini `d81235049384534c167caea52b85a694f6103d14` olarak belirtir. [O commit'in Qwen3 uygulaması](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/src/models/qwen3.cpp) 28 katmanlı 1.7B mimarisini içerir. [Qwen belgeleri](https://qwen.readthedocs.io/en/latest/run_locally/llama.cpp.html) GGUF/Q4_K_M kullanımını anlatır.
- Sonuç: kaynak ve mevcut Android x64 motoru düzeyinde Qwen3 desteği var; yükseltme gerektiren somut uyumsuzluk bulunmadı. **Seçilen 1.7B GGUF'nin emülatörde yüklenmesi, bellek yeterliliği, hızı ve Türkçe başarımı doğrulanmadı.** Android arm64 üzerinde de bu görevde çalıştırılmadı.

## Dosya ve indirme

[İstenen Unsloth dosyası](https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/blob/main/Qwen3-1.7B-Q4_K_M.gguf):

- Kimlik: `unsloth/Qwen3-1.7B-GGUF`, dosya: `Qwen3-1.7B-Q4_K_M.gguf`.
- URL: `https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf`.
- [Yayımlanan dosya işaretçisi](https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/raw/main/Qwen3-1.7B-Q4_K_M.gguf): **1.107.409.472 bayt**, yaklaşık 1,11 GB; SHA256 `b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897`. Bu uzak kaydın hash'idir; indirilen dosyanın hash'i bu görevde hesaplanmadı. Model kartında Apache-2.0 belirtilir.
- Mevcut `LlamaModelService` indiricisi model parametresiyle ortak kullanılır; varsayılan Llama olarak kalır. Yerel konum uygulama belgeleri altındaki `models/Qwen3-1.7B-Q4_K_M.gguf`; Llama'nın dosya adı ve yolu ayrıdır.
- Başlangıçta yalnızca dosya varlığı/boyutu kontrol edilir. İndirme, **Qwen modelini indir (~1,11 GB)** düğmesiyle başlar. Model testi veya ekran açılması indirme başlatmaz.
- Akış `.part` dosyasına yazılır; bitiş, HTTP uzunluğu, beklenen Qwen boyutu ve GGUF sihirli başlığı kontrol edildikten sonra asıl ada taşınır. Bu kontroller kriptografik hash doğrulaması veya model yükleme testi değildir. Mevcut son dosyanın üzerine yazılmaz. Hata/iptalde kısmi dosya temizlenir; hatalar görünür. İki indirme aynı anda başlatılamaz.
- “İndirildi” durumu aktarım ilerlemesinin %100 olmasına göre değil, başarılı son durumdan sonra atanır. Dosyanın indirilmesi ve çıkarım yapması ayrı gösterilir.

## Düşünmesiz çıkarım

`LocalLlamaTestRequest.d01Qwen`, mevcut Türkçe D01 isteğinin **aynı sabitini** kullanır. Yeni talimat veya `/no_think` eki yoktur. CPU, `gpuLayers=0`, iki thread, 2048 bağlam ve en fazla 384 yeni token kullanılır.

[Qwen'in resmî model kartındaki düşünmesiz öneri](https://huggingface.co/Qwen/Qwen3-1.7B#best-practices) uygulanır: sıcaklık **0.7**, top-P **0.8**, top-K **20**, min-P **0**. Tekrar cezası `1.0`, presence cezası `0` ilk denemenin tarafsız ek tercihleridir; Qwen'in bu iki değeri zorunlu tuttuğu iddia edilmez. Seed belirtilmez; çalıştırmalar deterministik değildir. Ayarlar ekranda görünür; Llama ayarları değişmez.

`chatTemplate(... enableThinking:false)` ve gerçek `create(... enableThinking:false)` aynı mesajları ve tarih bağlamını kullanır. Ön incelemede oluşturulan prompt yeniden user mesajına sarılmaz.

Qwen üretimi başlamadan şu şartlar aranır:

1. Gerçek dosyanın metadatasındaki mimari `qwen3` olmalı ve sohbet şablonu boş olmamalı. Eksik şablonda genel ChatML'ye sessiz geçiş yapılmaz.
2. Şablon uygulanmış prompt, Qwen assistant başlangıcı ve **boş/kapalı düşünme bloğuyla** bitmeli: `<|im_start|>assistant\n<think>\n\n</think>\n\n` (beyaz boşluk farklılıkları kabul edilir).
3. Raporlanmış şablonlu token sayısı + 384, motorun bildirdiği bağlam kapasitesini aşmamalı.

Şartlar sağlanmazsa açık hata verilir; istek değiştirilmez, başka model denenmez. Son prompt, metadatadaki model adı/mimarisi, yerel dosya yolu, token ölçümleri, düşünmesiz şablon kontrolü ve bitiş nedeni “Çıkarım ayrıntıları” bölümündedir. Model kimliği ve örnekleme daima görünür. API'nin ham içerik cevabı düzeltilmeden/filtrelenmeden gösterilir; hazır cevap kullanılmaz. Süreler toplam ve üretim olarak ayrılır. `stop` anlamsal başarı sayılmaz.

## Kontroller

- **17/17** saf Dart servis kontrolü geçti.
- **43/43** Flutter testi geçti: 11 test kartı, 13 API/şablon, 13 graf ekranı regresyonu ve 6 indirme kontrolü. HTTP/çıkarım sınırları fake verilerle test edildi; ağdan model indirilmedi. İndirme testleri Llama dosyasının korunması, yanlış URL olmaması, HTTP hatası, eksik aktarım, mevcut dosyanın korunması, eşzamanlılık, iptal ve kısmi dosya temizliğini içerir.
- Gerçek kurulu şablon motoru, paketin **Qwen3-4B test şablonuyla** çalıştırıldı: `enableThinking:false` kapalı bloğu oluşturuyor; `true` oluşturmuyor. `test/fixtures/qwen3_package_4b_template.jinja` bu yerel paket fixture'ının kopyasıdır. **Bu fixture aday 1.7B GGUF'den çıkarılmış metadata değildir ve üretimde kullanılmaz.** Asıl adayın şablonu indirildikten sonra yukarıdaki çalışma anı kontrolüne tabidir.
- Resmî Qwen3-1.7B tokenizer yapılandırması web üzerinden incelendi; kabuktan metadata alma denemesi ağ engeline takıldı. Ağ ayarları değiştirilmedi. Uygulamanın indirme yolu henüz emülatörde denenmedi.
- Değişen dokuz Dart dosyası Analysis Server ile kontrol edildi; hata, uyarı veya lint bulgusu yok. Android APK derlemesi/kurulumu, 1,11 GB gerçek indirme ve Qwen çıkarımı bu görevde yapılmadı. Mevcut uygulama/model dosyalarına ADB ile yazılmadı.

## Kullanıcı için sonraki tek işlem

Güncel kodla uygulamayı emülatörde açıp Stüdyo içindeki **Qwen modelini indir (~1,11 GB)** düğmesine basın. İndirme üretim başlatmaz; tamamlanınca ayrı **Qwen ile D01 dene** düğmesi kullanılabilir. Paket/model değişimi veya eski Llama dosyasını silme gerekmez.
