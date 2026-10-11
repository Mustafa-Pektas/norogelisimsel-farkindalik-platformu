import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

def set_cell_background(cell, hex_color):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), hex_color)
    tcPr.append(shd)

def create_report():
    doc = docx.Document()

    # Sayfa kenar boşlukları
    for section in doc.sections:
        section.top_margin = Inches(0.8)
        section.bottom_margin = Inches(0.8)
        section.left_margin = Inches(0.8)
        section.right_margin = Inches(0.8)

    # Başlık
    title = doc.add_paragraph()
    r_title = title.add_run("NÖROGELİŞİMSEL FARKINDALIK PLATFORMU\nTEKNİK TEKNOLOJİ SEÇİMİ, MİMARİ GEREKÇELENDİRME VE MÜHENDİSLİK KARAR RAPORU")
    r_title.bold = True
    r_title.font.size = Pt(16)
    r_title.font.color.rgb = RGBColor(26, 54, 93) # Koyu lacivert
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER

    sub = doc.add_paragraph()
    r_sub = sub.add_run("10 Ana Mimari Katman İçin Alternatif Analizi, Mühendislik Kısıtları (Trade-Off) ve Pugh Karar Matrisleri")
    r_sub.italic = True
    r_sub.font.size = Pt(11)
    r_sub.font.color.rgb = RGBColor(74, 85, 104)
    sub.alignment = WD_ALIGN_PARAGRAPH.CENTER

    doc.add_paragraph("-" * 80)

    # Giriş Metni
    p_intro = doc.add_paragraph()
    p_intro.add_run("1. RAPORUN AMACI VE MÜHENDİSLİK KARAR METODOLOJİSİ\n").bold = True
    p_intro.add_run(
        "Bir biyomedikal/yapay zekâ yazılım mühendisliği tasarım projesinde teknoloji seçimi; popülerliğe göre değil, "
        "projenin özgün kısıtlarına, etik-klinik sınırlarına, donanım kaynaklarına ve algoritmik gereksinimlerine göre yapılmalıdır. "
        "Bu rapor; 12–36 aylık erken çocukluk döneminde sentetik video üzerinden davranış göstergelerini analiz eden platformumuzda "
        "kullanılan 10 kritik teknoloji tercihinin hangi somut teknik gerekçelerle seçildiğini, elenen alternatiflerin neden "
        "uygun bulunmadığını (darboğazlar, lisans kısıtları, donanım maliyetleri, gecikme süreleri) ve yapılan mühendislik ödünleşimlerini (trade-offs) "
        "akademik ve endüstriyel standartta belgelemektedir.\n\n"
        "Değerlendirme Kriterlerimiz:\n"
        "1. Çıkarım Gecikmesi ve Hesaplama Yükü (Inference Latency & FPS / CPU-GPU Bağımlılığı)\n"
        "2. Doğruluk ve Biyometrik Kararlılık (Precision, Recall, Açısal Hata MAE, Landmark Jitter)\n"
        "3. Açık Kaynak Lisansı ve Yasal Uygunluk (Ticari/Akademik kısıtlar, KVKK/GDPR uyumu)\n"
        "4. Entegrasyon Ergonomisi ve Ekosistem Desteği (Python/C++ C-bindings, Mobil SDK köprüleri)\n"
        "5. Determinizm ve Güvenilirlik (Açıklanabilir XAI, Sıfır Halüsinasyon İlkesi)\n"
    )

    modules_data = [
        {
            "cat": "1. Yüz Tespiti, Landmark ve Baş Pozu Tahmini (Head Pose Tracking)",
            "selected": "MediaPipe FaceLandmarker + OpenCV SolvePnP / Transform Matrix",
            "alternatives": [
                ("Dlib (68 Landmark - HOG/ResNet)", "2014 yılı klasik mimarisidir. Başın dönüş açısı 45°'yi aştığında (profil pozisyonunda) landmarklar tamamen çöker ve yüz takibi kaybolur. Oklüzyon dayanıklılığı çok zayıftır. 68 nokta, çocuk yüzündeki ince mimik hareketlerini ve göz bebeklerini yakalamak için yetersizdir."),
                ("OpenPose (Face Keypoints)", "Caffe/CUDA bağımlılığı aşırı ağırdır. Yalnızca GPU üzerinde 10–15 FPS seviyesinde çalışabilir; CPU üzerinde gerçek zamanlı video işleme imkânsızdır. Ayrıca CMU Perceptive lisansı ticari kısıtlamalar içerir."),
                ("InsightFace (RetinaFace + 2D/3D)", "Yüksek doğruluk sunmasına rağmen birincil odak noktası yüz tanıma/kimlik eşleştirmedir (face recognition). Çocuk yüzünde 3D kafa oryantasyonu ve mimik blendshape verisi üretimi için ek modeller gerektirir ve gereksiz bellek kaplar."),
                ("HopeNet (ResNet50 based Head Pose)", "Yalnızca Yaw, Pitch ve Roll açılarını doğrudan tahmin eden derin ağdır. Başarılıdır ancak yalnızca kafa pozu verir; göz kırpma, gülümseme veya yüz landmark noktalarını üretmez. Mimik analizi için ikinci bir ağ çalıştırma zorunluluğu doğurarak gecikmeyi ikiye katlar.")
            ],
            "why_selected": "MediaPipe FaceLandmarker; 478 adet 3D yüz noktasını doğrudan standart CPU üzerinde 30+ FPS hızında üretir. 4x4 yüz transformasyon matrisi sayesinde Euler açıları (Yaw/Pitch/Roll) harici ağır modellere ihtiyaç duymadan milisaniyeler içinde elde edilir. Ayrıca 52 adet blendshape katsayısı (AU12 - Gülümseme, AU43 - Göz Kırpma) sunarak sosyal etkileşim analizini tek bir çıkarım hattında tamamlar. Apache 2.0 lisansı ile tamamen özgürdür."
        },
        {
            "cat": "2. Göz ve Bakış Kestirimi (Gaze Estimation & Focus Tracking)",
            "selected": "MediaPipe Iris Refinement + Geometrik Kafa-Bakış Vektör Füzyonu",
            "alternatives": [
                ("Donanım Tabanlı Göz Takip Cihazları (Tobii Pro Eye Tracker)", "Klinik araştırmalarda altın standart olsa da cihaz maliyeti $1.500–$10.000 arasındadır. Sistemin temel amacı mobil kamera ile ev ortamında sentetik simülasyon ve erişilebilir tarama yapmaktır. Özel donanım şartı projenin vizyonunu tamamen yok eder."),
                ("Gaze360 (Static/Recurrent 3D Gaze Estimation)", "Geniş açılı bakış tahmini sunsa da LSTM katmanları nedeniyle ardışık kare tamponlama (frame buffering) gerektirir. Gerçek zamanlı mobil/sunucu pipeline'ında 250ms+ gecikme oluşturur ve çocukların ani bakış kaydırmalarında gecikmeli tepki verir."),
                ("L2CS-Net (ResNet-50 / CNN Based Appearance Gaze)", "Yüksek açısal doğruluk sunar fakat CUDA/GPU bağımlılığı yüksektir. Mobil veya hafif backend konteynerlerinde çalıştırıldığında bellek tüketimi 1.2 GB'ı aşar ve maliyetleri artırır.")
            ],
            "why_selected": "MediaPipe Iris; göz bebeği merkezini (pupil landmark) 3D uzayda kafa yönelim vektörüyle anında birleştirir. Ortak dikkat (RJA/IJA) analizinde çocuğun uzaktaki nesneye mi yoksa işaret eden ele mi odaklandığını harici bir GPU modeline ihtiyaç duymadan, sıfır maliyetle ve 30+ FPS hızında doğrular."
        },
        {
            "cat": "3. İskelet ve El Pozu Tahmini (Pose & Gesture Tracking)",
            "selected": "MediaPipe Pose (33 Landmark) + MediaPipe Hands (21 Landmark)",
            "alternatives": [
                ("OpenPose (Body 25 + Hands)", "Son derece ağır bir mimariye sahiptir. Tüm vücut ve el modelini aynı anda çalıştırmak üst düzey bir GPU gerektirir (RTX 3080'de dahi 12-15 FPS). Lisansı ticari kısıtlıdır."),
                ("RTMPose / MMPose (OpenMMLab)", "mAP (Mean Average Precision) skoru yüksektir ancak bağımlılık zinciri (PyTorch, MMCV, MPEngine, ONNXRuntime) aşırı karmaşıktır. Küçük bir sürüm uyumsuzluğunda Docker konteynerleri çöker. Geliştirme ve bakım maliyeti ekibimiz için sürdürülemezdir."),
                ("YOLOv8-Pose (Ultralytics)", "Vücut iskeletini (17 keypoint) çok hızlı çıkarır ancak parmak eklemlerini desteklemez. Projemizin temel davranışlarından biri olan 'İşaret Etme' (ONT-04) davranışında işaret parmağı ekstansiyonu (DIP, PIP, MCP eklemleri) YOLOv8-Pose ile tespit edilemez.")
            ],
            "why_selected": "MediaPipe Pose (33 nokta) çocuğun gövde duruşunu ve uzanma mesafesini çıkarırken; MediaPipe Hands (21 nokta) işaret parmağının doğrultu vektörünü 3D uzayda milimetrik olarak verir. Yetişkinin elini araç olarak kullanma (Hand-leading) veya uzanma jestleri hafif CPU boru hattında eş zamanlı çözülür."
        },
        {
            "cat": "4. Zamansal Davranış Tanıma (Temporal Action Recognition)",
            "selected": "ST-GCN (Spatial-Temporal Graph Convolution) + Kural Tabanlı Kayan Pencere (Sliding Window)",
            "alternatives": [
                ("3D CNN Modelleri (I3D, SlowFast, C3D)", "Piksel düzeyinde 3D evrişim (spatiotemporal convolution) yaparlar. Giriş video tensörleri devasadır (GFLOPs seviyesi). Modelin neden 'atipik' karar verdiğini geriye dönük açıklamak imkânsızdır (Black-box problemi). Klinik açıklanabilirlik gereksinimini karşılayamaz."),
                ("Video Transformers (TimeSformer, ViViT)", "Görsel dikkat mekanizması çok güçlüdür ancak binlerce saatlik etiketli video veri setine ihtiyaç duyar. Çocukların tekrarlayıcı motor davranışları gibi nadir atipik hareketlerde aşırı öğrenmeye (overfitting) düşer ve çıkarım süresi çok uzundur."),
                ("Saf Kural Tabanlı Eşikleme (Heuristic Only)", "Karmaşık periyodik hareketleri (örneğin 2–4 Hz frekansındaki el çırpma / flapping veya gövde sallama) basit eşiklerle ayırt edemez. Yanlış alarm (False Positive) oranı çok yüksektir.")
            ],
            "why_selected": "ST-GCN; ham pikseller yerine iskelet eklem koordinatlarını bir grafik olarak işler. Arka plan ışığından ve oda dekorasyonundan tamamen izoledir. Kayan pencere (Sliding Window) mekanizması ile birleştirildiğinde '00:42–00:48 arasında ortak dikkat oluşmadı' veya '01:12–01:16 arasında 3 Hz stereotipi gözlendi' şeklinde kesin zaman damgalı kanıt üretir."
        },
        {
            "cat": "5. Sentetik Medya ve Karakter Motoru (Synthetic Media Generation)",
            "selected": "Blender 4.x Python API (bpy) + Parametrik Karakter İskeleti",
            "alternatives": [
                ("Generative Video Diffusion (Sora, Runway Gen-2, Kling, AnimateDiff)", "KESİNLİKLE ELENMİŞTİR: Difüzyon modelleri kareler arası temporal tutarlılık (temporal consistency) sağlayamaz; ellerde 6 parmak oluşması veya yüzün aniden değişmesi gibi anatomik halüsinasyonlar üretir. En önemlisi 'Kara Kutu'dur; çocuğun kafasının hangi milisaniyede kaç derece döndüğünü matematiksel olarak bilemezsiniz, dolayısıyla 'Kesin Referans' (Ground-Truth) üretilemez!"),
                ("Unreal Engine 5 (UE5 MetaHuman)", "Görsel kalitesi fotogerçekçidir ancak motor boyutu 60+ GB'tır. Çalıştırmak için üst seviye RTX GPU gerekir. Komut satırından (headless) otomatik senaryo derleme süreci aşırı hantaldır ve CI/CD süreçlerine entegre edilemez."),
                ("Unity 3D Engine", "Başarılı bir oyun motorudur ancak C# tabanlıdır. Yapay zekâ veri boru hattımız (Python) ile entegrasyonu için harici soket/RPC köprüleri kurmak gerekir. Ayrıca Unity'nin lisanslama politikalarındaki belirsizlikler akademik projeler için risk taşır.")
            ],
            "why_selected": "Blender, tamamen açık kaynaklıdır ve Python API'si (`import bpy`) ile işletim sistemi düzeyinde doğrudan kontrol edilir. Bir script ile çocuğun baş kemiği (rig bone) tam olarak 1.8. saniyede 45 derece döndürülür ve aynı anda milisaniyelik Ground-Truth JSON dosyası üretilir. Headless (arayüzsüz) sunucularda Docker içinde sıfır GPU ile çalışabilir."
        },
        {
            "cat": "6. İnteraktif Senaryo ve Durum Makinesi Motoru (Video Graph Engine)",
            "selected": "Deterministik Finite State Machine (Python Transitions) + JSON Schema Kısıtlaması",
            "alternatives": [
                ("Serbest LLM Ajanı (LLM-Native Autonomous Agent)", "KESİNLİKLE ELENMİŞTİR: LLM'e serbest karar yetkisi verildiğinde kurgusal davranışlar uydurabilir (hallucination) veya pedagojik/klinik sınırların dışına çıkabilir. Çocuk sağlığı simülasyonunda deterministik olmayan (stokastik) kontrol kabul edilemez."),
                ("Behavior Trees (py_trees)", "Geniş açık dünya oyunlarındaki yapay zekâlar için uygundur ancak ağaç dallanma derinliği arttıkça durum takibi ve test edilebilirlik zorlaşır. Projemizdeki 3 dallı (Yeşil, Sarı, Kırmızı) ayrık senaryolar için gereksiz karmaşıktır."),
                ("Unity AnimGraph / State Machine", "Yalnızca Unity editörü içine gömülüdür. Web/mobil backend tarafından bağımsız olarak yönetilemez ve JSON tabanlı olay akışına dönüştürülemez.")
            ],
            "why_selected": "Python Transitions kütüphanesi; durumları (States), tetikleyicileri (Triggers) ve geçiş koşullarını (Guards) matematiksel bir sonlu durum makinesi olarak kurgular. LLM yalnızca kısıtlı JSON Schema üzerinden izin verilen düğüm kimliklerinden (Node ID) birini seçebilir; sistem asla kural dışı animasyon oynatmaz."
        },
        {
            "cat": "7. Ses Sinyali İşleme ve Tetikleyici Uyaran Tespiti (Audio Processing)",
            "selected": "Librosa + WebRTC VAD (Voice Activity Detection) Spektral Tepe Analizi",
            "alternatives": [
                ("OpenAI Whisper / Faster-Whisper (Full ASR)", "Videonun tamamını yazıya dökmek (speech-to-text) 5–15 saniye ek gecikme yaratır ve yüksek RAM/GPU harcar. Projede konuşmanın tam transkripsiyonuna ihtiyaç yoktur; yalnızca yetişkinin seslendiği anın (t0 başlangıç milisaniyesi) tespit edilmesi yeterlidir."),
                ("PyAudio (Ham Ses Okuma)", "Yalnızca mikrofon/ses cihazı arayüzüdür. Arka plan gürültüsü filtreleme, ses enerjisi tepe noktası veya ses aktivite algılama algoritmaları içermez; tüm matematiksel filtrelerin sıfırdan yazılmasını gerektirir."),
                ("Vosk / PocketSphinx", "Hafif ASR motorlarıdır ancak Türkçe çocuk/ebeveyn konuşmalarında kelime tanıma hata oranı (WER) yüksektir ve ses başlangıç sınırını (onset timestamp) milisaniye hassasiyetinde işaretleyemez.")
            ],
            "why_selected": "WebRTC VAD; Google tarafından geliştirilmiş endüstri standardı hafif bir ses aktivite dedektörüdür. Librosa onset_detect algoritması ile birleştiğinde yetişkinin 'Ali!' dediği anın patlama noktasını 50 milisaniyenin altında gecikmeyle ve sıfır yapay zekâ yüküyle doğrudan işaretler."
        },
        {
            "cat": "8. Sunucu Mimarisi ve Asenkron Kuyruk (Backend & Service Layer)",
            "selected": "FastAPI + Celery + Redis + PostgreSQL",
            "alternatives": [
                ("Django + Django REST Framework", "Ağır ve hantal monolitik bir mimaridir. Varsayılan olarak senkron çalışır. Görüntü işleme ve streaming video aktarımında asenkron I/O yetenekleri FastAPI'ye göre 3-4 kat daha yavaştır."),
                ("Flask", "Hafif bir mikro-çatıdır ancak asenkron (async/await) desteği yerleşik değildir. Veri doğrulama için Pydantic entegrasyonu ve otomatik OpenAPI/Swagger dokümantasyonu sunmaz."),
                ("Node.js (Express / NestJS) veya Go (Fiber)", "Yüksek ağ performansı sunsalar da yapay zekâ ve bilgisayarlı görü kütüphaneleri (MediaPipe, OpenCV, PyTorch, Librosa) Python ekosistemindedir. İki farklı dilde mikroservis çalıştırmak küçük bir ekip için iletişim ve bakım darboğazı yaratır.")
            ],
            "why_selected": "FastAPI; Python'ın en hızlı modern web çatısıdır (Starlette ve Pydantic tabanlı). Asenkron mimarisi ile mobil cihazdan gelen büyük video yüklemelerini bloklanmadan karşılar. Celery ve Redis ise ağır video işleme ve inferans işlerini arka plandaki işçi düğümlerine (Worker) dağıtarak mobil uygulamanın asla donmamasını sağlar."
        },
        {
            "cat": "9. Mobil İstemci Çatısı (Mobile Client Framework)",
            "selected": "Flutter (Dart) - Modern UI & Custom Canvas Engine",
            "alternatives": [
                ("React Native (JavaScript / TypeScript)", "JavaScript köprüsü (Bridge) veya yeni Fabric mimarisi video analizi sırasında ağır telemetri verisi (478 landmark koordinatı) akarken thread darboğazına girer ve kare atlamalarına yol açar. Custom video overlay ve bounding box çizimlerinde performans düşüşü yaşanır."),
                ("Native Mobil Geliştirme (Swift - iOS & Kotlin - Android)", "En yüksek donanım performansını sunar ancak iki ayrı dilde, iki ayrı kod tabanının yazılmasını ve sürdürülmesini gerektirir. 14 haftalık bir tasarım projesinde kısıtlı kaynaklarla iki yerel uygulama geliştirmek mühendislik açısından verimsiz bir risk yönetimidir."),
                ("Progressive Web App (PWA) / Ionic", "Kamera erişimi, yerel dosya işleme ve video işleme yetenekleri tarayıcı güvenlik politikalarıyla kısıtlanmıştır. Mobil kullanıcı deneyimi akıcı değildir.")
            ],
            "why_selected": "Flutter; C++ tabanlı render motoru (Impeller/Skia) sayesinde 60/120 FPS akıcı arayüz sunar. `video_player` ve `CustomPainter` katmanları ile analiz edilen videonun kanıt zaman damgalarına (00:42) anında atlama, bounding box ve telemetri çizimlerini yerel hızda gerçekleştirir. Tek kod tabanı ile hem Android hem iOS derlenir."
        },
        {
            "cat": "10. Açıklanabilir Yapay Zekâ (XAI) ve Karar Çeviri Katmanı",
            "selected": "Pydantic & JSON-Schema Denetimli Yapılandırılmış LLM (Llama-3 / Ollama)",
            "alternatives": [
                ("Serbest Metin Üreten LLM (Unconstrained Prompting)", "KESİNLİKLE ELENMİŞTİR: Tıbbi ve etik açıdan en tehlikeli yaklaşımdır. Model halüsinasyon görerek aileye 'Çocuğunuzda otizm belirtisi var' gibi yetkisiz ve felaket tellallığı yapan ifadeler kullanabilir. Sağlıkta kabul edilemez."),
                ("Sadece Kural Tabanlı Şablonlama (Hardcoded Templates)", "Sıfır halüsinasyon riski taşır ancak son derece mekanik, robotik ve soğuk çıktılar üretir. Kullanıcıya empatik rehberlik ve video bağlamına uygun akıcı özet sunamaz."),
                ("Otonom Ajan Çatıları (LangChain, AutoGPT, CrewAI)", "Gereksiz katmanlar ve 'token' israfı oluşturur. Modelin kendi kendine internette gezinmesi veya araç çağırması determinizmi bozar ve yanıt süresini 15-20 saniyeye çıkarır.")
            ],
            "why_selected": "Pydantic ve JSON Schema kısıtlaması sayesinde LLM'in hareket alanı tamamen sınırlandırılır. Model yalnızca karar motorunun ürettiği doğrulanmış JSON verilerini (davranış kodu, gecikme, yönelim açısı, kanıt aralığı) alır; asla klinik hüküm ekleyemez, sadece verileri ailelerin kolayca anlayabileceği açık, empatik ve şeffaf bir Türkçe metne çevirir."
        }
    ]

    for mod in modules_data:
        p_head = doc.add_paragraph()
        r_h = p_head.add_run(mod["cat"])
        r_h.bold = True
        r_h.font.size = Pt(13)
        r_h.font.color.rgb = RGBColor(43, 108, 176)

        p_sel = doc.add_paragraph()
        r_s1 = p_sel.add_run("Seçilen Teknoloji: ")
        r_s1.bold = True
        r_s1.font.color.rgb = RGBColor(39, 103, 73)
        p_sel.add_run(mod["selected"] + "\n")

        p_why = doc.add_paragraph()
        p_why.add_run("Seçim Gerekçesi ve Sağladığı Avantajlar:\n").bold = True
        p_why.add_run(mod["why_selected"])

        doc.add_paragraph().add_run("Elenen Alternatifler ve Teknik Eksiklikleri / Darboğazları:").bold = True

        # Tablo oluştur
        tbl = doc.add_table(rows=1, cols=2)
        tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
        hdr_cells = tbl.rows[0].cells
        hdr_cells[0].text = "Elenen Alternatif Teknoloji"
        hdr_cells[1].text = "Neden Seçilmedi? (Teknik Kısıt, Lisans, Darboğaz veya Risk)"
        set_cell_background(hdr_cells[0], "E2E8F0")
        set_cell_background(hdr_cells[1], "E2E8F0")
        hdr_cells[0].paragraphs[0].runs[0].font.bold = True
        hdr_cells[1].paragraphs[0].runs[0].font.bold = True

        tbl.columns[0].width = Inches(2.2)
        tbl.columns[1].width = Inches(4.8)

        for alt_name, reason in mod["alternatives"]:
            row_cells = tbl.add_row().cells
            row_cells[0].width = Inches(2.2)
            row_cells[1].width = Inches(4.8)
            row_cells[0].text = alt_name
            row_cells[0].paragraphs[0].runs[0].font.bold = True
            row_cells[0].paragraphs[0].runs[0].font.size = Pt(9.5)
            row_cells[1].text = reason
            row_cells[1].paragraphs[0].runs[0].font.size = Pt(9)

        doc.add_paragraph()

    # Bölüm 11: Genel Mühendislik Karar Matrisi (Pugh Matrix)
    doc.add_page_break()
    p_pugh = doc.add_paragraph()
    r_pugh = p_pugh.add_run("11. BÜTÜNLEŞİK MÜHENDİSLİK KARAR MATRİSİ (PUGH ANALYSIS & TRADE-OFF MATRIX)\n")
    r_pugh.bold = True
    r_pugh.font.size = Pt(14)
    r_pugh.font.color.rgb = RGBColor(26, 54, 93)

    p_pugh_desc = doc.add_paragraph(
        "Aşağıdaki matris, 10 kritik mimari katmanda seçilen teknolojilerin temel mühendislik kriterlerine "
        "göre ağırlıklı puanlamasını (1: En Zayıf, 5: Mükemmel) göstermektedir. Sistemimizin toplam mimari skoru "
        "düşük gecikme, yüksek açıklanabilirlik, sıfır çocuk mahremiyeti riski ve kaynak verimliliği odaklıdır."
    )

    matrix_data = [
        ("Katman / Bileşen", "Seçilen Çözüm", "Gecikme/FPS", "Doğruluk", "Lisans/Etik", "Entegrasyon", "Açıklanabilirlik", "Toplam Skor"),
        ("1. Kafa Pozu", "MediaPipe FaceMesh", "5/5 (30+ FPS)", "4.5/5", "5/5 (Apache)", "5/5", "5/5", "24.5 / 25"),
        ("2. Bakış Takibi", "MediaPipe Iris+Geom", "5/5", "4/5", "5/5", "5/5", "4.5/5", "23.5 / 25"),
        ("3. İskelet & El", "MediaPipe Pose+Hands", "4.5/5", "4.5/5", "5/5", "5/5", "5/5", "24.0 / 25"),
        ("4. Davranış Tanıma", "ST-GCN + Kayan Pencere", "4/5", "4.5/5", "5/5", "4.5/5", "5/5 (Kanıtlı)", "23.0 / 25"),
        ("5. Sentetik Karakter", "Blender 4.x Python API", "4/5 (Headless)", "5/5 (Kesin)", "5/5 (GPL)", "5/5 (JSON GT)", "5/5", "24.0 / 25"),
        ("6. Video Graph FSM", "Python Transitions", "5/5", "5/5", "5/5", "5/5", "5/5 (Deterministik)", "25.0 / 25"),
        ("7. Ses & Uyaran", "Librosa + WebRTC VAD", "5/5 (<50ms)", "4.5/5", "5/5", "5/5", "5/5", "24.5 / 25"),
        ("8. Backend & Kuyruk", "FastAPI + Celery+Redis", "5/5 (Async)", "5/5", "5/5", "5/5", "5/5", "25.0 / 25"),
        ("9. Mobil İstemci", "Flutter (Dart)", "5/5 (60 FPS)", "5/5", "5/5", "4.5/5", "5/5 (UI Canvas)", "24.5 / 25"),
        ("10. Açıklanabilir XAI", "Pydantic Kısıtlı LLM", "4/5", "5/5 (Sıfır Halüs.)", "5/5", "5/5", "5/5 (Empatik)", "24.0 / 25"),
    ]

    p_tbl = doc.add_table(rows=len(matrix_data), cols=8)
    p_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER

    for r_idx, row in enumerate(matrix_data):
        cells = p_tbl.rows[r_idx].cells
        for c_idx, val in enumerate(row):
            cells[c_idx].text = val
            p = cells[c_idx].paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            if r_idx == 0:
                set_cell_background(cells[c_idx], "1A365D")
                p.runs[0].font.bold = True
                p.runs[0].font.color.rgb = RGBColor(255, 255, 255)
                p.runs[0].font.size = Pt(8.5)
            else:
                p.runs[0].font.size = Pt(8)
                if c_idx == 1:
                    p.runs[0].font.bold = True
                if c_idx == 7:
                    p.runs[0].font.bold = True
                    p.runs[0].font.color.rgb = RGBColor(39, 103, 73)
                if r_idx % 2 == 1:
                    set_cell_background(cells[c_idx], "F7FAFC")

    # Sonuç ve Jüri Savunma Stratejisi
    doc.add_paragraph("\n12. SONUÇ VE JÜRİ/HOCA SAVUNMA STRATEJİSİ\n").runs[0].font.bold = True
    doc.add_paragraph(
        "Bu rapor; projemizin mimari kararlarının tesadüfi olmadığını, her bir katmanda en az 3-4 alternatifin "
        "mühendislik kriterleriyle karşılaştırıldığını ispatlamaktadır. Hocanız veya jüri 'Neden X değil de Y kullandınız?' "
        "sorusunu yönelttiğinde, yukarıdaki somut teknik gerekçeler (GPU darboğazı, lisans kısıtlaması, Black-box açıklanamazlığı, "
        "Ground-Truth determinizmi ve mobil kaynak verimliliği) projemizin en güçlü bilimsel savunma dayanağı olacaktır."
    )

    output_path = "Teknik_Teknoloji_Secimi_ve_Karsilastirma_Raporu.docx"
    doc.save(output_path)
    print(f"Rapor basariyla olusturuldu: {output_path}")

if __name__ == "__main__":
    create_report()
