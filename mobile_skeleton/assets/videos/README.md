# 🎬 Ontoloji Video Klasörleri ve Dosya Standartları

Bu dizin, 12 hedef nörogelişimsel davranış göstergesi (ONT-01 - ONT-12) için sentetik video varlıklarını barındırır.

Her ontoloji klasörü içerisinde aşağıdaki **4 temel MP4 video dosyası** yer alır:

| Dosya Adı | Rol / Görev | İdeal Süre | Açıklama |
| :--- | :--- | :---: | :--- |
| `node_0.mp4` | **Öncül Uyaran (Ana Video)** | 5 sn | Çocuğun serbest oyunu ve yetişkinin uyarana başladığı an ($t_0$). |
| `branch_green.mp4` | **Yeşil Dal (Tipik)** | 5 sn | Hızlı, amaca yönelik tepki, göz teması ve sosyal tebessüm. |
| `branch_yellow.mp4` | **Sarı Dal (İzlem)** | 5 sn | Gecikmeli yönelim veya kısıtlı odaklanma (örn. hedefe değil ele bakma). |
| `branch_red.mp4` | **Kırmızı Dal (Atipik)** | 5 sn | Uyaranı yok sayma, sıfır yönelim veya nesneye hiperfokus. |

---

### 📂 Klasör Listesi:
1. `ont_01_isme_tepki/` — İsme Tepki (Response to Name) *(Hazır)*
2. `ont_02_ortak_dikkat/` — Ortak Dikkate Yanıt (Responding to Joint Attention)
3. `ont_03_isaret_etme/` — İlgi Göstermek İçin İşaret Etme (Protodeclarative Pointing)
4. `ont_04_taklit/` — Basit Taklit (Motor & Vokal İmitasyon)
5. `ont_05_sosyal_gulumseme/` — Sosyal Gülümseme & Karşılıklılık
6. `ont_06_goz_temasi/` — Göz Teması Sıklığı & Süresi
7. `ont_07_ce_e_oyunu/` — Ce-e Oyunu & Sosyal Oyunlara Katılım (Peek-a-boo)
8. `ont_08_nesne_getirme/` — Nesne Getirme & Göstermek İçin Uzatma
9. `ont_09_duygulanim_paylasimi/` — Duygulanım Paylaşımı & Sosyal Referanslama
10. `ont_10_yonerge_takibi/` — Basit Yönergeleri Takip Etme
11. `ont_11_iletisimsel_jestler/` — İletişimsel Jestlerin Kullanımı (Güle Güle, Baş Sallama)
12. `ont_12_akran_ilgisi/` — Akran İlgisi & Paralel Oyun

---
*Not: Bir klasöre videoları kopyaladığınızda Flutter uygulaması otomatik olarak videoları tanır ve interaktif simülatörde oynatır.*
