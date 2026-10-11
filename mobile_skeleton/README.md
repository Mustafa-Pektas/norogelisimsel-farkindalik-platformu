# Nörogelişimsel Farkındalık Platformu (Mobil Uygulama)

> **12–36 Aylık Erken Çocukluk Dönemine Yönelik Sentetik Video Tabanlı Davranış Analizi ve İnteraktif Simülasyon Sistemi**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Material 3](https://img.shields.io/badge/Material_Design-3-7C3AED)](https://m3.material.io)
[![Gemini LLM](https://img.shields.io/badge/Google_Gemini-1.5_Flash-4285F4?logo=google&logoColor=white)](https://ai.google.dev)
[![Platform](https://img.shields.io/badge/Platform-Android_%7C_iOS-green)](https://flutter.dev)

---

## 📌 Proje Özeti ve Amacı

Bu mobil uygulama; **12–36 aylık** erken çocukluk döneminde nörogelişimsel gelişim göstergelerini (isme tepki, ortak dikkat, işaret etme, akran ilgisi vb.) interaktif video simülasyonları ve yapay zekâ destekli senaryolar üzerinden takip etmeyi, aileler ve uygulayıcılar için klinik farkındalık oluşturmayı amaçlayan **tamamen bağımsız (standalone) bir mobil sağlık/eğitim platformudur.**

### ⚠️ Kritik Klinik Sınır ve Etik Bildirim
* **Bu uygulama kesinlikle bir tıbbi tanı veya otizm teşhis aracı DEĞİLDİR.**
* Sistem hiçbir koşulda tıbbi hüküm üretmez; önceden tanımlanmış klinik normları anlaşılır bir dille sunarak kullanıcıya **Yeşil (Tipik)**, **Sarı (Takip)** ve **Kırmızı (Risk)** gelişimsel farkındalık göstergeleri sağlar.
* Şüpheli durumlarda aileleri RAM (Rehberlik ve Araştırma Merkezleri) ve Çocuk Ergen Ruh Sağlığı uzmanlarına yönlendirir.

---

## 📱 5 Temel Çalışma Modu

Uygulama, alt navigasyon paneli ve ana kontrol paneli üzerinden 5 entegre mod sunar:

### 1. 📊 Video Analiz Modu (`VideoAnalysisScreen`)
* Kamera kaydı alma veya galeriden video yükleme imkânı.
* Zaman damgalı klinik bulgular (`00:02 Tepkisizlik`, `00:10 Tekerlek Çevirme`, `00:26 Ortak Dikkat Yok`).
* Dinamik bildirim çubukları ve tam ekran interaktif video inceleme deneyimi.

### 2. 🎬 İnteraktif Video Simülatörü (`InteractivePlayerScreen`)
* 12 klinik ontolojinin dallanan video simülasyonu (Node 0 kök video ve Yeşil/Sarı/Kırmızı dallar).
* Gecikme süresi ($\Delta t$), yönelim açısı (Yaw $\ge 45^\circ$) ve anlık klinik sınıflandırma metrikleri.
* 12–18 Ay, 18–24 Ay ve 24–36 Ay sürüklemeli yaş seçici kartı.

### 3. 🌳 Simülasyon ve Eğitim Modu (`SimulationModeScreen`)
* **Standart Çekim Protokolü:** Klinisyen veya ebeveyn için 3 adımlı net yönerge (Ne Yapacaksınız, Kamera & Ortam Düzeni, İzlenecek Tepki).
* **Yaşa Özel Norm Bilgisi:** Seçili yaş diliminde çocuktan beklenen davranış ve risk eşiği.
* **FSM Durum Ağacı:** Tipik, Takip ve Risk tepkileri için klinik anlamlandırma kartları.
* **Yapay Zekâ ile Ortam Uyarlama:** Google Gemini LLM ve RAG motoru kullanılarak ebeveynin ev ortamı ve oyuncaklarına göre senaryoyu anında kişiselleştirme.

### 4. 🎥 Sentetik Video Stüdyosu (`VeoStudioScreen`)
* Google Veo ve yeni nesil video üretim modelleri için klinik video prompt oluşturucu.
* Tutarlılık belirteçleri (`[CH-01]`, `[MOM-01]`, `[ENV-LIV-01]`), sinematik kamera açıları ve negatif prompt optimizasyonu.

### 5. 📖 Gelişim Rehberi & Klinik Normlar (`GuidanceTab` / `InstitutionsScreen`)
* 12 hedef davranış göstergesinin yaşa göre ayrıntılı norm kırılımları.
* Türkiye geneli Yetkili Sağlık Merkezleri ve RAM rehberi.

---

## 🧬 12 Temel Klinik Davranış Ontolojisi

| Kod | Davranış Adı | Yaş Aralığı | Kategori | Beklenen Tipik Davranış |
| :--- | :--- | :---: | :--- | :--- |
| **ONT-01** | İsme Tepki | 12–24 Ay | Sosyal Yönelim | 1–2 çağrıda başını ve bakışını ses yönüne çevirme |
| **ONT-02** | Ortak Dikkate Yanıt (RJA) | 12–36 Ay | Ortak Dikkat | İşaret edilen uzaktaki nesneye bakış yönlendirme |
| **ONT-03** | Ortak Dikkat Başlatma (IJA) | 14–36 Ay | Sosyal Paylaşım | Nesne ile yetişkin arasında ardışık bakış kaydırma |
| **ONT-04** | Deklaratif İşaret Etme | 12–36 Ay | İletişim | İlgi paylaşımlı işaret parmağı kullanımı |
| **ONT-05** | İstek Bildirme (Protoimperatif) | 12–24 Ay | İletişim | Nesneye uzanırken yetişkinle göz teması kurma |
| **ONT-06** | El Aleti Olarak Kullanma | 12–36 Ay | İletişim | Yetişkinin elini araç gibi kullanmama / göz teması |
| **ONT-07** | Ce-e Oyunu Katılımı | 12–24 Ay | Sosyal Oyun | Beklenti, gülümseme ve oyunu devam ettirme isteği |
| **ONT-08** | Nesne Getirme ve Gösterme | 15–36 Ay | Sosyal İlgi | Sevdiği oyuncağı paylaşmak amacıyla getirme |
| **ONT-09** | Duygulanım Paylaşımı | 12–36 Ay | Sosyo-Duygusal | Başarı veya sevinç anında yetişkine gülümseyerek bakma |
| **ONT-10** | Yönerge Takibi | 18–36 Ay | Alıcı Dil | Jest desteği olmadan tek adımlı yönergeyi yerine getirme |
| **ONT-11** | İletişimsel Jestler | 12–24 Ay | Sözel Olmayan Dil | Baybay, baş sallama, alkış gibi jestleri anlamlı kullanma |
| **ONT-12** | Akran İlgisi ve Paralel Oyun | 24–36 Ay | Akran Etkileşimi | Akranını izleme, yan yana oynama ve oyunu taklit etme |

---

## 🚀 Kurulum ve Çalıştırma

### Gereksinimler
* [Flutter SDK](https://flutter.dev/docs/get-started/install) (`>= 3.13.4`)
* [Dart SDK](https://dart.dev/get-dart) (`>= 3.1.0`)
* Android Studio / Xcode ve Android SDK
* Fiziksel Android/iOS cihaz veya Emülatör

### 1. Bağımlılıkları Yükleyin
```bash
flutter pub get
```

### 2. Uygulamayı Geliştirme Modunda Başlatın
```bash
flutter run
```

### 3. Release APK Derleyin
```bash
flutter build apk --release
```
Derlenen APK dosyası şu dizinde hazır olacaktır:  
`build/app/outputs/flutter-apk/app-release.apk`

---

## 🔑 Gemini API Yapılandırması

Uygulama, yapay zekâ destekli senaryo uyarlama özelliğinde **Google Gemini 1.5 Flash** modelini kullanır:
1. Uygulamayı açın ve sağ üst köşedeki **Anahtar (`🔑`)** simgesine dokunun.
2. [Google AI Studio](https://aistudio.google.com)'dan aldığınız ücretsiz Gemini API anahtarınızı girip **"Kaydet"** butonuna basın.
3. Anahtar cihaz hafızasında güvenle saklanır (`SharedPreferences`).
* *Not: API anahtarı girilmese bile uygulama yerel klinik kurallarla (offline kural tabanlı) senaryo uyarlamaya devam eder.*

---

## 📁 Proje Dosya Yapısı

```text
mobile_skeleton/
├── android/                   # Android yapılandırması ve manifest
├── assets/
│   └── videos/               # 12 ontolojiye ait sentetik karar ağacı videoları
├── lib/
│   ├── main.dart             # Uygulama başlangıç noktası (Tema & Material 3)
│   ├── models/
│   │   ├── models.dart       # Video analiz ve klinik bulgu modelleri
│   │   └── scenarios_data.dart # 12 ontoloji, yaş normları ve FSM dallanma verileri
│   ├── screens/
│   │   ├── home_screen.dart             # Ana panel ve 5 sekmeli navigasyon barı
│   │   ├── video_analysis_screen.dart   # Video analiz ve gözlem ekranı
│   │   ├── interactive_player_screen.dart # İnteraktif dallanan video oynatıcı
│   │   ├── simulation_mode_screen.dart  # Klinik simülasyon ve eğitim modu
│   │   ├── veo_studio_screen.dart       # Sentetik video stüdyosu ve prompt motoru
│   │   └── institutions_screen.dart     # Yetkili sağlık merkezleri rehberi
│   ├── services/
│   │   ├── llm_rag_service.dart         # Gemini LLM ve klinik RAG servis motoru
│   │   └── veo_prompt_service.dart      # Veo video üretim prompt servisi
│   └── widgets/
│       ├── age_slider_card.dart         # Sürüklemeli yaş grubu seçici kartı
│       ├── api_key_dialog.dart          # Gemini API anahtarı yönetim diyaloğu
│       ├── expandable_finding_card.dart # Açılabilir klinik bulgu kartları
│       ├── floating_video_controls.dart # Video oynatıcı yüzen kontrol çubuğu
│       ├── fullscreen_video_screen.dart # Tam ekran video ve karar paneli
│       └── scenario_picker_sheet.dart   # 12 ontoloji alt sayfa seçicisi
└── pubspec.yaml               # Paket bağımlılıkları ve video varlıkları
```

---

## 📄 Lisans ve Haklar
Bu proje nörogelişimsel farkındalık ve erken çocukluk dönemi klinik tarama standartları gözetilerek geliştirilmiştir. Tüm hakları saklıdır.
