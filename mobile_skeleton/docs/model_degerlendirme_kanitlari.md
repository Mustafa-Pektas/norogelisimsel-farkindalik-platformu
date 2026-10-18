# Yerel dil modelleri — kayıt temelli D01 değerlendirme kanıtları

İnceleme tarihi: **18 Ekim 2026**. Bu rapor yeni çıkarım, indirme veya test çalıştırmadan hazırlanmıştır. Kod ve ham kayıtlar değiştirilmemiştir.

## 1. Üç modelin kayıt ve karşılaştırılabilirlik özeti

**Birincil kanıt:** Erişilebilir Android emülatöründeki iki çalışmada toplam **12 ayrı ham deneme JSON’u** bulundu: Qwen için 6, MiniCPM için 6. Her çalışmada ayrıca 1 protokol ve 1 çalışma özeti var; bu 4 yardımcı dosya yeni deneme olarak sayılmadı. Llama için tam istem + tam ham cevap + deneme ölçümleri içeren birincil kayıt bulunamadı.

| Model | Bulunan ayrı ham deneme kaydı | Kaynak / kayıtlı kimlik | Karşılaştırılabilirlik |
| --- | ---: | --- | --- |
| Llama 3.2 1B Instruct, Q4_K_M GGUF | 0 | Kodda beklenen dosya `Llama-3.2-1B-Instruct-Q4_K_M.gguf`, model seçeneği `bartowski/Llama-3.2-1B-Instruct-GGUF`. Bunlar bulunamayan denemenin kimliğini bağımsız doğrulamaz. İkincil notlar aşağıda listelenmiştir. | **Kayıt bulunamadı / nicel değerlendirme yapılamadı.** Ön denemeler bu altı görevli protokolün sonuçlarına katılmadı. |
| Qwen3-1.7B Q4_K_M GGUF | 6 | `unsloth/Qwen3-1.7B-GGUF`; dosya `Qwen3-1.7B-Q4_K_M.gguf`; run `run_20261017T141026879605_IYDFAB` | Aynı üç Türkçe görev × iki tekrar. |
| MiniCPM5-1B-Turkish Q4_K_M GGUF | 6 | `thealper2/MiniCPM5-1B-Turkish`; dosya `MiniCPM5-1B-Turkish-Q4_K_M.gguf`; run `run_20261018T140902271445_HRDPKP` | Qwen ile tam istem, görev sırası ve kaydedilmiş ayarlar eşleşiyor. |

Model adları Qwen/MiniCPM kayıtlarındaki `model_id`, `model_file` ve GGUF tanı bilgileri birlikte okunarak belirtilmiştir. Qwen GGUF adı `Qwen3-1.7B`, mimarisi `qwen3`; MiniCPM GGUF adı `Final_Model`, mimarisi `llama`. Özellikle genel `Final_Model` adı tek başına model ailesini doğrulamaz. Ağırlık SHA256’sı bu deneme kayıtlarında yoktur; rapor için ağırlıklar yüklenmedi veya hash’lenmedi.

### Kaynağın bulunduğu yer

- Erişilen cihaz: `emulator-5554`; ADB kimliği `sdk_gphone16k_x86_64`.
- Paket: `com.neuroapp.neuro_awareness_app`.
- Ortak Android belge yolu: `/data/user/0/com.neuroapp.neuro_awareness_app/app_flutter/evaluations/d01_qwen/`.
- **MiniCPM kaydı da dizin adında “d01_qwen” geçen bu kökün altında.** Model kimliği klasör adından değil JSON alanlarından doğrulandı.
- Proje içinde yapılan ham kayıt içerik/dosya aramasında ayrıca gerçek Llama/Qwen/MiniCPM deneme JSON’u bulunmadı. Test fixture’ları ve kontrollü test cevapları gerçek model cevabı olarak sayılmadı.
- Arama proje kökü ve erişilebilir alt dizinleri ile bu uygulamanın erişilebilir JSON/TXT/LOG dosyalarını kapsadı; model ağırlıkları, SDK/build/cache/sanal ortam içerikleri kanıt arşivi olarak taranmadı. Proje kökündeki `d01_check_7923qsi4` için erişim reddedildi. Bu nedenle “bulunamadı”, yalnız incelenebilen kaynakların sonucudur; hiçbir yerde kayıt olmadığı iddiası değildir.
- Ham dosyalar ADB `run-as ... cat` ile yalnız okunup bellekte incelendi; projeye ayrı ham kayıt kopyası çıkarılmadı ve Git’e stage edilmedi.

### Eşleşen protokol ve ayarlar

İki `protocol.json` dosyasındaki protokol kimliği `d01_qwen_scene_eval_v1`; görev metinleri ve sıra birebir aynı. On iki denemenin her birindeki `prompt`, model kimliği ve `settings` alanları kendi protokolüyle karşılaştırıldı ve eşleşti. Kayıt kaynağı her denemede `llamadart_native`.

| Ayar | İki çalışmada kayıtlı değer |
| --- | --- |
| Cihaz / GPU katmanları | CPU / 0 |
| Bağlam / en fazla yeni token | 2048 / 160 |
| Düşünme modu | `enable_thinking=false` |
| Örnekleme | temperature 0.7, top-P 0.8, top-K 20, min-P 0, repeat penalty 1.0, presence penalty 0 |
| Seed | `null`; raporlanan örnekleme “belirtilmedi (native zaman tabanlı)” diyor. Gerçek seed kayıtlı değil. |
| İş parçacığı / batch iş parçacığı | 2 / 2 |
| Batch / micro-batch | 64 / 64 |
| Prompt prefix ayarı | `reuse_prompt_prefix=true` |
| Paket | `llamadart 0.12.0` |
| Önceki konuşma | Kayıtlı render önizlemelerinde yalnız ilgili tek user mesajı ve assistant başlangıcı var. Kayıt servisi her denemeye yeni servis/motor oluşturuyor. |

Bu, aynı kullanıcı istemi ve kaydedilmiş üretim ayarlarıyla yapılmış **iki küçük emülatör çalışmasının** karşılaştırmasıdır. Tokenizer ve modele özgü sohbet şablonu farklıdır; dolayısıyla son prompt baytları ve istek token sayıları eşit değildir. Gerçek seed, cihaz yükü ve bellek koşulları sabitlenip kaydedilmedi. Model ağırlığının tek başına bütün farkların nedeni olduğu söylenemez.

## 2. Deneme bazında bulgu tablosu

Aşağıdaki istemler her denemenin kendi `prompt` alanından; süre, token ve bitişler kendi JSON alanlarından alınmıştır. Alıntılar ilgili `raw_response` içinde birebir bulunur. Her satırın tam cevabı 3. bölümde kesilmeden yer alır. Kısa model adları ilk tablodaki depo/dosya kimliklerine karşılık gelir.

**Değerlendirme kaynağı:** Bu rapordaki içerik açıklamaları asistanın ham metinleri doğrudan okuyarak yaptığı sınırlı incelemedir; kullanıcı tarafından doldurulmuş puanlar değildir. On iki kaydın beş `human_evaluation` alanı da `null`, iki özetin `semantic_verdict` alanı da `null` kalmıştır. Önceki kullanıcı yorumları değerlendirme yerine kopyalanmamış, ham metinden yeniden kontrol edilmiştir.

| Tam model adı | Görev / deneme kimliği | Gerçek istem | Toplam / üretim (s) | İstek / çıktı / önbellek tokenı | Bitiş / çalışma hatası | Karşılanmayan koşul | Birebir ham alıntı |
| --- | --- | --- | ---: | ---: | --- | --- | --- |
| Qwen3-1.7B Q4_K_M GGUF | `common_start` / `common_start_1` | Bir çocuk videosunun yalnızca başlangıç sahnesini Türkçe, 2–3 kısa cümleyle yaz. Deniz 30 aylıktır. Evde oyuncakla oynarken annesine bakmaz. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez ‘Deniz’ der. Sahneyi bu çağrının hemen ardından bitir; çocuğun tepkisini anlatma. Yalnızca sahne metni yaz; başlık, JSON ve açıklama ekleme. | 80.381698 / 76.340015 | 141 / 160 / 0 | `length`; `execution_status=completed`; `error=null` | Çocuk tepkisini anlatmama ve yalnız sahne metni yazma koşulları ihlal edildi. JSON ve başlık eklendi; çıktı ayrıca kesik. | `Sahne, çocuğun şaşkınlık ve korku duymasını gösterir.` |
| Qwen3-1.7B Q4_K_M GGUF | `common_start` / `common_start_2` | Bir çocuk videosunun yalnızca başlangıç sahnesini Türkçe, 2–3 kısa cümleyle yaz. Deniz 30 aylıktır. Evde oyuncakla oynarken annesine bakmaz. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez ‘Deniz’ der. Sahneyi bu çağrının hemen ardından bitir; çocuğun tepkisini anlatma. Yalnızca sahne metni yaz; başlık, JSON ve açıklama ekleme. | 62.787148 / 62.024284 | 141 / 135 / 0 | `stop`; `execution_status=completed`; `error=null` | Çağrı sonrasında çocuk tepkisi ve annenin korkusu ekleniyor; aynı ifade tekrarlanıyor. JSON/başlık yasağı ihlal. | `gözlerini kırpmadan, gözlerini kırpmadan` |
| Qwen3-1.7B Q4_K_M GGUF | `turn_to_mother` / `turn_to_mother_1` | Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz başını annesine çevirir. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme. | 56.815004 / 55.327175 | 151 / 114 / 0 | `stop`; `execution_status=completed`; `error=null` | Yeni isim çağrısı ekleniyor; yalnız devam sahnesi yerine başlık ve açıklamalı JSON veriliyor. | `Kuyruklu bir sesle 'Deniz' diye bir kez seslenir.` |
| Qwen3-1.7B Q4_K_M GGUF | `turn_to_mother` / `turn_to_mother_2` | Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz başını annesine çevirir. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme. | 52.386821 / 50.802949 | 151 / 100 / 0 | `stop`; `execution_status=completed`; `error=null` | Dokunma ve ek konuşma ekleniyor; anlatı açıklama alanında yineleniyor. JSON/başlık yasağı ihlal. | `Ayağına bir kere dokunur. Sesini doğal bir şekilde 'Deniz' der.` |
| Qwen3-1.7B Q4_K_M GGUF | `continue_playing` / `continue_playing_1` | Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz annesine dönmeden oyununa devam eder. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme. | 67.344709 / 66.233579 | 157 / 150 / 0 | `stop`; `execution_status=completed`; `error=null` | Dokunulma durumu ve ek konuşma ekleniyor; yalnız devam yerine açıklamalı JSON veriliyor. | `Dokunulduğunda doğal sesle 'Deniz' dedi.` |
| Qwen3-1.7B Q4_K_M GGUF | `continue_playing` / `continue_playing_2` | Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz annesine dönmeden oyununa devam eder. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme. | 81.426862 / 80.533955 | 157 / 153 / 0 | `stop`; `execution_status=completed`; `error=null` | Dokunulma ve ek ses/konuşma ekleniyor; başlangıç yeniden anlatılıyor. JSON/başlık/açıklama yasağı ihlal. | `Dokunulduğunda doğal sesle 'Deniz' der.` |
| MiniCPM5-1B-Turkish Q4_K_M GGUF | `common_start` / `common_start_1` | Bir çocuk videosunun yalnızca başlangıç sahnesini Türkçe, 2–3 kısa cümleyle yaz. Deniz 30 aylıktır. Evde oyuncakla oynarken annesine bakmaz. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez ‘Deniz’ der. Sahneyi bu çağrının hemen ardından bitir; çocuğun tepkisini anlatma. Yalnızca sahne metni yaz; başlık, JSON ve açıklama ekleme. | 27.190695 / 24.102239 | 180 / 53 / 0 | `stop`; `execution_status=completed`; `error=null` | Oyun, anneye bakmama ve annenin tek çağrısı anlatılmıyor. Sahne yerine yönerge, başlık ve açıklama veriliyor. | `Yalnızca bir sahne metni yaz: 'Deniz' birçocuk video sonu.` |
| MiniCPM5-1B-Turkish Q4_K_M GGUF | `common_start` / `common_start_2` | Bir çocuk videosunun yalnızca başlangıç sahnesini Türkçe, 2–3 kısa cümleyle yaz. Deniz 30 aylıktır. Evde oyuncakla oynarken annesine bakmaz. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez ‘Deniz’ der. Sahneyi bu çağrının hemen ardından bitir; çocuğun tepkisini anlatma. Yalnızca sahne metni yaz; başlık, JSON ve açıklama ekleme. | 24.702159 / 23.394959 | 180 / 67 / 0 | `stop`; `execution_status=completed`; `error=null` | İstenen başlangıç olayları yok; istem parçası ve bağlam dışı tekrar sahnenin yerini alıyor. | `Döngüyü, döngüyü, döngüyü, sıkından çok döngüyü, döngüyü.` |
| MiniCPM5-1B-Turkish Q4_K_M GGUF | `turn_to_mother` / `turn_to_mother_1` | Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz başını annesine çevirir. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme. | 38.342695 / 37.073060 | 200 / 160 / 0 | `length`; `execution_status=completed`; `error=null` | Başlangıç ve istem yönergeleri kopyalanıyor; yalnız devam sahnesi koşulu karşılanmıyor. Çıktı kesik. | `Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme.` |
| MiniCPM5-1B-Turkish Q4_K_M GGUF | `turn_to_mother` / `turn_to_mother_2` | Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz başını annesine çevirir. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme. | 39.150908 / 37.451498 | 200 / 160 / 0 | `length`; `execution_status=completed`; `error=null` | Başlık ve talimat listesi tekrar ediliyor; sahne anlatımı/biçim koşulları ihlal. Çıktı kesik. | `Başlık: Deniz Başıntılık. Yeni çağrı: Deniz, annesine, dokunma, işaret, başka uyaran ekle.` |
| MiniCPM5-1B-Turkish Q4_K_M GGUF | `continue_playing` / `continue_playing_1` | Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz annesine dönmeden oyununa devam eder. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme. | 37.634176 / 36.212768 | 203 / 160 / 0 | `length`; `execution_status=completed`; `error=null` | Başlangıç ve yazım yönergeleri yeniden veriliyor; anlaşılır devam sahnesi kurulmuyor. Çıktı kesik. | `Yalnızca, dokunma, işaret veya başka uyaran eklenmiş, tüm yalnızca devam eder.` |
| MiniCPM5-1B-Turkish Q4_K_M GGUF | `continue_playing` / `continue_playing_2` | Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz annesine dönmeden oyununa devam eder. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme. | 39.269580 / 38.400430 | 203 / 160 / 0 | `length`; `execution_status=completed`; `error=null` | Ortak başlangıç ve istem yönergeleri kopyalanıyor; yalnız devam koşulu ihlal. Çıktı kesik. | `Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz:` |
| Llama 3.2 1B Instruct, Q4_K_M GGUF — kodda beklenen seçenek | Görev/deneme kimliği bulunamadı | Kayıt bulunamadı; gerçek deneme istemi yeniden oluşturulmadı. | Ölçüm yok | Ölçüm yok | Kayıt bulunamadı | Nicel veya doğrudan deneme değerlendirmesi yapılamadı. | Ham cevap kaydı bulunamadı. |

### İhlal türleri ayrı ayrı

| Tür | Qwen’in bu altı kaydı | MiniCPM’nin bu altı kaydı | Llama |
| --- | --- | --- | --- |
| Yönerge / biçim ihlali | Altı cevabın tamamı JSON/başlık alanları içeriyor; istem açıkça bunları yasaklıyor. Ayrıca istenmeyen tepki/çağrı/konuşma/dokunulma anlatımları var. | Başlık/açıklama, istem kopyalama veya yönerge benzeri listeler var. **MiniCPM’nin bu cevapları JSON değildir**; sorun Qwen’in JSON ihlaliyle aynı ad altında gösterilmedi. | Ham kayıt yok. |
| Tekrar / anlamsal bozulma | Özellikle `common_start_2` içindeki yinelenen sözler ve bazı devam cevaplarındaki bozuk özne/ifadeler. Bu altı cevabın tamamına aynı düzeyde “anlamsız” etiketi atanmadı. | `common_start_2` içindeki “döngüyü” tekrarı; `turn_to_mother_2` başlık/liste tekrarı; diğerlerinde yönerge kopyalama ve bağlamı bozuk metin. | Ham kayıt yok. |
| Token sınırına ulaşma / kesilme | 1 kayıt: `common_start_1`, `length`, 160 çıktı tokenı. | 4 kayıt: iki `turn_to_mother` ve iki `continue_playing`, `length`, her biri 160 çıktı tokenı. | Token/bitiş kaydı yok. |
| Teknik çalışma hatası | Bu altı kayıtta `error=null`, durum `completed`; çalışma özeti de hata içermiyor. | Bu altı kayıtta `error=null`, durum `completed`; çalışma özeti de hata içermiyor. | Çalışma hatasını doğrulayacak birincil kayıt yok. |

`completed` ve `stop` yalnız teknik bitiş bilgisidir; talimata uyma veya anlamsal başarı değildir. `length` kayıtlarında 160 token sınırına gerçekten ulaşılmış ve metin gözle görülür biçimde kesiktir. API’nin `length` etiketi tek başına bütün native durdurma nedenlerini ayırmaz. Buna karşılık MiniCPM’nin iki başlangıç cevabı `stop` ile bitmiştir; onların bozuk içeriği token sınırına dayanılarak açıklanamaz.

**Bu kayıt grubunda kritik koşulların tümünü eksiksiz karşıladığı gösterilebilen cevap yok.** Bu, genel bir model başarı oranı veya bütün görevlerde başarısızlık iddiası değildir. Otomatik anahtar kelime puanı, klinik sonuç veya modelin kendi başarı beyanına dayalı karar üretilmedi. Belirsiz aktör/eylem yorumları aşağıda açıkça ayrıldı.

### Aynı protokolde süre ve token karşılaştırması

Toplam süre `elapsed_s`, üretim süresi `generation_s` alanlarından hesaplandı; önceki konuşmadan sayı alınmadı.

| Model | Deneme | Toplam sürelerin toplamı (s) | Ortalama toplam (s) | Üretim sürelerinin toplamı (s) | Ortalama üretim (s) | İstek / çıktı tokenı toplamı | length / stop |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Qwen3-1.7B Q4_K_M GGUF | 6 | 401.142242 | 66.857 | 391.261957 | 65.210 | 898 / 812 | 1 / 5 |
| MiniCPM5-1B-Turkish Q4_K_M GGUF | 6 | 206.290213 | 34.382 | 196.634954 | 32.772 | 1166 / 760 | 4 / 2 |
| Llama | 0 erişilebilir ham kayıt | Hesaplanmadı | Hesaplanmadı | Hesaplanmadı | Hesaplanmadı | Bilinmiyor | Bilinmiyor |

Ortalama süreler 3 ondalığa yuvarlandı; tek denemelerin kayıtlı süreleri tabloda 6 ondalıkla gösterildi.

| Görev (iki tekrarın ortalaması) | Qwen toplam / üretim (s) | MiniCPM toplam / üretim (s) |
| --- | ---: | ---: |
| `common_start` | 71.584 / 69.182 | 25.946 / 23.749 |
| `turn_to_mother` | 54.601 / 53.065 | 38.747 / 37.262 |
| `continue_playing` | 74.386 / 73.384 | 38.452 / 37.307 |

Bu iki çalışmada MiniCPM’nin gözlenen süreleri daha kısa. Bu, kaliteli sahne ürettiği, M21’de daha iyi çalışacağı veya aynı uzunlukta içeriği daha hızlı ürettiği anlamına gelmez: çıktı uzunlukları, bitişler ve tokenizasyon farklıdır; içerik koşulları karşılanmamıştır. Önceki Llama tekli/ön denemeleri bu tabloya eklenmedi.

## 3. Gerçek istemler ve tam ham cevaplar

Aşağıdaki bloklar kayıtlı `raw_response` alanlarının tamamıdır; yazım hataları, tekrarlar, kesik sözcükler ve görünmeyen karakterler temizlenmedi. Sonu kesik cevaplar tamamlanmadı. Aynı görevdeki iki istem kendi kayıtlarından birebir eşleştiği için görev başında tek kez tam metinle gösterildi.

### 3.1 Llama — kayıt eksikliği ve dil ayrımı

**Kayıt bulunamadı / nicel değerlendirme yapılamadı.** Llama için tam ham cevap veya önceki denemenin gerçek istemi elde edilemedi; cevap örneği uydurulmadı.

- Türkçe merhaba ve Türkçe D01 ön denemelerine ilişkin ikincil anlatımlar var: `docs/d01_senaryo_testi.md`, `docs/d01_cikarim_incelemesi.md`.
- İngilizce karşılaştırma ayrı bir istek yolu olarak `docs/d01_prompt_karsilastirmasi.md` içinde tanımlı; `docs/DEVAM_NOTU.md` İngilizce denemenin daha anlaşılır ama kurallara tam uymadığını kullanıcı gözlemi olarak özetliyor. **Tam İngilizce cevap kaydı yok.**
- `docs/yerel_model_testi.md` merhaba yapılandırmasını (512 bağlam / 32 çıktı üst sınırı), D01 belgeleri ise 2048 / 384 yapılandırmasını anlatıyor. Bunlar aynı protokol değildir; üst sınırlar gerçek token tüketimi değildir. Bu belgelerden eski cevap, süre, bitiş veya başarı oranı türetilmedi.
- Bugünkü kodda bulunan istem sabiti, geçmişteki belirli bir denemeye gerçekten gönderilen istemin birincil kaydı yerine konmadı. İkincil notların kullanıcıdan aktardığı süreler burada ölçüm tablosuna taşınmadı.
- `test/fixtures/llama32_device_template.json` yalnız sohbet şablonu/BOS/EOS fixture’ıdır; Llama cevap kaydı değildir.

Llama için Türkçe–İngilizce kalite karşılaştırması **ham kanıt yetersizliği nedeniyle belirsizdir**; altı görevli Türkçe Qwen/MiniCPM karşılaştırmasının parçası değildir.

### 3.2 Qwen3-1.7B Q4_K_M GGUF

Run: `run_20261017T141026879605_IYDFAB`. Kaynak model: `unsloth/Qwen3-1.7B-GGUF`; dosya: `Qwen3-1.7B-Q4_K_M.gguf`. Bu bölümdeki altı kayıt **Türkçe** protokole aittir; İngilizce deneme kaydı değildir.

#### Ortak başlangıç — gerçek istem

````text
Bir çocuk videosunun yalnızca başlangıç sahnesini Türkçe, 2–3 kısa cümleyle yaz. Deniz 30 aylıktır. Evde oyuncakla oynarken annesine bakmaz. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez ‘Deniz’ der. Sahneyi bu çağrının hemen ardından bitir; çocuğun tepkisini anlatma. Yalnızca sahne metni yaz; başlık, JSON ve açıklama ekleme.
````

##### `common_start_1` — tam ham cevap

Kaynak: `run_20261017T141026879605_IYDFAB/common_start_1.json`. Başlangıç/bitiş (UTC): `2026-10-17T14:10:27.096635Z` → `2026-10-17T14:11:47.489305Z`.

````text
{
  "title": "Deniz'in Başlangıç Sahnesi",
  "description": "Deniz 30 aylık. Evde oyuncakla oynarken annesine bakmaz. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez 'Deniz' der. Sahne, çocuğun şaşkınlık ve korku duymasını gösterir.",
  "scene": "Deniz, evde oyuncakla oynarken annesine bakmaz. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez 'Deniz' der. Çocuk, şaşk
````

**Somut uyuşmazlık:** İstenen son nokta annenin çağrısının hemen sonrasıdır. Çocuğa şaşkınlık/korku tepkisi yükleniyor. Başlık/description/scene alanları yasaklanan JSON biçimidir. Son “şaşk” sözcüğü ve kapanmayan nesne, kayıtlı length/160 token ile birlikte kesilmeyi gösterir.

**Belirsizliği korunan yorum:** Metnin kesildiği kesin; son sözcüğün neye tamamlanacağı belirsiz.

##### `common_start_2` — tam ham cevap

Kaynak: `run_20261017T141026879605_IYDFAB/common_start_2.json`. Başlangıç/bitiş (UTC): `2026-10-17T14:11:47.502753Z` → `2026-10-17T14:12:50.353179Z`.

````text
{
  "title": "Deniz'in Başlangıç Sahnesi",
  "sahne_metni": "Deniz, evde oyuncakla oynarken annesine bakmaz. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez 'Deniz' der. Çocuk, bir kez daha gözlerini kırpmadan, gözlerini kırpmadan kendi kendine öyle bir şekilde baktı ki, annesi de onu görünce korkudan kendi kendine öyle bir şekilde baktı."
}
````

**Somut uyuşmazlık:** Çocuk için çağrı sonrası bakış anlatılıyor; ardından annenin korkusu ekleniyor. “gözlerini kırpmadan” art arda yineleniyor. Bu, çağrıdan hemen sonra tepki anlatmadan biten sahne değildir. JSON başlığı ve tek uzun sahne_metni alanı da biçim koşulunu karşılamıyor.

**Belirsizliği korunan yorum:** Korku annesine atfediliyor; bunu çocuğun korkusu diye yeniden yorumlamadık. Bakışın hedefi ve bazı bağlaçların anlamı belirsiz.

#### Yönelme alternatifi — gerçek istem

````text
Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz başını annesine çevirir. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme.
````

##### `turn_to_mother_1` — tam ham cevap

Kaynak: `run_20261017T141026879605_IYDFAB/turn_to_mother_1.json`. Başlangıç/bitiş (UTC): `2026-10-17T14:12:50.365302Z` → `2026-10-17T14:13:47.262795Z`.

````text
{
  "başlık": "Deniz'in Gözü",
  "metin": "Deniz başını annesine çevirir. Kuyruklu bir sesle 'Deniz' diye bir kez seslenir. Anneciğin dokunmadan ve işaret etmeden doğal sesle bir kez 'Deniz' der.",
  "açıklama": "Yeni çağrı, dokunma ve doğal ses eklendi. Metin, olayı ilerletecek şekilde anlatır."
}
````

**Somut uyuşmazlık:** İlk cümle istenen baş yöneltmeyi içeriyor. Sonraki cümlede yeni seslenme, ardından anneden bir başka “Deniz” çağrısı var. İstemdeki başlangıcın tek çağrısına yeni konuşmalar eklenmiş. Modelin açıklama alanında kendi çıktısı hakkında yazdığı iddialar değerlendirme kanıtı olarak kullanılmadı.

**Belirsizliği korunan yorum:** “Kuyruklu bir ses” ifadesi bağlamda bozuk/olağandışı; ilk ek seslenmenin öznesi belirsiz. Somut ihlal, yeni seslenme metninin bulunmasıdır.

##### `turn_to_mother_2` — tam ham cevap

Kaynak: `run_20261017T141026879605_IYDFAB/turn_to_mother_2.json`. Başlangıç/bitiş (UTC): `2026-10-17T14:13:47.292019Z` → `2026-10-17T14:14:39.755010Z`.

````text
{"baslik": "Deniz'ın Sesli Takip", "yeni_call": "Deniz, annesine doğru bir kez döner. Ayağına bir kere dokunur. Sesini doğal bir şekilde 'Deniz' der.", "açıklama": "Deniz, annesine doğru bir kez döner. Ayağına bir kere dokunur. Sesini doğal bir şekilde 'Deniz' der."}
````

**Somut uyuşmazlık:** Baş yöneltme olsa da devamında dokunma ve “Deniz” deme eylemi bulunuyor. Aynı anlatı yeni_call ve açıklama alanlarında iki kez veriliyor. İstenen yalnız devam metnidir; yeni uyaran ve açıklama eklenmemeliydi.

**Belirsizliği korunan yorum:** Dokunanın ve konuşanın kim olduğu, ayağın kime ait olduğu belirsiz; “anne çocuğun ayağına dokundu” şeklinde kesinleştirilmedi.

#### Oyuna devam alternatifi — gerçek istem

````text
Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz annesine dönmeden oyununa devam eder. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme.
````

##### `continue_playing_1` — tam ham cevap

Kaynak: `run_20261017T141026879605_IYDFAB/continue_playing_1.json`. Başlangıç/bitiş (UTC): `2026-10-17T14:14:39.786652Z` → `2026-10-17T14:15:47.224474Z`.

````text
{
  "baslik": "Deniz'ın Sesli İsimi",
  "metin": "Deniz annesine dönmeden oyununa devam eder. Dokunulduğunda doğal sesle 'Deniz' dedi. Annesi ne kadar uzakta olursa olunsa, oyunun devam etmesini istemektedir.",
  "acıklama": "Deniz, annesine bakmazken sesli ismini verir. Dokunulduğunda doğal sesle 'Deniz' dener. Oyunun devam etmesi için annesi ne kadar uzakta olursa olunsa istemektedir."
}
````

**Somut uyuşmazlık:** İlk cümle oyuna devam koşulunu söylerken sonraki metin dokunulma ve ek sesli yanıt/konuşma getiriyor. Açıklama alanı olayları tekrar ediyor ve anlaşılması güç ifadeler ekliyor. İstenen ek uyaran olmadan oyuna devam sahnesiyle uyuşmuyor.

**Belirsizliği korunan yorum:** “Dokunulduğunda” koşullu bir ifade; dokunan kişinin kimliği ve ne zaman dokunduğu belirsiz. Kesin bir yetişkin eylemi ya da video olayı diye sunulmadı.

##### `continue_playing_2` — tam ham cevap

Kaynak: `run_20261017T141026879605_IYDFAB/continue_playing_2.json`. Başlangıç/bitiş (UTC): `2026-10-17T14:15:47.239381Z` → `2026-10-17T14:17:08.741745Z`.

````text
{
  "başlık": "Deniz'ın Sesli İsim",
  "metin": "Deniz annesine dönmeden oyununa devam eder. Dokunulduğunda doğal sesle 'Deniz' der. Annesi ne kadar uzakta olsa, sesi bir kez duyulur. Oyunun devam etmesi, annenin farkında olmasa da devam eder.",
  "açıklama": "Başlangıçta Deniz annesine bakmaz. Annesi doğal sesle 'Deniz' der. Oyunun devam etmesi, annenin farkında olmasa da devam eder."
}
````

**Somut uyuşmazlık:** İlk cümlede oyuna devam var; sonrasında dokunulma ve ek ses bulunuyor. Açıklama alanında çağrı öncesi durum ve annenin çağrısı yeniden yazılıyor. Bu nedenle yalnız çağrı sonrasını anlatma ve başlangıcı tekrar etmeme koşulları da karşılanmıyor.

**Belirsizliği korunan yorum:** Dokunma/konuşmanın öznesi ve “annenin farkında olmasa da” ifadesinin kesin anlamı belirsiz.

### 3.3 MiniCPM5-1B-Turkish Q4_K_M GGUF

Run: `run_20261018T140902271445_HRDPKP`. Kaynak model: `thealper2/MiniCPM5-1B-Turkish`; dosya: `MiniCPM5-1B-Turkish-Q4_K_M.gguf`. Bu bölümdeki altı kayıt **Türkçe** protokole aittir; İngilizce deneme kaydı değildir.

#### Ortak başlangıç — gerçek istem

````text
Bir çocuk videosunun yalnızca başlangıç sahnesini Türkçe, 2–3 kısa cümleyle yaz. Deniz 30 aylıktır. Evde oyuncakla oynarken annesine bakmaz. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez ‘Deniz’ der. Sahneyi bu çağrının hemen ardından bitir; çocuğun tepkisini anlatma. Yalnızca sahne metni yaz; başlık, JSON ve açıklama ekleme.
````

##### `common_start_1` — tam ham cevap

Kaynak: `run_20261018T140902271445_HRDPKP/common_start_1.json`. Başlangıç/bitiş (UTC): `2026-10-18T14:09:02.687081Z` → `2026-10-18T14:09:30.006141Z`.

````text
Yalnızca bir sahne metni yaz: 'Deniz' birçocuk video sonu.

Başlık: video sonu
Açıklama: 30 aylıktır.
````

**Somut uyuşmazlık:** Tam cevap yalnız bu satır ve “Başlık: video sonu / Açıklama: 30 aylıktır.” satırlarından oluşuyor. Annenin adını bir kez söylemesi ve ortak başlangıcın temel olayları yok. İlk satır sahne anlatmak yerine talimat biçiminde. Kayıt stop ile bitmiş; kesilme gerekçesi ileri sürülmedi.

**Belirsizliği korunan yorum:** “birçocuk video sonu” anlaşılır bir olay dizisi kurmuyor. Birinden tepki veya belirli bir dokunma olayı çıkarılmadı.

##### `common_start_2` — tam ham cevap

Kaynak: `run_20261018T140902271445_HRDPKP/common_start_2.json`. Başlangıç/bitiş (UTC): `2026-10-18T14:09:30.036230Z` → `2026-10-18T14:09:54.860390Z`.

````text
Sahneyi bu çağrının hemen ardından bitir; cümle: "Döngüyü, döngüyü, döngüyü, sıkından çok döngüyü, döngüyü."
````

**Somut uyuşmazlık:** Cevap “Sahneyi bu çağrının hemen ardından bitir” talimatıyla başlıyor ve döngü sözcüğünü tekrarlıyor. Oyun, anneye bakmama ve annenin isim çağrısı anlatılmıyor. Kayıt stop ile bitmiş; bu bozulmayı token sınırında kesilmeyle açıklamıyoruz.

**Belirsizliği korunan yorum:** “sıkından çok döngüyü” ifadesi bu görevde anlamlı bir sahne oluşturmuyor.

#### Yönelme alternatifi — gerçek istem

````text
Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz başını annesine çevirir. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme.
````

##### `turn_to_mother_1` — tam ham cevap

Kaynak: `run_20261018T140902271445_HRDPKP/turn_to_mother_1.json`. Başlangıç/bitiş (UTC): `2026-10-18T14:09:54.876203Z` → `2026-10-18T14:10:33.227013Z`.

````text
Başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez 'Deniz' der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz başını annesine çevirir. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sah
````

**Somut uyuşmazlık:** Tam cevap ortak başlangıcı yeniden yazıyor; ardından “Yalnızca ... yaz” ve “Başlangıcı yeniden anlatma” yönergelerini cevabın içine alıyor. Hedef baş yöneltme cümlesi de bu yönerge kopyasının içinde. Bu, 2–3 cümlelik bağımsız devam anlatımı değildir. Son “sah” metni length/160 token kaydıyla birlikte kesik bırakılmış.

**Belirsizliği korunan yorum:** Baş yöneltme ifadesinin bulunması, sahnenin uygun üretildiğini tek başına göstermez. Kopyalanan başlangıç çağrısı ayrıca gerçekleşmiş yeni çağrı olarak sayılmadı.

##### `turn_to_mother_2` — tam ham cevap

Kaynak: `run_20261018T140902271445_HRDPKP/turn_to_mother_2.json`. Başlangıç/bitiş (UTC): `2026-10-18T14:10:33.257260Z` → `2026-10-18T14:11:12.418578Z`.

````text
Başlangıcı, Deniz başını annesine çevirir. Başlık: Deniz Başıntılık. Yeni çağrı: Deniz, annesine, dokunma, işaret, başka uyaran ekle. Başlık: Deniz Başıntılık. Yeni çağrı: Deniz, annesine, dokunma, işaret, başka uyaran ekle. Başlık: Deniz Başıntılık. Yeni çağrı: Deniz, annesine, dokunma, işaret, ba
````

**Somut uyuşmazlık:** İstenen baş yöneltme kısa bir parça olarak var; ardından aynı “Başlık / Yeni çağrı ... ekle” dizisi yineleniyor. Sahne metni yerine yönerge benzeri liste ve başlıklar oluşmuş. Son “ba” parçası length/160 token ile kesik.

**Belirsizliği korunan yorum:** “dokunma” sözcüğünün burada ad mı olumsuz emir mi olduğu ve listeden gerçek bir uyaran olayı çıkarılıp çıkarılamayacağı belirsiz; kesin dokunma/çağrı gerçekleşti denmedi.

#### Oyuna devam alternatifi — gerçek istem

````text
Verilen başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz annesine dönmeden oyununa devam eder. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca devam sahnesinin metnini yaz; başlık, JSON ve açıklama ekleme.
````

##### `continue_playing_1` — tam ham cevap

Kaynak: `run_20261018T140902271445_HRDPKP/continue_playing_1.json`. Başlangıç/bitiş (UTC): `2026-10-18T14:11:12.449327Z` → `2026-10-18T14:11:50.213855Z`.

````text
Yalnızca, dokunma, işaret veya başka uyaran eklenmiş, tüm yalnızca devam eder. Başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez ​​‘Deniz’ der. Yalnızca bu başlangıcın hemen sonrası Türkçe, 2–3 kısa cümleyle yaz: Deniz annesine dönmeden oyununa devam eder. Ba
````

**Somut uyuşmazlık:** Bozuk ilk cümlenin ardından başlangıç ve “Türkçe, 2–3 kısa cümleyle yaz” talimatı tekrar ediliyor. Cevap, başlangıcı yeniden anlatmama ve yalnız devam sahnesi yazma koşullarını karşılamıyor. Son “Ba” parçası length/160 token ile kesik.

**Belirsizliği korunan yorum:** İlk cümlede hangi uyaranın kime eklendiği belirsiz. “dokunma” kelimesi geçti diye somut bir dokunma olayı veya davranış sonucu atanmadı.

##### `continue_playing_2` — tam ham cevap

Kaynak: `run_20261018T140902271445_HRDPKP/continue_playing_2.json`. Başlangıç/bitiş (UTC): `2026-10-18T14:11:50.227425Z` → `2026-10-18T14:12:29.503494Z`.

````text
Başlangıç: 30 aylık Deniz evde oyuncakla oynarken annesine bakmaz; annesi dokunmadan ve işaret etmeden doğal sesle bir kez Deniz'ye der. Yalnızca bu başlangıcın hemen sonrasını Türkçe, 2–3 kısa cümleyle yaz: Deniz annesine dönmeden oyununa devam eder. Başlangıcı yeniden anlatma; yeni çağrı, dokunma, işaret veya başka uyaran ekleme. Yalnızca dev
````

**Somut uyuşmazlık:** Cevap “Başlangıç:” ile ortak sahneyi yeniden anlatıyor; sonra yazım talimatlarını tekrar ediyor. Oyuna devam cümlesi bulunsa da yönerge kopyasının içinde. Son “dev” parçası length/160 token ile kesik; eksik devam tamamlanmadı.

**Belirsizliği korunan yorum:** “Deniz’ye der” dilsel olarak bozuk; buradan farklı bir çağrı sayısı veya konuşmacı sonucu çıkarılmadı.

## 4. Sınırlamalar ve sohbet şablonu kanıtı

### Emülatör, bellek ve ölçüm anlamı

- Bunlar erişilen Android x86_64 **emülatör kayıtlarıdır**. Samsung Galaxy M21 veya iPhone 11 üzerinde ölçülmüş performans sayılmaz; gerçek telefonlarda gecikme, kararlılık ve bellek yeterliliği gösterilmedi.
- **Bu 12 çıkarıma ait RAM veya tepe RAM ölçümü kayıtlarda yok.** Varsa başka zamanda alınmış tek bir bellek görüntüsü bu çıkarımların tepe belleği yerine geçmez. Bu rapor için yeni bellek/performans ölçümü yapılmadı.
- `elapsed_s` serviste model dosyası kontrolü/yükleme ve kaynak kapatmayı da kapsayan toplam kronometredir. `generation_s` yükleme sonrasında `generate()` öncesinde başlar; runtime’ın şablon/metadata incelemesini de kapsar. Yalnız token çözme hızı değildir. Kaynak: `lib/services/local_llama_test_service.dart`, `lib/services/llamadart_test_runtime.dart`.
- Başlangıç/bitiş UTC tarihleri ve kronometre alanları aynı ölçüm değildir; süreler burada tarih farklarından yeniden uydurulmadı. Çalışmalar farklı günlerdedir; emulator RAM ayrımı, cihaz yükü, CPU frekansı, termal durum ve arka plan yükü çalışma kayıtlarına sabitlenmiş deney koşulları olarak yazılmamıştır.
- Dosya adları/kimlikleri kayıtlıdır; ağırlıkların bu çalışmalara ait SHA256’sı yoktur. Kayıt dosyası SHA256’ları aşağıda verilir; bunlar model ağırlığı hash’i değildir.
- İki tekrar, dağılım veya genel başarı oranı çıkarmak için yeterli bir örneklem değildir. Çıktı token sınırı da metnin kalitesini tek başına açıklamaz. Bir dil/biçim sorunu ile kesin model mimarisi, şablon ya da eğitim kusuru arasında nedensellik kurulmadı.

### Kayıtta görülen son prompt ile doğrulanamayanlar

- **Qwen:** Altı kaydın `rendered_prompt_preview` alanında ilgili tam istem tek user bloğunda, ardından assistant başlangıcı ve boş `<think>\n\n</think>` bloğu var. `thinking_template_check` düşünmesiz başlangıcın doğrulandığını söylüyor. Önizlemelerde araç/fonksiyon listesi veya önceki diyalog görünmüyor.
- **MiniCPM:** Altı önizleme `<s><|im_start|>user` ile başlayıp aynı user istemini, assistant başlangıcını ve boş think bloğunu içeriyor. Kayıt “MiniCPM kendi GGUF şablonu, enableThinking=false; Qwen boş think kontrolü uygulanmadı” diyor. Bu **runtime’ın raporladığı kontroldür**; yayıncının kullanım örneğiyle bağımsız uyum kanıtı değildir.
- MiniCPM’nin metinsel önizlemesindeki BOS/rol/think yapısı kayıttan görülebilir. **Boş think bloğunun GGUF’nin özgün şablonundan mı yoksa renderer uyarlamasından mı geldiği, yayıncının eğitim/çıkarım örneğiyle tam eşleşme ve native tokenizasyon sırasında özel belirteçlerin olası eklenmesi bu kayıtlardan kesinleştirilemiyor.** MiniCPM’nin bozuk cevabını kesin şablon hatası diye sunmuyoruz.
- **Llama:** `docs/d01_prompt_karsilastirmasi.md`, cihaz GGUF şablonuyla son promptun geçmişte yeniden render edilip araç talimatlarının etkin olmadığının incelendiğini anlatıyor; belge bunun geçmiş çıkarım anında yakalanmış native giriş olmadığını açıkça belirtiyor. Bu raporda o renderer çalıştırılmadı, gerçek denemeye ait tam prompt/cevap kaydı bulunamadı.
- Her iki ham çalışmadaki önizlemeler, kaydedilmiş renderer çıktılarıdır; native motora giden kesin token dizisinin bağımsız dökümü değildir. Önizleme ile gerçek native girişin bayt/token düzeyinde eşitliğini veya hiçbir otomatik special-token işlemi olmadığını iddia etmiyoruz.
- Bütün ham `human_evaluation` alanları boş bırakılmıştır. Bu rapor otomatik olarak tamamlanmış insan değerlendirmesi veya modelin kendini doğrulaması değildir.

## 5. Kaynak dosyalar ve bütünlük

### Birincil Android dosyaları

Aşağıdaki tüm dosyalar şu köke göre verilmiştir:

```text
/data/user/0/com.neuroapp.neuro_awareness_app/app_flutter/evaluations/d01_qwen/
```

| Kök altındaki dosya | Okunan JSON baytlarının SHA256’sı |
| --- | --- |
| `run_20261017T141026879605_IYDFAB/protocol.json` | `08c95a65c233a6d824b8edaf11762771a5637cc54662e936ac83b8563461d190` |
| `run_20261017T141026879605_IYDFAB/common_start_1.json` | `c50882ef5f957f7b89a8be3262781978900c1fc2b9ac356a66cf14136755a43f` |
| `run_20261017T141026879605_IYDFAB/common_start_2.json` | `83d0193b2569086e03fa03841c4fd293015cd66b0753b8933d4a4342940b5e32` |
| `run_20261017T141026879605_IYDFAB/turn_to_mother_1.json` | `9848ddad6f63024c8cdb9600c4e443ce30d5b71940cf25d3d5bbf62c26e9654b` |
| `run_20261017T141026879605_IYDFAB/turn_to_mother_2.json` | `9ea82c5fdab19ac2f1bb93cb11b04291453e2ef3b1bbc50ce61f14f7262258e5` |
| `run_20261017T141026879605_IYDFAB/continue_playing_1.json` | `4476056fdcac6493310a8b69c835faefbcb64481e26ff48e2efa158e79aad409` |
| `run_20261017T141026879605_IYDFAB/continue_playing_2.json` | `9d578b71ba15b9a10bf831d12bc7a051e7b16b40005ac7728607e7531048c09a` |
| `run_20261017T141026879605_IYDFAB/run_summary.json` | `5d62497a5e8a425a76f55a5a10c325f44d5aaa0b48478445c324cf02ce8a9aa2` |
| `run_20261018T140902271445_HRDPKP/protocol.json` | `ed7acbb94c3b7d20d67b82ff0f5c86547c03480c51c9dd21efb6a5893b7a6c9d` |
| `run_20261018T140902271445_HRDPKP/common_start_1.json` | `916c16178ac20091bc6479281e4f00df469746d9e908473c54992a9b3e708263` |
| `run_20261018T140902271445_HRDPKP/common_start_2.json` | `8a781104f9b886e7835707cee15fce4f2b09b06695566bab86acb2f0e75c4a1f` |
| `run_20261018T140902271445_HRDPKP/turn_to_mother_1.json` | `62ef11810cc9f9f49ff02834bdebb132ac11e504830abd6c49ad8d1cbbe3e9f6` |
| `run_20261018T140902271445_HRDPKP/turn_to_mother_2.json` | `40f25f712c5f18ccbb003324e5635b40b328260dee5f732cd3450ea1191949ed` |
| `run_20261018T140902271445_HRDPKP/continue_playing_1.json` | `dd45f5b9e25b29dbfe68a1e476fd0d50bb775c5ed21c00e912fef47292cae230` |
| `run_20261018T140902271445_HRDPKP/continue_playing_2.json` | `c8d74efef11bd884eb94d260b70dac9e8cb9f8d23691549c709dc8e89db6fe8a` |
| `run_20261018T140902271445_HRDPKP/run_summary.json` | `56af104feee520400527b2c22a505ba1cde1a4f6c8626547046b776cf15c1bd9` |

Bu manifestteki 12 deneme dosyası asıl cevap kanıtıdır; `protocol.json` istem/ayar dondurmasını, `run_summary.json` ise yalnız yürütme özetini destekler. Sayısal alanlar ve tam metinler bu incelemede doğrudan bu dosyalardan okundu.

### Proje kaynakları ve ikincil belgeler

Yollar `C:\Projeler\Norogelisim\mobil_uygulama\mobile_skeleton\` köküne göredir:

- [Dondurulmuş protokol asset’i](../assets/evaluations/d01_qwen_v1.json): dosyalardaki aynı üç görevin proje kopyası; tek başına çıkarım sonucu değildir.
- [Değerlendirme kayıt servisi](../lib/services/d01_evaluation_service.dart): ayrı denemeler, alanların yazımı, boş insan değerlendirmesi ve çalışma özeti.
- [Yerel çıkarım servisi](../lib/services/local_llama_test_service.dart): ham metin biriktirme, toplam/üretim kronometreleri, hatalar ve kaynak kapatma.
- [Native runtime adaptörü](../lib/services/llamadart_test_runtime.dart): şablon önizlemesi, CPU/örnekleme, token/bitiş tanı bilgileri.
- [Model seçenekleri](../lib/models/local_model_option.dart): beklenen model depo/dosya adları; geçmiş deneme kaydı yerine kullanılmadı.
- [Llama yerel test notu](yerel_model_testi.md), [Llama D01 ön test notu](d01_senaryo_testi.md), [çıkarım incelemesi](d01_cikarim_incelemesi.md), [TR/EN prompt incelemesi](d01_prompt_karsilastirmasi.md), [devam notu](DEVAM_NOTU.md): Llama için bulunan **5 ikincil belge**; her biri yeni/ayrı deneme olarak sayılmadı.
- [Llama sohbet şablonu fixture’ı](../test/fixtures/llama32_device_template.json) ve [fixture açıklaması](../test/fixtures/README.md): model cevabı değil.
- [Önceki Qwen değerlendirme notu](d01_run_20261017T141026879605_IYDFAB_degerlendirme.md): kullanıcı incelemesi ve önceki asistan kontrolü ayrı yazılmış tarihsel not. Yeni rapordaki sayılar ve alıntılar ondan kopyalanmak yerine ham dosyalardan doğrulandı.
- [Değerlendirme akışının hazırlık notu](d01_degerlendirme.md): ilk yazıldığı aşamada altı gerçek çıkarımın henüz yapılmadığını söyler. Bu tarihsel hazırlık durumu, sonradan oluşmuş ham kayıtların yokluğu anlamına gelmez.

Tarihsel devam notundaki “MiniCPM’nin gerçek çıkarımı henüz doğrulanmadı” ifadesi, artık erişilen altı `llamadart_native/completed` kaydıyla aynı tarihsel aşamaya ait değildir. Bu raporda teknik çıkarım kayıtları bulunduğu belirtilir; bunun içerik başarısı olmadığı ayrıca korunur.

**Sunumda kullanılacak sınır:** “Qwen ve MiniCPM aynı sabit Türkçe görevlerde farklı türde yönerge ve içerik ihlalleri üretti; erişilen küçük örnek grubu güvenilir kontrollü senaryo üretimini göstermedi. Llama için ham arşiv bulunamadığından aynı protokolde nicel kıyas yapılamadı.” Bu ifade genel model yeteneği, klinik sonuç veya gerçek telefon performansı iddiası değildir.
