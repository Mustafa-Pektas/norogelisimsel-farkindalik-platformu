# Sadeleştirme ön incelemesi

20 Ekim 2026 · Salt okunur kaynak incelemesi · Mevcut sürüm esas alınmıştır.

## Başlangıç, kararlar ve kanıt sınırı

- Dal: `mertcan/senaryo-grafi`. Son commit: `02d7730931fc47aea6f49dc8e6a2fc18ca30fe16` — `feat: D01-D10 kataloğu, stüdyo sadeleştirmesi ve video hata yönetimi`.
- Üst klasörler ve depo içindeki aramada uygulanabilir `AGENTS.md` bulunmadı.
- Başlangıçta değişmiş yedi üretilmiş dosya vardı: `linux/flutter/generated_plugin_registrant.cc`, `generated_plugin_registrant.h`, `generated_plugins.cmake`; `macos/Flutter/GeneratedPluginRegistrant.swift`; aynı üç `windows/flutter/` dosyası. Ayrıca takip edilmeyen `docs/demo_2026-10-18/model_ham_cevap.txt` vardı; dosya 0 bayttır. Hiçbirine dokunulmadı.
- Stash: `stash@{0}`, `d2788869691dad482216f8a6f6abea8b9641578d`; korunmuştur. Başka sürümle birleştirme, commit veya push yapılmadı.
- Yalnız bu rapor oluşturuldu. Kod, veri, test, bağımlılık, yapılandırma ve önceki raporlar değiştirilmedi. Uygulama, test, model, çıkarım, indirme veya derleme başlatılmadı; cihaz kayıtlarına yeni erişim yapılmadı.
- Dayanaklar: [devam notu](DEVAM_NOTU.md), [18 Ekim kapsamlı incelemesi](uygulama_kapsamli_inceleme_2026-10-18.md), [katalog notu](davranis_katalogu_v02.md), [senaryo sözleşmesi](scenario_input_contract.md), [kayıt temelli model raporu](model_degerlendirme_kanitlari.md). Bu belgelerin ilgili bulguları güncel kod yollarıyla karşılaştırıldı; tarihsel iddialar güncel çalışma kanıtı sayılmadı.
- Davranış kaynağı [Davranis_Kartlari_v02.md](../../../belgeler/Davranis_Kartlari_v02.md), sürüm 0.2'dir. Eski 12 ONT görevi güncel davranış listesi değildir. Kartların klinik geçerliliği bu incelemeyle doğrulanmaz.

**Ürün kararı artık açıktır:** Son kullanıcı hazırlanmış içeriği izler ve devamını seçer. Senaryo/model/graf/JSON/prompt/video eşleme araçları proje ekibine aittir. Aşağıdaki öneriler bu ayrımı kullanır; kimlik doğrulaması veya yeni hesap sistemi önermez. Sunucuya taşıma planı gelecekteki iştir; mevcut yerel çalışma bu raporda sunucu hizmeti gibi anlatılmaz.

Kanıt işaretleri: **K** güncel kod/yapılandırma; **T** kontrollü test kaynağı var, burada çalıştırılmadı; **B** önceki kullanıcı bildirimi; **R** önceki kayıt temelli rapor; **M** manuel/cihaz doğrulaması gerekli. Koşullu hata yolu, gerçekleşmiş cihaz olayı olarak sunulmaz. Dosya konumları uygulama köküne görelidir; satırlar bu commit'e aittir.

### Kısa sonuç ve önceki rapordan değişenler

İki ayrı hat mevcuttur:

```text
İçerik denemesi:
Cihazdaki Qwen → ham cevap → sınırlı biçim normalizasyonu + uygulama metadata'sı
→ ScenarioInput → tek düzeyli ScenarioGraph → graf görüntüleyici
                                                     [burada biter]

Hazır içerik denemesi:
Sabit D01 grafı + sabit klip planı → dış araç için prompt kopyalama
→ galeriden video bağlama → uygulama kopyası + kalıcı yerel eşleme
→ önizleme / gerçek video sonuyla ilerleyen kullanıcı seçimli oynatma
```

Şablon üretimi ve teknik model değerlendirmesi bunlardan ayrı yollardır. Yeni grafın klip planı veya videosu yoktur. Düğmeleri toplamak bu veri boşluğunu kapatmaz.

Korunacaklar: güncel 10 kartın bağımsız kataloğu; D01'in sabit 30 ay kapsamının açıklanması; taslakla geri çıkış onayı; çalışan video başarılı adayla değiştirilene kadar korunması; kullanıcı videosuna sabit bulgu aktarılmaması; kapalı bölümlerde servis/state korunması; ham cevap ile düzenlenen içeriğin ayrılması; yapısal doğrulama; göreli yollu video eşlemesi; gerçek bitiş olayı ve tek oynatıcı kullanan graf denemesi.

18 Ekim raporunun F01'i ana katalog/ayrıntı açısından artık eski durumdur; eski ONT tüketicileri ise durur. F03 ana panel metni, F04 kazara geri çıkış, F05 açılış hatası ve F15 eski ana ekran testi için düzeltmeler kaynakta vardır. F04 kalıcı kayıt/üzerine yazma sorununu çözmez. F16'nın Stüdyo gruplaması yapılmıştır; gizli admin girişi ve kullanıcı/üretici ayrımı hâlâ tam çözülmemiştir. Bunlar yeniden tamamlanmamış iş gibi listelenmemiştir.

Doküman farkı: `scenario_input_contract.md:5` içindeki ekran/LLM bağlantısı yok ifadesi, güncel ortak ekranın converter çağrısı ve Qwen demosunu artık tam anlatmıyor; bağımsız converter'ın kendisi yine LLM çalıştırmaz. Aynı belgenin `:77` gezinme tarifi eski klip planı yolunu esas alır; bugün Stüdyo'da doğrudan giriş de vardır. Bu raporda güncel kod esas alındı; önceki belge değiştirilmedi. Doküman senkronizasyonu düşük riskli, sonraya bırakılabilecek bakım işidir.

## 1. Güncel ekran ve giriş envanteri

### 1.1 Ana panel, video ve bilgi ekranları

| Kimlik / ekran–kontrol | Ulaştığı gerçek kod yolu / konum | Durum ve hedef kişi | Öneri ve gerekçe | Bağımlılık riski |
|---|---|---|---|---|
| E01 · Ana gezinme | `main.dart:24` → `HomeScreen`; `home_screen.dart:88` `IndexedStack`, `:122` `NavigationBar` | Üç sekme: Ana Panel, Video izle, Senaryo Stüdyosu. Çocuk ekranlar sekme görünmese de yaşar. Son kullanıcı ve ekip karışık. K | **Koru/sadeleştir:** sekmeleri çoğaltmadan içerik dağılımını düzelt. | Görünürlük değişikliği oynatıcı/servis kapatma sayılmaz; S04. |
| E02 · Panelde Şablon yaşı, kaydırıcı ve üç yaş kısayolu | `home_screen.dart:165`; `widgets/age_slider_card.dart:91,104` → `_currentMonth` → Stüdyo `initialAgeMonths` | Eski şablon girdisi. Kartları, Qwen demosunu veya hazır videoyu yaşa uyarlamaz. Üretici. K | **Üretici alanına taşı/birleştir:** Stüdyo'daki mevcut şablon yaş kontrolü yeterli; izleyenin ilk işini engelliyor. | Home–Stüdyo parametre akışı ve yaş testleri korunmalı; S08. |
| E03 · Video izle giriş kartı ve alt sekme | `home_screen.dart:139,211` → sekme 1 → `VideoAnalysisScreen` | Seçme/izleme; otomatik analiz vaadi ana girişte kaldırılmış. Son kullanıcı. K/T | **Koru:** aynı iş için kart + sekme olağan bir kısayoldur, tek başına gereksiz tekrar değildir. | Hedef sekme değişmemeli. |
| E04 · Senaryo Stüdyosu giriş kartı ve alt sekme | `home_screen.dart:144,219` → sekme 2 → `SyntheticVideoStudioScreen` | Teknik/üretici ağırlıklı alan ile hazır örnek aynı sekmede. K | **Yeniden adlandır/içeriği ayır:** son kullanıcı için “Senaryolar”; üretim kontrolleri mevcut ekip bölümünde. | Yalnız isim değiştirmek video içeriği yayımlama akışı oluşturmaz; S01. |
| E05 · 10 davranış kartı | `home_screen.dart:227–250` → `BehaviorCards.all` → `OntologyDetailScreen(card)` | D01–D10 bilgi kataloğu; hesaplanan puan yok. Son kullanıcı ve ekip. K/T | **Koru:** kısa açıklama ve ayrıntı bağlantısı farkındalık amacına uygun. | Eski `ScenarioModel` ile değiştirilmemeli; S06. |
| E06 · Davranış ayrıntısı: Amaç, Hazırlık, Yapılacak işlem | `ontology_detail_screen.dart:43–55` | Güncel karta ait bilgi; normal kullanımda açık. K/T | **Koru:** görev anlaşılır kalıyor. D kimliği yerine adın önceliği sonraki görsel kontrolde değerlendirilebilir. | Metin/kurallar değişmeden yerleşim iyileştirilebilir. |
| E07 · Ayrıntılı gözlem kuralları / Teknik bilgiler | Aynı dosya `:87,116`; altı koşul, dört sonuç sözlüğü, kaynak ve pilot penceresi | İkisi başlangıçta kapalı; içerik silinmemiş. Daha çok ekip/ayrıntı isteyen kişi. K/T | **Koru:** son sadeleştirme yerinde. Pilot süreleri klinik eşik değil. | Kart kuralları ve tam metin erişimi korunmalı. |
| E08 · D01 model demosu / D02–D10 destek açıklaması | Aynı dosya `:57–82` → `ScenarioGraphImportScreen(initialScenarioContent:true)`; D01 düğmesi debug | D01, 30 aylık Deniz/Qwen denemesi. Diğer kartlarda üretim düğmesi yok. Üretici. K/T | **Üretici alanına taşı:** bilgi ayrıntısından teknik teste geçiş izleyenin işini böler; mevcut Stüdyo girişi korunur. | D01 işlevini silmek yerine kısayol sadeleştirilmeli. |
| E09 · API anahtarı simgeleri | `home_screen.dart:80`; `video_analysis_screen.dart:522` → `ApiKeyDialog.show` → `LlmRagService` tercih kaydı | Yerel Qwen veya video izleme bunları kullanmaz. Üretici/eski uzak LLM yolu. K | **Normal görünümden kaldır/üreticiye taşı:** izleme için anahtar gerekmiyor; S03. | Servisi veya anahtarı silmek gerekmez; eski ekran tüketicileri var. |
| E10 · Video ekranı üst başlığı | `video_analysis_screen.dart:516` | Hâlâ “Video Analiz Modu”; panel/sekme “Video izle”. K | **Yeniden adlandır:** “Video izle” ile tutarlı olsun. | Düşük; başlık beklentileri etkilenir. |
| E11 · Video yüzeyi, oynatma, 5 sn ileri/geri, ses, tam ekran | Aynı dosya `:536–605`; `FloatingVideoControls`; `_openFullscreen:462` | Kullanıcı dosyası/örnek oynatılır. Yükleme otomatik play değildir; tam ekran aynı controller'ı kullanır. Son kullanıcı. K/T | **Koru:** açılış ve önceki videoyu koruma davranışını bozma. Oran ve görünmez sekme sesi S04/S09. | Paylaşılan controller'ın sahibi ana ekrandır. |
| E12 · Video Yükle/Değiştir, galeri/kamera, örneğe dönüş | `_showVideoSourceSheet:365`, `_pickVideo:342`, `_openCandidate:269`, `_resetToDefaultVideo:363` | Yerel seçim; sunucuya yükleme veya kalıcı klip eşlemesi değildir. K/T | **Yeniden adlandır:** “Video seç”; galeri/kamera seçimleri anlaşılır. Kalıcı klip bağlama ile birleştirme. | İptal/başarısız adayda eski videonun korunması şartı değişmemeli. |
| E13 · İlk örnek hata/yeniden deneme ve seçili dosya bilgisi | `video_analysis_screen.dart:610–685` | Örnek açılamazsa hata ve seçim/tekrar imkânı var. Özel video “analiz edilmedi”. K/T | **Koru:** eski sonsuz yükleme bulgusu bu sürüm için tekrarlanmamalı. | Geç sonuç ve kapanmış ekran korumaları korunmalı. |
| E14 · Önemli Anlar, kanıt kapsülü, örnek rapor/renkli sonuç, bulgu açılırları | `_clinicalCases:65`, `_onVideoTick:219`, `build:687–803`, `_friendlyResultTitle:881`; `ExpandableFindingCard` | Sabit veridir; sadece örnek yolunda. Kullanıcı videosuna geçmez. Risk/norm dili hâlâ var. K/T | **Üretici örnek alanına taşı; normal görünümden çıkar:** S02. Zaman atlama işlevi bağımsız korunabilir. | `AwarenessLevel` ve paylaşılan bulgu widget'larını topluca silme. |
| E15 · Kurumlar girişleri ve kurum listesi | `home_screen.dart:254`; `video_analysis_screen.dart:806` → `InstitutionsScreen` | Dört sabit kurumun adres/telefon metni; canlı dizin, arama veya harita çağrısı yok. Son kullanıcı yardımcı bilgi. K | **Koru/yeniden adlandır:** “Bilgi ve başvuru kaynakları”; “yetkili” ibaresi doğrulanmış güncel onay izlenimi vermesin. | Kayıtların güncelliği bu görevde dış kaynaktan doğrulanmadı; metin ve `HealthCenter` paylaşılıyor. |

### 1.2 Stüdyo ve teknik üretim alanı

| Kimlik / bölüm–kontrol | Kod yolu / konum | Gerçek durum ve hedef | Öneri ve gerekçe | Bağımlılık riski |
|---|---|---|---|---|
| E16 · Üst “Senaryodan graf oluştur” | `synthetic_video_studio_screen.dart:594–618` → ortak ekran, senaryo modu | Debug giriş; mevcut Qwen demo/JSON yolu. Üretici. K/T | **Koru; ekip alanında tek ana giriş yap.** Klip planından dolaşma zorunluluğu kaldırılmış. | F04 çıkış koruması korunmalı. |
| E17 · Hazır D01 örneği → Örnek akışı görüntüle | Aynı dosya `:621–643` → `ScenarioGraphScreen()` → sabit asset | Release koşuluyla gizlenmiyor. Graf çizimi; video oynatmaz. Son kullanıcıya yardımcı özet/ekibe inceleme. K/T | **Koru/yeniden adlandır:** “Örnek senaryonun akışı”; doğrudan video deneyiminin yerine geçmemeli. | Aynı görüntüleyici yeni graf için de kullanılıyor; silinemez. |
| E18 · Hazır D01 → Klip planı ve videolu deneme | `:645–663` → `ClipProductionPlanScreen`, debug | Promptlar, eşlemeler ve oynatma girişinin bir arada olduğu üretici yolu. K/T | **Üretici alanında tut.** İzleyeni bu hazırlık ekranından geçirmek yerine mevcut oynatıcıya hazır bağlamla erişim gereksinimini S01 olarak ayır. | Asset graf/plan ve cihaz eşlemeleri gerekir; körlemesine düğme taşımak yeterli değil. |
| E19 · Teknik model denemeleri | `:666–760`, `ExpansionTile`, `maintainState:true` | Başlangıçta kapalı. İndirme, beş tekli kart ve altı deneme alanı; debug koşulu yok. Geliştirici. K/T | **Koru; üretici alanında teknik alt bölüm olarak sakla.** Mevcut state koruma iyi. | Kapatmak iptal etmek değildir; servislerin yaşamı değişmemeli. |
| E20 · Llama indir/iptal/sil; Qwen/MiniCPM seç/indir/iptal | `_buildLlamaManagementCard:1047`; `_buildComparisonDownloadCard:263`; `LlamaModelService` | Ayrı GGUF dosyaları. Karşılaştırma seçimi altı denemeyi etkiler, Qwen demosunu değiştirmez. K | **Teknik bölümde koru; kapsam adlarını açık tut.** Son kullanıcıya indirme şartı gösterme. | Model dosyası indirildi ≠ başarılı çıkarım. Silme düğmesi gerçek dosya siler. |
| E21 · Llama merhaba, TR/EN D01, Qwen D01, Qwen Ortak başlangıç | `LocalLlamaTestRequest` ve `LocalLlamaTestCard`; Stüdyo `:696–750` | Gerçek yerel çıkarım girişleri; hazır cevap yok. Sonuncusu artık yalnız oyun ortamı ister. Geliştirici. K/T/R | **Birleştir/sade ad ver:** kartları işlev silmeden aynı teknik bölümde tut; sonuncuya “Oyun ortamı testi”. | İstemler/protokoller farklıdır; sonuçları tek deney gibi birleştirme. |
| E22 · Altı deneme, durdur, kayıt kopyala, ham kayıt açılırı | `_buildD01EvaluationControls:342`; `D01EvaluationService.run` | Sabit üç görev × iki tekrar; disk kayıtları; boş insan alanları. Geliştirici. K/T/R | **Koru; tekli Qwen kartından bağımsız teknik değerlendirme alt başlığına taşı.** Model seçiminin kapsamı anlaşılır olsun. | İstemleri/kayıtları yeniden etiketleme; kalıcı dosyalar korunmalı. |
| E23 · Şablon örnekleri: motor, yaş, ONT seçimi, gözlem durumu, üret | Stüdyo `:763–909`; `_buildEngineSelectorCard:915`, `_buildDoctorConfigCard:1392`, `_generateScenario:446` | Başlangıçta kapalı/state korunur. İki motor düğmesi de aynı hazır şablon servisine gider. Risk profili ve eski ONT içerir. Üretici/tarihsel örnek. K/T | **Üretici alanında sakla; aynı işi yapan motor seçimini kaldırma adayı.** Tek “Eski şablon örneği” açıklaması yeterli. | Mevcut servis API'leri ve testler kullanılmaya devam edebilir; toplu kimlik değişikliği yapılmamalı. |
| E24 · Adım adım/Tek metin, senaryo kopyala | `_buildViewModeToggle:1848`, `_buildUnifiedScenarioCard:2117`, `_buildStepCard:2268`, export eylemleri `:771` | Şablon çıktısının iki sunumu; yeni ScenarioInput/graf değildir. Üretici. K | **Koru/birleştir:** tek düzen + isteğe bağlı tam metin tercihi düşünülebilir; ham LLM cevabı diye adlandırma. | İki görünümün kopyaladığı metinler farklı; içeriği kaybettirmeden karar verilmeli. |
| E25 · Gizli admin şablon kontrolleri | `_handleEasterEggTap:61`, `build:554`; `_buildAdminVideoSlicingCard:1640`, `:1770`, `:1783`, `_buildStepCard` | Klip süreleri, toplam süre, promptlar, JSON, kopyalama; doğrulama kartı ölçüm yapılmadığını söyler. Üretici/geliştirici. K/T | **Açık ekip bölümüne taşı; gizli hareketi kaldırma adayı.** Admin/doktor adı yetki değildir; S05/S06. | Promptları son kullanıcıya açmamak, mevcut kopyalama ve kayıtları korumak gerekir. |

### 1.3 Ortak girdi, graf ve video araçları

| Kimlik / ekran–kontrol | Kod yolu / konum | Gerçek durum ve hedef | Öneri ve gerekçe | Bağımlılık riski |
|---|---|---|---|---|
| E26 · Senaryo / graf içe aktar: Senaryo içeriği / Hazır graf | `scenario_graph_import_screen.dart:189,349` | Aynı ekranda ayrı tür; türe göre editör taslağı oturumda korunur. Üretici. K/T | **Koru:** iki ayrı ekran oluşturma. Giriş adı “Senaryo hazırlama”; “Hazır graf” teknik içe aktarma olarak kalabilir. | İki türün doğrulaması aynı değildir; zorla tek parser'a indirme. |
| E27 · Yerel model kartı, ham cevap, JSON, D01 örneği | Aynı dosya `:110–187,261,393–431`; `LocalLlamaTestCard` | Sabit Qwen/D01/30 ay; metadata uygulamadan. Örnek ayrı asset. Ham cevap servis state'inde değişmeden kalır. Üretici. K/T/B | **Koru/sadeleştir:** ham cevabı mevcut açılır düzenle sunmak ve doğrulama eylemine erişimi kısaltmak uygun. | Metin/graf kaybı ve kaynak ayrımı S07; otomatik içerik tamamlama eklenmemeli. |
| E28 · Graf oluştur / Doğrula / Grafı görüntüle, hata ve özet | `_validate:211`, `_viewGraph:304`; `ScenarioInput` → `ScenarioGraphConverter` veya `ScenarioGraph.fromJsonString` | Yapısal kontrol; içerik doğruluğu değil. Tek düzeyli dönüşüm. Üretici. K/T | **Koru:** başarılı yapıyı “senaryo onaylandı” diye adlandırma. | Referans/erişilebilirlik ve kaynak beyanı kontrolleri korunmalı. |
| E29 · Senaryo Grafı: kutular, ayrıntı, zoom/sürükle/Tümünü göster | `scenario_graph_screen.dart:32,171,356,417` | Sabit asset veya verilen nesne; video/model çalıştırmaz. Üretici; hazır içeriğin akış özeti için yardımcı. K/T | **Koru:** kısa kutular ve tam metin paneli iyi; asıl izleme düğmesi gibi sunma. | Yeni ve sabit graf aynı görüntüleyiciyi kullanır. |
| E30 · Klip üretim planı: sınırlar/süreklilik ve sahne açılırları | `clip_production_plan_screen.dart:58,323–350` → iki asset yükleme + `validateAgainst` | Sabit D01, 5 sahne/7 klip; ortak sahne bir kez. Üretici. K/T | **Koru, ekip alanında.** Tek klip ≤8 sn; toplam senaryo 8 sn değildir. | Genel plan modeli ile sabit asset birbirine karıştırılmamalı. |
| E31 · Tam prompt/kopyala | `_ClipDetails:366–424` | Gerçek clipboard eylemi; dış üretim için metin. Üretici. K/T | **Koru; son kullanıcıya taşıma.** Otomatik video üretimi yok. | Prompt anlatısı gözlem kanıtı değildir. |
| E32 · Video seç/değiştir/kaldır, dosya adı/durum | `_selectVideo:91`, `_removeVideo:125`, `_videoControls:151` → `ClipVideoStore` | Galeriden uygulama kopyası, kalıcı eşleme. İptal/hata önceki eşlemeyi korur. Üretici. K/T/B | **Koru:** basit Video izle seçimiyle birleştirme; farklı veri yaşamı var. | Galeri kaynağı silinmemeli; uygulama kopyası ancak başarılı kayıt sonrası temizlenir. |
| E33 · Klip önizlemesi | `ClipVideoPreviewScreen._initialize:35`, `_control:65`, `dispose:104` | Kayıtlı kopya; otomatik play yok; oran korunur; eksik/açılmayan dosya hata verir ve eşleme kalır. Üretici. K/T/B | **Koru:** “İncelenmedi” doğru. Arka plan davranışı manuel kontrol edilmeli. | Önizleme eşlemeyi değiştirmez; controller bu ekrana ait. |
| E34 · Grafı dene: Başlat, Duraklat/Devam, dal, ayrıntı, baştan başlat | `clip_production_plan_screen.dart:283` → `GraphPlaybackScreen`; `graph_playback_controller.dart:65–206` | Yalnız mevcut debug üretim girişinden; kullanıcı gerçek dalı seçer. Hedef izleme deneyimine en yakın bileşen, bugün geliştirici denemesi. K/T/B | **Koru; ekipte “Videolu akışı dene”, hazır son kullanıcı bağlamında “Senaryoyu izle”.** Henüz genel yayımlanmış içerik listesi yok. | Seçilen graf+plan+eşleme bağlamı aynı olmalı; S01/S10. |
| E35 · Klip planından Senaryo / graf içe aktar | `clip_production_plan_screen.dart:301` → ortak ekran, hazır graf modu | E16 ve debug D01 ayrıntısı ile aynı ekrana üç yol; yeni graf burada planı değiştirmez. Üretici. K | **Tekrarıyla birleştir:** ana ekip girişi korunursa bu ters yönlü kısayol kaldırma adayıdır. | Ortak ekran veya servis silinmez; gezinme testleri güncellenir. |

### 1.4 Ana gezinmede çağrılmayan eski ekranlar

- `SimulationModeScreen`: `lib/` çağrı aramasında sınıfı oluşturan güncel ana rota bulunmadı. Eski ONT/yaş/dal simülasyonu, kişisel bağlam alanları ve Gemini/yerel şablon yolu vardır; kendi içinden Stüdyo'ya gider. `simulation_mode_screen.dart:92,164,887,921`.
- `InteractivePlayerScreen`: ana gezinmeden kurucu çağrısı bulunmadı. Eski asset/renk dalları, video olmadığında 3 saniyelik sentetik akış ve sabit açı/sınıflama metinleri vardır (`:129–210`). Bunlar yeni graf oynatıcısının ölçümleri değildir.
- Bu nedenle ikisi **normal kullanımdan uzak tutulmalı**, fakat dosyaları doğrudan silinmemeli: `FullscreenVideoScreen`, `interactive_player_screen.dart` içindeki `SimulationState` enum'unu import eder. `ScenarioBranchModel`, eski seçici ve tam ekran tarafından paylaşılır. `ScenariosRepository` de aktif şablon üretimi tarafından kullanılır.
- `ScenarioPickerSheet` eski ekranlarda kullanılır; tek başına çağrılmayan genel bir seçici değildir. `FloatingDecisionSheet` için aktif çağrı bulunmadı; bu, bütün eski model dosyasını silmek için gerekçe değildir.
- `AnalysisReport` kurucusu; `formatLlamaPrompt`, `formatDoctorLlamaPrompt`, `getDownloadedSizeBytes` için `lib/` ve test aramasında kullanım bulunmadı. `generateDoctorScenarioWithLlama` ise testte çağrılır; onun sonuç tipi/servisi de aynı eski servis dosyasındadır. Bunlar **ayrı temizlik adayları**, bu turun zorunlu işleri değildir.

## 2. Gizli özellikler ve gerçek sınırları

| Giriş | Etkinleşme / görünürlük | Amaç ve sonuç | Güvenlik/ürün yorumu |
|---|---|---|---|
| Stüdyo başlığına 5 dokunuş | Ardışık dokunuşlar arası >2 sn olursa sayaç başa döner. `_handleEasterEggTap:61`; başlık `:554`. | `_isAdminMode` aç/kapat; prompt, süre/klip, export ve şablon ayrıntıları. İkinci dokunuştan itibaren hafif titreşim. | `kDebugMode` ile çevrili değil. Kaynakta release için de derlenir; şifre/rol kontrolü yok. “Admin/Doktor” sadece yerel bool ve metin. |
| Eski Simülasyon başlığına 5 dokunuş | `simulation_mode_screen.dart:45,100`; aynı 2 sn aralık kuralı | `_isResearcherMode`; “MÜHENDİS” etiketi, prompt ayrıntıları. | Ekranın aktif ana rotası yok; bu yüzden bugün ana panelden ulaşılır denmez. Yine gerçek yetki değil. |
| Debug Senaryodan graf oluştur | `synthetic_video_studio_screen.dart:594` | Ortak teknik giriş | Derleme görünürlüğü; hesap doğrulaması değil. |
| Debug D01 model demosu | `ontology_detail_screen.dart:63` | Aynı ortak ekranın senaryo modu | Sadece kısayol; D02–D10 desteği açmaz. |
| Debug Klip planı ve videolu deneme | Stüdyo `:645`; plan içinde `kDebugMode:283` | Grafı dene ve içe aktarma | Giriş gizliliği ile bütün araçların korunması aynı şey değil; teknik test/şablon bölümleri ayrıca debug ile gizlenmiyor. |
| Video üstüne dokunma | `video_analysis_screen.dart:550`; `fullscreen_video_screen.dart:417` | Otomatik gizlenen medya kontrollerini açar/kapatır | Olağan oynatma hareketi; yetki girişi değil. Çıkış tam ekran simgesidir, standart AppBar geri düğmesi yok. |

`lib/` genelinde `onLongPress`, `onLongPressStart`, `onDoubleTap`, `onSecondaryTap` gibi ek gizli kontrol callback'leri bulunmadı. Standart metin seçimi/platform davranışlarının veya paket içi hareketlerin hiç bulunmadığı iddia edilmez.

**Öneri:** Gizli admin dokunuşunu erişim modeli olarak kullanmamak; mevcut üretici araçlarını açık ve tek bir ekip bölümünde toplamak. Bunu yaparken promptları normal kullanıcının önüne taşımamak. Release dağıtımının ekip ve son kullanıcı için nasıl ayrılacağı ürün kararıdır; yeni hesap sistemi bu küçük düzenlemenin ön koşulu değildir.

## 3. Son kullanıcı / içerik üreticisi / geliştirici ayrımı

| Kişi ve görevi | Kalması gereken mevcut bileşen | Bugünkü karışıklık / sınır |
|---|---|---|
| Son kullanıcı: farkındalık bilgisi edinme | Ana panelde kısa açıklama, D01–D10 kataloğu ve sade ayrıntılar, isteğe bağlı başvuru bilgisi | Şablon yaşı ve API anahtarı ilk ekranda gereksiz karar istiyor. |
| Son kullanıcı: hazırlanmış senaryoyu izleme ve devamını seçme | Mevcut `GraphPlaybackScreen`/controller'ın video bitişi ve dal seçimi davranışı | Giriş debug klip üretim alanında. Release'de görünen hazır örnek graf yalnız çizimdir. Son kullanıcıya hazırlanmış içeriği sunma adımı tamamlanmamıştır. |
| Son kullanıcı: bir yerel video izleme | Mevcut `VideoAnalysisScreen`'in seçme/izleme bölümü | Bu, dallı senaryo kataloğu veya analiz değildir. Yerel dosya seçme gereksinimi normal kullanıcı hedefinde ayrıca tartılmalı; mevcut işlev hemen silinmemeli. |
| İçerik üreticisi: senaryo ve akış hazırlama | Ortak girdi ekranı, mevcut Qwen demo, `ScenarioInput`/converter, graf görüntüleyici | JSON teknik kalabilir; serbest metin anlayan veya içerik onaylayan sistem gibi sunulmamalı. |
| İçerik üreticisi: dış üretim ve dosya hazırlama | Klip planı/prompt, eşleme, önizleme, videolu akışı dene | Bugün yalnız sabit D01. Yeni grafla birleşmiş değildir; “İncelenmedi” anlamı korunmalı. |
| Geliştirici: motor ve model kalitesi karşılaştırma | Model indirici, TR/EN ve tekli testler, altı deneme, ham tanılar | Son kullanıcı işi değildir. Karşılaştırma modeli ile sabit Qwen demo birbirinden ayrılmalı. |
| Tarihsel örnek üretimi | Eski ONT şablonları ve eski ekran kodu | Güncel görev/kart desteği olarak sunulmamalı. Çağrı ve ortak tipler incelenmeden silinmemeli. |

### 3.1 Gerçek veri bağlantıları ve kimlikler

| Adım | Girdi → çıktı / saklama | Sonraki bağlantı ve kanıt |
|---|---|---|
| Model seçimi/indirme | `LocalModelOption` → belge dizini `models/<dosya>`; ayrı Llama/Qwen/MiniCPM isimleri | **Bağlı, teknik yol.** Model seçimi altı denemeyi etkiler. Genel Qwen tekli kartları ve graf demosu Qwen'e sabittir. `llama_model_service.dart:48,106`; Stüdyo `:263,342`. |
| Gerçek çıkarım | `LocalLlamaTestService.run` → `LlamadartTestRuntime.load/generate` → CPU `LlamaEngine.setModel/create` | **Bağlı.** Yerel dosya, temiz tek user mesajı; model yoksa hata. Otomatik indirme, başka model/şablona dönüş yok. `llamadart_test_runtime.dart:21,38,140`. |
| Eski şablon üretimi | Yaş/ONT/risk/süre → `generateSession` | **Ayrı şablon yolu.** `generateWithLlama` da aynı servise delegedir (`llama_model_service.dart:329`); GGUF kullanmaz. Şablon etiketi kaynakta doğru. |
| Ham cevap → editör | Servis `state.text` aynen korunur; ekrandaki kopya işlenir | **Bağlı.** Yalnız tüm cevabı çevreleyen JSON çiti ve tek `scenarioInput` açılır. Bozuk JSON veya anlatı onarılmaz. `scenario_graph_import_screen.dart:124,150`. |
| Metadata ve kaynak | Uygulama `d01GraphDemoMetadata` sağlar: sabit `d01-qwen-yerel-demo`, dil/yaş/D01/0.2 | **Bağlı.** Modelin metadata'sı uygulamanın sabit değerleriyle ezilir; bu ekranda açıklanır. Yeni anlatı eklenmez. Düzenleme `model_output_edited` olur. `local_llama_test_service.dart:80`; ortak ekran `:177,201`. |
| Girdi doğrulama → graf | `ScenarioInput.fromJsonString` → `ScenarioGraphConverter.convert` | **Bağlı.** Boş/eksik/yanlış tür/fazla alanlar kontrol edilir. N alternatif → 1+2N sahne ve 2N geçiş; tek dallanma düzeyi. Genel sözleşme iki alternatif zorlamaz; sabit D01 demo ayrıca iki alternatif ister (`:230`). |
| Graf → görüntü | Doğrulanmış nesne → `ScenarioGraphScreen(graph,sourceLabel)` | **Bağlı; burada durur.** Metinleri değiştirmeden taşır. Kaynak beyanı içerik veya köken doğrulaması değildir. |
| Graf → klip planı | Yeni nesne için çağrı/kayıt/asset üretimi yok | **Eksik.** Plan ekranı daima sabit asset yollarından yükler. Yeni grafın yanında sabit D01 planını açmak gerçek bağlantı olmaz. |
| Sabit graf + plan | `d01-elle-hazirlanmis-taslak-001` + `d01-elle-hazirlanmis-klip-plani-001` | **Sabit örnek, bağlı.** `ScenarioClipPlan.validateAgainst` scenarioId, sahne referansı ve bütün sahnelerin kapsanmasını denetler. |
| Video seç → eşleme | Galeri → uygulama kopyası → `clip_video_bindings.json` | **Bağlı.** Anahtar `(planId,clipId)`; yollar belge dizinine göreli. Kopya ve indeks başarılı olmadan eski eşleme bozulmaz. `clip_video_store.dart:132,149,185`. |
| Eşleme → oynatma | Plan klip sırası + graf geçişi + kayıtlı kopya | **Sabit örneğe bağlı.** Klip gerçek bitiş bildirimiyle ilerler; hedef süre zamanlayıcısı yok. Çok çıkışta kullanıcı seçim yapar. Eksik video atlanmaz. |
| Senaryo sonu | Bitiş sahnesinin son klibi → `completed`, “Senaryo tamamlandı” | **Bağlı.** Başta tekrar oynatılabilir. Seçilen yol arşivi, o yolu otomatik tekrar etme kaydı veya tek video dosyası üretimi yok. `graph_playback_controller.dart:170–203`. |

Kimlik notu: Elle hazırlanmış senaryo girdisinin `scenarioId`'si `d01-elle-hazirlanmis-donusum-001` olup sabit videolu grafla aynı değildir. Üç örneğin birbirine dönüştüğü varsayılmamalı. Converter'ın `alternative_1/ending_1` kimlikleri sıraya bağlıdır. İleride içerik değiştirilip aynı planId/clipId korunursa eski video anlamı karışabilir; **bugün yeni graf/video yanlış eşlemesi doğrulanmış değildir**, bağlantı zaten yoktur. Kalıcı bağlantı öncesi kimlik/sürüm kuralı belirlenmeli; mevcut eşlemeler yeniden etiketlenmemeli.

### 3.2 Güncel davranışların eski içerikle sınırı

`BehaviorCards.all`, D01–D10 adlarını ve altı gözlem koşulu alanını sürüm 0.2'den taşır. Aşağıdaki adlar uygulamadaki güncel katalogdur; eski ONT'lerle ad benzerliğinden eşleme yapılmamıştır.

| Güncel kart | Katalog konumu (`behavior_cards.dart`) | Üretim/video durumu |
|---|---|---|
| D01 · İsme tepki verme | `:52` | Sabit 30 ay Qwen demo + ayrı elle hazırlanmış graf/klip planı. D01'e özgü içerik doğruluğu otomatik doğrulanmaz. |
| D02 · Yetişkinin işaret ettiği hedefe yönelme | `:86` | Bilgi kartı; güncel üretim/video bağlantısı yok. |
| D03 · İstemek için işaret etme | `:119` | Aynı sınır. İsteme, paylaşma/gösterme ile birleştirilmez. |
| D04 · Hayali oyun — mış gibi yapma | `:151` | Aynı sınır. Model/yönergesiz boş fincan–bebek görevi korunur. |
| D05 · Paylaşmak için elindeki nesneyi gösterme | `:181` | Aynı sınır. Yardım isteme/teslim ile eşit sayılmaz. |
| D06 · Basit motor hareketi taklit etme | `:212` | Aynı sınır. Eski ONT-06 yetişkin elini araç kullanma görevi değildir. |
| D07 · Gülümsemeye karşılık verme | `:244` | Aynı sınır. Ce-e oyununun uyaranlarıyla aynı koşul değildir. |
| D08 · Jest desteği olmadan tek basamaklı sözel yönergeyi yerine getirme | `:275` | Aynı sınır. Eski ONT-08 nesne getirme/ce-e şablonuyla karıştırılmaz. |
| D09 · Nesneyi bir kaba yerleştirme | `:306` | Aynı sınır. Kendiliğinden görev; yönergeli görev veya eski işlevsel oyuncak kartı değildir. |
| D10 · Kalemle kendiliğinden karalama yapma | `:342` | Aynı sınır. Eski sallanma/tekrarlayıcı hareket kartı değildir. |

D01/02/06/07/08 için 10 sn, diğerleri için 20 sn pencereler pilot kayıt düzenidir; klinik eşik değildir. D01 tek çağrı, çağrı öncesi yönelmemiş olma ve ek uyaran olmaması koşullarını taşır. Sabit klip planı 6 sn ortak oyun ve her dalda 8+8+2 sn hedefler: her yol 24 sn planlanır. Çağrı bitişinden sonraki gerçek 10 sn görünürlük/süreklilik ayrı videodan doğrulanmalıdır; ayrı üretimler kesintisiz gözlem kanıtı değildir.

**Karışmanın kaldığı yerler:** Stüdyo ONT seçicisi `ScenariosRepository` okur; eski risk/yaş profilleri ve dışa aktarma metinleri devam eder. ONT-01 kaydı 1–3 çağrı ve >3 sn risk ifadesi taşır (`scenarios_data.dart:77–84`); bunlar D01 kuralları değildir. `_getPhasesForCode` içindeki ONT-07/08 ortak ce-e dalı (`synthetic_video_service.dart:786`) somut eski şablon hatasıdır. Örnek raporun ONT kodları da eski katalogla tutarlı bir ortak kimlik sözlüğü değildir. Ana panelin güncel kataloğa geçmesi bu tüketicileri göç ettirmemiştir; bu ayrım korunmalıdır.

## 4. Sadeleştirme kararları: ne korunmalı, ne birleştirilmeli?

| Karar | Kapsam ve somut gerekçe | En küçük güvenli yaklaşım / bağımlılık |
|---|---|---|
| **Koru** | Güncel katalog, ayrıntı açılırları, F04 onayı, F05 aday video, kaynak etiketleri, doğrulayıcılar, eşleme/oynatma | Çalışan sorumlulukları birleştirerek yeniden yazma. Özellikle ScenarioInput, graf ve plan doğrulaması farklı kuralları denetler. |
| **Birleştir** | Ortak içe aktarmaya Stüdyo, D01 ayrıntısı ve klip planından üç giriş; aynı amaç için kullanıcıdan yön seçimi isteniyor | Üretici tarafında Stüdyo ana girişini esas al; diğer teknik kısayollar azaltılabilir. Ekran/servis kopyalama yok. |
| **Birleştir/kaldırma adayı** | Şablon motorunun iki düğmesi aynı `generateSession` içeriğine gidiyor | UI'de tek şablon seçeneği; eski servis metodunu hemen silmek zorunlu değil. TR/EN gerçek testleri bununla birleştirme. |
| **Üretici alanına taşı** | Home şablon yaşı, API anahtarı, D01 demo kısayolu, JSON/model/prompt/eşleme | Mevcut Stüdyo ve alt bölümler kullanılır. Son kullanıcıdan teknik parametre istememek için; yalnız debug gizlemek yetkilendirme sayılmaz. |
| **Yeniden adlandır** | Video Analiz Modu → Video izle; Video Yükle → Video seç; genel Senaryo Stüdyosu kullanıcı girişi → Senaryolar; ekipte Grafı dene → Videolu akışı dene | Gerçek işlevi anlatır. “Grafı dene” bugün doğru bir geliştirici adı; son kullanıcı için teknik. Yeni grafın videosu varmış gibi adlandırma yapılmamalı. |
| **Sakla/ayrı ele al** | Şablon örnekleri, uzun tanılar, eski ONT/risk içeriği | Ekip/tarihsel alanında kapalı. Mevcut gruplama korunur; kapatma işlemi state'i silmemeli. |
| **Normal görünümden kaldır** | Risk/norm bildiren sabit örnek rapor, Gemini'nin izleme veya yerel üretim için gerekliymiş gibi sunulması | Kaynak veriyi/model tiplerini silmeden görünür alanı sınırla. Yalnız daha uzun uyarı eklemek yeterli değil. |
| **Gerekli eksiği tamamla; ayrı iş** | Hazır içerikten izleyiciye ulaşma; yeni grafın kendi plan/video bağlantısı | Bunlar aynı iş değil. Önce mevcut hazır D01 bağlamının kullanıcıya uygun girişi; sonra yeni graf için plan/kimlik bağlantısı. Bu rapor bunları uygulanmış saymaz. |
| **Sonraya bırak** | Eski ekran dosyalarını kaldırma, sunucuya taşıma, model değiştirme, genel refactor | Hedef akış netleşmeden geniş değişiklik çalışan enum, servis ve testleri kırabilir. Dosya büyüklüğü tek başına silme/refactor gerekçesi değildir. |

## 5. Öncelikli bulgular ve veri/hata değerlendirmesi

P0: veri kaybı/yanıltıcı sonuç/temel hedefin kesilmesi. P1: kullanımı belirgin zorlaştırır. P2: bakım veya görsel iyileştirme. Aşağıdaki kayıtlar tekrar eden nedenleri birleştirir; envanterdeki işlemler bu bulgulara dayanır.

| Bulgu | Sorun ve kullanıcı etkisi | Dayanak / kanıt | En küçük düzeltme | Öncelik / risk |
|---|---|---|---|---|
| **S01 · İzleme ile hazırlama arasındaki sınır ve eksik bağlantı** | İzleyici Stüdyo'da üretici araçları görür; hazır videolu deneyim debug planın arkasındadır. Modelin grafı ise görüntüde biter. | E16–E18/E26–E35; `ScenarioGraphImportScreen._viewGraph`, `ClipProductionPlanScreen._load`. K/B | Mevcut hazır örnek ile üretici girişlerini ayır; yeni graf–plan bağlantısını ayrı eksik olarak tut. Son kullanıcı erişimi için hazır graf+plan+eşleme bağlamı açık taşınmalı. | P0 hedef uçtan uca akış için; bağlantı geliştirmesi orta/yüksek, yalnız düzenleme düşük/orta. |
| **S02 · Örnek raporda klinik risk dili sürüyor** | “Gelişimsel Normlara Uygun (Risk Saptanmadı)”, “Sınırda Tepki”, “Klinik İnceleme” normal video sekmesinde sabit rapora ait olsa da klinik değerlendirme izlenimi verir. | `video_analysis_screen.dart:784,881`; `models.dart:1`; `ExpandableFindingCard`. K. Kullanıcı videosuna aktarılmadığı ayrı olumlu bulgudur. | Örnek raporu son kullanıcı görünümünden çıkar/ekibin tarihsel örneğine ayır; kullanıcı videosunun analiz edilmediği açıklamasını koru. | P0 yanlış anlam riski; düşük/orta. Paylaşılan tipleri silme. |
| **S03 · API anahtarı yanlış görevin yanında** | Ana panel ve video izleme Gemini/Veo üretimi açıklayan dialoga gider; aktif Qwen ve şablon bu anahtarı kullanmaz. İzlemek için kayıt/anahtar gerekli sanılabilir. | `ApiKeyDialog.show:34`; `LlmRagService.generateScenario:49–78`; E09. K | Simgeleri normal panel/video alanından kaldır veya mevcut teknik bölüme taşı. Uzak eski yol varlığını inkâr etme; sunucu entegrasyonu ekleme. | P1, vaat yönünden P0; düşük. Tercih kaydı/servis korunabilir. |
| **S04 · Sekme görünürlüğü videoyu durdurmuyor** | Home `IndexedStack`'i oynatıcıyı yaşatır. Sekme değiştirme/back ile panele dönme yalnız indeksi değiştirir; Video ekranına pause/görünürlük bilgisi verilmez. Diğer iş sırasında ses sürebilir. | `home_screen.dart:31,88,124`; `VideoAnalysisScreen` yaşam döngüsü. K/koşullu M; cihazda burada tetiklenmedi. | Sekme terkinde mevcut controller'ı duraklat; dönüşte otomatik başlatma. Aynı controller'ı kullanan tam ekranın sahipliğini koru. | P1; orta. Graf oynatıcısının kendi tek-oynatıcı garantisi, gizli diğer sekmeyi kapsamıyor. |
| **S05 · Gizli admin bir yetki değil** | Üretim promptları beş dokunuşla ve release'de de açılabilen yerel bool'un arkasında. Doktor/admin/mühendis isimleri gerçek rol varmış gibi anlaşılabilir. | Stüdyo `:61,554,806`; eski Simülasyon `:45`. K | Gizli hareket yerine mevcut açık ekip bölümünde görünürlük; henüz yetkilendirme iddiası kurma. Yeni hesap altyapısı bu tur için gerekmez. | P1; orta. Prompt görünürlüğü istemeden genişlememeli. |
| **S06 · Tarihsel şablon güncel kart değil** | ONT/risk/başarı normları ve ONT-08→ce-e hatası; gizli şablon klip seçicisinde 10 sn seçeneği de var. Güncel ≤8 sn üretim planıyla aynı kapsam sanılabilir. | `scenarios_data.dart:77–84`; `synthetic_video_service.dart:786`; Stüdyo `:1608,1693`; export `:166,216`. K | Eski şablonu ekipte tarihsel olarak ayır; ONT-08 düzeltmesini kendi hedefli işi yap. 10 sn seçeneği bu üretim sınırıyla uyumlu değil; güncel plan değişmeden ayrı düzeltilmeli. | P0 içerik/doğruluk, yalnız sınırlandırma düşük/orta; kimlik göçü yüksek. |
| **S07 · Oturum taslağı hâlâ kaybolabilir** | F04 kazara çıkışı azaltır; bilinçli çıkış/OS kapanışı kaydı yok. Örnek yüklemek veya yeni üretim editörü onaysız değiştirebilir. Kullanıcı daha önce ekran kapanınca ham cevabını kaybetti. | Ortak ekran `:60,124,261,322`; `LocalLlamaTestService` yalnız state. K/B/T. Yeni kayıp denemesi yapılmadı. | F04 korunmalı. Sonraki küçük koruma örnek/yeni üretimle üzerine yazma onayı olabilir; kalıcı saklama ayrı iş. Bu incelemede kayıt eklenmedi. | P0; orta. Ham cevap–editör–kaynak ayrımı bozulmamalı. |
| **S08 · Stüdyo yaşı dış parametreyle geri alınabilir** | Home rebuild'de `initialAgeMonths` yeniden verilir; Stüdyo `didUpdateWidget` bunu `oldWidget` yerine kendi seçimiyle karşılaştırır. Stüdyo'daki farklı yaş beklenmedik şekilde Home yaşına dönebilir ve şablon yeniden üretilebilir. | `home_screen.dart:93`; Stüdyo `:180–193`. K/koşullu M. Eski initialOntologyCode artık Home'dan verilmez; yaş yolu sürer. | Dış parametre gerçekten değişince uygula; `oldWidget` ile kıyasla. Modelin sabit 30 ay demosuna dokunma. | P1; düşük/orta. Üretici yaş kontrolünü tek yere toplamak da bu sorumluluğu sadeleştirir. |
| **S09 · Yerleşim ve erişilebilir adlar** | Video alanı sabit16:9; portre dosya doğru oranla gösterilmeyebilir. Tek satır medya kontrolleri ve uzun admin/yaş başlıkları büyük yazıda taşma riski taşır. Ses/oynat/tam ekran simgelerinde açık tooltip eksik; mute görünümü yerel `_isMuted` ile gerçek volume'dan ayrılabilir. | Video `:556`; `FloatingVideoControls:42,73–143`; `AgeSliderCard:42–76`; Stüdyo `:1413,1651`. K/M | Gerçek oran, dar alanda Wrap/Flexible ve eylem adları; sesi controller değerinden göster. Önce ilgili durumun görsel/etkileşim kontrolü. | P1; düşük/orta. “Taştı” diye cihazda görülmüş sonuç iddiası yok. |
| **S10 · Kapanış hatası yeniden başlatmayı kilitleyebilir** | `_releasing.then` zinciri pause/close hatasında başarısız kalır; restart aynı hatalı Future'ı tekrar bekler. Normal eksik dosya toparlanmasıyla aynı sorun değil. | `GraphPlaybackController._releasePlayer:89`, `_loadCurrent:108`, `_fail:206`. K/koşullu M; gerçek kapatma hatası bildirilmedi. | Kapanış sonucunu açık yönet; eski oyuncunun kapandığı bilinmeden kilidi kaldırıp ikinci oyuncu açma. | P1; orta. Tek oyuncu ve eski olay koruması korunmalı. |
| **S11 · Model/test kapsamları birbirine karışıyor** | Karşılaştırma seçimi MiniCPM olsa bile tekli Qwen ve graf demo sabit kalır. “Ortak başlangıç” kartı yalnız oyun ister; altı görev protokolünde çağrı vardır. | Stüdyo `:135,342`; `LocalLlamaTestRequest.qwenCommonStart:148`, `d01GraphDemo:91`. K/R | Teknik adları göreve göre düzelt; altı denemeyi tekli oyun kartı altından ayrı alt başlığa al. İstem/ham kayıt değiştirme. | P1; düşük. Bunları aynı deney protokolü sayma. |
| **S12 · Eksik eski asset ve yanıltıcı README** | `assets/videos` altında yalnız README; pubspec'teki 12 ONT alt klasörü ve örnek MP4 mevcut değil. README ilk ONT'yi hazır ve dosya kopyalamayı otomatik tanıma gibi anlatır. | `pubspec.yaml` asset bloğu; `assets/videos/README.md`; eski `videoAssets` ve `_clinicalCases`. K/B | Gerçek mevcut asset bildirimi/dokümanını düzelt; kaynak video uydurma. Kalıcı belge dizini videoları asset'lerden ayrıdır. | P2/P1 örnek açılışı; düşük/orta. Önceki derlemeler uyarılara rağmen tamamlandı bildirimi var; kesin derleme engeli denmiyor. |
| **S13 · Uzun teknik içerik birincil eylemi uzaklaştırıyor** | Ortak ekran JSON'dan önce uzun metadata/biçim açıklaması ve ham model cevabı çizer. Uzun cevap sonrası “Graf oluştur”a erişim zorlaşabilir; şablonda iki davranış ekleme ve iki çıktı görünümü de seçim yükü yaratır. | Ortak ekran `:379–431`; `LocalLlamaTestCard:82–124`; Stüdyo `:1480,1571,1848`. K/M | Teknik ayrıntıları mevcut açılırlarda tut; ana iş ve kısa durum önce gelsin. Aynı davranış seçicinin iki çağrısından biri yeterli olabilir. | P1; düşük/orta. Tam ham cevaba erişim ve editör korunmalı; metni küçültmek çözüm değil. |
| **S14 · Eski uzak üretim yolu yanıltıcı ilerleme/fallback taşır** | Eski RAG kaynak PDF taradığını ve FSM'e eklediğini söyler; kod sabit repository okur, API hatasında şablona döner. `addGeneratedScenario` gövdesi boştur. | `llm_rag_service.dart:41–84,96`; `scenarios_data.dart:63`; çağrı eski Simülasyon `:937`. K | Mevcut ana akışa yeniden bağlama; ileride kullanılacaksa kaynak ve kayıt mesajlarını gerçek davranışla düzelt. | P2 bugün, yeniden açılırsa P0; orta. Qwen demosunda bu fallback yoktur. |
| **S15 · iOS/cihaz kanıtı yok** | Info.plist'te fotoğraf/kamera/mikrofon kullanım açıklamaları yok; galeri/kamera yollarının iPhone'a hazır olduğu doğrulanamaz. M21/iPhone performansı kaynak kodundan çıkarılamaz. | `ios/Runner/Info.plist`, ImagePicker çağrıları; R/B. | Gerçekte kullanılacak iOS eylemlerinin izin hazırlığını ayrı dar iş yap; sonra gerçek cihazda doğrula. Yeni model/sunucu bu incelemeye eklenmez. | P1 iPhone hedefi için; düşük/orta. Burada bir iPhone çökmesi gözlenmedi. |

### 5.1 Veri yaşam süresi

| Veri | Sekme/alt ekran dönüşünde | Ekran kapanıp yeniden açılınca | Uygulama yeniden açılınca | Dayanak |
|---|---|---|---|---|
| Home yaşı/sekmesi | Home state'inde kalır | Home yeniden kurulursa varsayılan | Kalıcı kayıt yok | `HomeScreen` alanları |
| Stüdyo model seçimi/şablon/tekli cevaplar | IndexedStack ve `maintainState:true` ile kalır; yaş S08'e tabidir | Yeni ekran nesnesinde varsayılan/state sıfır | Tekli cevaplar kaydedilmez | Stüdyo init/dispose, LocalLlamaTestService |
| Ortak ham cevap/düzenlenmiş JSON/doğrulama/graf | Graf görüntüleyiciye gidip gelince aynı state; girdi türü değişince iki metin korunur ama doğrulama sonucu temizlenir | Onaylı çıkış sonrası kaybolur; F04 onaysız çıkışı önler | Kurtarma yok | Ortak ekran `_drafts`, `_requestExit`, `_selectType`, `dispose` |
| Oluşan grafın kaynak beyanı | Nesne ve gösterim metninde kalır | Kalıcı kayıt yok | Yok | Converter `authoringNote`, `_viewGraph` |
| Video izle'deki kullanıcı dosyası/seçim | IndexedStack'te kalır; tam ekran aynı controller | Ekran yeniden kurulunca örnek denenir | Bu yol kopya/eşleme kaydetmez | `_pickVideo`, `_openCandidate`, `initState` |
| Klip video eşlemesi ve uygulama kopyası | Kalıcı indeks okunur | `loadPlan` ile tekrar yüklenir | Belge dizininde saklıdır; uygulama verisi silinirse korunma garantisi yok | `ClipVideoStore` |
| Model dosyaları | Belge dizininde | Yeniden bulunur | Kalıcı dosya kalır | `LlamaModelService.getModelFile` |
| Yarım model indirmesi | Kopma/iptal `finally` yolunda `.part` silinir; süreç zorla ölürse artık dosya kalabilir | Yeniden deneme HTTP GET/200 ve `openWrite`, Range yok; baştan yazar | Kaldığı yerden devam yok | `llama_model_service.dart:140–157,237–248` |
| Altı değerlendirme kayıtları | Dosyalar korunur; UI son çalışma snapshot'ını tutar | Dosyalar kalır; mevcut UI geçmiş run tarayıcısı değil | `evaluations/d01_qwen/run_*` kalır; MiniCPM de bu isimli kökü kullanır | Stüdyo `:136`; D01EvaluationService `_write/_execute` |
| Gemini anahtarı | Tercih kaydında | Kalır | SharedPreferences'ta kalır; bu görev değeri okunmadı | LlmRagService get/save/clear |
| Seçilen oynatma yolu/konum | Controller state'inde | Yeni açılış başlangıca döner | Yol/oturum arşivi yok | GraphPlaybackController |

### 5.2 Korunacak hata/iptal ve kaynak davranışları

- **Video seçimi:** F05 `_selectionRequest/_openRequest`, `mounted`, iptal Completer'ı ve idempotent `_release` kullanır. Başarısız aday mevcut controller'ı değiştirmez; eski bulgular kullanıcı videosuna taşınmaz. Tam ekran geçişinde aynı controller kullanımı korunmalı. Bu test kaynağı vardır; gerçek codec hatası burada denenmedi.
- **Klip eşleme:** Disk yazımı geçici indeks+rename ve seri işlem kuyruğu kullanır. Kopyalama/kayıt hatasında eski çalışan eşleme kalır. Kaldırma galeriyi değil uygulama kopyasını temizler. Ekran kapandıktan sonra başlamış dosya işlemi tamamlanabilir; `mounted` UI güncellemesini önler, disk işlemini iptal etmez. Bunu “iptal edilip hiçbir kayıt yapılmadı” diye sunmamak gerekir.
- **Graf denemesi:** Epoch ve `_endHandled` eski/çift video sonunu reddeder; klip değişiminde eski oyuncu kapanmadan yenisi oluşturulmaz. Arka planda `suspend`, geri gelince yalnız bayrak sıfırlanır, otomatik play yapılmaz. Ekran geri çıkışında `close`, sonra `dispose` vardır. Kaynak kapatma hatası S10 ayrı açık işidir.
- **Tek klip önizlemesi:** Dosya eksik/açılamazsa eşleme silinmez; dispose oynatıcıyı bırakır, yüklemeden geç dönüş `mounted` ile korunur. Ekran graf denemesi gibi özel lifecycle gözlemcisi taşımaz; video_player'ın uygulama yaşam döngüsü davranışı ve dönüşte otomatik devam durumu cihazda sınanmalıdır.
- **Model:** Global `_owner` eşzamanlı ikinci testi engeller; her çalıştırma yeni runtime ve temiz konuşma kullanır. İptal yükleme sırasında zorla isolate öldürmez; kapatma beklenir. Kapatma hatasında yeni testi kilitli tutup kullanıcıya yeniden başlatma mesajı verir (`local_llama_test_service.dart:219–343`). “İptal”in anında tamamlanacağı vaat edilmemeli.
- **Eski şablon:** `_generateScenario` 250 ms gecikmeli callback ile çalışır; son state ataması mounted kontrolündedir. Bu yolun genel bir iptal/istek kimliği mekanizması yoktur. Kaynakta olası beklenmedik durum olarak not edildi; gerçek takılma veya sonuç yarışı bu görevde gösterilmedi. Şablon alanını kaldırmadan önce tüketicileri korunmalı.

### 5.3 Görünüm ve erişilebilirlik: kanıt sınırı

İyi mevcut parçalar: graf kutusunda kısa başlık/iki satır özet ve tam metin alt paneli; sahne `Semantics` etiketi; graf zoom/Tümünü göster tooltip'leri; dal düğmelerinde sarılan metin ve en az 48 yükseklik; seçenek ayrıntısında tam metin; klip kontrollerinde `Wrap`; önizleme ve graf videosunda gerçek en-boy oranı. Bunlar yeniden yapılmamalı.

Koddan görülen riskler: 11–12 punto alt sekme/ikincil metinler; Stüdyo'daki sabit Row başlıkları ve 14 boyutlu kapatma simgesinin 4 padding'i; `GestureDetector` yaş kısayollarında açık seçili/eylem semantiğinin eksikliği; kompakt medya IconButton'larının etiket ve dar alanda sarılma eksikliği; renkli eski risk sınıfları. Grafın iki satır kesmesi, tam metin paneli varken tek başına içerik kaybı değildir. Yeni ayrıntı ekranı kaydırılabilir ve açılırları vardır; eski raporun uzun açık metin eleştirisi aynen taşınmaz.

Bu görevde ekran görüntüsü/gerçek etkileşim görülmedi. Kontrastın ölçüldüğü, büyük yazıda kesin taşma olduğu veya ekran okuyucunun kullanılamadığı iddia edilmez. JSON ekranında SingleChildScrollView ve çok satırlı alan var; klavye açıkken doğrulama/çıkış düğmelerine erişim manuel kontroldür. Genel uyarı paragrafları eklemek yerine doğru alanı doğru kişiye sunmak tercih edilmelidir.

### 5.4 Test ve gerçek kullanım kanıtı

| Kaynak | Hedeflediği davranış | Bu rapordaki anlamı / boşluk |
|---|---|---|
| `behavior_cards_test.dart`, `widget_test.dart` | On doğru kimlik/ad; ayrıntı metni/açılır tam içeriği; D02–D10 yanlış üretim düğmesi olmaması; D01 sabit demo; gerçek sekme hedefleri | Güncel test kaynakları var. Burada çalıştırılmadı. Home testleri kontrollü video/platform kullanır; telefon kanıtı değil. |
| `scenario_model_demo_test.dart`, `scenario_graph_import_screen_test.dart` | Ham cevap, metadata, kaynak, biçim normalizasyonu; hatalı girdiler; F04 AppBar/sistem geri, kalınca aynı graf, boş ekran/aktif üretim | Kontrollü servis. İçerik anlamsal doğruluğunu veya OS sonrası kurtarmayı doğrulamaz. |
| `studio_sections_test.dart` ve etkilenen giriş testleri | İlk kapalı bölümler; girişler; model/servis/ham cevap ve şablon görünümü korunması | Testte FormFieldState tür düzeltmesi mevcut. Son koşunun geçtiği sonuç burada yok. |
| `video_analysis_source_test.dart` | Önceki video, aday başarı/hata/iptal, eski picker/create sonuçları, kapatma, kullanıcı videosunda örnek bulgu olmaması, tam ekran controller ortaklığı | Gerçek video motoru yok. Sekme sesi ve gerçek dosya/codec/iOS izinleri boşluk. |
| `scenario_graph_converter_test.dart`, graf/plan kontrol dosyaları | Metin koruma, değişken alternatif, eksik/geçersiz veri ve referanslar | Yapısal test; davranış uygunluğu ve promptun gerçekleşmesi değil. |
| `clip_video_store_checks.dart`, eşleme ekran testleri | Gerçek geçici dosyalarla kopya/indeks; kayıt hatasında geri alma; yeniden yükleme ve eksik dosya | Telefon galerisi değil. Widget testlerinde runAsync/kontrollü sınırlar kullanılmış; yeni tur başlatılmadı. |
| Önizleme/graf oynatma kontrollü testleri | Başlatma, iki yol, gerçek son bildirimi benzetimi, çift son, eksik video, restart, arka plan, geç yükleme | Dar ekran/büyük yazı için graf ve dal ekranında beklentiler var. Gerçek native kapanış hatasından sonra toparlanma, TalkBack/VoiceOver ve her ekranın dar hali tam kanıtlı değil. |
| Kullanıcı bildirimi (DEVAM_NOTU) | Modelden graf demosu; video bağlama, yeniden açılınca eşleme, önizleme ve iki yolun tamamlanması | Emülatör gözlemi. Aynı test videosu farklı kliplerde kullanıldı; içerik/süreklilik doğrulanmadı. |
| Kayıt temelli model raporu | Qwen 6, MiniCPM 6 gerçek deneme; Llama tam ham kayıt yok | Küçük örneklerde yönerge/biçim ihlalleri; genel model başarısızlığı sonucu değil. Bu görev ham dosyaları yeniden taramadı/çalıştırmadı. |

Gerçek M21 ve iPhone 11 testi, bu değerlendirmelerin çıkarım tepe RAM ölçümü ve bugünkü kaynak için yeni temiz test/analiz sonucu yoktur. CPU yerel motoru mevcut olması hedef cihazda kabul edilebilir hız/bellek kanıtı değildir. Eski notlarda MiniCPM denenmedi ifadesi ile sonraki altı gerçek kaydın tarihi farklıdır; sonraki kayıt raporu esas alınır. Sunucu planı bu eksikleri bugün otomatik çözmüş sayılmaz.

## 6. Mevcut bileşenlerle önerilen sade gezinme

Yeni sekme/ekran veya hesap sistemi gerekmeksizin önerilen dağılım:

1. **Ana Panel:** Kısa amaç, hazırlanmış senaryolara giriş, farkındalık için güncel kartlar; başvuru bilgisi ikincil. Şablon yaşı, API anahtarı ve D01 teknik demo kısayolu izleyenin temel görevinden çıkarılır. Giriş kartı + alt sekme aynı hedefi açabilir.
2. **Video izle:** Yerel video seçip oynatma işlevi korunur; analiz iddiası ve teknik model ayarı bulunmaz. Örnek klinik rapor normal yolun devamı değildir. Bu sekmenin son ürün için gerçekten gerekli olup olmadığı ayrı soru; bugün silme önerisi değildir.
3. **Mevcut Stüdyo sekmesi / kullanıcıya “Senaryolar”:** Hazır D01 örneği başlangıçta açık ve net etiketli. Akış çizimi yardımcı eylem; asıl izleme mevcut GraphPlaybackScreen ile olmalı. **Bugünkü giriş sadece debug klip planında olduğundan bu normal kullanıcı yolu tamamlanmış değildir.** Hazır kayıtlı bağlamın açık girişini sağlamak, modelden gelen yeni grafı oynatmak anlamına gelmez.
4. **Aynı Stüdyo içinde “İçerik hazırlama” ekip bölümü:** Mevcut ortak senaryo ekranı → graf; ayrı hazır D01 üretim planı/prompt/video eşleme → önizleme/akışı dene. “Teknik model denemeleri” ve “Eski şablon örnekleri” mevcut kapalı alt bölümler olarak kalır. Hidden admin yerine araçların amacı açık olur; bunun erişim yetkilendirmesi olmadığı korunur.

Hazır senaryo izleme ile içerik hazırlama aynı kişi görevi değildir. Dağıtımda üretici bölümünün nasıl sunulacağı kararı verilmeden yalnız sekme adını değiştirmek veya debug düğmesini görünür yapmak yeterli/otomatik güvenli kabul edilmemeli. Yeni genel arşiv, rol altyapısı veya yeni grafik motoru bu önerinin koşulu değildir.

## 7. İlk uygulama turu — en fazla üç küçük değişiklik

Bu rapor **uygulama talimatı değildir**; aşağıdaki üç dar iş sonraki görev olarak seçilebilir. Mevcut çalışan parçalara dokunmadan öncelik önerisidir.

| Sıra | Küçük kapsam | Korunacak sınır ve kabul ölçütü | Risk |
|---|---|---|---|
| **1 · Yanıltıcı video yüzeyini sadeleştir (S02/S03)** | Mevcut video başlığını “Video izle” yap; Home/video API anahtarı girişlerini normal yüzeyden çıkar; sabit risk/örnek raporun normal kullanıcı görünümünü kapat. | Seçme/izleme, F05 eski videoyu koruma, örneğe ait içerik ayrımı ve tam ekran aynı controller kalır. Ortak modeller/veriler silinmez. Yeni analiz yok. | Düşük/orta; ilgili kaynak/gezinti testleri daha sonra hedefli güncellenir. |
| **2 · Ekip araçlarına tek anlaşılır giriş (S01/S05)** | Mevcut Stüdyo bölümlerinde üretim/JSON/model/prompt araçlarını açık “İçerik hazırlama” altında tut; gizli beş dokunuşu ekip erişimi için zorunlu yol olmaktan çıkar. Klip planındaki tekrarlayan içe aktarma kısayolunu azalt. | Servisler build'de yeniden oluşturulmaz; kapatma state/üretim/cevap silmez. Promptlar izleyene açılmaz. Sabit örnek ile yeni graf ayrılığı korunur; yeni graf–video bağlantısı yapıldığı söylenmez. Release/ekip görünürlüğünün biçimi önce netleştirilir. | Orta; widget taşınırken state kimliği ve debug koşulları korunmalı. |
| **3 · Sekme değişiminde sesi güvenli durdur (S04)** | Home–Video izle görünürlük geçişinde mevcut videoyu duraklat; geri dönüşte otomatik başlatma. | F05 aday/önceki controller sahipliği ve tam ekran korunur. Grafın lifecycle davranışı yeniden yazılmaz; yeni oynatıcı altyapısı eklenmez. | Orta; hedefli kontrollü sekme/oynatma kontrolü gerekir. |

Yeni graf–klip/video bağlantısı, kalıcı taslak kaydı, ONT-08 içeriği, iOS izinleri ve kalan görsel sorunlar açık kalır. Hepsini tek sadeleştirme PR'ına yüklemek veya aynı anda yeni sunucu/model bağlamak önerilmez.

## 8. Açık sorular ve manuel kontrol listesi

### Karar gerektiren sorular

- Son kullanıcıya ilk sunulacak içerik yalnız hazır D01 mi? Hangi videoların gerçekten hazırlanıp gözden geçirildiği bu görevde doğrulanmadı; cihazda eşleme varlığı içerik onayı değildir.
- Ekip araçları aynı dağıtımda mı yoksa ekip/debug dağıtımında mı tutulacak? Son kullanıcı ile üretici görevi belli; **dağıtım/görünürlük biçimi** henüz kodda gerçek yetki sistemiyle çözülmüş değildir. Bu soru yeni hesap sistemi gerektiriyor diye varsayılmamalı.
- Son kullanıcı kendi yerel videosunu izlemeye gerçekten ihtiyaç duyuyor mu? Analiz bağlı değilken bu iş ile hazırlanmış dallı içerik ayrı tutulmalı.
- Eski ONT şablonları yalnız tarihsel örnek olarak saklanacak mı? Güncel D kodlarına otomatik dönüştürülmemeli; ONT-08 hatası ve klinik dil ayrı düzeltilmeli.
- Yeni graf ve ilerideki plan için içerik değişince kimlik/sürüm nasıl ayrılacak? Mevcut videoların yanlış plana bağlanmaması için bu karar kalıcı bağlantıdan önce gerekir.
- Taslaklar için beklenen saklama süresi nedir? F04 çıkış onayı, kalıcı kayıt isteğinin yerine geçmez. Sunucu planı da mevcut taslağı bugün kaydetmez.

### Sonraki manuel kontrol — bu görevde başlatılmadı

1. **Dar ekran / büyük yazı:** Ana panelin başlığı/alt sekmeleri, şablon yaş satırı; Video izle kontrol satırı ve portre video; Stüdyo admin başlıkları ve ONT seçici; JSON alanı klavye açıkken; graf ayrıntı paneli; uzun dal seçimi. Metin küçültmeden tam eyleme/metne erişimi kontrol et.
2. **Normal kullanıcı yolculuğu:** Teknik terim bilmeden hazırlanmış senaryoya ulaşma, Başlat, iki ayrı yol, bitiş ve yeniden başlatma. Bugün debug plan adımı gerektirdiğini özellikle kaydet; yeni Qwen grafı ile hazır D01 videosunu aynı senaryo sanma.
3. **Ses ve görünürlük:** Video oynarken sekme değişimi, sistem geriyle panel, kurumlar üst rotası, tam ekran çıkışı, arka plan/geri dönüş; önizleme ile graf oynatıcı için ayrı kontrol. Grafın geri dönüşte otomatik başlamaması beklenir. Bir controller'ın sesi/simgesi diğer görünümle tutarlı mı kontrol et.
4. **Taslak:** Ham cevap + düzenlenmiş JSON + geçerli graf varken AppBar/sistem geri → Ekranda kal; aynı durum korunmalı. Grafı açıp geri gelince onay/taslak kaybı olmamalı. Bilinçli çıkış ve yeniden açılışta kayıt yokluğu açık; yeni örnek/yeni üretim üzerine yazması ayrıca değerlendirilmeli.
5. **Video hatası:** Açılmayan ilk örnek, seçim iptali, bozuk dosya, yavaş eski seçim sonucu, çalışan videoyu değiştirirken hata, eksik kayıtlı kopya. Yeni başarı bildirimi yalnız açılışta; eşleme silinmemeli. Test koşulları gerçek cihaz izni/codec kanıtı değildir.
6. **Erişilebilirlik:** TalkBack/VoiceOver ile oynat/ses/tam ekran ve graf düğme adları, seçili durumlar, odak sırası, açılırların durumu, küçük simge hedefleri, renk dışındaki anlam. Kontrast ve gerçek dokunma hedefleri ölçülmeden uygunluk iddiası kurma.
7. **Hedef cihazlar:** Galaxy M21 4 GB ve iPhone 11'de izin, arka plan, dosya kopyası/oynatma; yerel motor ekipte kalacaksa ayrıca ölçümlü bellek/hız. Bu görev cihaz, native motor veya uygulama başlatmadı.

### Tamamlanmayan kontroller

Flutter testleri/statik analiz/derleme; uygulamanın gerçek ekran etkileşimi; güncel ekran görüntüleri; emülatör ve telefon/iOS denemeleri; gerçek kapatma hatası; yeni model uyumu/çıkarımı; sunucu hizmeti; kurum bilgisi güncelliği ve erişilemeyen cihazdaki mevcut video içeriği kontrol edilmedi. Önceki kayıt raporunun ham dosyaları yeniden okunmadı. Bu eksikler tamamlandı sayılmaz; yeni başarılı test sayısı veya performans sonucu üretilmemiştir.

**Kapanış:** Bu incelemenin ürünü yalnız bu dosyadır. Önceki raporlar ve çalışan parçalar korunmuştur; hiçbir öneri uygulanmamıştır.

## Ek — Eski şablon araçları — bağımlılık ve gereklilik kararı

20 Ekim 2026 · Motor seçicisinin kaldırılmasından sonraki kaynak koduna dayanır. Önceki bölümler tarihsel kayıttır; bu ek onların metnini değiştirmez. İki ana amaç **Video Analizi** ve **Simülasyon ve Eğitim** olarak korunur. Gerçek analiz bağlantısı henüz tamamlanmamıştır. Aşağıdaki öneri yalnız eski şablon bölümüne ilişkindir; bu görevde uygulanmadı.

**Karar: C — Bölümü aktif arayüzden ve otomatik üretim yaşam döngüsünden çıkar; ortak bağımlılıkları şimdilik koru.** Eski ONT/risk temelli doğrusal oturum güncel senaryo hattının ön koşulu değildir. Kaldırma, onun yeteneklerinin yeni hatta taşındığı anlamına gelmez. Genel klip planı/prompt ve uygun toplu dışa aktarım açık eksiklerdir; bu dar kaldırma işinde yeni sistem yapılmamalıdır.

### İşlev karşılaştırması

Konumlar `mobile_skeleton/` köküne göredir. Kanıt güncel kaynak ve testlerin okunmasıdır; bu incelemede test, uygulama, model veya cihaz işlemi başlatılmadı.

| İşlev | Eski şablonun ürettiği / dayanak | Mevcut aktif karşılık ve fark | Kaldırma etkisi / gereklilik |
|---|---|---|---|
| Senaryo içeriği ve alternatifler | Yaş + ONT listesi + tek risk profiliyle `SyntheticVideoSession` ve sıralı `SyntheticVideoStep` üretir; `synthetic_video_studio_screen.dart:397`, `synthetic_video_service.dart:370`. | `ScenarioGraphImportScreen._validate` (`:211`) → `ScenarioInput` → `ScenarioGraphConverter.convert` (`scenario_graph_converter.dart:8`) ortak başlangıç ve değişken sayıda alternatif/bitişten tek düzeyli graf kurar. | Aynı veri değildir: eski yol seçenekli oynatma grafı kurmaz. Güncel içerik/graf hattı korunur; eski ONT/risk oturumu iki ana işlev için zorunlu değildir. |
| Yaş, davranış ve süre ayarı | `_buildTemplateConfigCard` (`:1164`), `_buildClipPromptSettingsCard` (`:1412`): 12–36 ay, eski ONT/profil, 180/210/240 sn toplam, 3/4/5/6/8/10 sn klip. Servis toplamı 180–240, klibi 3–10 sn aralığına sınırlar (`synthetic_video_service.dart:378`). | Yeni girdide yaş/davranış/kart metadata'sı vardır; mevcut Qwen/D01 demosu sabit 30 aydır. Yeni graf ekranı toplam süre veya genel klip süresi planlamaz. | Eski parametrik üretim kaybolur. Metadata ile süre planlaması birbirinin karşılığı değildir. Eski risk/norm seçenekleri güncel karta göç ettirilmemeli; 10 sn seçeneği güncel en fazla 8 sn üretim sınırına uymaz. |
| Klip planı, süreklilik ve promptlar | Servis karakter/ortam, zaman aralıkları, kamera, devam direktifi ve İngilizce promptları bir doğrusal oturuma ekler (`synthetic_video_service.dart:391–455`). | `ClipProductionPlanScreen._load` (`:57`) hazır D01 grafını ve planını asset'ten okur; `ScenarioClipPlan.validateAgainst` (`scenario_clip_plan.dart:173`) bağlantı/kapsamı, `PlannedClip` (`:30`) süre ≤8 sn koşulunu denetler. Promptlar mevcut JSON'dadır; ekran bunları üretmez. | D01 için mevcut prompt görüntüleme/kopyalama korunur. **Yeni veya başka bir graf için genel klip bölme, başlangıç/bitiş sürekliliği ve prompt hazırlama bağlantısı eksiktir.** Eski ONT jeneratörünü tutmak bu boşluğu doldurmaz. |
| Kopyalama ve dışa aktarım | Şablon metni, bütün İngilizce promptlar, eski `session_meta`/`clips` JSON'u ve tek klip promptu kopyalanır (`synthetic_video_studio_screen.dart:702,713,724,2227`; model metotları `synthetic_video_service.dart:166,205,216`). `exportFullMarkdown` da modelde vardır (`:179`); taranan lib/test içinde çağrısı bulunmadı. | D01 planında tek klibin tam promptu panoya kopyalanır (`clip_production_plan_screen.dart:391`). `ScenarioGraph.toJsonString` (`scenario_graph.dart:258`) ve `ScenarioClipPlan.toJsonString` (`scenario_clip_plan.dart:204`) veri API'leridir; ortak graf ekranında genel prompt/toplu paket dışa aktarım eylemi değildir. | Eski doğrusal metin/JSON ve toplu prompt kopyalama erişimi kaybolur. **Aktif içerik için toplu prompt/uygun veri dışa aktarımı mevcut değildir**; ihtiyaç açık kalır. Eski `exportGroundTruthJson` adı gözlenmiş davranış kanıtı sayılmaz; biçimi `ScenarioInput`, `ScenarioGraph` veya `ScenarioClipPlan` yerine geçirilemez. |
| Video bağlama, önizleme, dallı oynatma | Eski şablonun `blockId`/zaman aralıkları üretim taslağıdır; bu bölümden kalıcı video eşlemesine veya dallı oynatıcıya aktarılmaz. | Hazır D01 planı `ClipVideoStore` ile `(planId, clipId)` eşlemesi kullanır (`clip_video_store.dart:99,150`); `ClipProductionPlanScreen` önizleme ve `GraphPlaybackScreen` açar (`:169,290`). | Bu hat eski şablondan bağımsızdır; kaldırmayla silinmemeli. **Modelden oluşan grafın bu plana/video hattına bağlantısı hâlâ yoktur.** |
| Gerçek davranış analizi | Şablondaki kontrol listeleri, risk/profil ve zamanlar üretilmiş taslaktır. Analiz çalıştırılmaz. | Video Analizi bugün seçme/izlemedir; gerçek servis henüz bağlı değildir. | Şablon kaldırmak gerçek analiz yeteneğini kaldırmaz; mevcut olmayan analizi tamamlamaz. |

### Bağımlılık ve güvenli kaldırma sınırı

- **Yalnız şablona ait UI/state:** `_selectedAge`, `_selectedOntologies`, `_selectedRisk`, `_selectedTotalSec`, `_selectedDuration`, `_scenarioViewMode`, `_session`, `_isGenerating`, `_showClipPromptDetails` (`synthetic_video_studio_screen.dart:38–54`); `studio-template-examples` bölümü (`:684`). Bu UI tamamen kaldırılırsa bağlı `_generateScenario`, ONT seçici, yaş/risk/süre yardımcıları, klip başlığı/ayrıntıları, tek metin üretme ve çizme yardımcıları da aynı dar kapsamda kaldırma adayıdır (`:377–397,930–1542,1557–2227`). İsim benzerliğiyle gerçek model testleri bu listeye dahil edilmemelidir.
- **Kurucu parametreleri:** `initialAgeMonths` ve `initialOntologyCode` (`:20–28`) yalnız şablon girdilerini başlatır/günceller (`initState:108`, `didUpdateWidget:129`). Home artık ikisini de göndermiyor (`home_screen.dart:94`); diğer lib çağrısı `simulation_mode_screen.dart:889` parametresizdir. Yaş parametresi testte kullanılıyor (`studio_sections_test.dart:154,181`). Bu, API'nin topluca silinmesine gerekçe değildir: sonraki dar işte imzaları uyumluluk için koru, kaldırılmış şablonu otomatik başlatmalarını kaldır. `modelTestService` ise teknik test servisinin enjeksiyonudur; korunmalıdır.
- **Paylaşılan kod korunmalı:** `LlamaModelService` indirme/dosya bulma için teknik testler ve Qwen graf demosunda kullanılır; sınıf/import bütünü kaldırılamaz. `_copyToClipboard` şablon dışında değerlendirme kayıtlarının kopyalanmasında da kullanılır (`synthetic_video_studio_screen.dart:340,470`). `ScenariosRepository` / `scenarios_data.dart` ayrıca `simulation_mode_screen.dart` ve `interactive_player_screen.dart` tarafından tüketilir. Eski ekran erişilebilirliği bu görevde yeniden değerlendirilmedi; ortak veri silinmemelidir.
- **Eski servis/model API'leri şimdilik tutulmalı:** `SyntheticVideoSession`/`SyntheticVideoStep`, `DoctorClinicalScenario`/`DoctorScenarioBranch`, `SyntheticVideoPromptService`, `LlamaModelService.generateWithLlama` ve `generateDoctorScenarioWithLlama` birbirlerine ve servis testlerine bağlıdır (`llama_model_service.dart:311–344`; `template_source_labels_test.dart:32–62`). Yeni graf bunları kullanmıyor olsa da UI kaldırma işi dosya/model temizliği değildir. Şablon bölümüne özgü import ancak ekrandaki son kullanımı da kaldırıldığında kaldırılabilir.
- **Test etkisi:** `studio_sections_test.dart:152,287,420` yaş güncellemesini, şablon araçlarını ve bölüm state'ini hedefler. `template_source_labels_test.dart:65,107` UI kaynağını/ölçülmemiş sonuçların yokluğunu; ilk iki testi ise korunacak servisleri hedefler. `widget_test.dart:146,248,405` eski şablon kaydırıcısıyla hazırlık yapar. UI kaldırılırsa bu hazırlık değiştirilir; D01 demosunun sabit 30 ay metadata/istem beklentileri kaldırılmaz. Teknik servis/ham cevap koruma, graf/plan girişleri, video eşleme ve oynatma testleri korunur. Test dosyası bütünü silinmemelidir.

### Otomatik üretim ve kapanış tekrarları

`HomeScreen` bütün sekmeleri `IndexedStack` içinde kurar (`home_screen.dart:88–95`). Stüdyo `initState` sonunda koşulsuz `_generateScenario()` çağırır (`synthetic_video_studio_screen.dart:125`); bölümün debug, kapalı veya sekmenin görünmez olması bunu engellemez. İş 250 ms sonra mevcut şablon servisiyle yapılır (`:397–414`); **model çıkarımı değildir**. Dış şablon girdisi değişince `didUpdateWidget` de üretimi tetikleyebilir (`:129–145`). Dolayısıyla yalnız ExpansionTile'ı kaldırmak/gizlemek otomatik işi durdurmaz; ilgili yaşam döngüsü çağrıları ve state birlikte ele alınmalıdır. `mounted` yalnız sonuç state'ine yazmadan önce kontrol edilir; ertelenen şablon hesabının kendisini iptal etmez.

Kapanış tekrarının kaynağı görünüm değil, süreyi dolduran algoritmadır: `_buildClinicalPhases` önce iki sabit `COOLDOWN` fazı ekler (`synthetic_video_service.dart:552–579`). `generateSession` her fazı bir klibe koyar; faz listesi bittiği hâlde hedef süre dolmadıysa `_createCooldownPhase` ile aynı ek sakinleşme fazını listenin sonuna ekler (`:406–464`). Sonraki turda aynı koşul tekrar sağlanırsa bir yenisi daha eklenir. Yardımcının `cur`/`target` parametreleri metni çeşitlendirmez (`:913`). İki saniyeden kısa artıkta döngü durabilir (`:411`); bu yüzden belirli bir tekrar sayısı veya tam süre gerçekleştiği iddia edilmez. Tek metin görünümü bütün `COOLDOWN` açıklamalarını birleştirdiğinden tekrar orada da görünür (`synthetic_video_studio_screen.dart:1774,1864`). Güncel dallı graf böyle bir kapanış doldurma kuralı gerektirmez.

### A / B / C değerlendirmesi

| Seçenek | Kazanç | Bedel / risk | Karar |
|---|---|---|---|
| A — Bölümü korumak | Eski parametrik oturum ve toplu kopyalamaya erişim sürer. | ONT/risk ve 3–10 sn modeli güncel görevlerle karışabilir; otomatik doldurma/tekrar ve ayrı veri hattı sürer. | Önerilmez; iki ana işlev için zorunlu bağımlılık bulunmadı. |
| B — Özgün gerekli araçları aktif hatta taşıyıp UI'yi kaldırmak | Genel prompt/üretim paketi ihtiyacını doğru bağlamda karşılayabilir. | Bugün yeni graf→klip dönüşümü yoktur. Eski jeneratörü taşımak metin, kimlik, dal, süreklilik ve ≤8 sn uyumunu çözmez; küçük UI işi olmaktan çıkar. | Bu ilk kaldırma turu için önerilmez. Gerekli yetenek eksikleri kayda alınır; aktarılmış sayılmaz. |
| **C — Aktif UI ve otomatik üretimi kaldırıp ortak kodu korumak** | Teknik kalabalık ve ilgisiz otomatik şablon işi azalır; çalışan iki içerik hattı korunur. | Eski parametrik taslak/toplu export erişimi kaybolur; bunlar başka düğmeye taşınmış değildir. Ortak eski kod bir süre depoda kalır. | **Önerilen tek seçenek.** Dar ve geri alınabilir; yeni ekran veya alternatif şablon sistemi gerektirmez. |

### Sonraki en küçük uygulama kapsamı

Yalnız Stüdyo'nun eski şablon bölümünü, ona özel state/yardımcıları ve `initState`/`didUpdateWidget` üretim tetiklerini kaldır; kurucu imzalarını ve ortak servis/model/verileri şimdilik koru. İlgili widget testlerinde eski UI hazırlığını güncelle; hazır örnek, senaryo/graf, teknik model servis/state koruması ve D01 sabit 30 ay beklentilerini tut. Video Analizi ve hazır D01 planı/eşleme/oynatma kodu değişmesin. Genel klip/prompt/toplu export açığını bu işe dahil etme ve çözülmüş gösterme.

Bu ekte yalnız karar belgelendi. Mevcut değişiklikler ve `stash@{0}` korundu; kod, test, asset, model, cihaz kayıtları ve önceki rapor bölümleri değiştirilmedi. Cihazda kullanım, çıktı kalitesi ve testlerin geçme durumu bu dar kaynak incelemesinde doğrulanmadı.
