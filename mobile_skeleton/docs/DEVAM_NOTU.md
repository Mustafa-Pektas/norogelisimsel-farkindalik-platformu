# Devam notu

Bu not, önceki inceleme raporlarının ardından geçerli olan durumu özetler.

- **Llama emülatörde gerçek çıkarım yaptı.** İlk kısa model testinde “Merhaba!” cevabı alındı. Türkçe D01 denemeleri yetersiz: bozuk/tekrarlı metin ve istenmeyen JSON görüldü. İngilizce D01 cevabı daha anlaşılır, ancak kurallara tam uymuyor. Bunlar kullanıcının gerçek emülatör denemelerindeki gözlemleridir; talimatlara uyum veya senaryo doğruluğu otomatik doğrulanmış değildir.
- **Qwen entegrasyonu eklendi; gerçek indirme/çıkarım henüz denenmedi.** Ayrı seçenek `Qwen3-1.7B-Q4_K_M.gguf`; kullanıcı düğmeye basmadan indirme başlamaz. Llama dosyası korunur. CPU, 2048 bağlam, 384 çıktı tokenı, düşünmesiz şablon kontrolü ve Qwen'in önerdiği temel örnekleme ayarları kullanılır. Kaynak düzeyinde destek bulunması cihazda başarılı çalıştığının kanıtı değildir.
- **Senaryo Üret akışı hâlâ şablon kullanıyor.** Ayrı yerel model testlerindeki gerçek çıkarım, bu eski akışa bağlanmadı. Modelin indirilmiş olması, Senaryo Üret düğmesinin LLM kullandığı anlamına gelmez.
- **Senaryo grafı elle hazırlanmış örnektir.** Tek asset, altı sahne ve iki alternatif devam içerir. Genel veri modeli JSON okuma/yazma ve bağlantı doğrulaması yapar; görsel ekran kısa kutular, sahne ayrıntıları ve görünüm kontrolleri sunar. Graf model çıktısı veya video analizi sonucu değildir. Dalları kimin seçeceği belirlenmemiştir.

Klinik tanı, risk puanı, otomatik davranış sonucu veya gecikme hesabı eklenmedi. Video analizi ayrı çalışma hattıdır; sentetik videolar dışarıda hazırlanacaktır.

## Kontroller

Son kod kontrolleri: 43 Flutter testi ve 17 servis kontrolü geçti; ilgili yeni/değişen Dart kodunun statik analizi temiz. Graf modelinin 24 kontrolü de geçti. Testlerdeki kontrollü cevaplar gerçek model sonucu değildir. Qwen'in gerçek GGUF şablonu, indirme sonrasında çalışma anında ayrıca doğrulanır. Android arm64 ve iOS bu çalışma kapsamında çalıştırılmadı.

Uygulama klasöründen normal Flutter ortamında ilgili kontroller:

```powershell
dart --disable-dart-dev --packages=.dart_tool/package_config.json test/scenario_graph_checks.dart
dart --disable-dart-dev --packages=.dart_tool/package_config.json test/local_llama_test_checks.dart
flutter test test/scenario_graph_screen_test.dart test/local_llama_test_card_test.dart test/llamadart_test_runtime_test.dart test/local_model_download_test.dart
```

## Bir sonraki küçük deneme

Güncel uygulamayı emülatörde açıp **Qwen modelini indir (~1,11 GB)** düğmesini kullanın. İndirme başarıyla tamamlandıktan sonra ayrı **Qwen ile D01 dene** kartıyla aynı sade Türkçe isteği sınayın. Ham cevap, model kimliği, gerçek prompt, bitiş nedeni ve süreler birlikte incelenmelidir; hatada hazır cevaba veya başka modele geçilmez.

İlgili ayrıntılar: [Qwen karşılaştırması](qwen_d01_karsilastirmasi.md), [son prompt incelemesi](d01_prompt_karsilastirmasi.md), [D01 çıkarım incelemesi](d01_cikarim_incelemesi.md). Bu eski raporlardaki “henüz denenmedi” ifadeleri raporun yazıldığı aşamaya aittir; güncel kullanıcı gözlemleri için bu not esas alınır.
