# Farkındalık göstergeleri

Bu renkler **manuel etiket ile algoritmanın uyumunu ve değerlendirme
yeterliliğini** gösterir. Çocuğun gelişimi, sağlık durumu veya klinik risk
puanı değildir. Ana gösterge EMA 0.50 içindir; ham ve EMA 0.25 ayrı gösterilir.

- **Yeşil:** Video baştan sona insan tarafından eksiksiz incelenmiş; ölçüm
  yeterli; eksik/fazla tespit, tolerans dışı sınır farkı ve etiketlenmiş
  yönlerde uyuşmazlık yok. İki tarafta da hareket yoksa bu, incelenen
  videoda hareket bulunmadığı konusunda uyumdur; isme tepki sonucu değildir.
- **Sarı:** Etiket incelemesi yok/tamamlanmamış, ölçüm eksik, hareket sınırı
  bilinmiyor veya istenen yön karşılaştırması yapılamıyor. Eksik veriyle
  kaçırma/fazladan tespit sayılmaz. Yön etiketi verilmemişse yön sınanmaz;
  zaman uyumu yeşil olsa bile yön doğrulanmış sayılmaz.
- **Kırmızı:** Değerlendirilebilir etiketlerde kaçırılan hareket, fazladan
  algoritma adayı, zaman toleransı aşımı veya yön uyuşmazlığı var. Aynı
  zamanda veri eksikliği de varsa uyarısı korunur; kırmızı önceliklidir.

## Açık karşılaştırma kuralları

İnsan etiketleri yalnız `reviewed: true`, inceleyen adı dolu ve ilgili
aralık `complete: true` ise karşılaştırılır. `movements: []` ancak bu aralık
tamamen incelenip hareket görülmediyse negatif referans olur. İncelenmeyen
aralıktaki adaylar fazladan tespit sayılmaz. Bir hareket ve bir aday en fazla
bir defa eşleştirilir. Önce eşleşme sayısı en yüksek tutulur, sonra toplam
başlangıç farkı en düşük eşleştirme seçilir. Eşleşme doğru tespit ilanı değildir.

Varsayılan başlangıç eşleştirme sınırı **0.75 sn**; ayrıca hareket aralıkları
kesişmeli veya başlangıçlar **0.20 sn** içinde olmalıdır. Eşleşen başlangıç
ve bitiş için ayrı ayrı kabul edilen fark **±0.20 sn**. Bilinmeyen ya da
inceleme aralığı dışındaki bitiş tolerans kontrolüne sokulmaz, belirsiz kalır.
Sınır farkları algoritma eksi manuel zamandır; pozitif değer daha geçtir.

Ölçüm yeterliliği: ilgili aralıkta beklenen 24 FPS karelerin en az **%80**'i
geçerli ve en uzun ölçüm boşluğu en fazla **0.25 sn** olmalıdır. Eksik
kare numaraları ve eksik zamanlar bu kapsama dahil edilmez. Kaçırma için
manuel hareketin, fazladan tespit için algoritma adayının kendi aralığı
kontrol edilir. Yeşil için bütün inceleme aralıklarının ölçümü de yeterli olmalı.

Bu değerler doğrulanmış bilimsel eşikler değil, açık mühendislik başlangıç
kurallarıdır. Farklı protokol gerekirse ayarlardaki `comparison_rules` ile
değiştirilir ve rapora yazılır. Sonuçlara bakıp en iyi görünen filtre otomatik
seçilmez. Etiketler hareket dedektörüne veya filtreye verilmez.

## Hata nedenleri

Rapor **gözlenen bulgu** ile **olası açıklamayı** ayrı tutar. Zaman farkı,
kayıp ölçüm ve yön uyuşmazlığı bulgudur. Filtre gecikmesi, hareketlerin
birleşmesi/bölünmesi, poz titreşimi ve hedef tahmin hatası yalnız araştırma
önerisidir; kök neden oldukları otomatik olarak kanıtlanmaz. Videoyu ve
etiketi kontrol ettikten sonra insan notunu etiket dosyasına ekleyin.
