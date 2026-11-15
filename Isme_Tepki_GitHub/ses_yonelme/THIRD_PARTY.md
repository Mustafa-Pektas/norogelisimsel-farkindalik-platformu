# Teknik kaynaklar

- Gaze-LLE / Gaze Target Estimation via Large-Scale Learned Encoders:
  https://github.com/fkryan/gazelle
  MIT lisansı, üçüncü taraf model. `gazelle_dinov2_vitb14_inout` kullanılır.
  Kaynak referansı config içinde sabitlenmiştir. Model ağırlıkları pakete
  gömülmez; ilk kullanımda resmî kaynaktan indirilir.
- DINOv2:
  https://github.com/facebookresearch/dinov2
  Gaze-LLE'nin görsel omurgası. Python 3.9 uyumluluğu için model yükleyicisi
  DINOv2 kaynak kodunu resmî `85a24602099d397264d5b30461ad7f3bfd726ca1`
  commitine sabitler. Referans `settings.dinov2_repo` içinde tutulur.
  Ağırlıklar resmî indirme adresinden gelir; ağırlık SHA'ları ayrıca kilitlenmeli.
- MediaPipe Face Mesh:
  https://github.com/google-ai-edge/mediapipe/blob/master/docs/solutions/face_mesh.md
  Bu pakette mevcut Python 3.9 ortamıyla uyumlu `mediapipe==0.10.21` eski
  `solutions.face_mesh` API'si kullanılır. Face Landmarker Tasks API'siyle
  karıştırılmamalıdır.
- OpenCV poz tahmini:
  https://docs.opencv.org/4.x/d5/d1f/calib3d_solvePnP.html
  SQPnP başlangıç pozu ve LM iyileştirmesi kullanılır.
- OpenCV optik akış:
  https://docs.opencv.org/4.x/d4/dee/tutorial_optical_flow.html
- PyTorch:
  https://pytorch.org/get-started/previous-versions/

DirectMHP-S ve 6DRepNet360 için kullanılan resmî kaynak bağlantıları depo
README dosyasındadır.
