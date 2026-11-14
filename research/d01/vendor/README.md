# Kaynak atfı ve paylaşım kaydı

`friend_vision.py`, ekip arkadaşının kullanıcı tarafından sağlanan
`Isme_Tepki.zip` paketindeki
`Isme_Tepki_Paylasim/kod/ses_yonelme/sesyon/vision.py` dosyasının
değiştirilmemiş kopyasıdır. Kişi/yazar adı pakette açıkça belirtilmediğinden
bir yazar adı uydurulmamıştır.

- ZIP SHA256: `2b7cb0df7e5571e228d3e96174048fc197173bb0f29f66e805a2fb1720c1e4fa`
- Dosya SHA256: `4fbe1f9049ccacef00fdfd73028b5a697e57978abdb05de950f9e51012c8a9e4`
- Kullanıcı, 8 Kasım 2026 tarihli görevde bu dosyanın kaynak atfıyla D01
  pilotu kapsamında GitHub'da paylaşılmasına açıkça izin verdi; bu kayıt
  o kapsamın izlenebilirliğidir. Pakette dosyanın kendisi için ayrıca
  açık bir lisans bulunmadı. Bu not yeni bir genel lisans veya başka
  projelerde sınırsız yeniden dağıtım izni oluşturmaz.

Yeniden kullanılan parçalar: ileri/geri Lucas–Kanade optik akış ve
yaklaşık SQPnP + LM baş pozu hesabı. MediaPipe Tasks adaptasyonu ve
konum/görünüm ilişkilendirmesi `../fast_tracking.py` içindedir.
Optik akıştan mutlak baş açısı üretilmez.

Paketin `kod/ses_yonelme/THIRD_PARTY.md` belgesi MediaPipe ve OpenCV
kaynaklarını belirtir:

- MediaPipe: https://github.com/google-ai-edge/mediapipe
- OpenCV PnP: https://docs.opencv.org/4.x/d5/d1f/calib3d_solvePnP.html
- OpenCV optik akış: https://docs.opencv.org/4.x/d4/dee/tutorial_optical_flow.html

Bu dosyayla model ağırlığı, video veya paketli deney çıktısı dağıtılmaz.
Üçüncü taraf yazılımların kendi lisans ve atıf koşulları geçerlidir.

Otomatik kelime zamanı adaptörü `../automatic_call.py`, aynı ZIP'in
`kod/audio_label_tool/audio_labels.py` dosyasındaki `normalize` ve tam isim
eşleştirmesini; `kod/isme_tepki/analiz.py` içindeki faster-whisper kelime
zamanlaması çağrısını yeniden kullanır. Kullanıcı bu uyarlamayı ayrıca istedi.
Orijinal araçta çıktılar incelenmemiş taslaktır; yeni pilot da ASR zamanlarını
tahmin olarak tutar, kullanıcı onayı veya klinik doğrulama uydurmaz.
