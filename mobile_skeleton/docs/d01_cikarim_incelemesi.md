# D01 kısa çıkarım incelemesi — 16 Ekim 2026

> Aşama raporudur. Güncel durum ve sonraki işlem: [Devam notu](DEVAM_NOTU.md).

Kullanıcı önceki gerçek denemede toplam 61,62 sn, üretim 60,06 sn ve koşullara uymayan cevap bildirdi. Bu süreler kullanıcı gözlemidir. Bu incelemede gerçek GGUF ile yeni çıkarım yapılmadı; aşağıdaki doğrulamalar uygulama ve kurulu **llamadart 0.12.0** kaynakları ile izole testlerden gelir. Gerçek cihazdaki GGUF metadatası ve önceki çalışmanın token sayıları elde edilmedi. Bozuk cevabın kesin nedeni belirlenmiş değildir.

## Düğmeden çıkarıma

`lib/screens/synthetic_video_studio_screen.dart` içindeki ayrı `_d01Test`, `LocalLlamaTestCard` üzerinden `LocalLlamaTestService.run()` çağrısını alır. `LlamaModelService.getModelFile()` mevcut indirme kodunun yerel GGUF yolunu verir; dosya yoksa hata gösterilir. Yapılandırılmış dosya adı `Llama-3.2-1B-Instruct-Q4_K_M.gguf` olarak kalır. Dosya adından gerçek dosya içeriğinin doğru olduğu sonucu çıkarılmadı.

`lib/services/local_llama_test_service.dart` her denemede yeni runtime oluşturur. `lib/services/llamadart_test_runtime.dart`, `LlamaEngine(LlamaBackend())`, `setModel(LlamaModel(ModelSource.path(path)), ...)` ve `engine.create(messages, ...)` kullanır. Başarı, hata veya iptal sonunda motor kapatılır. Testler arasında sohbet geçmişi, ChatSession veya kaydedilmiş KV durumu yüklenmez. Varsayılan `reusePromptPrefix=true`, yeni açılan motoru önceki motorun konuşmasına bağlamaz.

Uygulamanın gönderdiği mesaj listesi **tek `user` mesajıdır**. Ayrı `system`, önceki `assistant` mesajı, araç, JSON şeması veya elle eklenmiş sohbet özel belirteci yoktur. Mevcut Senaryo Üret yolu, video prompt servisi ve graf bu çağrıya katılmaz; bu görevde değiştirilmedi.

## Tam mesaj içeriği

Önceki D01 isteğinin tamamı (`role: user`):

```text
D01 davranış kartı 0.2 için kısa bir Türkçe senaryo taslağı yaz.
30 aylık Deniz evde oyuncağıyla oynar. Çağrı öncesinde yetişkine dönük değildir.
Yetişkin doğal sesle yalnızca bir kez "Deniz" der. Dokunma, el sallama, ek jest veya eşzamanlı başka yönerge yoktur.
Çağrı duyulur; çocuğun başı ve çağıran yetişkinin konumu anlaşılır. Çağrı öncesi ve sonrası kesintisizdir.
Yalnızca üç kısa bölüm yaz; toplam en fazla 80 kelime kullan:
Ortak başlangıç: oyuncakla oyun ve tek isim çağrısı.
Alternatif A: çağrıdan sonra Deniz başını çağıran yetişkine çevirir.
Alternatif B: Deniz oyununa devam eder.
İki devam planlanan alternatiflerdir; aynı denemede art arda gerçekleşmez. Bunları gözlenmiş davranış veya video kanıtı sayma; davranış sonucu atama.
Tanı, risk puanı, klinik yorum, normal/anormal sınıflama veya klinik gecikme eşiği yazma. Sayısal tepki süresi uydurma.
JSON veya graf üretme; yalnızca üç kısa bölüm yaz.
```

Yeni D01 isteğinin tamamı (`role: user`):

```text
Türkçe bir çocuk videosu taslağı yaz. Yalnızca aşağıdaki üç başlığı kullan, her başlığa bir veya iki kısa cümle yaz:
Başlangıç: 30 aylık Deniz evde oyuncakla oynar ve annesine bakmaz. Annesi dokunmadan ve işaret etmeden bir kez ‘Deniz’ der.
Alternatif A: Deniz başını annesine çevirir.
Alternatif B: Deniz annesine dönmeden oyununa devam eder.
Bunlar aynı başlangıcın iki ayrı devamıdır. JSON veya ek açıklama yazma.
Bu taslağı doğal sahne anlatımına dönüştür.
```

Ekrandaki “Modele gönderilen istek” aynı sabiti gösterir. Cevap, API'nin döndürdüğü içerik parçaları birleştirilerek değiştirilmeden gösterilir; JSON/İngilizce/bozuk ifade silinmez, yeniden yazılmaz, hazır senaryoyla değiştirilmez. Paket kendi sohbet bitiş belirteçlerini ve çıktı ayrıştırmasını yönetir; gösterilen ham metin API'nin içerik çıktısıdır.

## Kurulu paketin sohbet şablonu

İncelenen kök: yerel Pub önbelleğindeki `llamadart-0.12.0/lib/src/`. GitHub ana dalı kullanılmadı.

| Kaynak | Doğrulanan davranış |
| --- | --- |
| `core/engine/engine.dart`, `create`, `_renderChatTemplate` | Ham mesajlar sohbet şablonundan geçirilir; yerel llama.cpp yolu oluşan prompt ile üretim yapar. |
| `core/engine/chat_template_renderer.dart` | Model şablonu override edilmemişse `tokenizer.chat_template` metadatasını kullanır; assistant üretim başlangıcını şablona aktarır. |
| `core/template/chat_template_engine.dart` | Şablon yoksa genel ChatML şablonuna geçebilir; şablon render hatası istisna üretir. Bu, hazır cevap fallback'i değildir. |
| `core/template/handlers/llama3_handler.dart` | Llama 3 şablonu seçilirse GGUF şablonu render edilir; araçsız çağrıda `<\|eot_id\|>` metin durdurucusu kullanılır. `contentOnly` format kodu bu yolda şablon uygulanmadığı anlamına gelmez. |
| `core/engine/chat_completion_request_planner.dart` | Şablon durdurucuları ve `GenerationParams.stopSequences` birleşir; uygulama JSON yanıt biçimi istemez. |
| `backends/llama_cpp/llama_cpp_service.dart` | Örnekleme ve token üretimi yerel native llama.cpp üzerinden yürür. |

Uygulama elle şablonlamadığı ve `create` ham mesaj aldığı için çift şablonlamaya dair bulgu yok. Yanlış rol veya geçmiş taşıma bulgusu yok. Bununla birlikte **telefondaki GGUF'nin hangi şablonu içerdiği ve o denemede hangi şablonun uygulandığı henüz çalışma anında doğrulanmadı**. Dosya adı, tek başına bu doğrulamanın yerine geçmez. Şablonun kendisi varsayılan bir system metni üretebilir; uygulamanın açıkça göndermediği system metni olmadığını bundan dolayı iddia etmiyoruz.

Yeni inceleme, `chatTemplate` ile render edilmiş promptu ve token sayımını alır; ardından **render edilmiş metin yerine aynı ham mesaj listesi** `create`'e verilir. İki çağrı aynı `templateNow` değerini kullanır. Bu ön inceleme ikinci bir sohbet katmanı eklemez.

## Sınırlar, örnekleme, durma

| Ayar | Koddan doğrulanan değer |
| --- | --- |
| İstenen bağlam / en fazla yeni token | 2048 / 384; değiştirilmedi |
| CPU | `gpuLayers=0`, iki üretim ve iki batch thread, batch/microbatch 64 |
| Örnekleme | `temp=0.8`, `topK=40`, `topP=0.9`, `minP=0`, tekrar cezası `1.1`, presence cezası `0` |
| Seed | Uygulama belirtmiyor; kurulu native kod zaman tabanlı seed seçiyor. Önceki denemenin gerçek seed'i bilinmiyor. |
| Ek stop / JSON grammar | Uygulamada boş stop listesi, grammar yok, responseFormat yok, araç yok |
| Thinking | `enableThinking=false`; bunun modelin her metin davranışını engellediği varsayılmadı |

Native döngü çıktı token sınırı, bağlam dolması, modelin EOG tokenı, etkin metin durdurucusu veya iptal ile sonlanabilir. İşlem hataları da akışı kesebilir. API'nin `finishReason=length` değeri token sınırı ve bağlam sınırını birlikte kapsar; `stop` EOG ile metin durdurucusunu tek başına ayırmaz.

Önceki kod yalnızca `chunk.text` tuttuğu için usage ve finish reason kayboluyordu. **Önceki isteğin token sayısı, üretilen token sayısı ve durma nedeni ölçülmüş veri olarak elimizde yok.** Süreden veya 384 üst sınırından gerçek token sayısı çıkarılmadı. Bağlam taşması, erken stop veya örnekleme ayarlarının bozuk cevaba neden olduğu doğrulanmadı.

## Yapılan küçük değişiklikler

- İstek yukarıdaki metne sadeleştirildi; örnekleme, model, bağlam ve çıktı üst sınırı sabit bırakıldı.
- D01 için “Çıkarım ayrıntıları” paneli eklendi: tam rol/mesaj listesi, GGUF şablonu, render edilmiş istek, format kodu, şablonlu token sayımı, motorun bildirdiği bağlam kapasitesi, etkin metin durdurucuları, örnekleme, varsa native usage ve API bitiş nedeni.
- Şablonlu sayım `addSpecial=false` ile yapılır; backend üretiminin native istek sayımı ayrıca gösterilir. Aynı sayılar olduğu varsayılmaz. Raporlanmayan ölçüm için sayı uydurulmaz.
- Şablonlu istek sayısı + 384, motorun bildirdiği kapasiteyi aşarsa üretim açık hata ile durur; istek sessizce kesilmez. Kontrol, native usage geldiğinde ayrıca görülebilen gerçek üretim sayımının yerini tutmaz.
- `length` bitişinde cevabın tamamlanmamış olabileceği belirtilir. Ölçümler kapanışta korunur, sonraki denemede sıfırlanır. Ham cevaba müdahale edilmez.

Bu düzeltmeler gözlemlenebilirliği sağlar; cevabın artık başarılı olacağı henüz doğrulanmadı. Sonraki denemede önce metnin üç bölüme uyumu, ardından gerçek şablon/token/bitiş bilgileri birlikte incelenmelidir.

## Kontroller

- 16/16 saf Dart servis kontrolü: hatalar, eşzamanlı istek kilidi, iptal, kaynak kapatma, ölçüm saklama/sıfırlama.
- 28/28 Flutter testi: 9 test kartı, 6 yayımlanmış API sınırı, 13 mevcut graf ekranı regresyon testi. Sınır, rol/şablon ayrımı, usage/bitiş nedeni ve boşluklar dahil ham metin koruma test edildi. Bu testlerdeki token sayıları fake test verisidir; gerçek model ölçümü değildir.
- Değişen yedi Dart dosyasının Analysis Server kontrolü: hata, uyarı veya lint yok. Testler mevcut SDK'nın derleyicisi ve `flutter_tester` ile, mevcut paket çözümlemesi üzerinden çalıştırıldı; paket indirilmedi.
- Bu görevde yeni Android derlemesi ve gerçek model denemesi yapılmadı. Mobil model kalitesi ve cihazdaki gerçek GGUF şablonu henüz yeniden doğrulanmadı.

Sonraki tek deneme: güncel uygulamayı emülatörde yeniden başlatıp Stüdyo → D01 senaryo testi → D01 senaryosu üret işlemini çalıştırın; ham cevap ile “Çıkarım ayrıntıları” panelini birlikte inceleyin.
