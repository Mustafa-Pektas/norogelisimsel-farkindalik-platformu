# Devam notu — 19 Ekim 2026

## Bu turda tamamlananlar — kaynak kodu ve hazırlanmış testler

- **Taslakla geri çıkış koruması (F04):** Ortak senaryo/graf ekranında ham cevap, kullanıcı metni veya süren çıkarım varsa AppBar ve sistem geri çıkışında onay istenir. Güvenli seçenek “Ekranda kal”dır; vazgeçilince metin, doğrulama sonucu ve graf korunur. Graf görüntüleyicisini açmak terk etme sayılmaz. Bilinçli çıkış mevcut iptal/kapatma yolunu kullanır. Bu koruma kalıcı kayıt veya uygulama kapanınca kurtarma değildir; örnek yükleme/yeni üretimle üzerine yazma koruması henüz yoktur.
- **Ana panel girişleri (F03/F15):** Panel ve alt sekmede “Video izle” adı kullanılır; otomatik/zaman damgalı analiz vaadi kaldırıldı. Senaryo girişi taslakları, hazır örnekleri ve ayrı model denemelerini tamamlanmış tek hat gibi sunmaz.
- **Video açılışı (F05):** Yeni video ayrı aday oynatıcıda açılır; başarılı olmadan çalışan video ve seçim değiştirilmez. İptal/hata önceki videoyu korur. Başarısız aday kapatılır; ilk örnek açılamazsa hata, video seçme ve yeniden deneme olanağı vardır. Geç seçim/açılış sonuçları ve ekran kapanışı için korumalar eklendi. “Video yüklendi” yalnız başarılı açılışta gösterilir. Kullanıcı videosuna örnek bulgu taşınmaması ve tam ekranın çalışan oynatıcıyı paylaşması korunur. Sekme değişiminde ses konusu bu turun dışında kaldı.
- **Stüdyo düzeni:** Debug alanında senaryo içeriği/modelden graf ekranına doğrudan giriş vardır. “Hazır D01 örneği” ayrı tutuldu. “Teknik model denemeleri” ve “Şablon örnekleri” başlangıçta kapalıdır; bölümler kapanınca servisler, süren işlem ve cevaplar sıfırlanmaz. Debug görünürlüğü yetkilendirme değildir. Yeni grafın hazır D01 videolarına bağlı olduğu iddia edilmez.
- **Güncel katalog:** Ana panel ve mevcut ayrıntı ekranı `BehaviorCards` üzerinden sürüm 0.2'nin D01–D10 kartlarını gösterir. Eski ONT şablon kimlikleri, kayıtlar ve video eşlemeleri yeniden etiketlenmedi. Güncel kart yolunda eski risk/norm/ölçülmemiş başarı yüzdeleri yoktur. D01 debug demosu sabit 30 aylık Deniz kapsamını korur; D02–D10 için üretim/video düğmesi eklenmedi. Kaynak ve sınırlar: [güncel katalog notu](davranis_katalogu_v02.md).
- **Ayrıntı düzeni:** Amaç, Hazırlık ve Yapılacak işlem açıktır. Tam gözlem koşulları ve dört sonuç durumu “Ayrıntılı gözlem kuralları”nda; kaynak/sürüm ve pilot bilgileri “Teknik bilgiler”dedir. İkisi başlangıçta kapalıdır. Pilot pencereleri ve sınırları korunur; klinik eşik değildir. D01 girişi uzun ayrıntılardan önce gelir.
- **Hedefli test kaynakları:** `scenario_model_demo_test.dart`, `video_analysis_source_test.dart`, `studio_sections_test.dart`, `behavior_cards_test.dart`, `widget_test.dart` ve etkilenen mevcut gezinme/şablon testleri güncellendi. Kontrollü model/video bağımlılıkları gerçek çıkarım veya cihaz doğrulaması sayılmaz.

## Kanıt ve kontrol durumu — kaynaklar ayrı

- **Asistanın bu turdaki kontrolleri:** Kaynak değişiklikleri, talimat dosyalarının bulunma durumu, dal/origin, çalışma ağacı ve stash incelendi. Yeni Flutter testi, statik analiz, uygulama, çıkarım, indirme veya derleme başlatılmadı. Bugünkü son kodun testlerinin geçtiği veya analizinin temiz olduğu burada doğrulanmadı. Git diff/whitespace denetimi Flutter testi veya statik analiz yerine geçmez.
- **Kullanıcının paylaştığı test/analiz bilgisi:** `studio_sections_test.dart` için `DropdownButtonFormField<LocalModelOption>` nesnesinin yanlışlıkla `DropdownButton<LocalModelOption>` olarak okunduğu tür hatası bildirildi. Testte gerçek `FormFieldState<LocalModelOption>.value` üzerinden seçim denetimi yapılarak düzeltildi; beklentiler korunuyor. Bu düzeltmeden ve son katalog/açılır bölüm değişikliklerinden sonra kullanıcıdan geçen test sayısı veya temiz analiz çıktısı paylaşılmadı. Önceki eksik asset uyarılarıyla test/derlemelerin tamamlandığı bildirimi, bugünkü değişikliklerin geçtiğine kanıt değildir.
- **Kullanıcının emülatör gözlemleri (önceki aşama):** Modelden senaryo → graf demosu; video bağlama, yeniden açılışta eşlemenin korunması, önizleme ve A/B yollarının tamamlanması bildirildi. Aynı video farklı kliplerde kullanıldığı için içerik/süreklilik doğrulanmadı. Ekran kapanınca model cevabının kaybı da kullanıcı tarafından yaşandı; F04 yalnız kazara çıkış onayı ekler. Bugünkü katalog, bölüm düzeni ve F04/F05 için yeni emülatör doğrulaması bu kapanış turunda yapılmadı.
- **Kayıt temelli kanıt:** Model çıktılarıyla ilgili sonuçların kaynağı aşağıdaki önceki aşama özeti ve [kayıt raporu](model_degerlendirme_kanitlari.md)'dur. Yeni ölçüm veya ham kayıt eklenmedi.

## Açık işler

- Yeni grafın kendi klip planına/promptlarına ve video eşlemelerine bağlanması; sabit D01 hattı bunun yerine geçmez.
- Kalıcı taslak kaydı/kurtarma; ayrıca örnek yükleme ve yeni üretimin mevcut taslağı ezmesine karşı koruma.
- D02–D10 için üretim/video desteği.
- Eski ONT-08 şablonunun yanlış ce-e akışına gitmesi.
- Kalan eski video raporu/metinleri ve sekme ses davranışı.
- Teknik demo ekranının sadeleştirilmesi.
- Son değişikliklerin hedefli test ve statik analiz sonuçlarının doğrulanması; gerçek telefon (Galaxy M21 dahil) ve iOS/iPhone 11 doğrulaması.

İnceleme dayanağı [18 Ekim kapsamlı raporu](uygulama_kapsamli_inceleme_2026-10-18.md)'dur; bu tarihsel rapor bugünkü değişikliklerle yeniden yazılmadı. Stash, ham değerlendirmeler, modeller, videolar ve cihaz eşlemeleri korunur.

## Önceki aşamadan korunan durum — 18 Ekim

- **Emülatör denemesi (kullanıcı bildirimi):** Video bağlama, uygulama yeniden açıldığında eşlemenin korunması, tek klip önizlemesi ve grafın A/B yollarının tamamlanması denendi. Aynı test videosu farklı kliplerde kullanıldı; video içeriği, gerçek süreler ve klipler arası süreklilik doğrulanmadı.
- **D01 grafı ve üretim planı elle hazırlanmış örnektir.** Beş sahne, iki alternatif yol ve hedef süreleri en fazla 8 saniye olan yedi klip vardır. Ortak oyun çağrıdan önce biter; iki alternatifin ilk klibi çağrı ile ilgili devamı birlikte planlar. Her izlenen yolda tek çağrı hedeflenir. Devam klipleri çağrıyı tekrarlamaz; çağrı sonrası gözlem süresi gerçek videodan ayrıca doğrulanmalıdır.
- **Geliştirici üretim alanı yalnız debug derlemelerinde görünür; bu yetkilendirme değildir.** Prompt kopyalama, kalıcı yerel video eşleme, önizleme ve kullanıcı seçimli graf denemesi bu alandadır. Video bağlamak veya oynatmak davranışın gerçekleştiğine dair kanıt değildir; eşleme kayıtları cihazda kalır.
- **Modelden senaryo → graf demosu emülatörde gösterildi (kullanıcı bildirimi).** Ortak içe aktarma alanında mevcut Qwen'den alınan içerik, uygulamanın sağladığı metadata ile `ScenarioInput` üzerinden mevcut dönüştürücüye ve graf görüntüleyicisine aktarılır. Ham cevap korunur; yalnız tüm cevabı çevreleyen JSON çiti ve tek `scenarioInput` sarmalayıcısı açıkça belirtilen biçim normalizasyonuyla açılır. Eksik anlatı tamamlanmaz ve otomatik yeniden çıkarım yapılmaz. Kullanıcının düzenlediği taslak ayrı kaynakla etiketlenir. Yapısal dönüşüm, senaryo içeriğinin doğru veya D01'e uygun olduğunu kanıtlamaz.
- **Yeni grafın klip planı/video bağlantısı henüz yok.** Senaryo içeriği ve hazır graf içe aktarma oturum içinde çalışır; sabit D01 klip planı ile mevcut video eşlemeleri ayrı akıştır. Mevcut Senaryo Üret yolu hâlâ şablon kullanır ve artık bunu açıkça belirtir. Video Analiz ekranı seçilen videoya sabit örnek bulguları sonuç olarak taşımaz; ölçülmemiş başarı/güven yüzdeleri kaldırılmıştır. Video analizi ayrı çalışma hattıdır.
- **Kayıt temelli model değerlendirmesi:** Qwen ve MiniCPM için aynı üç görev × iki tekrara ait altışar ham kayıt raporlandı; ham dosyalar değiştirilmedi veya Git'e eklenmedi. Bu örnek grubunda içerik/yönerge ihlalleri görüldü; sonuç genel model yeteneğine genellenmez. Llama'nın önceki emülatör çıkarımı ve TR/EN denemeleri kullanıcı bildirimlerinde yer alır; tam istem/cevap/ölçüm içeren ham kayıt bulunamadığından aynı protokolde nicel kıyas yapılmadı. RAM/tepe bellek ölçümü bu değerlendirme kayıtlarında yok. Kaynaklar ve sınırlamalar: [model değerlendirme kanıtları](model_degerlendirme_kanitlari.md).

## Kontrol durumu

Bu commit hazırlığında yeni test, model indirme veya çıkarım başlatılmadı. Emülatör gözlemleri kullanıcı bildirimidir; tüm otomatik testlerin geçtiği anlamına gelmez. Girdi/dönüştürücü, ortak ekran, demo/normalizasyon, kısa dal etiketleri ve kaynak gösterimleri için hedefli testler hazırlanmıştır; son değişikliklerin Flutter testleri ve statik analizinin temiz sonucu **burada doğrulanmadı**. Çalıştırılacak komutlar [senaryo sözleşmesinde](scenario_input_contract.md) ve ilgili çalışma notlarında bulunur. M21 ve iPhone 11 üzerinde doğrulama yapılmadı.

İlgili önceki raporlar: [değerlendirme akışı](d01_degerlendirme.md), [önceki tekli test istemi](qwen_ortak_baslangic_onceki_istem.md), [prompt incelemesi](d01_prompt_karsilastirmasi.md). Bu raporlardaki durum ve kontrol ifadeleri yazıldıkları aşamaya aittir; güncel durum için bu not esas alınır.
