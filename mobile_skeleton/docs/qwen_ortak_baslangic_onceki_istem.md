# Qwen ortak başlangıç testinin önceki istemi

Bu metin, yalnız oyun ortamı istemine geçilmeden önce `LocalLlamaTestRequest.qwenCommonStart` içinde kullanılan tam istemdir. Geri erişim için ayrı korunmuştur; uygulamaya yeni kart veya test seçeneği eklemez.

```text
Bir çocuk videosunun yalnızca başlangıç sahnesini Türkçe, 2–3 kısa cümleyle yaz.
Deniz 30 aylıktır. Evde bir oyuncakla oynarken annesine bakmamaktadır. Annesi ona dokunmadan ve işaret etmeden, doğal sesle yalnızca bir kez ‘Deniz’ der.
Sahneyi bu çağrının hemen ardından bitir. Çocuğun çağrıya vereceği tepkiyi henüz anlatma.
Yalnızca sahne metnini yaz; başlık, JSON ve açıklama ekleme.
```

Önceki ayarlar: Qwen3-1.7B Q4_K_M, CPU, düşünme kapalı, bağlam 2048, en fazla 160 yeni token. Bu ayarlar değiştirilmedi.

Mevcut tekli testin yeni istemi iki kısa Türkçe cümleyle bir oyuncak ve basit oyun eylemi ister; yetişkin, konuşma, isim çağrısı ve birine verilen tepkiyi dışlar. Kartın açıklaması buna uygun güncellendi. Ham cevap, süre ve token gösterim hattı değiştirilmedi. Yeni istem için test veya gerçek model çıkarımı başlatılmadı.

Bu tekli test değişikliği, altı denemelik değerlendirme protokolünün sabit istemlerini değiştirmez. `run_20261017T141026879605_IYDFAB` ham değerlendirme kayıtlarına dokunulmadı.
