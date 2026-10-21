# Qwen D01 değerlendirme notu — 17 Ekim 2026

Run: `run_20261017T141026879605_IYDFAB`

Bu ayrı not asistan tarafından hazırlanmıştır. Aşağıdaki içerik incelemesi kullanıcı bildirimine, sayısal kontroller ise mevcut ham kayıtlara dayanır. Otomatik doldurulmuş insan değerlendirmesi değildir. Ham cevaplar, kayıtların `human_evaluation` alanları ve `semantic_verdict` değiştirilmedi.

## Kaynak ve kapsam

Emülatördeki uygulama belge dizininin `evaluations/d01_qwen/run_20261017T141026879605_IYDFAB/` klasöründeki `protocol.json`, `run_summary.json` ve altı deneme JSON'u ADB ile salt okunur incelendi. Kayıt kaynağı `llamadart_native`; altı deneme teknik olarak `completed`, hata `null`. Bu durum içerik başarısını ifade etmez.

Model: `unsloth/Qwen3-1.7B-GGUF`, dosya `Qwen3-1.7B-Q4_K_M.gguf`. Sabit protokol `d01_qwen_scene_eval_v1`; üç görev ikişer kez, sıralı. Denemelerdeki tam istemler ve ayarlar `protocol.json` ile eşleşiyor. Önceden dondurulan istemlerin kaynağı [değerlendirme asset'i](../assets/evaluations/d01_qwen_v1.json).

Kayıtlı ayarlar: CPU, GPU katmanı 0, bağlam 2048, yeni token sınırı 160, düşünme kapalı; temperature 0.7, top-P 0.8, top-K 20, min-P 0, repeat penalty 1.0, presence penalty 0. Seed belirtilmemiş; gerçek native seed bilinmiyor. Threads/batch threads 2/2, batch/micro batch 64/64, `reuse_prompt_prefix=true`, paket `llamadart 0.12.0`. Kod her denemeye yeni motor ve tek kullanıcı mesajıyla başlıyor; önceki cevap sonraki göreve taşınmıyor.

## Kullanıcı incelemesi

Aşağıdaki gözlemler kullanıcının bu çalışmaya ilişkin bildirdiği incelemedir; asistanın kullanıcı adına ürettiği puanlar değildir.

| Deneme | Kullanıcının bildirdiği içerik sorunu |
| --- | --- |
| `common_start_1` | Yasak çocuk tepkisi ekliyor; `length` ile kesiliyor. |
| `common_start_2` | Tepki/korku ve bozuk tekrarlar ekliyor. |
| `turn_to_mother_1` | Yeni isim çağrıları ekliyor. |
| `turn_to_mother_2` | Dokunma ve seslenme ekliyor. |
| `continue_playing_1` | Dokunma ve ek konuşma/ses ekliyor. |
| `continue_playing_2` | Dokunma ve ek konuşma/ses ekliyor. |

Kullanıcı incelemesine göre altı cevap da istenmeyen JSON biçiminde; bu altı örnek içinde kritik içerik koşullarını eksiksiz karşılayan cevap yok.

## Asistanın kayıt kontrolü ve sınırlı değerlendirmesi

Ham metinlerin okunması yukarıdaki sorunları destekliyor: ilk başlangıçta şaşkınlık/korku, ikinci başlangıçta tepki ve tekrarlar; yönelme cevaplarında ek çağrı veya dokunma; oyun devamlarında dokunma ve ek ses/konuşma bulunuyor. Altı cevap da JSON nesnesi biçimine yöneliyor; ilk cevap tamamlanmamış JSON metni. Cevapların kendi açıklama/başarı iddiaları değerlendirme kanıtı kabul edilmedi. Yalnızca anahtar kelimelerle başarı sınıflaması yapılmadı.

Bu küçük, sabit istemli ve tek emülatördeki örnek grubunda eksiksiz uygun örnek bulunmaması, modelin her görevde başarısız olduğunu veya genel bir başarı oranını göstermez. Davranış gözlemi, tanı veya video doğruluk referansı üretilmedi. Ham kayıtlardaki beş insan değerlendirme alanının tamamı hâlâ `null`; bu not onlardan ayrı, kaynakları belirtilmiş bir değerlendirmedir.

## Kayıtlardan hesaplanan süreler ve tokenlar

| Deneme | Toplam s (`elapsed_s`) | Üretim s (`generation_s`) | İstek tokenı | Çıktı tokenı | API bitişi |
| --- | ---: | ---: | ---: | ---: | --- |
| `common_start_1` | 80.381698 | 76.340015 | 141 | 160 | `length` |
| `common_start_2` | 62.787148 | 62.024284 | 141 | 135 | `stop` |
| `turn_to_mother_1` | 56.815004 | 55.327175 | 151 | 114 | `stop` |
| `turn_to_mother_2` | 52.386821 | 50.802949 | 151 | 100 | `stop` |
| `continue_playing_1` | 67.344709 | 66.233579 | 157 | 150 | `stop` |
| `continue_playing_2` | 81.426862 | 80.533955 | 157 | 153 | `stop` |

- Deneme toplam sürelerinin toplamı: **401.142242 s** (6 dk 41.142 s); ortalama **66.857040 s**.
- Üretim sürelerinin toplamı: **391.261957 s**; ortalama **65.210326 s**.
- İlk `started_at_utc` (`14:10:27.096635Z`) ile son `finished_at_utc` (`14:17:08.741745Z`) arası **401.645110 s**. Deneme dışı kayıt/geçiş aralıklarını da içerdiği için sürelerin toplamından farklıdır.
- İstek tokenı toplamı 898, çıktı tokenı toplamı 812; her denemede önbellekten token 0. Bunlar ayrı çıkarımların toplamlarıdır, tek bir bağlamın kullanımı değildir.
- Kaynak kodda toplam kronometre model yükleme ve kaynak kapatmayı da kapsıyor. Üretim kronometresi yükleme sonrasında `generate()` öncesinde başlıyor; şablon incelemesini de kapsıyor, yalnızca token çözme süresi değildir. Kaynak: [test servisi](../lib/services/local_llama_test_service.dart), [kayıt servisi](../lib/services/d01_evaluation_service.dart).
- İlk cevap 160 token çıktı sınırına ulaşıyor. `stop` içerik koşullarının karşılandığı anlamına gelmez. Bu altı denemenin RAM kullanımı/tepe RAM'i **ölçülmedi**; sürelerden RAM veya 4B performansı çıkarılamaz.

## Sonraki aday: dosya ve motor kontrolü

Aday `unsloth/Qwen3-4B-Instruct-2507-GGUF` / `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`. [Yayıncının dosya sayfası](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/blob/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf) ve [yalnızca LFS işaretçisi](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/raw/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf) üzerinden doğrulanan bilgiler:

- Boyut: **2,497,281,120 bayt** = yaklaşık **2.50 GB / 2.326 GiB**.
- Yayınlanan SHA256: `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597`.
- Bu uzak dosyanın yayınlanan özeti; dosya indirilmediği için yerel dosya özeti hesaplanmadı. Xet hash'i SHA256 ile karıştırılmadı.

Yerel paket 0.12.0'ın changelog'u ve önbelleği native `v0.6.0-2` kullanıyor. [Resmî native sürüm kaydı](https://github.com/leehack/llamadart-native/releases/tag/v0.6.0-2) llama.cpp commit'ini `d81235049384534c167caea52b85a694f6103d14` olarak belirtiyor. Kurulu APK içindeki x86_64 `libllama.so` ve bu önbellek aynı ELF Build ID'yi taşıyor: `81f115cb8f3bfaf8c3523e52058ccb1756e737b3`; kurulu ikilide `qwen3` ve `Q4_K` tanımları da var. Paketleme sonrası dosyalar bayt düzeyinde aynı değil; eşleştirme Build ID'ye dayanıyor.

[Bu commit'in Qwen3 yükleyicisi](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/src/models/qwen3.cpp) 36 katman ve 2560 gizli boyutunu 4B olarak tanıyor. [Qwen'in aday model yapılandırması](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/main/config.json) `Qwen3ForCausalLM` / `qwen3`, 36 katman, 2560 gizli boyut kullanıyor. Böylece mimari ve kuantizasyon ailesi desteği kaynak/ikili düzeyinde mevcut. **Aday GGUF'nin gerçekten yüklenmesi, içindeki şablonun render edilmesi ve CPU çıkarımı bu incelemede doğrulanmadı.** Şu an paket yükseltmesini gerektiren somut mimari uyumsuzluğu bulunmadı.

## Think kontrolünde gelecekte uyarlanacak yer

[Qwen'in resmî model kartına](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507) göre Instruct-2507 yalnızca düşünmesiz çalışır; çıktıda `<think></think>` üretmemesi normaldir ve `enable_thinking=False` ayrıca gerekli değildir. [Resmî tokenizer şablonu](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/main/tokenizer_config.json) normal üretim başlangıcını `<|im_start|>assistant\n` olarak bitirir; boş think bloğu eklemez. Araç talimatları şablonun `tools` koşulundadır.

Mevcut [llamadart_test_runtime.dart](../lib/services/llamadart_test_runtime.dart) dosyasında 98–109. satırlardaki `closedThinking` kontrolü, Qwen için assistant başlangıcında boş think bloğu arayıp yoksa üretimi durduruyor. Bu, hibrit Qwen3-1.7B için olan beklentidir; Instruct-2507'ye aynen uygulanmamalıdır. İleride model türüne göre ayrılmalı: 1.7B kontrolü korunmalı, 2507'de modelin kendi şablonunun normal assistant başlangıcı doğrulanmalı; yapay think bloğu eklenmemelidir. Gerçek GGUF şablonu ile araçsız/tek kullanıcı mesajının son promptu yükleme sonrasında ayrıca kontrol edilmelidir. Bu görevde kontrol değiştirilmedi.

## Emülatör belleği ve depolama: mevcut anlık durum

17 Ekim 2026'da `emulator-5554` / `Pixel_6`, x86_64 üzerinde salt okunur kontrol:

| Ölçüm | Sonuç | Kaynak |
| --- | --- | --- |
| Çalışan emülatörün RAM ayarı | 4096 MiB (4 GiB) | AVD `hardware-qemu.ini`, `hw.ramSize=4096` |
| Kalıcı AVD yapılandırması | 2048 MiB | `config.ini`, `hw.ramSize=2048`; çalışan ayardan farklı |
| Android'in gördüğü toplam RAM | 4,006,180 KiB ≈ 3.821 GiB | `/proc/meminfo`, `MemTotal` |
| Kullanılabilir RAM | 2,459,288 KiB ≈ 2.345 GiB | `/proc/meminfo`, `MemAvailable` |
| Tam boş RAM | 407,876 KiB ≈ 398.3 MiB | `/proc/meminfo`, `MemFree`; kullanılabilir RAM ile aynı ölçü değildir |
| Swap toplam / boş | 751,152 / 419,272 KiB | `/proc/meminfo`; fiziksel RAM sayılmadı |
| Uygulama PSS / RSS | 375,426 / 472,224 KiB | `dumpsys meminfo`, bu inceleme anı |
| Veri bölümünde boş alan | 6,691,724 KiB ≈ 6.382 GiB | `df -k /data`; AVD bölüm ayarı 10G |

Bunlar bitmiş denemelerin tepe bellek ölçümü değildir. Ana bilgisayar RAM'i ve emülatör süreç komut satırı için CIM sorguları erişim engeli nedeniyle doğrulanamadı; dönen boş değerler RAM=0 olarak yorumlanmadı. Çalışan/kalıcı RAM farkının hangi başlatma seçeneğinden kaynaklandığı doğrulanmadı; sonraki açılışta 4 GiB'nin korunacağı varsayılmamalıdır.

Asistanın bellek değerlendirmesi: depolama yeni ağırlık dosyası için yeterli görünüyor. Kullanılabilir RAM ise dosya boyutundan yalnızca yaklaşık **20 MiB** fazla. Dosya boyutu gerçek toplam RAM tüketimi değildir; KV önbelleği, hesaplama tamponları ve uygulama/Android için ek alan gerekir. `mmap`/swap ile yüklemenin kesin başarısız olacağı söylenemez; fakat mevcut bellekte altı 4B denemesine geçmek için yeterli pay gösterilemedi. **Mevcut RAM bütçesiyle devam önerilmiyor.** Gerçek yükleme ve tepe RAM ölçümü olmadan güvenli çalışma garantisi verilemez.

## Karşılaştırma planı ve en küçük sonraki işlem

Önce ana bilgisayarda yeterli boş RAM doğrulanmalı; uygunsa çalışan AVD için 6 GiB gibi daha geniş bir RAM bütçesi ayrı adımda ayrılıp kullanılabilir bellek yeniden ölçülmeli. 6 GiB doğrulanmış minimum gereksinim veya başarı garantisi değildir. Bu incelemede RAM ayarı değiştirilmedi.

Bellek payı sağlandıktan ve ayrı model seçeneği/şablon kontrolü uyarlandıktan sonra aynı protokoldeki üç **tam istem değiştirilmeden**, aynı sırada ikişer deneme yapılmalı. Önceki ham cevaplar yeni istemlere eklenmemeli. CPU/2048 bağlam/160 çıktı sınırı ve mevcut örnekleme/iş parçacığı ayarları korunmalı; yalnızca model kimliği, dosyası ve modele uygun şablon politikası ayrılmalı. Değerlendirme servisindeki sabit `LocalModelOption.qwen3` seçimleri de yeni model kimliğiyle açıkça ayrılmalı; eski dosyanın üstüne yazılmamalıdır.

Yeni çalışma ayrı run klasörüne; tam istemler, ayarlar, ham cevaplar, tokenlar, süreler, bitiş nedenleri ve hatalarla kaydedilmeli. İnsan değerlendirme alanları boş başlayıp ayrı kullanıcı incelemesiyle doldurulmalı; düzeltme/yeniden deneme/şablon cevabı eklenmemeli. Seed bilinmediğinden eşlenmiş seed karşılaştırması iddia edilmemeli. AVD RAM'i değişirse zaman karşılaştırması aynı bellek koşullarında yapılmış sayılmamalı; hem RAM yapılandırması hem gerçek tepe bellek ayrıca kaydedilmeli.

Bu görevde yalnızca bu not eklendi. Yeni model/paket indirilmedi, entegrasyon veya gerçek 4B çıkarımı yapılmadı. Kod, ayarlar, modeller, önceki sonuçlar ve stash korundu; commit/push yapılmadı.
