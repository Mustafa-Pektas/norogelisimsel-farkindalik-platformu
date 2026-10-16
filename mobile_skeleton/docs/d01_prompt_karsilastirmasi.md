# D01 son prompt ve İngilizce karşılaştırma — 16 Ekim 2026

> Aşama raporudur. Güncel durum ve sonraki işlem: [Devam notu](DEVAM_NOTU.md).

İkinci Türkçe denemenin 64,51 sn sürmesi, bozuk/tekrarlı JSON üretmesi ve `stop` ile bitmesi kullanıcı tarafından bildirildi. `stop`, cevabın talimata uyduğunu göstermez; tek başına EOG tokenı ile metin durdurucusunu ayırmaz.

## Gerçekte ne incelendi?

Çalışan emülatöre ADB ile salt okunur erişildi. `com.neuroapp.neuro_awareness_app` uygulamasının `app_flutter/models/Llama-3.2-1B-Instruct-Q4_K_M.gguf` dosyasının başlık/metadatası okundu; model indirilmedi veya değiştirilmedi. GGUF v3, model adı `Llama 3.2 1B Instruct`, BOS `<|begin_of_text|>`, EOS `<|eot_id|>` bulundu. Metadatanın bitiş ofseti 7.822.851 bayttı; yalnızca baştaki sınırlı bölüm okundu, ağırlıklar yüklenmedi.

**Şablon tanımına bakmakla yetinilmedi.** Mevcut Türkçe D01 mesajı ve bu cihaz dosyasındaki gerçek `tokenizer.chat_template`, kurulu **llamadart 0.12.0** paketinin `ChatTemplateEngine.render` çağrısına verildi. `addAssistant=true`, `enableThinking=false`, araç ve responseFormat olmadan, 16 Ekim 2026 tarih bağlamıyla son prompt yeniden üretildi. Aynı renderer, `LlamaEngine.create` yolunda da kullanılıyor. Yeniden üretilen tam metin aşağıdadır.

Sınır: Bu, önceki çıkarım sırasında yakalanmış native giriş kaydı değildir. O denemenin bellekteki promptuna veya native token dizisine erişilmedi; birebir aynı giriş baytları kullanıldığını sonradan kanıtlamıyoruz. Yeni gerçek model çıkarımı yapılmadı. Buradaki çalışma **cihazdaki dosyanın şablonu + mevcut istek + kurulu gerçek renderer** kontrolüdür; tahmini bir Llama şablonu veya Python ile taklit edilmiş Jinja çıktısı değildir.

## Bulgular

- Başlangıç bir kez BOS, sonra şablonun eklediği `system` bloğudur. System içeriği yalnızca bilgi kesim tarihi ve bugünün tarihidir.
- Sonra tek `user` bloğunda mevcut D01 isteğinin tamamı bulunur; mesaj bölünmez veya önceki konuşmayla birleşmez. Ardından `<|eot_id|>` gelir.
- Son bölüm tam olarak `<|start_header_id|>assistant<|end_header_id|>` ve iki yeni satırdır. Assistant cevabı önceden doldurulmamıştır.
- Şablon tanımındaki `Given the following functions`, `To call a function`, `Respond in the format` ve `Environment: ipython` ifadeleri **oluşan promptta yoktur**. JSON yazmama talimatı kullanıcı mesajında kalır.
- Sonuç `format=0` (`contentOnly`), `grammar=null`, boş grammar tetikleyicileri ve `<|eot_id|>` durdurucusudur. Format 0, sohbet başlıklarının uygulanmadığı anlamına gelmez.
- Çift şablonlama veya yanlışlıkla etkinleşen araç çağrısı bulgusu çıkmadı. Bozuk cevabın Türkçe dil başarımından mı, genel talimat takibinden mi kaynaklandığı henüz bilinmiyor.

Kurulu paketten doğrulanan yol (`llamadart-0.12.0/lib/src/`):

| Kaynak | İlgili davranış |
| --- | --- |
| `core/engine/engine.dart:1635`, `:1683` | `create` ham mesajları render eder, yerel llama.cpp yoluna `result.prompt` verir. |
| `core/engine/chat_template_renderer.dart` | GGUF şablonu ve mesajları `ChatTemplateEngine.render` çağrısına iletir. |
| `core/template/chat_template_engine.dart:151` | Araç yolu yalnızca araç listesi boş değilse ve toolChoice izin veriyorsa açılır. Varsayılan `auto`, tek başına araç açmaz. |
| `core/template/handlers/llama3_handler.dart:75` | Araç verilmemişse şablona `tools=null` gider. GGUF'nin `tools is not none` koşullu fonksiyon talimatları çalışmaz. |
| `core/template/handlers/llama3_handler.dart:83` | Araçsız sonuç `contentOnly`; JSON araç grammar'ı oluşturulmaz. |
| `core/engine/chat_completion_request_planner.dart:176` | Araç çağrısı ayrıştırması da dolu araç listesi gerektirir; bu istekte kapalıdır. |

## Yeniden oluşturulan tam Türkçe son prompt

```text
<|begin_of_text|><|start_header_id|>system<|end_header_id|>

Cutting Knowledge Date: December 2023
Today Date: 16 Oct 2026

<|eot_id|><|start_header_id|>user<|end_header_id|>

Türkçe bir çocuk videosu taslağı yaz. Yalnızca aşağıdaki üç başlığı kullan, her başlığa bir veya iki kısa cümle yaz:
Başlangıç: 30 aylık Deniz evde oyuncakla oynar ve annesine bakmaz. Annesi dokunmadan ve işaret etmeden bir kez ‘Deniz’ der.
Alternatif A: Deniz başını annesine çevirir.
Alternatif B: Deniz annesine dönmeden oyununa devam eder.
Bunlar aynı başlangıcın iki ayrı devamıdır. JSON veya ek açıklama yazma.
Bu taslağı doğal sahne anlatımına dönüştür.<|eot_id|><|start_header_id|>assistant<|end_header_id|>


```

## Eklenen karşılaştırma

Türkçe test değiştirilmedi. Stüdyoda ayrı **D01 İngilizce karşılaştırma → D01 İngilizce dene** kartı eklendi. `LocalLlamaTestRequest.d01English`, aynı olayları İngilizce isteyip İngilizce cevap bekler: 30 aylık Deniz, oyuncakla oyun, anneye bakmama, dokunma/işaret olmadan tek isim çağrısı, başını anneye çevirme veya dönmeden oyuna devam etme. Üç başlık, başlık başına bir/iki kısa cümle, ayrı alternatifler, JSON/ek açıklama yasağı ve doğal sahne anlatımı isteği korunur. Tam İngilizce metin ekrandaki “Modele gönderilen istek” panelindedir.

Aynı yerel dosya, CPU, 2048 bağlam, 384 çıktı üst sınırı ve örnekleme ayarları korunur. Her test yeni motor ve tek user mesajı kullanır. Seed belirtilmediği için denemeler deterministik değildir; tek çift deneme dil kaynaklı bir nedeni kesin kanıtlamaz.

İki testin ham API metinleri, süreleri ve çıkarım ayrıntıları ayrı servis durumlarında tutulur; İngilizce testi çalıştırmak Türkçe cevabı değiştirmez. Cevaplar düzeltilmez, filtrelenmez veya hazır yanıtla değiştirilmez. Bunlar ekranın yaşam süresindeki durumlardır; uygulama yeniden başlatılınca kalıcı konuşma arşivi olarak yüklenmez. Ortak kilit ikinci native çıkarımı engeller; model yönetimi üç testten herhangi biri çalışırken kilitlidir. Mevcut Senaryo Üret, graf, paket sürümleri ve model değiştirilmedi.

## Kontroller ve sonraki adım

- 17/17 saf Dart servis kontrolü geçti; Türkçe/İngilizce kilit ve ayrı ham cevapların korunması dahil.
- 32/32 Flutter testi geçti: 10 test kartı, 9 API/şablon testi, 13 mevcut graf ekranı testi. Şablon testleri gerçek kurulu renderer'ı ve cihazdan alınan fixture'ı kullanır; metin üretimi testlerde fake'tir.
- Değişen altı Dart dosyasında statik analiz: hata/uyarı/lint yok. SDK'nın mevcut derleyicisi, Flutter test motoru ve Analysis Server kullanıldı; paket indirilmedi.
- Android için yeni derleme/kurulum ve İngilizce gerçek model denemesi yapılmadı. Emülatördeki mevcut uygulama/cevap bu çalışma sırasında yeniden başlatılmadı veya değiştirilmedi.

Şablon fixture'ı `test/fixtures/llama32_device_template.json`; yalnızca şablon ve BOS/EOS metinlerini içerir, ağırlık içermez. Fixture SHA256: `ea7028f25e4a49092b6f1c237d6856295182938e10115c3aabde1721a8767ca5` (model dosyasının hash'i değildir).

Sonraki deneme: güncel uygulamada Stüdyo → **D01 İngilizce karşılaştırma → D01 İngilizce dene**. Ham cevabın üç başlığa ve olaylara uyumunu, bitiş nedenini ve gerçek promptu Türkçe denemeyle karşılaştırın.
