# Devam notu — 17 Ekim 2026

- **Emülatör denemesi (kullanıcı bildirimi):** Video bağlama, uygulama yeniden açıldığında eşlemenin korunması, tek klip önizlemesi ve grafın A/B yollarının tamamlanması denendi. Aynı test videosu farklı kliplerde kullanıldı; video içeriği, gerçek süreler ve klipler arası süreklilik doğrulanmadı.
- **D01 grafı ve üretim planı elle hazırlanmış örnektir.** Beş sahne, iki alternatif yol ve hedef süreleri en fazla 8 saniye olan yedi klip vardır. Ortak oyun çağrıdan önce biter; iki alternatifin ilk klibi çağrı ile ilgili devamı birlikte planlar. Her izlenen yolda tek çağrı hedeflenir. Devam klipleri çağrıyı tekrarlamaz; çağrı sonrası gözlem süresi gerçek videodan ayrıca doğrulanmalıdır.
- **Geliştirici üretim alanı yalnız debug derlemelerinde görünür; bu yetkilendirme değildir.** Prompt kopyalama, kalıcı yerel video eşleme, önizleme ve kullanıcı seçimli graf denemesi bu alandadır. Video bağlamak veya oynatmak davranışın gerçekleştiğine dair kanıt değildir; eşleme kayıtları cihazda kalır.
- **LLM'den graf üretimi bağlı değil.** Graf elle hazırlanmış asset'i kullanır; mevcut Senaryo Üret akışı hâlâ şablon kullanır. Video analizi ayrı çalışma hattıdır; klinik sonuç veya otomatik onay üretilmez.
- **MiniCPM karşılaştırma entegrasyonu eklendi; gerçek çıkarımı henüz doğrulanmadı.** Model ayrı dosya/seçenek olarak tanımlıdır; indirme yalnız kullanıcı işlemiyle başlar. Sabit üç görev × iki deneme seçilen Qwen/MiniCPM modeliyle yürütülebilir; modelin kendi GGUF şablonu kullanılır. Qwen'e özgü boş think bloğu kontrolü MiniCPM'ye uygulanmaz.
- **Önceki gerçek model sonuçları:** Llama emülatörde çıkarım yaptı; Türkçe D01 cevapları yetersiz, İngilizce daha anlaşılır ancak kurallara tam uymuyor. Qwen'in altı gerçek denemesinde kritik koşulları eksiksiz sağlayan örnek bulunmadı; bu sonuç genel model başarısına genellenmez. Ham değerlendirme kayıtları değiştirilmedi. Kaynakları ayrılmış inceleme: [Qwen değerlendirme notu](d01_run_20261017T141026879605_IYDFAB_degerlendirme.md).

## Kontrol durumu

Bu commit hazırlığında yeni test, model indirme veya çıkarım başlatılmadı. Emülatör gözlemleri kullanıcı bildirimidir; tüm otomatik testlerin geçtiği anlamına gelmez. Son graf statik analizinin temiz sonucu **henüz doğrulanmadı**; önceki aşamalardaki test/analiz sonuçları son değişikliklerin sonucu olarak sunulmuyor. M21 ve iPhone 11 üzerinde doğrulama yapılmadı.

İlgili önceki raporlar: [değerlendirme akışı](d01_degerlendirme.md), [önceki tekli test istemi](qwen_ortak_baslangic_onceki_istem.md), [prompt incelemesi](d01_prompt_karsilastirmasi.md). Bu raporlardaki durum ve kontrol ifadeleri yazıldıkları aşamaya aittir; güncel durum için bu not esas alınır.
