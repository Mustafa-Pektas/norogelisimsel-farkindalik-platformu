# Nörogelişimsel Farkındalık Platformu — RAG Klinik Bilgi Tabanı ve Akademik Dayanaklar Raporu

**Hedef Yaş Grupları:** 12–18 Ay · 18–24 Ay · 24–36 Ay  
**Kapsam:** RAG (Retrieval-Augmented Generation) Bilgi Tabanı Kaynak Netleştirmesi, Yaşa Duyarlı Ölçütler ve Akademik Kanıt Matrisi  

---

## 1. Metodolojik Çerçeve ve Simülasyon Tanımları

Bu doküman, **Nörogelişimsel Farkındalık Platformu** bünyesindeki RAG (Retrieval-Augmented Generation) mekanizmasının kullandığı kuralları, eşikleri ve gözlem ölçütlerini **uluslararası altın standart klinik tanı/tarama ölçekleri** ve **nörogelişimsel literatür** ile netleştirmek amacıyla hazırlanmıştır.

### Yasal ve Etik Kapsam Bildirimi (Scope Notice)
> **ÖNEMLİ BİLGİLENDİRME:**  
> Bu bilgi tabanı ve RAG mekanizması; eğitim, araştırma, simülasyon ve yapay zeka video analiz kurallarının doğrulanması amacıyla yapılandırılmıştır. Klinik bir tanı aracı, tıbbi cihaz veya resmi tanısal puanlama sistemi değildir.  
> Ölçeklerde (ADOS-2, STAT, AOSI) yer alan maddeler klinisyenin doğrudan yarı-yapılandırılmış gözlemine dayanırken; bilgi tabanımızdaki sayısal saniye eşikleri video analizi ve Sonlu Durum Makinesi (FSM) senaryo simülasyonu için **uzman tanımlı ve kalibrasyon bekleyen operasyonel simülasyon parametreleridir**.

### Temel Kavramlar ve Ölçüm Referansları
1. **Tepki Gecikmesi Referans Noktası:**  
   `latencySeconds` (tepki gecikmesi), tepkiyi tetikleyen son çağrının veya yetişkin uyaranının başlangıcından çocuğun ilk yönelim hareketine kadar geçen süre olarak ölçülür. 10 saniyelik gözlem penceresi ilk çağrıyla başlar.
2. **Vaka Düzeyi Risk ile Hedef Davranış Sonucu Ayrımı:**  
   Klinik taramalarda genel riski yüksek olan bir çocuk kimi alanlarda (örneğin nesne yerleştirme D09) tipik performans sergileyebilir. Simülasyon motorumuzdaki `riskProfile` (hedef davranış çıktısı) parametresi, o test vakasında üretilecek veya sınanacak spesifik davranış sonucunu (`TİPİK`, `ATİPİK` veya `SINIRDA`) operasyonel olarak belirler.

---

## 2. Klinik ve Bilimsel Kaynak Havuzu

| Kaynak Kodu | Kaynak Adı / Ölçek | Yazarlar & Künye | Projedeki Yeri ve İşlevi |
|---|---|---|---|
| **REF-01** | **ADOS-2 (Autism Diagnostic Observation Schedule - 2nd Ed.)** | Lord, C., Rutter, M., DiLavore, P.C., Risi, S., Gotham, K., Bishop, S. (2012). Western Psychological Services. | Yarı-yapılandırılmış doğrudan klinisyen gözlemi. Modül 1 maddeleri: B6 (İsme Yanıt), B11 (Ortak Dikkate Tepki), B7/A7 (İsteme/İşaret), C1/C2 (İşlevsel/Hayali Oyun), B9 (Gösterme), B2 (Sosyal Gülümseme). Not: 12–30 ay için Toddler Modülü, 31+ ay için Modül 1 kullanılır; madde kodları modüle göre farklılaşabilir. |
| **REF-02** | **STAT (Screening Tool for Autism in Toddlers and Young Children)** | Stone, W.L., Coonrod, E.E., Ousley, O.Y. (2000); Stone, W.L., Coonrod, E.E., Turner, L.M., Pozdol, S.L. (2004). Vanderbilt University. | 24–36 ay için tasarlanmış klinisyen etkileşimli erken tarama aracı (24 ay altında, ≥14 ay, keşfedici kullanım). 4 alan: Oyun (Görev 1-2), İsteme (Görev 3-4), Dikkat Yönlendirme (Görev 5-8), Motor Taklit (Görev 9-12). *(Not: İsme tepki görevi STAT kapsamında yer almaz; 24-36 ay aralığı STAT'ın standart klinik tarama penceresiyle tam örtüşmektedir).* |
| **REF-03** | **AOSI (Autism Observational Scale for Infants)** | Bryson, S.E., Zwaigenbaum, L., McDermott, C. et al. (2008). Journal of Autism and Developmental Disorders. | 12–18 ay bebekler için görsel yönelim, sese oryantasyon ve erken atipik ipuçlarını doğrudan gözlemleyen ölçek. |
| **REF-04** | **Bayley-4 (Bayley Scales of Infant and Toddler Development - 4th Ed.)** | Bayley, N., Aylward, G.P. (2019). NCS Pearson. | Bilişsel, alıcı dil ve ince motor gelişim normları. D08 (jestsiz tek komut), D09 (nesne yerleştirme), D10 (karalama) görevlerinin gelişimsel temeli. |
| **REF-05** | **M-CHAT-R/F (Modified Checklist for Autism in Toddlers with Follow-Up)** | Robins, D.L., Fein, D., Barton, M.L. (2009; Pediatrics 2014 validasyon çalışması). | 16–30 ay erken otizm risk taraması. İlgili ebeveyn bildirim maddeleri: M1 (İşarete bakma - D02), M3 (Mış gibi oyun - D04), M6 (İstemek için işaret - D03), M9 (Gösterme - D05), M10 (İsme tepki - D01), M11 (Gülümseme - D07), M15 (Taklit - D06), M18 (Sözel yönergeyi anlama / jestsiz yakın karşılık - D08). |
| **REF-06** | **Mundy Ortak Dikkat Modeli (ESCS)** | Mundy, P., Delgado, C., Block, J., Venezia, M. et al. (2003, 2007). | Ortak dikkatin iki ekseni: **RJA** (Responded Joint Attention / İşarete tepki verme - D02) ve **IJA** (Initiated Joint Attention / Gösterme/ortak dikkat başlatma - D05). |
| **REF-07** | **Denver II Türk Standardizasyonu** | Frankenburg, W.K. et al. (1992); Yalaz, K., Anlar, B. (Hacettepe Üniversitesi Çocuk Sağlığı Enstitüsü). | Türk çocuklarında kişisel-sosyal, dil ve ince motor basamaklarının yüzdelik gelişim normları. |
| **REF-08** | **M-CHAT Türkiye Uygulama ve Uyarlama Çalışması** | Kara, B., Mukaddes, N.M., Altınkaya, İ., Güntepe, D., Gökçay, G., Özmen, M. (2014). Autism, 18(3), 331–338. | Türkiye'de sağlam çocuk polikliniğinde orijinal M-CHAT ile erken otizm taraması çalışması. |
| **REF-09** | **DSM-5-TR (Diagnostic and Statistical Manual of Mental Disorders)** | American Psychiatric Association (APA, 2022). | OSB Tanı Kriterleri: **A1** (Sosyal-duygusal karşılıklılık), **A2** (Sözel olmayan iletişimsel davranışlar), **A3** (İlişkileri geliştirme ve hayali oyun), Eşlik eden dil bozukluğu belirleyicisi. |
| **REF-10** | **CDC Developmental Milestones (Learn the Signs. Act Early.)** | CDC & American Academy of Pediatrics (AAP, 2022 kılavuzu). | 12, 15, 18, 24 ve 30 ay çocuk gelişim basamakları ve aile takip kılavuzları. |
| **REF-11** | **Leslie Zihin Kuramı ve Mış Gibi Yapma Modeli** | Leslie, A.M. (1987). Psychological Review, 94(4), 412–426. | D04 sembolik hayali oyununun zihinsel mekanizması (ayrıştırma/decoupling). |
| **REF-12** | **Tomasello İletişimsel Niyet Teorisi** | Tomasello, M. (1995). Joint attention as social cognition. In C. Moore & P. J. Dunham (Eds.), Joint Attention (pp. 103–130). Lawrence Erlbaum. | D05 nesne gösterme davranışının deklaratif ortak dikkat başlatma işlevi. |
| **REF-13** | **Rogers & Pennington Erken Taklit Modeli** | Rogers, S.J., Pennington, B.F. (1991). Development and Psychopathology, 3(2), 137–162. | D06 erken motor taklit ve sosyal karşılıklılık gelişim modeli. |
| **REF-14** | **Gesell Gelişimsel İnce Motor Normları** | Gesell, A. (1940). The First Five Years of Life. Harper & Brothers. | D10 kendiliğinden karalama ve erken kalem kavrama normları. |

---

## 3. Yaş Bantları ve Gelişimsel Eşikler Mimarisi

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ YAŞ BANDI 1: 12–18 AY (Erken Oryantasyon & Temel Ortak Dikkat)                         │
│ • Klinik Odak: Sese oryantasyon, basit isme yönelme, ilkel motor taklit, nesne keşfi.   │
│ • Simülasyon Tipik Gecikme Eşiği: ≤ 2.0 saniye (en fazla 2 çağrı hakkı tanınır)        │
│ • Simülasyon Atipik Gecikme Eşiği: ≥ 3.0 saniye gecikme veya hiç yönelmeme             │
│ • Sınırda (Gri Bölge) Eşiği: 2.0 s – 3.0 s arası gecikmeli / tereddütlü yanıt          │
│ • Başlıca Referanslar: AOSI (Bryson 2008), ADOS-2, Bayley-4 (12-18m), CDC              │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ YAŞ BANDI 2: 18–24 AY (Kritik Tarama Penceresi & Sosyal Paylaşım)                      │
│ • Klinik Odak: Doğrudan göz temasıyla isme yönelme, izole işaret parmağı, nesne gösterme│
│ • Simülasyon Tipik Gecikme Eşiği: ≤ 1.8 saniye (doğrudan göz teması kilidi)            │
│ • Simülasyon Atipik Gecikme Eşiği: ≥ 2.5 saniye gecikme, tünel bakışı veya hand-leading │
│ • Sınırda (Gri Bölge) Eşiği: 1.8 s – 2.5 s arası gecikmeli / tereddütlü yanıt          │
│ • Başlıca Referanslar: M-CHAT-R/F (Robins 2014), ADOS-2, Mundy ESCS (2007)             │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ YAŞ BANDI 3: 24–36 AY (İleri Sosyal Karşılıklılık & Çok Basamaklı Sembolik Oyun)       │
│ • Klinik Odak: Çok basamaklı sembolik oyun (bebeğe içirme), jestsiz sözel yönerge,    │
│   3 noktalı ortak dikkat döngüsü (Yetişkin -> Nesne -> Yetişkin).                     │
│ • Simülasyon Tipik Gecikme Eşiği: ≤ 1.5 saniye + sözel/jestsel karşılık ('efendim')    │
│ • Simülasyon Atipik Gecikme Eşiği: ≥ 2.5 saniye gecikme veya sembolik oyun yokluğu     │
│ • Sınırda (Gri Bölge) Eşiği: 1.5 s – 2.5 s arası gecikmeli yanıt                       │
│ • Başlıca Referanslar: ADOS-2 Modül 1, STAT (Stone 2004), Bayley-4 (24-36m), DSM-5-TR  │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. 10 Davranış Kartının Klinik Kanıt Matrisi

### D01 — İsme Tepki Verme (Response to Name)
* **Altın Standart Ölçekler:** ADOS-2 Modül 1 Madde B6 (Response to Name); AOSI Sese Oryantasyon; M-CHAT-R/F Madde 10. *(STAT bu görevi içermez).*
* **Altın Standart Haritalaması:** ADOS-2 Modül 1 Madde B6 (Sosyal Etkileşim).
* **Gecikme Kuralı Geçerli mi:** **EVET** (Anlık sese yönelim ölçülür).
* **Ölçüm Referansı:** `latencySeconds`, son çağrının başlangıcından çocuğun ilk yönelim hareketine kadar geçen süre olarak ölçülür. 10 sn gözlem penceresi ilk çağrıyla başlar.
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: En fazla 2 çağrıda son çağrıdan itibaren ≤ 2.0 sn içinde yönelir. Atipik: 2 çağrıya rağmen son çağrıdan itibaren ≥ 3.0 sn veya pencere bitene kadar yönelmez. Sınırda: İlk çağrıda yönelmez, 2. çağrıda 2.0–3.0 sn arasında tereddütle yönelir.
  * **18–24 Ay:** Tipik: Tek çağrıda ≤ 1.8 sn içinde doğrudan göz temasıyla yönelir. Atipik: ≥ 2.5 sn boyunca başını çevirmez, oyuncağa kilitli kalır (tünel bakışı). Sınırda: 1.8–2.5 sn arasında gecikmeli yönelir.
  * **24–36 Ay:** Tipik: Tek çağrıda ≤ 1.5 sn içinde yönelir ve sözel/jestsel karşılık verir ('efendim', tebessüm). Atipik: ≥ 2.5 sn boyunca çağrıyı yok sayar. Sınırda: 1.5–2.5 sn arasında yönelir fakat sözel karşılık eklemez.
* **DSM-5-TR Eşleşmesi:** Kriter A1 (Sosyal-duygusal karşılıklılık eksikliği).

---

### D02 — Yetişkinin İşaret Ettiği Hedefe Yönelme (Responding to Joint Attention - RJA)
* **Altın Standart Ölçekler:** ADOS-2 Modül 1 Madde B11 (Response to Joint Attention); STAT Görev 5–8 (Directing Attention); Mundy ESCS RJA Modeli; M-CHAT-R/F Madde 1.
* **Altın Standart Haritalaması:** ADOS-2 Modül 1 Madde B11 (Ortak Dikkat).
* **Gecikme Kuralı Geçerli mi:** **EVET**.
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: 2.0 sn içinde 1–2 metre mesafedeki hedefe yönelir. Atipik: ≥ 3.0 sn boyunca hedefe bakmaz, sadece parmağa bakar veya ilgisiz kalır. Sınırda: 2.0–3.0 sn arasında gecikmeli yönelir.
  * **18–24 Ay:** Tipik: 1.8 sn içinde 3+ metre mesafedeki hedefe yönelir; parmağa takılıp kalmaz. Atipik: ≥ 2.5 sn boyunca hedefe bakmaz. Sınırda: 1.8–2.5 sn arasında bakar fakat bakışı hedefe sabitleyemez.
  * **24–36 Ay:** Tipik: 1.5 sn içinde hedefe bakar ve ardından yetişkine dönerek 3 noktalı ortak dikkat döngüsünü tamamlar (Yetişkin -> Nesne -> Yetişkin). Atipik: ≥ 2.5 sn boyunca hedefe bakmaz veya hedefe baksa bile yetişkinle hiçbir bakış koordinasyonu kurmaz. Sınırda: 1.5–2.5 sn arasında hedefe bakar fakat yetişkine geri dönmez.
* **DSM-5-TR Eşleşmesi:** Kriter A2 (Sözel olmayan iletişimsel davranışlarda kısıtlılık).

---

### D03 — İstemek İçin İşaret Etme (Proto-Imperative Pointing / Requesting)
* **Altın Standart Ölçekler:** ADOS-2 Modül 1 Madde B7 (Requesting) & Madde A7 (Pointing); STAT Görev 3–4 (Requesting); M-CHAT-R/F Madde 6; Bayley-4 İletişim Basamakları.
* **Altın Standart Haritalaması:** ADOS-2 Modül 1 Madde B7/A7 (İletişimsel İsteme).
* **Gecikme Kuralı Geçerli mi:** **HAYIR** (20 sn gözlem penceresinde eylemin niteliği değerlendirilir).
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: Tüm elle uzanma veya izole işaret parmağı başlangıcı; yetişkine bakar/ses çıkarır. Atipik: İstek belirtmez, öfkelenir veya yetişkinin elini alet gibi kullanır (hand-leading). Sınırda: Uzanır ancak yetişkinle göz teması kurmadan tek başına çabalar.
  * **18–24 Ay:** Tipik: İzole işaret parmağı ile gösterir, bakış koordinasyonu kurar. Atipik: İşaret parmağı kullanmaz; yetişkinin elini cansız alet gibi çeker (hand-leading). Sınırda: Tüm eliyle gösterir veya bakış koordinasyonu kurmakta gecikir.
  * **24–36 Ay:** Tipik: İzole işaret parmağıyla hedefe yönelir, yetişkine bakarak kelime/ses ile talebini pekiştirir ('ver', 'araba'). Atipik: Hand-leading yapar veya öfkelenir. Sınırda: İşaret eder fakat sözel ifade eklemez.
* **DSM-5-TR Eşleşmesi:** Kriter A2 (İletişimsel jestlerin atipik kullanımı).

---

### D04 — Hayali Oyun — Mış Gibi Yapma (Symbolic & Functional Play)
* **Altın Standart Ölçekler:** ADOS-2 Modül 1 Madde C1 (Functional Play with Objects) & Madde C2 (Imagination/Creativity); STAT Görev 1–2 (Play); M-CHAT-R/F Madde 3; Leslie (1987) Zihin Kuramı.
* **Altın Standart Haritalaması:** ADOS-2 Modül 1 Madde C1/C2 (Oyun).
* **Gecikme Kuralı Geçerli mi:** **HAYIR** (20 sn gözlem penceresinde sembolik oyun niteliği değerlendirilir).
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: Boş fincanı kendi ağzına götürerek temel işlevsel kullanım gösterir. Atipik: Fincanı yere vurur, çiğner veya döndürür. Sınırda: Fincanı ağzına götürür gibi yapar ancak tamamlamadan atar.
  * **18–24 Ay:** Tipik: Boş fincanı oyuncak bebeğe götürerek içiriyormuş gibi yapar (başka nesneye yönelik sembolik oyun). Atipik: Bebeğe yönelik mış gibi eylem yapmaz, fincanı fırlatır veya vurur. Sınırda: Bebeğe yaklaştırır fakat içirme hareketini canlandırmadan bırakır.
  * **24–36 Ay:** Tipik: Çok basamaklı sembolik oyun sergiler (bebeğe içirir, ardından yatırır veya tabağı kaşıkla karıştırır). Atipik: Sembolik oyun hiç görülmez; oyuncakları fırlatır veya döndürür. Sınırda: Tek basamaklı içirme yapar fakat ikinci sembolik basamağa geçemez.
* **DSM-5-TR Eşleşmesi:** Kriter A3 (Gelişim düzeyine uygun hayali oyun oynamada güçlük).

---

### D05 — Paylaşmak İçin Nesne Gösterme (Initiating Joint Attention - IJA / Showing)
* **Altın Standart Ölçekler:** ADOS-2 Modül 1 Madde B9 (Showing); Mundy ESCS IJA Modeli; M-CHAT-R/F Madde 9; Tomasello (1995).
* **Altın Standart Haritalaması:** ADOS-2 Modül 1 Madde B9 (Sosyal Etkileşim).
* **Gecikme Kuralı Geçerli mi:** **HAYIR** (20 sn gözlem penceresinde kendiliğinden paylaşım değerlendirilir).
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: Oyuncağı yetişkine doğru uzatarak gösterme inisiyatifi sergiler. Atipik: Oyuncağı yetişkine yöneltmez; kendi içine odaklı kalır. Sınırda: Oyuncağı kaldırır ancak yetişkinin yüzüne bakmadan havada tutar.
  * **18–24 Ay:** Tipik: Oyuncağı yetişkinin göz hizasına kaldırır, gülümseyerek göz teması kurar. Atipik: Nesneyi yetişkine yöneltmez, tek başına oynar. Sınırda: Uzatır ancak tebessüm veya göz teması eklemez.
  * **24–36 Ay:** Tipik: Oyuncağı gösterirken sözel paylaşım ('bak', 'araba') ve ortak sevinç ifadesi sergiler. Atipik: Gösterme davranışı hiç sergilemez. Sınırda: Gösterir fakat sözel ifade veya duygulanım paylaşımı zayıftır.
* **DSM-5-TR Eşleşmesi:** Kriter A1 (Sosyal ilgiyi ve zevkleri kendiliğinden paylaşma eksikliği).

---

### D06 — Basit Motor Hareketi Taklit Etme (Motor Imitation)
* **Altın Standart Ölçekler:** STAT Görev 9–12 (Motor Imitation); M-CHAT-R/F Madde 15; Rogers & Pennington (1991). *(ADOS-2 Modül 1 tanı algoritmasında doğrudan puanlanan bağımsız bir motor taklit maddesi bulunmadığı için ADOS atfı kaldırılmıştır).*
* **Altın Standart Haritalaması:** STAT Görev 9-12 (Motor Taklit).
* **Gecikme Kuralı Geçerli mi:** **HAYIR** (10 sn pencerede eylem doğruluğu değerlendirilir).
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: Alkış veya el sallama hareketini modelden sonra taklit eder. Atipik: Elleri hareketsiz kalır veya ilgisiz motor hareketlere dalar. Sınırda: Elleri yaklaştırır fakat alkışı tamamlayamaz.
  * **18–24 Ay:** Tipik: Belirgin biçimde el çırpar ve yetişkine bakar. Atipik: El çırpmaz; ellerini kucağında tutar veya parmak stereotipileri yapar. Sınırda: Taklit eder ancak göz teması kurmaz.
  * **24–36 Ay:** Tipik: Hareketi gecikmesiz taklit eder ve gülümseyerek ortak etkileşim kurar. Atipik: Modeli tamamen görmezden gelir. Sınırda: Taklit eder fakat hareket zayıf ve tereddütlüdür.
* **DSM-5-TR Eşleşmesi:** Gelişimsel Taklit Becerisi (Doğrudan DSM tanı kriteri değildir, sosyal karşılıklılıkla dolaylı ilişkilidir).

---

### D07 — Gülümsemeye Karşılık Verme (Social Smiling / Reciprocal Smile)
* **Altın Standart Ölçekler:** ADOS-2 Modül 1 Madde B2 (Responsive Social Smile); M-CHAT-R/F Madde 11; AOSI Sosyal Duygulanım.
* **Altın Standart Haritalaması:** ADOS-2 Modül 1 Madde B2 (Sosyal Etkileşim).
* **Gecikme Kuralı Geçerli mi:** **EVET**.
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: 2.0 sn içinde sıcak bir tebessümle karşılık verir. Atipik: 3.0+ sn boyunca yüz ifadesi donuk kalır. Sınırda: 2.0–3.0 sn arasında gecikmeli veya silik bir tebessüm gösterir.
  * **18–24 Ay:** Tipik: 1.8 sn içinde gülümsemeyle karşılık verir, göz temasını uzatır ve pozitif sesler çıkarır. Atipik: 2.5+ sn boyunca ifadesiz kalır. Sınırda: 1.8–2.5 sn arasında tebessüm eder fakat göz temasını derhal keser.
  * **24–36 Ay:** Tipik: 1.5 sn içinde tebessümle karşılık verir ve duygulanımını senkronize eder. Atipik: 2.5+ sn boyunca sosyal gülümseme yoksunluğu sergiler. Sınırda: 1.5–2.5 sn arasında tebessüm eder fakat duygulanım paylaşımı sınırlıdır.
* **DSM-5-TR Eşleşmesi:** Kriter A1 (Duygusal karşılıklılık ve pozitif duygulanım paylaşımı eksikliği).

---

### D08 — Jest Desteği Olmadan Tek Basamaklı Sözel Yönerge (Receptive Language)
* **Altın Standart Ölçekler:** Bayley-4 Alıcı Dil Alt Testi; Denver II Dil Normları; M-CHAT-R/F Madde 18 (Sözel komutu anlama / jestsiz yakın karşılık).
* **Altın Standart Haritalaması:** Bayley-4 Alıcı Dil (Dil Gelişimi).
* **Gecikme Kuralı Geçerli mi:** **EVET** (Sözel komuta yönelim ölçülür).
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: 2.0 sn içinde arabaya yönelir veya uzatma hamlesi yapar. Atipik: 3.0+ sn boyunca yönergeyi duymazdan gelir. Sınırda: 2.0–3.0 sn arasında bakar fakat teslim hareketini tamamlayamaz.
  * **18–24 Ay:** Tipik: 1.8 sn içinde arabayı kavrar ve jest desteği olmaksızın teslim eder. Atipik: 2.5+ sn boyunca arabayı vermez, duymamış gibi oynar. Sınırda: 1.8–2.5 sn arasında eline alır ancak teslim etmekte tereddüt eder.
  * **24–36 Ay:** Tipik: 1.5 sn içinde arabayı alıp yetişkine teslim eder. Atipik: 2.5+ sn boyunca yönergeyi tamamen görmezden gelir. Sınırda: 1.5–2.5 sn arasında teslim eder fakat komutun hemen ardından duraksar.
* **DSM-5-TR Eşleşmesi:** DSM-5-TR Eşlik Eden Dil Bozukluğu Belirleyicisi ve İletişimsel Karşılıklılık (A1).

---

### D09 — Nesneyi Bir Kaba Yerleştirme (Object Placement)
* **Altın Standart Ölçekler:** Bayley-4 Bilişsel ve İnce Motor Alt Testleri; Denver II Küp/Kutu Basamakları; CDC 12, 15, 18, 24 ve 30 Ay Gelişim Göstergeleri.
* **Altın Standart Haritalaması:** Bayley-4 Bilişsel / İnce Motor (İlişkisel Manipülasyon).
* **Gecikme Kuralı Geçerli mi:** **HAYIR** (Gecikme aranmaz, manipülasyon doğruluğu izlenir).
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: Bloğu eliyle kaldırıp kutunun içine bırakır. Atipik: Kutunun dışına fırlatır veya sadece ağzına götürür. Sınırda: Kenara vurur fakat içine bırakamaz.
  * **18–24 Ay:** Tipik: Bloğu kontrollü biçimde kutu ağzına taşır ve içine bırakır. Atipik: Masaya sertçe vurur veya döndürür. Sınırda: Kenarda bırakır veya içine düşürmekte zorlanır.
  * **24–36 Ay:** Tipik: Amaca uygun yerleştirir, kapağı kapatır veya sıralı dizer. Atipik: Stereotipik tekrarlarla bloğu fırlatır. Sınırda: Kutuya atar fakat sıralı yerleştirme yapmaz.
* **Klinik Statüsü:** Gelişimsel Bilişsel / İnce Motor Görev *(DSM tanı kriteri değildir)*.

---

### D10 — Kalemle Kendiliğinden Karalama Yapma (Spontaneous Scribbling)
* **Altın Standart Ölçekler:** Bayley-4 İnce Motor; Denver II Karalama Normları (Yalaz & Anlar); Gesell (1940) İnce Motor Gelişimi.
* **Altın Standart Haritalaması:** Bayley-4 İnce Motor (Kendiliğinden Çizim İnisiyatifi).
* **Gecikme Kuralı Geçerli mi:** **HAYIR** (Gecikme aranmaz, motor inisiyatif izlenir).
* **Yaş Bazlı Ölçütler (`byAgeBand`):**
  * **12–18 Ay:** Tipik: Boyayı kâğıda sürterek görünür rastlantısal çizgiler oluşturur. Atipik: Kâğıda çizgi çekmez; boyayı ağzına götürür veya masaya vurur. Sınırda: Dokundurur fakat çizgi oluşturacak sürtmeyi yapamaz.
  * **18–24 Ay:** Tipik: Kâğıt üzerinde sürekli dairesel veya çizgisel karalamalar üretir. Atipik: Hiç çizgi bırakmaz; boyayı ısırır veya fırlatır. Sınırda: Kısa tek bir çizgi çeker, ardından kalemi bırakır.
  * **24–36 Ay:** Tipik: Kâğıt sınırları içinde kalarak sürekli ve yönlü karalamalar yapar. Atipik: Masaya vurur veya kâğıdı yırtar. Sınırda: Çizer fakat kâğıdın dışına taşırır veya hızla ilgisini kaybeder.
* **Klinik Statüsü:** Gelişimsel İnce Motor İnisiyatif Görevi *(DSM tanı kriteri değildir)*.

---

## 5. Ontoloji (ONT) Kodlarının Haritası ve Gerekçesi

İlk prototip ontolojisinde bazı davranışlar mekânsal ve hedef ayrımlarıyla birden fazla koda bölünmüştü; standart 10 davranış kartına indirgenmiştir:

| ONT Kodu | Hedef Davranış Kartı | Açıklama ve Eşleme Gerekçesi |
|---|---|---|
| **ONT-01** | **D01** (İsme tepki) | 1:1 Doğrudan eşleme. |
| **ONT-02** | **D02** (İşarete yönelme) | Yakın mesafe (1–2m) görsel hedef. |
| **ONT-03** | **D05** (Gösterme) | Nesne paylaşımı. |
| **ONT-04** | **D02** (İşarete yönelme) | Uzak mesafe (3m+) görsel hedef. D02 kartı altında birleştirildi. |
| **ONT-05** | **D03** (İstemek için işaret) | Nesne odaklı isteme. |
| **ONT-06** | **D03** (İstemek için işaret) | Yetişkin odaklı isteme. D03 kartı altında birleştirildi. |
| **ONT-07** | **D05** (Gösterme) | Duygulanım paylaşımı odaklı gösterme. D05 altında birleştirildi. |
| **ONT-08** | **D07** (Gülümseme) | 1:1 Doğrudan eşleme. |
| **ONT-09** | **D04** (Mış gibi oyun) | 1:1 Doğrudan eşleme. |
| **ONT-10** | **D06** (Motor taklit) | 1:1 Doğrudan eşleme. |
| **ONT-11** | **D08** (Sözel yönerge) | 1:1 Doğrudan eşleme. |
| **ONT-12** | **D09** (Kutuya yerleştirme) | 1:1 Doğrudan eşleme. |
| **ONT-13** | **D10** (Karalama) | 1:1 Eşleme (Kalemle kendiliğinden karalama). |

---

## 6. Örnek RAG Prompt Enjeksiyon Çıktısı (Kol B)

Sistem bir vaka için çalıştığında modele enjekte edilen seçici kural metni (diğer profillerin ölçütleri modele sızdırılmaz):

```text
[YASAL / ETİK UYARI]
Bu bilgi tabanı eğitim, araştırma, simülasyon ve yapay zeka video analizi kural doğrulama parametrelerini içerir; klinik tanı aracı, tıbbi cihaz veya onaylanmış tanısal puanlama sistemi değildir. Sayısal saniye eşikleri, video tabanlı analiz ve simülasyon için uzman tanımlı, kalibrasyon bekleyen operasyonel simülasyon parametreleridir.

[KLİNİK KURAL ENJEKSİYONU - SEÇİCİ RETRIEVAL (KOL B)]
Hedef Kart: D01 — İsme tepki verme
Gözlem Amacı: İsim çağrısından sonra yetişkine yönelmeyi veya ona yönelik sesli yanıtı gözlemek.
Altın Standart Ölçek Dayanağı: ADOS-2 Modül 1 — Madde B6 (Sosyal Etkileşim)
DSM-5-TR Eşleşmesi: Kriter A1 (Sosyal-duygusal karşılıklılık eksikliği)
Yetişkin Uygulama Kuralı: Çocuk oyuncağıyla ilgilenirken yetişkin, çocuğun adını doğal ses tonuyla söyler (12–18 ay grubunda ilk çağrıya yanıt alınamazsa 5 sn sonra 2. çağrı yapılabilir; 18–36 ayda tek çağrı esastır). Dokunmaz, el sallamaz veya eşzamanlı başka komut vermez.
Çocuk Başlangıç Şartı: Çocuğun başı, çağrı öncesi ve sonrası görünür olsun; çağrı duyulsun ve yetişkinin konumu bilinsin.
Gözlem Penceresi: 10 saniye
Geçerli Gözlem Koşulu: Çağrı duyulur; çağıran kişinin konumu bilinir; çocuk çağrıdan önce zaten ona yönelmiş değildir. Çağrı öncesi ve sonrası kesintisiz görünür.
Hedef Yaş Bandı: 18–24 Ay
Hedef Davranış Çıktısı: TİPİK
Zamanlama Eşiği (TİPİK):
  - UYARAN fazında çocuğun tepki gecikmesi (latencySeconds) en fazla 1.8 saniye olmalı ve yetişkine net yönelme görülmelidir.
  - Ölçüm Referansı: latencySeconds, tepkiyi tetikleyen son uyarının başlangıcından çocuğun ilk yönelim hareketine kadar geçen süre olarak ölçülür.
Aktif Klinik Ölçüt (TİPİK):
  Tek doğal isim çağrısında 1.8 saniye içinde doğrudan yetişkinin gözlerine yönelir ve göz teması kurar.
Geçersizlik Şartları (BU HATALARI KESİNLİKLE YAPMA):
  * Ses yoktur veya anlaşılmazdır
  * Çocuk zaten çağrıdan önce yetişkine dönüktür
  * Çağrıyla aynı anda yetişkin çocuğa dokunmuştur veya el sallamıştır
  * Kritik çağrı anı kesilmiştir
```

---

## 7. Teknik Notlar ve Simülasyon Kılavuzu

* **Seçici Enjeksiyon (Kol B):** Token israfını ve modelin zihninin karışmasını önlemek amacıyla Kol B çıktısı yalnızca hedeflenen risk profiline ait aktif ölçütü basar.
* **Kapsamlı Enjeksiyon (Kol C):** Benchmark ve tam bağlam karşılaştırmalarında kullanılmak üzere tüm kartların 3 yaştaki tüm ölçütlerini katalog halinde sunar.
* **Kalibrasyon:** Sayısal gecikme eşikleri ileride video veri setleri üzerinden toplanacak ampirik sürelerle kalibre edilebilecek modüler bir parametre mimarisindedir.

---

## 8. Sınırlılıklar

* **Yaş kapsamı:** STAT 24–36 ay için tasarlanmıştır (24 ay altı keşfedici kullanım); 12–18 ay bandı için AOSI ve M-CHAT-R/F destekleyici kaynak olarak kullanılmıştır.
* **ADOS-2 modülleri:** Toddler Modülü 12–30 ay, Modül 1 31+ ay içindir; bu dokümandaki madde kodları Modül 1 temellidir ve Toddler Modülü'nde farklılaşabilir. Madde kodları yayımlı kılavuzdan değil, ikincil kaynaklardan derlenmiştir; resmî kılavuzla karşılaştırılmalıdır.
* **Gecikme eşikleri:** `latencySeconds` eşikleri uzman tanımlı simülasyon parametreleridir; klinik ölçeklerden türetilmiş ampirik değerler değildir.
* **Kapsam:** Bu bilgi tabanı tanı koymaz; erken farkındalık simülasyonu için klinik literatüre dayalı bir referans katmanıdır.

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

### E. Yapay Zeka, RAG ve Metodoloji Referansları
18. **Lewis, P., Perez, E., Piktus, A., Petroni, F., Karpukhin, V., Goyal, N., Küttler, H., Lewis, M., Yih, W., Rocktäschel, T., Riedel, S., & Kiela, D. (2020).** Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks. *Advances in Neural Information Processing Systems (NeurIPS 2020)*, 33, 9459–9474.
19. **Vaswani, A., Shazeer, N., Parmar, N., Uszkoreit, J., Jones, L., Gomez, A. N., Kaiser, Ł., & Polosukhin, I. (2017).** Attention is all you need. *Advances in Neural Information Processing Systems (NeurIPS 2017)*, 30, 5998–6008.
