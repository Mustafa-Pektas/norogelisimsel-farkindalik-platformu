# 🎬 Google Flow ile Kesintisiz Video Grafı Rehberi
> **Davranış:** [ONT-01] İsme Tepki (Response to Name)  
> **Konsept:** 3 Kilit Kareli (Keyframe), 5 Videolu Kapalı Döngü Karar Grafı  
> **Tarih:** 16 Ekim 2026

---

## 📌 1. Sistemin Temel Mantığı (Topolojik Döngü)

Video geçişlerinde atlama (jump-cut) veya sahne kayması olmaması için tüm sistem **3 adet Kilit Resim** üzerine kuruludur:

```
[KİLİT RESİM 1] ──► [🎬 1. Başlangıç Videosu] ──► [KİLİT RESİM 2]
                                                        │
                         ┌──────────────────────────────┼──────────────────────────────┐
                         ▼                              ▼                              ▼
                   🟢 2. YEŞİL (Tipik)            🟡 3. SARI (Gecikmeli)         🔴 4. KIRMIZI (Atipik)
             (Start: Resim 2 ➔ End: Resim 3) (Start: Resim 2 ➔ End: Resim 3) (Start: Resim 2 ➔ End: Resim 3)
                         └──────────────────────────────┬──────────────────────────────┘
                                                        │
                                                        ▼
                                                 [KİLİT RESİM 3] ──► [🎬 5. Son Sahne]
```

### 🖼️ Bilgisayarındaki Resim Dosyaları:
Klasör: `c:\Users\hasan\OneDrive\Belgeler\GitHub\psikolojiksel\video_graf_resimleri\`
* **`kilit_resim_1_giris.jpg`:** Çocuk arabaya uzanır, kadın arkada bağdaş kurmuş oturup izler.
* **`kilit_resim_2_seslenme.jpg`:** Çocuk arabayı tutar, kadın başı dik "Ali!" diye seslenir.
* **`kilit_resim_3_notr_kapanis.jpg`:** Çocuk iki elini arabanın üzerine koyup nötr durur, kadın arkada sakince izler.

---

## 🚫 Katı Yapay Zeka Kuralları (Prompt Standartları)
1. **Kamera:** `Static locked-off shot`. Asla "tripod" kelimesi kullanılmaz (sahneye demir üçayak dikmemesi için). Sıfır hareket, sıfır zoom.
2. **Ses:** `Silent room without background music`. Arkada saçma müzikler çalmaz, sadece doğal oda ve tekerlek sesi.
3. **Kadın:** Arkada yerde oturur, **elinde asla kitap yoktur**, asla ayağa kalkıp yürümez, gözünü çocuktan ayırmaz.
4. **Çocuk:** Ağzı tamamen kilitlidir ve sessizdir; asla kendi kendine konuşmaz.

---

## 🎬 5 VİDEOLUK TAM PROMPT SETİ

*(Tüm videolar Google Flow'da **5 saniye** ve **16:9** olarak ayarlanacaktır)*

### 1. VİDEO: Başlangıç Videosu (Doğal Oyun & Seslenme)
* **Google Flow Resimleri:**
  * **görsel1:** `kilit_resim_1_giris.jpg`
  * **görsel2:** `kilit_resim_2_seslenme.jpg`
* **Zaman Çizelgesi:**
  * `0.0s – 3.0s`: Çocuk halıda arabayı hafifçe ileri geri sürer.
  * `3.5s`: Arkadaki kadın seslenir: *"Ali!"*.
  * `3.5s – 5.0s`: Çocuk arabayı tutarken durur, başı önde `görsel2`'ye oturur.
* **Prompt:**
```text
Static locked-off shot, completely still perspective with zero movement, zero panning, zero tilt, zero zoom. Silent room without background music.

STRICT ACTOR CONSTRAINTS:
1. The toddler's mouth remains 100% closed and silent. The toddler NEVER speaks.
2. The woman in the background remains seated cross-legged on the floor in her spot; she NEVER stands up, she NEVER walks forward.
3. The woman holds NO book or object; her hands rest in her lap while her eyes stay continuously fixed on the toddler, watching him attentively.

From 0.0 to 3.0 seconds, starting from görsel1: The toddler sits on the rug and gently pushes the red wooden car forward and backward a few inches in solitary play. The woman remains seated cross-legged in the background, intently watching the child play.
At 3.5 seconds: Looking directly at the toddler, the woman speaks clearly: "Ali!".
From 3.5 to 5.0 seconds: Hearing his name, the toddler stops hand motion on the car, keeping his head down and freezing in place, landing smoothly and identically into the exact pose of görsel2 by second 5.0 while the woman watches him closely.
```

---

### 🟢 2. VİDEO: Yeşil Tepki (Tipik — Hızlı Dönüş & Tebessümlü Göz Teması)
* **Google Flow Resimleri:**
  * **görsel1:** `kilit_resim_2_seslenme.jpg`
  * **görsel2:** `kilit_resim_3_notr_kapanis.jpg`
* **Zaman Çizelgesi:**
  * `0.0s – 1.0s`: Çağrıyı duyunca 1 saniye içinde başını sağa 60° çevirir.
  * `1.0s – 2.5s`: Kadınla doğrudan göz teması kurar ve gülümser.
  * `2.5s – 5.0s`: Başını tekrar önüne indirir, iki elini arabanın üstüne koyup `görsel2`'ye oturur.
* **Prompt:**
```text
Static locked-off shot, completely still perspective with zero movement, zero panning, zero tilt, zero zoom. Quiet room acoustics, no background music.

PREVIOUS SCENE CONTEXT: The woman seated 1.5m behind called "Ali!" and is looking directly at the child, waiting for his response. The child paused holding the car (görsel1).

STRICT ACTOR CONSTRAINTS:
1. The toddler does not speak; his mouth is closed except for a smile.
2. The woman remains seated in the background in her exact spot, hands in lap, keeping her eyes fixed on the child.
3. Natural mutual gaze: The woman is looking at the child, and the child looks back at the woman.

From 0.0 to 1.0 second, starting from görsel1: Hearing his name, the toddler smoothly and immediately rotates his head 60 degrees to the right toward the woman.
From 1.0 to 2.5 seconds: The toddler establishes direct, warm eye contact with the woman. The woman smiles back as she watches him. They share a joyful, connected mutual gaze.
From 2.5 to 5.0 seconds: The toddler naturally turns his head back down, places both hands flat on top of the red car, and settles peacefully into the exact pose of görsel2 by second 5.0 while the woman continues to watch him attentively.
```

---

### 🟡 3. VİDEO: Sarı Tepki (Gecikmeli — Ağır Yönelim & Kaçamak Bakış)
* **Google Flow Resimleri:**
  * **görsel1:** `kilit_resim_2_seslenme.jpg`
  * **görsel2:** `kilit_resim_3_notr_kapanis.jpg`
* **Zaman Çizelgesi:**
  * `0.0s – 2.5s`: Çocuk arabaya bakmaya devam eder, hemen dönmez.
  * `2.5s – 3.5s`: Yavaşça ve tereddütle yana kaçamak bir bakar, gülümsemez.
  * `3.5s – 5.0s`: Başını önüne indirir, iki elini arabanın üstüne koyup `görsel2`'ye oturur.
* **Prompt:**
```text
Static locked-off shot, completely still perspective with zero movement, zero panning, zero tilt, zero zoom. Quiet room acoustics, no background music.

PREVIOUS SCENE CONTEXT: The woman called "Ali!" and is looking directly at the child, patiently waiting to see if he will respond. The child holds the car (görsel1).

STRICT ACTOR CONSTRAINTS:
1. The toddler remains silent with mouth closed.
2. The woman holds no book; her hands rest in her lap while she keeps her gaze fixed on the child the entire time, waiting for a reaction.

From 0.0 to 2.5 seconds, starting from görsel1: The woman sits watching the child, but the toddler shows clear delayed response, continuing to look down at the car without moving his head.
From 2.5 to 3.5 seconds: Slowly and hesitantly, the toddler turns his head slightly toward the woman, giving a brief, quiet glance toward her face without smiling. The woman watches this brief glance attentively.
From 3.5 to 5.0 seconds: The toddler lowers his gaze back down, places both hands flat on top of the red car, and settles calmly into the exact neutral sitting pose of görsel2 by second 5.0.
```

---

### 🔴 4. VİDEO: Kırmızı Tepki (Atipik — Sıfır Tepki & Tekere Kilitlenme)
* **Google Flow Resimleri:**
  * **görsel1:** `kilit_resim_2_seslenme.jpg`
  * **görsel2:** `kilit_resim_3_notr_kapanis.jpg`
* **Zaman Çizelgesi:**
  * `0.0s – 3.5s`: Sese hiç tepki vermez, başını kaldırmadan parmağıyla tekeri döndürür.
  * `3.5s – 5.0s`: Tekeri bırakır, iki elini arabanın üstüne koyup `görsel2`'ye oturur.
* **Prompt:**
```text
Static locked-off shot, completely still perspective with zero movement, zero panning, zero tilt, zero zoom. Quiet room acoustics, no background music.

PREVIOUS SCENE CONTEXT: The woman called "Ali!" and is looking directly at the child, waiting for a response. The child holds the car (görsel1).

STRICT ACTOR CONSTRAINTS:
1. The toddler remains completely silent.
2. The woman holds no book; her hands rest in her lap while she keeps her gaze locked on the child throughout the entire clip, observing his lack of response.
3. The toddler NEVER looks up and NEVER turns his head.

From 0.0 to 3.5 seconds, starting from görsel1: While the woman sits watching and waiting, the toddler completely ignores the call. His gaze remains rigidly fixed downward on the red car as he repetitively spins the front wheel with his index finger.
From 3.5 to 5.0 seconds: The toddler stops spinning the wheel, places both hands flat on top of the red car, and remains completely still with head down, landing accurately into the exact pose of görsel2 by second 5.0 while the woman continues to observe him.
```

---

### 🎬 5. VİDEO: Son Sahne (Kapanış & Serbest Oyuna Devam)
* **Google Flow Resimleri:**
  * **görsel1:** `kilit_resim_3_notr_kapanis.jpg`
  * *(Bitiş için görsel2 gerekmez)*
* **Zaman Çizelgesi:**
  * `0.0s – 5.0s`: Çocuk iki eli arabanın üzerindeyken arabayı halıda 30 cm ileri sürer, doğal oyununa devam eder.
* **Prompt:**
```text
Static locked-off shot, completely still perspective with zero movement, zero panning, zero tilt, zero zoom. Quiet room acoustics, no background music.

PREVIOUS SCENE CONTEXT: The reaction phase ended. The toddler settled his hands on the car, and the woman is seated quietly watching him play (görsel1).

STRICT ACTOR CONSTRAINTS:
1. The toddler remains silent and seated in his spot on the rug.
2. The woman in the background holds no book, hands resting in her lap, calmly watching the child play.

From 0.0 to 5.0 seconds, starting seamlessly from görsel1: The toddler gently pushes the red wooden car forward 30 centimeters across the geometric rug, watching the wheels roll. The woman continues watching him peacefully from the background. The toddler remains seated in the same spot, continuing calm, independent solitary play in the soft morning light.
```
