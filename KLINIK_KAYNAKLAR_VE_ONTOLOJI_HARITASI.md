# Nörogelişimsel Farkındalık Platformu — Klinik Kaynaklar ve Ontoloji Haritası

Bu doküman, platformun **RAG (Retrieval-Augmented Generation)** mimarisinde, senaryo simülasyonunda ve video analizi modülünde kullanılan **klinik ölçekleri, akademik literatür dayanaklarını, davranış ontolojilerini (ONT/D kodları) ve 3 yaş bandı eşiklerini** eksiksiz olarak belgelemektedir.

---

## 1. Yönetici Özeti ve Amaç

Nörogelişimsel Farkındalık Platformu, **12–36 ay** arasındaki çocuklarda Otizm Spektrum Bozukluğu (OSB) ve nörogelişimsel farklılıkların erken farkındalığına yönelik yapay zeka tabanlı fotogerçekçi simülasyon ve video analizi gerçekleştiren bir araştırma ve eğitim sistemidir.

Büyük Dil Modelleri (LLM) nörogelişimsel davranışları tek başına üretirken halüsinasyona ve yaşa uygun olmayan klinik ölçütler üretmeye meyillidir. Platformumuz, **kanonik bir klinik bilgi tabanı (`clinical_knowledge_base.json`) ve seçici bir RAG mekanizması (`retriever.js`)** kullanarak üretilen her sahnenin yaşa özel altın standart ölçeklerle (ADOS-2, STAT, M-CHAT-R/F, Bayley-4) %100 uyumlu olmasını sağlar.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   RAG KLİNİK BİLGİ TABANI AKIŞI                       │
│                                                                        │
│   [Kullanıcı/Test Talebi] ───► Yaş: 12–36 Ay | Davranış: D01..D10      │
│                                           │                            │
│                                           ▼                            │
│                              [retriever.js: Filtreleme]                │
│                                           │                            │
│                  ┌────────────────────────┴───────────────────────┐    │
│                  ▼                                                ▼    │
│    Kol B (Kural Enjeksiyonu)                        Kol C (Full Context)│
│  - Yalnız ilgili yaş bandı                         - Tüm 10 kart       │
│  - Yalnız seçili risk profili                      - Tüm referanslar   │
│  - Negatif ölçüt sızdırmaz                         - 3 yaş bandı       │
│                  │                                                │    │
│                  └────────────────────────┬───────────────────────┘    │
│                                           ▼                            │
│                              [Google Gemini 2.5 / Veo]                 │
│                                           │                            │
│                                           ▼                            │
│                        26 Sahneli Klinik Eğitim Senaryosu              │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Kanonik Klinik Referans Kütüphanesi (14 Temel Kaynak)

Aşağıdaki 14 kaynak, bilgi tabanımızın kuramsal ve ampirik omurgasını oluşturur:

| Ref ID | Kaynak / Ölçek Adı | Yazarlar & Künye | Projedeki Klinik Rolü ve İşlevi | İlgili Davranışlar |
|---|---|---|---|---|
| **REF-01** | **ADOS-2** *(Autism Diagnostic Observation Schedule - 2nd Edition)* | Lord, C., Rutter, M., DiLavore, P.C., Risi, S., Gotham, K., Bishop, S. (2012). WPS. | Doğrudan klinisyen gözlemine dayalı altın standart tanı aracı. Modül 1 maddeleri: B6 (İsme yanıt), B11 (Ortak dikkat), B7/A7 (İşaretle isteme), C1/C2 (Sembolik/hayali oyun), B9 (Gösterme), B2 (Sosyal gülümseme). *(12–30 ay için Toddler Modülü, 31+ ay için Modül 1 esastır).* | D01, D02, D03, D04, D05, D07 |
| **REF-02** | **STAT** *(Screening Tool for Autism in Toddlers and Young Children)* | Stone, W.L., Coonrod, E.E., Ousley, O.Y. (2000); Stone, W.L. et al. (2004). Vanderbilt University. | 24–36 ay için tasarlanmış 12 görevlik interaktif tarama aracı: Oyun (G1-2), İsteme (G3-4), Dikkat Yönlendirme (G5-8), Motor Taklit (G9-12). | D02, D03, D04, D06 |
| **REF-03** | **AOSI** *(Autism Observational Scale for Infants)* | Bryson, S.E., Zwaigenbaum, L., McDermott, C. et al. (2008). *JADD*. | 12–18 ay bebeklerde sese yönelme, görsel takip ve erken atipik ipuçlarını doğrudan gözlemleyen klinisyen ölçeği. | D01, D02 |
| **REF-04** | **Bayley-4** *(Bayley Scales of Infant and Toddler Development - 4th Ed.)* | Bayley, N., Aylward, G.P. (2019). NCS Pearson. | Bilişsel, alıcı dil ve ince motor basamak normları. Jestsiz yönerge (D08), kutuya koyma (D09) ve karalama (D10) gelişim normlarının temeli. | D08, D09, D10 |
| **REF-05** | **M-CHAT-R/F** *(Modified Checklist for Autism in Toddlers with Follow-Up)* | Robins, D.L., Fein, D., Barton, M.L. (2009; *Pediatrics* 2014). | 16–30 ay erken otizm risk taraması. Ebeveyn bildirim maddeleri: M1 (İşarete bakma), M3 (Mış gibi oyun), M6 (İşaretle isteme), M9 (Gösterme), M10 (İsme tepki), M11 (Gülümseme), M15 (Taklit), M18 (Sözel yönerge). | D01, D02, D03, D04, D05, D06, D07, D08 |
| **REF-06** | **Mundy ESCS** *(Early Social Communication Scales)* | Mundy, P., Delgado, C., Block, J., Venezia, M. et al. (2003, 2007). | Ortak dikkatin iki ekseni: **RJA** (Responded Joint Attention / İşarete tepki - D02) ve **IJA** (Initiated Joint Attention / Gösterme/ortak dikkat başlatma - D05). | D02, D05 |
| **REF-07** | **Denver II Türk Standardizasyonu** | Frankenburg, W.K. et al. (1992); Yalaz, K., Anlar, B. (Hacettepe Üniversitesi). | Türk çocuklarında kişisel-sosyal, dil ve ince motor basamaklarının yüzdelik gelişim persentilleri. | D01, D08, D09, D10 |
| **REF-08** | **M-CHAT Türkiye Uyarlaması** | Kara, B., Mukaddes, N.M., Altınkaya, İ., Güntepe, D., Gökçay, G., Özmen, M. (2014). *Autism*, 18(3), 331–338. | Sağlam çocuk polikliniğinde Türkçe M-CHAT ile erken otizm taraması validasyonu. | D01, D02, D03, D05, D07 |
| **REF-09** | **DSM-5-TR** *(Diagnostic and Statistical Manual of Mental Disorders)* | American Psychiatric Association (APA, 2022). | OSB tanı ölçütleri: Kriter A1 (Sosyal-duygusal karşılıklılık), Kriter A2 (Sözel olmayan iletişimsel davranışlar), Kriter A3 (İlişki geliştirme ve hayali oyun). | D01, D02, D03, D04, D05, D07 |
| **REF-10** | **CDC Developmental Milestones** | CDC & American Academy of Pediatrics (AAP, 2022 revizyonu). | 12, 18, 24 ve 30 ay çocuk gelişim basamakları ve aile takip göstergeleri. | D01, D03, D05, D08, D09, D10 |
| **REF-11** | **Leslie Sembolik Oyun Kuramı** | Leslie, A.M. (1987). *Psychological Review*, 94(4), 412–426. | D04 mış gibi yapma davranışının zihinsel mekanizması (birincil temsilden ayrıştırma / decoupling). | D04 |
| **REF-12** | **Tomasello İletişimsel Niyet Teorisi** | Tomasello, M. (1995). *Joint attention as social cognition*. Lawrence Erlbaum. | D05 nesne gösterme davranışının deklaratif ortak dikkat başlatma işlevi. | D05 |
| **REF-13** | **Rogers & Pennington Erken Taklit Modeli** | Rogers, S.J., Pennington, B.F. (1991). *Dev & Psychopathol*, 3(2), 137–162. | D06 motor taklidin sosyal karşılıklılık ve ben-öteki ayrımındaki gelişimsel rolü. | D06 |
| **REF-14** | **Gesell İnce Motor Normları** | Gesell, A. (1940). *The First Five Years of Life*. Harper & Brothers. | D10 kendiliğinden karalama ve erken kalem kavrama motor gelişim evreleri. | D10 |

---

## 3. Ontoloji Eşleme Matrisi (ONT-01..13 ➔ D01..D10)

Mobil uygulama ve video analiz servisindeki ontoloji kodları (`ONT-xx`) ile kanonik davranış kartları (`Dxx`) arasındaki eşleme aşağıdaki gibidir:

| Ontoloji Kodu | Hedef Davranış Kodu | Davranış Başlığı (Türkçe / İngilizce) | Eşleme Gerekçesi ve Kapsamı | Zaman Sınırı Var mı? |
|---|---|---|---|---|
| **ONT-01** | **D01** | İsme Tepki Verme *(Response to Name)* | Doğrudan eşleşme. Sesli çağrıya yönelme. | **EVET** (Gecikmeli) |
| **ONT-02** | **D02** | Yetişkinin İşaretine Yönelme (Yakın Hedef) | Ortak dikkat tepkisi (RJA). Yakın masadaki nesneye yönelme. | **EVET** (Gecikmeli) |
| **ONT-03** | **D05** | Nesne Gösterme (Görsel Paylaşım) | İlgiyi paylaşmak için oyuncağı kaldırma (IJA). | **HAYIR** (Niteliksel) |
| **ONT-04** | **D02** | Yetişkinin İşaretine Yönelme (Uzak Hedef) | Ortak dikkat tepkisi (RJA). Odadaki uzak hedefe yönelme. | **EVET** (Gecikmeli) |
| **ONT-05** | **D03** | İstemek İçin İşaret (Nesne Odaklı) | Ulaşamadığı oyuncağı izole parmakla isteme (Imperative). | **HAYIR** (Niteliksel) |
| **ONT-06** | **D03** | İstemek İçin İşaret (Yetişkin Odaklı) | Yetişkine bakarak nesneyi işaret etme. | **HAYIR** (Niteliksel) |
| **ONT-07** | **D05** | Nesne Gösterme (Sosyal Paylaşım) | Yetişkinin gözüne bakarak oyuncağı gösterme (IJA). | **HAYIR** (Niteliksel) |
| **ONT-08** | **D07** | Gülümsemeye Karşılık Verme *(Reciprocal Smile)* | Yetişkin tebessümüne sosyal gülümsemeyle yanıt verme. | **EVET** (Gecikmeli) |
| **ONT-09** | **D04** | Mış Gibi Hayali Oyun *(Pretend Play)* | Boş fincanla içirme, bebeği besleme, sembolik oyun. | **HAYIR** (Niteliksel) |
| **ONT-10** | **D06** | Basit Motor Taklit *(Motor Imitation)* | El çırpma, bay-bay yapma veya nesne taklidi. | **HAYIR** (Niteliksel) |
| **ONT-11** | **D08** | Sözel Yönergeyi Yerine Getirme *(Verbal Instruction)* | Jest/işaret olmadan tek basamaklı komutu anlama. | **EVET** (Gecikmeli) |
| **ONT-12** | **D09** | Nesneyi Kaba Yerleştirme *(Object Placement)* | Bloğu kutunun içine amaca uygun bırakma. | **HAYIR** (Niteliksel) |
| **ONT-13** | **D10** | Kalemle Kendiliğinden Karalama *(Spontaneous Scribbling)* | Pastel boyayla kâğıt üzerinde çizgiler oluşturma. | **HAYIR** (Niteliksel) |

---

## 4. Yaş Bantları ve Klinik Ölçütler Mimarisi

Bilgi tabanımız çocuk gelişimini 3 homojen klinik yaş bandına ayırır:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ YAŞ BANDI 1: 12–18 AY (Erken Oryantasyon & Temel Ortak Dikkat)                         │
│ • Klinik Odak: Sese oryantasyon, basit isme yönelme, ilkel motor taklit, nesne keşfi.   │
│ • Simülasyon Tipik Gecikme: ≤ 2.0 saniye (en fazla 2 çağrı hakkı tanınır)              │
│ • Simülasyon Atipik Gecikme: ≥ 3.0 saniye gecikme veya hiç yönelmeme                   │
│ • Sınırda (Gri Bölge): 2.0 s – 3.0 s arası gecikmeli / tereddütlü yanıt                │
│ • Temel Referanslar: AOSI (Bryson 2008), ADOS-2 Toddler, Bayley-4, CDC                 │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ YAŞ BANDI 2: 18–24 AY (Kritik Tarama Penceresi & Sosyal Paylaşım)                      │
│ • Klinik Odak: Doğrudan göz temasıyla isme yönelme, izole işaret parmağı, gösterme.   │
│ • Simülasyon Tipik Gecikme: ≤ 1.8 saniye (doğrudan göz teması kilidi)                  │
│ • Simülasyon Atipik Gecikme: ≥ 2.5 saniye gecikme, tünel bakışı veya hand-leading       │
│ • Sınırda (Gri Bölge): 1.8 s – 2.5 s arası gecikmeli / tereddütlü yanıt                │
│ • Temel Referanslar: M-CHAT-R/F (Robins 2014), Kara et al. (2014), Mundy ESCS          │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ YAŞ BANDI 3: 24–36 AY (İleri Sosyal Karşılıklılık & Çok Basamaklı Sembolik Oyun)       │
│ • Klinik Odak: Çok basamaklı sembolik oyun (bebeğe içirme), jestsiz sözel yönerge,    │
│   3 noktalı ortak dikkat döngüsü (Yetişkin ➔ Nesne ➔ Yetişkin).                       │
│ • Simülasyon Tipik Gecikme: ≤ 1.5 saniye + sözel/jestsel karşılık ('efendim', tebessüm)│
│ • Simülasyon Atipik Gecikme: ≥ 2.5 saniye gecikme veya sembolik oyun yokluğu           │
│ • Sınırda (Gri Bölge): 1.5 s – 2.5 s arası gecikmeli yanıt                             │
│ • Temel Referanslar: ADOS-2 Modül 1, STAT (Stone 2004), Bayley-4 (24-36m), DSM-5-TR    │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Davranış Kartları Detay Kataloğu (D01 – D10)

### D01: İsme Tepki Verme (Response to Name)
* **Klinik Kaynaklar:** REF-01 (ADOS-2 B6), REF-03 (AOSI), REF-05 (M-CHAT-R/F M10), REF-08 (Kara 2014)
* **DSM-5-TR Tanı Eşleşmesi:** Kriter A1 (Sosyal-duygusal karşılıklılık)
* **Zaman Duyarlılığı:** **EVET** (`hasLatencyThreshold: true`, Referans: Son çağrının başlangıcı)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: En fazla 2 doğal çağrıda ≤ 2.0 sn içinde yetişkine yönelir. Atipik: 2 çağrıya rağmen ≥ 3.0 sn boyunca yönelmez. Sınırda: 1. çağrıda tepki vermez, 2. çağrıda 2.0–3.0 sn arasında döner.
  * **18–24 Ay:** Tipik: Tek doğal çağrıda ≤ 1.8 sn içinde göz teması kurar. Atipik: ≥ 2.5 sn boyunca başını çevirmez, oyuncağa kilitli kalır. Sınırda: 1.8–2.5 sn arasında gecikmeyle döner.
  * **24–36 Ay:** Tipik: Tek çağrıda ≤ 1.5 sn içinde yönelir ve sözel/jestsel karşılık verir ('efendim', gülümseme). Atipik: ≥ 2.5 sn boyunca çağrıyı tamamen duymazdan gelir. Sınırda: 1.5–2.5 sn arasında döner fakat sözel/jestsel karşılık eklemez.
* **Geçersizlik Şartları:** Çağrı duyulamazsa; çocuk çağrıdan önce zaten dönükse; çağrıyla eşzamanlı dokunulmuşsa.

### D02: Yetişkinin İşaret Ettiği Hedefe Yönelme (Responding to Joint Attention)
* **Klinik Kaynaklar:** REF-01 (ADOS-2 B11), REF-02 (STAT Görev 5-8), REF-05 (M-CHAT M1), REF-06 (Mundy RJA)
* **DSM-5-TR Tanı Eşleşmesi:** Kriter A2 (Sözel olmayan iletişimsel davranışlar)
* **Zaman Duyarlılığı:** **EVET** (`hasLatencyThreshold: true`)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: İşaret edilen yakın hedefe ≤ 2.0 sn içinde başını çevirir. Atipik: ≥ 3.0 sn boyunca hedefe bakmaz, yetişkinin parmak ucuna bakar. Sınırda: 2.0–3.0 sn arasında bakar.
  * **18–24 Ay:** Tipik: ≤ 1.8 sn içinde hem yakın hem uzak hedefe bakar. Atipik: ≥ 2.5 sn boyunca yönelmez. Sınırda: 1.8–2.5 sn arasında yönelir.
  * **24–36 Ay:** Tipik: ≤ 1.5 sn içinde hedefe bakar ve 3 noktalı döngüyü tamamlar (Yetişkin ➔ Nesne ➔ Yetişkin). Atipik: ≥ 2.5 sn boyunca bakmaz veya baksa bile yetişkinle bakış koordinasyonu kurmaz. Sınırda: 1.5–2.5 sn arasında bakar fakat yetişkine geri dönmez.

### D03: İstemek İçin İşaret Etme (Imperative Pointing)
* **Klinik Kaynaklar:** REF-01 (ADOS-2 B7/A7), REF-02 (STAT Görev 3-4), REF-05 (M-CHAT M6), REF-08
* **DSM-5-TR Tanı Eşleşmesi:** Kriter A2 (Sözel olmayan iletişimsel davranışlar)
* **Zaman Duyarlılığı:** **HAYIR** (Niteliksel gözlem)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: Ulaşamadığı nesneye tüm eliyle uzanır veya ilkel işaret eder, yetişkine bakar. Atipik: Yetişkinin elini alet gibi çeker (hand-leading) veya öfke nöbeti geçirir. Sınırda: Uzanır fakat yetişkinle göz teması kurmaz.
  * **18–24 Ay:** Tipik: İzole işaret parmağını uzatır ve eşzamanlı yetişkine bakar. Atipik: Hand-leading yapar. Sınırda: Bütün eliyle gösterir, izole parmak ayrışmamıştır.
  * **24–36 Ay:** Tipik: İzole işaret parmağıyla gösterirken kelime/ses ekler ('ver', 'araba'). Atipik: Hand-leading yapar veya ağlar. Sınırda: İşaret eder fakat sözel ifade eklemez.

### D04: Hayali Oyun — Mış Gibi Yapma (Pretend Play)
* **Klinik Kaynaklar:** REF-01 (ADOS-2 C1/C2), REF-02 (STAT Görev 1-2), REF-05 (M-CHAT M3), REF-11 (Leslie 1987)
* **DSM-5-TR Tanı Eşleşmesi:** Kriter A3 (İlişkileri geliştirme ve hayali oyun)
* **Zaman Duyarlılığı:** **HAYIR** (Niteliksel sembolik eylem)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: Boş fincanı kendi ağzına götürür (işlevsel taklit). Atipik: Fincanı yalnızca yere vurur, fırlatır veya ağzına alıp çiğner. Sınırda: Fincanı elinde tutar fakat işlevsel hareket yapmaz.
  * **18–24 Ay:** Tipik: Boş fincanla oyuncak bebeğe su içirir (tek basamaklı sembolik eylem). Atipik: Nesneyle sembolik bağ kurmaz; tekerlek döndürür veya sıraya dizer. Sınırda: Fincanı bebeğe yaklaştırır fakat içirme eylemini tamamlamaz.
  * **24–36 Ay:** Tipik: Çok basamaklı sembolik oyun sergiler (bebeğe içirir, tabağı karıştırır, bebeği uyutur). Atipik: Sembolik oyun hiç görülmez; nesneleri fırlatır. Sınırda: Tek basamaklı içirme yapar fakat ikinci basamağa geçemez.

### D05: Paylaşmak İçin Nesneyi Gösterme (Showing / Initiating Joint Attention)
* **Klinik Kaynaklar:** REF-01 (ADOS-2 B9), REF-05 (M-CHAT M9), REF-06 (Mundy IJA), REF-12 (Tomasello 1995)
* **DSM-5-TR Tanı Eşleşmesi:** Kriter A2 (Ortak dikkat başlatma / Sosyal paylaşım)
* **Zaman Duyarlılığı:** **HAYIR** (Niteliksel bildirimsel eylem)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: Oyuncağı yetişkine doğru uzatır ve bakar. Atipik: Oyuncağı kendi bedenine saklar veya hiç yönelmez. Sınırda: Uzatır fakat yetişkine bakmaz.
  * **18–24 Ay:** Tipik: Oyuncağı yetişkinin göz hizasına kaldırır, gülümser ve göz teması kurar. Atipik: Gösterme davranışı hiç görülmez. Sınırda: Gösterir fakat göz teması kurmaz.
  * **24–36 Ay:** Tipik: Oyuncağı gösterirken sözel paylaşım ('bak', 'araba') ve ortak sevinç sergiler. Atipik: İlgiyi paylaşma davranışı yoktur. Sınırda: Gösterir fakat sözel ifade veya duygulanım paylaşımı sınırlıdır.

### D06: Basit Motor Hareketi Taklit Etme (Motor Imitation)
* **Klinik Kaynaklar:** REF-02 (STAT Görev 9-12), REF-05 (M-CHAT M15), REF-13 (Rogers & Pennington 1991)
* **DSM-5-TR Tanı Eşleşmesi:** Kriter A1/A2 ile ilişkili (Sosyal öğrenme ve karşılıklılık)
* **Zaman Duyarlılığı:** **HAYIR** (Gözlem penceresi içinde eylem varlığı)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: Yetişkinin el çırpmasını ilkel biçimde taklit eder. Atipik: Hareketi tamamen görmezden gelir, hiçbir taklit girişimi olmaz. Sınırda: Bir elini diğerine sürter fakat tam çırpamaz.
  * **18–24 Ay:** Tipik: El çırpma veya bay-bay hareketini gecikmesiz ve neşeyle taklit eder. Atipik: Yetişkinin modelini yok sayar. Sınırda: Hareketi yapar fakat heves ve sosyal temas zayıftır.
  * **24–36 Ay:** Tipik: Hareketi gecikmesiz taklit eder ve gülümseyerek ortak etkileşim kurar. Atipik: Modeli tamamen görmezden gelir. Sınırda: Taklit eder fakat hareket zayıf ve tereddütlüdür.

### D07: Gülümsemeye Karşılık Verme (Reciprocal Social Smile)
* **Klinik Kaynaklar:** REF-01 (ADOS-2 B2), REF-05 (M-CHAT M11), REF-08 (Kara 2014)
* **DSM-5-TR Tanı Eşleşmesi:** Kriter A1 (Sosyal-duygusal karşılıklılık)
* **Zaman Duyarlılığı:** **EVET** (`hasLatencyThreshold: true`)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: Yetişkin gülümsedikten sonra ≤ 2.0 sn içinde tebessümle karşılık verir. Atipik: ≥ 3.0 sn boyunca ifadesiz kalır. Sınırda: 2.0–3.0 sn arasında silik bir tebessüm gösterir.
  * **18–24 Ay:** Tipik: ≤ 1.8 sn içinde canlı bir tebessüm ve göz temasıyla karşılık verir. Atipik: ≥ 2.5 sn boyunca duygulanım donukluğu sergiler. Sınırda: 1.8–2.5 sn arasında gecikmeyle gülümser.
  * **24–36 Ay:** Tipik: ≤ 1.5 sn içinde tebessümle karşılık verir ve duygulanımını senkronize eder. Atipik: ≥ 2.5 sn boyunca sosyal gülümseme yoksunluğu sergiler. Sınırda: 1.5–2.5 sn arasında tebessüm eder fakat duygulanım paylaşımı sınırlıdır.

### D08: Jestsiz Tek Basamaklı Sözel Yönergeyi Yerine Getirme (Receptive Language)
* **Klinik Kaynaklar:** REF-04 (Bayley-4 Alıcı Dil), REF-05 (M-CHAT M18), REF-07 (Denver II)
* **DSM-5-TR Tanı Eşleşmesi:** Eşlik eden dil bozukluğu / Kriter A2
* **Zaman Duyarlılığı:** **EVET** (`hasLatencyThreshold: true`)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: 'Topu ver' komutunda komutu tanır ve nesneye yönelir. Atipik: Sözel komuta hiçbir tepki vermez. Sınırda: Komuttan sonra nesneye bakar fakat harekete geçmez.
  * **18–24 Ay:** Tipik: ≤ 1.8 sn içinde nesneyi alıp yetişkine uzatır. Atipik: ≥ 2.5 sn boyunca komuta duyarsız kalır. Sınırda: 1.8–2.5 sn arasında yönergeyi gecikmeli tamamlar.
  * **24–36 Ay:** Tipik: ≤ 1.5 sn içinde arabayı alıp yetişkine teslim eder. Atipik: ≥ 2.5 sn boyunca yönergeyi tamamen görmezden gelir. Sınırda: 1.5–2.5 sn arasında teslim eder fakat komutun hemen ardından duraksar.

### D09: Nesneyi Bir Kaba Yerleştirme (Object Placement)
* **Klinik Kaynaklar:** REF-04 (Bayley-4 İnce Motor), REF-07 (Denver II), REF-10 (CDC)
* **DSM-5-TR Tanı Eşleşmesi:** Gelişimsel düzey belirteci (Tanı kriteri değildir, motor normdur)
* **Zaman Duyarlılığı:** **HAYIR** (`hasLatencyThreshold: false`)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: Bloğu açık kutunun içine kendiliğinden bırakır. Atipik: Nesneyi kutuya bırakamaz; yalnızca masaya vurur. Sınırda: Bloğu kutunun kenarına sürter, bırakmakta zorlanır.
  * **18–24 Ay:** Tipik: Bloğu amaca uygun biçimde kutunun içine atar. Atipik: Bloğu ağzına alır veya kutuyu devirir. Sınırda: Yönergeden sonra tereddütle bırakır.
  * **24–36 Ay:** Tipik: Amaca uygun yerleştirir, kapağı kapatır veya sıralı dizer. Atipik: Stereotipik tekrarlarla bloğu fırlatır. Sınırda: Kutuya atar fakat sıralı yerleştirme yapmaz.

### D10: Kalemle Kendiliğinden Karalama Yapma (Spontaneous Scribbling)
* **Klinik Kaynaklar:** REF-04 (Bayley-4 İnce Motor), REF-07 (Denver II), REF-14 (Gesell 1940)
* **DSM-5-TR Tanı Eşleşmesi:** Gelişimsel düzey belirteci (Tanı kriteri değildir, motor normdur)
* **Zaman Duyarlılığı:** **HAYIR** (`hasLatencyThreshold: false`)
* **Yaş Ölçütleri:**
  * **12–18 Ay:** Tipik: Pastel boyayı kavrar ve kâğıt üzerine rastgele izler bırakır. Atipik: Boyayı yalnızca ağzına götürür veya masaya fırlatır. Sınırda: Boyayı kâğıda dokundurur fakat çizgi oluşturmaz.
  * **18–24 Ay:** Tipik: Kendiliğinden ileri-geri karalamalar yapar. Atipik: Kâğıt yerine boyayı duvara vurur veya çiğner. Sınırda: Yalnızca tek bir nokta koyup bırakır.
  * **24–36 Ay:** Tipik: Kâğıt sınırları içinde kalarak sürekli ve yönlü karalamalar yapar. Atipik: Masaya vurur veya kâğıdı yırtar. Sınırda: Çizer fakat kâğıdın dışına taşırır veya hızla ilgisini kaybeder.

---

## 6. RAG Deney Mimarisi ve Karşılaştırma Kolları (Benchmark A/B/C)

Platform, yapay zekanın klinik doğruluk başarısını test etmek için 3 deney kolu barındırır:

```
┌─────────────┬─────────────────────────────────┬────────────────────────────────────────────────────────┐
│ Kol Adı     │ Deney Modu                      │ Modele Gönderilen Bağlam Metni                         │
├─────────────┼─────────────────────────────────┼────────────────────────────────────────────────────────┤
│ **KOL A**   │ **Temel Model (Baseline)**      │ Yalnızca davranış adı, yaş ve çocuğun adı.             │
│             │                                 │ Klinik kural veya saniye eşiği verilmez.               │
├─────────────┼─────────────────────────────────┼────────────────────────────────────────────────────────┤
│ **KOL B**   │ **Seçici RAG (Rule Injection)** │ Hedef yaşa ve profile duyarlı kural enjeksiyonu.       │
│             │ *(Önerilen Üretim Mimarisi)*    │ Negatif kriter sızdırılmaz; token tasarrufludur.       │
├─────────────┼─────────────────────────────────┼────────────────────────────────────────────────────────┤
│ **KOL C**   │ **Tam Bilgi Tabanı (Full-Ctx)** │ Tüm 10 kart, 3 yaş bandı ve referans listesi bütünüyle │
│             │                                 │ modele verilir (Yüksek token tüketimi).                │
└─────────────┴─────────────────────────────────┴────────────────────────────────────────────────────────┘
```

### Otomatik Benchmark Koşucusu
* **Dosya:** `backend/run_benchmark_experiment.js`
* **Vaka Sayısı:** 10 Temsili Vaka (V01–V10, 12–36 ay)
* **Ölçülen Metrikler:**
  1. **API Gecikmesi (Latency):** Yanıt alma süresi (ms).
  2. **FSM Süreklilik Oranı:** Ardışık 26 sahne arasındaki durum sürekliliği (`fsmMatchRate`).
  3. **$\Delta t$ Eşik Uyumu:** Modelin atadığı `latencySeconds` sürelerinin klinik kurala uyumu (`deltaTCompliant`).
  4. **Kayıt Yeri:** `backend/logs/model_benchmarks.jsonl`

---

## 7. Akademik Sınırlılıklar ve Savunma Kılavuzu (Limitations)

Tez veya jüri savunmasında sistemin bilimsel sınırlarını dürüstçe açıklamak en önemli akademik erdemdir:

1. **Tanı Aracı Değildir:** Bu platform klinisyen yerine geçip tıbbi tanı koymaz. Erken farkındalık oluşturma, aile eğitimi ve araştırmacılara standart veri sağlama amaçlı bir simülasyon sistemidir.
2. **Saniye Eşikleri Simülasyon Parametresidir:** ADOS-2 ve STAT gibi altın standart klinik ölçekler sayısal kronometre süreleri yerine kategorik puanlama (0, 1, 2) kullanır. Bilgi tabanımızdaki 1.5 sn, 1.8 sn, 2.0 sn gibi eşikler, video simülasyonunun ve FSM motorunun işletilebilmesi için **uzman tanımlı simülasyon tasarım parametreleridir**.
3. **STAT Yaş Uyarlaması:** STAT orijinal literatürde 24–35 ay için valide edilmiştir. Bilgi tabanımızdaki 24–36 ay aralığı bu ölçekle tam örtüşürken; 12–18 ve 18–24 ay alt gruplarındaki görevler keşfedici uyarlama niteliğindedir.
4. **ADOS-2 Modül Sınırı:** ADOS-2'de 12–30 ay için Toddler Modülü, 31+ ay için Modül 1 kullanılır. Dokümandaki madde kodları Modül 1 odaklı olup Toddler Modülü ile madde numarası farkları bulunabilir.

---

## 8. İlgili Sistem Dosyaları

* **JSON Bilgi Tabanı:** [`backend/rag/clinical_knowledge_base.json`](file:///c:/Users/hasan/OneDrive/Belgeler/GitHub/psikolojiksel/backend/rag/clinical_knowledge_base.json)
* **RAG Motoru ve Filtresi:** [`backend/rag/retriever.js`](file:///c:/Users/hasan/OneDrive/Belgeler/GitHub/psikolojiksel/backend/rag/retriever.js)
* **Klinik Dayanaklar Raporu:** [`backend/rag/RAG_KAYNAK_VE_KLINIK_DAYANAKLAR.md`](file:///c:/Users/hasan/OneDrive/Belgeler/GitHub/psikolojiksel/backend/rag/RAG_KAYNAK_VE_KLINIK_DAYANAKLAR.md)
* **Sunucu Entegrasyonu:** [`backend/server.js`](file:///c:/Users/hasan/OneDrive/Belgeler/GitHub/psikolojiksel/backend/server.js)
* **Benchmark Servisi:** [`backend/services/benchmark_service.js`](file:///c:/Users/hasan/OneDrive/Belgeler/GitHub/psikolojiksel/backend/services/benchmark_service.js)
* **Doğrulama Testleri:** [`backend/test/rag_retriever.test.js`](file:///c:/Users/hasan/OneDrive/Belgeler/GitHub/psikolojiksel/backend/test/rag_retriever.test.js)

---

## 9. Kaynakça (Akademik Referanslar — APA 7th Edition)

### A. Uluslararası Altın Standart Tanı ve Tarama Ölçekleri
1. **Lord, C., Rutter, M., DiLavore, P. C., Risi, S., Gotham, K., & Bishop, S. (2012).** *Autism Diagnostic Observation Schedule, Second Edition (ADOS-2) Manual (Part I): Modules 1–4*. Torrance, CA: Western Psychological Services (WPS).
2. **Stone, W. L., Coonrod, E. E., & Ousley, O. Y. (2000).** Screening Tool for Autism in Two-Year-Olds (STAT): Development and preliminary data. *Journal of Autism and Developmental Disorders*, 30(6), 607–612. https://doi.org/10.1023/A:1005647629002
3. **Stone, W. L., Coonrod, E. E., Turner, L. M., & Pozdol, S. L. (2004).** Psychometric properties of the STAT for early autism screening. *Journal of Autism and Developmental Disorders*, 34(6), 691–701. https://doi.org/10.1007/s10803-004-5289-8
4. **Bryson, S. E., Zwaigenbaum, L., McDermott, C., Rombough, V., & Brian, J. (2008).** The Autism Observation Scale for Infants: Scale development and reliability data. *Journal of Autism and Developmental Disorders*, 38(4), 731–738. https://doi.org/10.1007/s10803-007-0440-7
5. **Bayley, N., & Aylward, G. P. (2019).** *Bayley Scales of Infant and Toddler Development – Fourth Edition (Bayley-4)*. Bloomington, MN: NCS Pearson.
6. **Robins, D. L., Casagrande, K., Barton, M., Chen, C. M. A., Dumont-Mathieu, T., & Fein, D. (2014).** Validation of the Modified Checklist for Autism in Toddlers, Revised with Follow-up (M-CHAT-R/F). *Pediatrics*, 133(1), 37–45. https://doi.org/10.1542/peds.2013-1813
7. **Frankenburg, W. K., Dodds, J., Archer, P., Shapiro, H., & Bresnick, B. (1992).** The DENVER II: A major revision and restandardization of the Denver Developmental Screening Test. *Pediatrics*, 89(1), 91–97. https://doi.org/10.1542/peds.89.1.91

### B. Türkiye Uyarlama ve Geçerlik Çalışmaları
8. **Kara, B., Mukaddes, N. M., Altınkaya, İ., Güntepe, D., Gökçay, G., & Özmen, M. (2014).** Using the Modified Checklist for Autism in Toddlers in a well-child clinic in Turkey: An autism screening study. *Autism*, 18(3), 331–338. https://doi.org/10.1177/1362361312467705
9. **Anlar, B., & Yalaz, K. (1996).** *Denver II Gelişimsel Tarama Testi Türk Çocuklarına Uyarlanması ve Standardizasyonu*. Ankara: Hacettepe Çocuk Sağlığı Derneği Yayınları.

### C. Kuramsal Bilişsel ve Nörogelişimsel Modeller
10. **Mundy, P., Delgado, C., Block, J., Venezia, M., Hogan, A., & Seibert, J. (2003, 2007).** *A Manual for the Early Social Communication Scales (ESCS)*. Coral Gables, FL: Department of Psychology, University of Miami.
11. **Mundy, P., & Newell, L. (2007).** Attention, joint attention, and social cognition. *Current Directions in Psychological Science*, 16(5), 269–274. https://doi.org/10.1111/j.1467-8721.2007.00518.x
12. **Leslie, A. M. (1987).** Pretense and representation: The origins of "theory of mind". *Psychological Review*, 94(4), 412–426. https://doi.org/10.1037/0033-295X.94.4.412
13. **Tomasello, M. (1995).** Joint attention as social cognition. In C. Moore & P. J. Dunham (Eds.), *Joint attention: Its origins and role in development* (pp. 103–130). Hillsdale, NJ: Lawrence Erlbaum Associates.
14. **Rogers, S. J., & Pennington, B. F. (1991).** A theoretical approach to the deficits in infantile autism. *Development and Psychopathology*, 3(2), 137–162. https://doi.org/10.1017/S0954579400000043
15. **Gesell, A. (1940).** *The first five years of life: A guide to the study of the preschool child*. New York, NY: Harper & Brothers.

### D. Klinik Tanı Kılavuzları ve Gelişim Standartları
16. **American Psychiatric Association. (2022).** *Diagnostic and statistical manual of mental disorders* (5th ed., text rev.; DSM-5-TR). Washington, DC: American Psychiatric Association. https://doi.org/10.1176/appi.books.9780890425787
17. **Centers for Disease Control and Prevention, & American Academy of Pediatrics. (2022).** *Learn the Signs. Act Early: Milestone Moments*. Atlanta, GA: U.S. Department of Health and Human Services, CDC. https://www.cdc.gov/ncbddd/actearly/

### E. Yapay Zeka, RAG ve Sentetik Simülasyon Referansları
18. **Lewis, P., Perez, E., Piktus, A., Petroni, F., Karpukhin, V., Goyal, N., Küttler, H., Lewis, M., Yih, W., Rocktäschel, T., Riedel, S., & Kiela, D. (2020).** Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks. *Advances in Neural Information Processing Systems (NeurIPS 2020)*, 33, 9459–9474.
19. **Vaswani, A., Shazeer, N., Parmar, N., Uszkoreit, J., Jones, L., Gomez, A. N., Kaiser, Ł., & Polosukhin, I. (2017).** Attention is all you need. *Advances in Neural Information Processing Systems (NeurIPS 2017)*, 30, 5998–6008.
