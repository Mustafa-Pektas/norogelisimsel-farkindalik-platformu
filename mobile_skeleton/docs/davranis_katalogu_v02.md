# Güncel davranış kataloğu

- Kaynak: proje üst klasöründeki `belgeler/Davranis_Kartlari_v02.md`, sürüm 0.2.
- Ana panel ve mevcut davranış ayrıntı ekranı `BehaviorCards` verisini okur. Kısa açıklamalar kartlardan sadeleştirilmiştir; işlem ve gözlem koşulları kart metninden aktarılmıştır.
- `ScenarioModel` ve `ScenariosRepository` eski ONT şablonları/simülasyonları için korunur. D kodlarına otomatik eşleme, eski kayıt veya video eşlemesi göçü yapılmaz.
- Ana paneldeki yaş seçimi yalnız eski şablon örneklerini etkiler. Güncel kartlar ilk teknik pilotta 30–36 ayı temel alır; yaşa göre yeni beceri beklentisi oluşturulmaz.
- D01 ayrıntısı mevcut debug model demosuna gider; bu demo 30 aylık Deniz ile sınırlıdır. D02–D10 için üretim veya video bağlantısı yoktur; ayrıntılarda bu bağlantıları vaat eden düğmeler bulunmaz.
- Pilotun 10/20 saniyelik kayıt pencereleri klinik başarı/gecikme eşiği değildir. Kartlar, senaryo ve üretim promptları gerçekleşmiş davranış kanıtı olarak sunulmaz.
- **Açık iş:** Eski ONT-08 şablonunun yanlış ce-e akışına gitmesi bu değişiklikte düzeltilmedi. Eski şablon içerikleri güncel kartlarla uyumlu kabul edilmez.
- Hedefli kontroller: `behavior_cards_test.dart`, `widget_test.dart`, `studio_sections_test.dart`. Bu değişiklik hazırlanırken test, çıkarım veya uygulama çalıştırılmadı.
