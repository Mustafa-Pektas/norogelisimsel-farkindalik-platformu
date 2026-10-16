# Yerel GGUF metin testi

> Aşama raporudur. Güncel durum ve sonraki işlem: [Devam notu](DEVAM_NOTU.md).

Bu işlem Senaryo Stüdyosu'ndaki ayrı **Modeli test et** kartıdır. Senaryo Üret
düğmesini, şablonları veya Senaryo Grafı örneğini değiştirmez.

## Paket ve API kararı

- Bağımlılık tam sürümle `llamadart: 0.12.0` olarak sabitlendi; `^` kullanılmadı.
  İncelemede pub.dev ana sayfası 0.13.1 gösterirken `latest` API sayfası 0.12.0'a
  yönlendi, başka `latest` sayfalarında daha eski sürümler görüldü. Ana dal veya
  sürümü belirsiz `latest` örnekleri yerine erişilebilen yayımlanmış 0.12.0 motor
  API'si esas alındı. Bu test için en yeni sürüm gerektiği varsayılmadı.
- Gereksinimler: Dart >=3.10.7, Flutter >=3.38.0. Mevcut SDK dosyasında Flutter
  3.47.5 / Dart 3.13.4 okundu; `dart --version` da 3.13.4 döndürdü.
- 0.12.0'ın README'sindeki GGUF native eşleşmesi `llamadart-native v0.6.0-2`.
  Native dosyaları paketin build hook'u indirip uygulamaya ekler; ayrı native
  paket veya elle kopyalanan bir `.so` eklenmedi. Model bu işlemle indirilmez.
- Hook yapılandırması yalnızca `llama_cpp` ve `cpu` seçer. LiteRT-LM, Vulkan,
  görüntü modelleri ve Apple companion paketleri eklenmedi.
- Resmî tabloda Android arm64 ve x64 (x86_64 emülatör) GGUF/CPU desteği var.
  32 bit Android hedefleri bu denemeye dahil değildir. Cihazda çalışma ve
  native ABI uyumu henüz denenmedi; belgede desteklenmesi çalışma kanıtı değildir.
- Kullanılan çağrılar: `LlamaEngine(LlamaBackend())`,
  `setModel(LlamaModel(ModelSource.path(path)), params: ModelParams(...))`,
  `create(..., params: GenerationParams(maxTokens: 32))`,
  `cancelGeneration()` ve `await dispose()`.
- İstek: `Türkçe tek cümleyle merhaba de.`; bağlam 512, GPU katmanı 0, CPU
  thread sayısı 2, batch/micro-batch 64, en fazla 32 yeni token. Modelin kendi
  chat şablonunu motor uygular; uygulama yanıt şablonu veya fallback üretmez.
- Native backend'in belgelenen worker isolate mekanizması kullanılır. Bu
  uygulamada ana isolate üzerinde senkron tensor/çıkarım döngüsü yoktur.

Resmî kaynaklar:

- [Yayımlanmış 0.12.0 paketi ve native sürüm eşleşmesi](https://pub.dev/packages/llamadart/versions/0.12.0)
- [0.12.0 LlamaEngine API](https://pub.dev/documentation/llamadart/0.12.0/llamadart/LlamaEngine-class.html)
- [Android destek tablosu](https://llamadart.leehack.com/docs/platforms/support-matrix)
- [Native hook yapılandırması](https://llamadart.leehack.com/docs/platforms/native-build-hooks)
- [Worker isolate mimarisi](https://llamadart.leehack.com/docs/guides/architecture)
- [Resmî kaynak depo](https://github.com/leehack/llamadart)

## Dosya, iptal ve hata davranışı

Dosya yolu mevcut `LlamaModelService.getModelFile()` fonksiyonundan alınır:
uygulamanın belgeler dizinindeki `models/Llama-3.2-1B-Instruct-Q4_K_M.gguf`.
Dosya yoksa **Model indirilmedi** gösterilir. Bu test otomatik model indirmez.
Telefon ve emülatör farklı uygulama depolarına sahiptir; telefondaki dosya
emülatörde var kabul edilmez.

Durumlar yükleme, üretim, iptal bekleme, kaynak kapatma ve terminal sonuç olarak
ayrıdır. Tamamlandı yalnızca boş olmayan cevap alındıktan ve kaynaklar
kapatıldıktan sonra gösterilir. Kısmi cevap hata/iptal durumunda kısmi olarak
kalır; örnek cevapla tamamlanmaz. Toplam süre dosya kontrolü, yükleme, üretim ve
kapatmayı; üretim süresi chat hazırlığı ve metin akışını kapsar.

İptal `cancelGeneration()` çağırır. Yüklemeyi anında durdurduğu varsayılmaz:
yükleme tamamlanırsa üretime geçilmeden motor kapatılır. Native işlem güvenle
sonlanıp `dispose()` tamamlanmadan ikinci test açılmaz. Ekrandan ayrılma aynı
temizleme yolunu kullanır; isolate zorla öldürülmez. Native kapatma hata verirse
yeni model açılmaz ve uygulamayı tamamen yeniden başlatma bilgisi gösterilir.
Model testi sırasında aynı ekrandaki indirme/silme işlemleri kilitlenir;
indirme sürerken test düğmesi devre dışıdır.

## Bu ortamda doğrulananlar ve engeller

- 13 servis yaşam döngüsü testi geçti: eksik dosya, boş cevap, hata, kısmi çıktı,
  yükleme/üretim iptali, paralel istek engeli, tekrar deneme ve kapatma hatası.
- Flutter test motorunda 5 kart testi geçti: durum/çıktı/süre, düğmeden hata,
  iptal, indirme kilidi, 320×640 ekranda 2× yazı ve kaydırma.
- Senaryo grafı modelinin 24 testi geçti. Graf dosyalarına dokunulmadı.
- Test runtime'ı yalnızca `test/support` içindedir; kontrollü cevaplar yaşam
  döngüsü/UI kontrolü içindir. Uygulama bu sınıfı import etmez. Bu testler gerçek
  GGUF çıkarımı kanıtı değildir.
- Statik analiz servis, kart, stüdyo bağlantısı ve testler için çalıştırıldı.
  Yeni native adaptörün tam tür/API kontrolü paket çözümlenene kadar engellidir:
  `package:llamadart/llamadart.dart` bulunamadı.
- `flutter pub get` ve Android debug APK derleme denemeleri
  `<Flutter SDK>/bin/cache/lockfile` erişim hatasıyla durdu. Paket sunucusuna
  doğrudan erişim denemesi de `WinError 10061` verdi. Ağ/SDK ayarları değiştirilmedi.
- `pubspec.lock` ve mevcut `package_config.json` elle değiştirilmedi. Paket ve
  native arşivler bu ortamda kurulmadı. Gerçek model yükleme/üretim, APK derlemesi
  ve iOS çalışması henüz doğrulanmadı.

## Normal PowerShell ile tamamlama

Uygulama kökünde çalıştırın. Bu komutlar model indirmez; paket çözümleme ve ilk
derleme sırasında gereken native kütüphaneler için ağ erişimi gerekir.

```powershell
Set-Location .\mobile_skeleton
flutter pub get
```

Paket çözümleme başarılı olduktan sonra, gerçek paket API'siyle kontroller:

```powershell
flutter analyze lib/services/local_llama_test_service.dart lib/services/llamadart_test_runtime.dart lib/widgets/local_llama_test_card.dart lib/screens/synthetic_video_studio_screen.dart test/local_llama_test_card_test.dart test/local_llama_test_checks.dart test/support/fake_local_llama_runtime.dart
dart --disable-dart-dev --packages=.dart_tool/package_config.json test/local_llama_test_checks.dart
dart --disable-dart-dev --packages=.dart_tool/package_config.json test/scenario_graph_checks.dart
flutter test test/local_llama_test_card_test.dart test/scenario_graph_screen_test.dart
flutter build apk --debug --target-platform android-x64,android-arm64
flutter run -d emulator-5554
```

Emülatör kimliği farklıysa `flutter devices` ile listelenen kimliği kullanın.
Uygulama açılınca Senaryo Stüdyosu → Yerel model testi → **Modeli test et**.
Gerçek cevabın ve sürenin görünmesini, iptali ve tekrar denemeyi kontrol edin.
Dosya o emülatörde yoksa test hata vermelidir; sahte başarı beklenmez.
