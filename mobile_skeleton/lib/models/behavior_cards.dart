/// Güncel katalog: belgeler/Davranis_Kartlari_v02.md (kart sürümü 0.2).
/// Eski ScenarioModel/ONT şablonlarından bağımsızdır; eski kimlikleri eşlemez.
class BehaviorCard {
  const BehaviorCard({
    required this.id,
    required this.title,
    required this.summary,
    required this.purpose,
    required this.preparation,
    required this.instruction,
    required this.conditions,
    required this.pilotWindowSeconds,
  });

  final String id;
  final String title;
  final String summary;
  final String purpose;
  final String preparation;
  final String instruction;
  final List<String> conditions;
  final int pilotWindowSeconds;

  String get cardVersion => BehaviorCards.version;
}

class BehaviorCards {
  static const version = '0.2';
  static const sourceName = 'Davranis_Kartlari_v02.md';
  static const conditionLabels = [
    'Geçerli gözlem koşulu',
    'Gözlendi: aranacak kanıt',
    'Gözlenmedi: yalnız bu denemeye ait',
    'Belirsiz durumlar',
    'Değerlendirilemeyen durumlar',
    'Kaydedilecekler',
  ];
  static const ageScope =
      'İlk teknik pilot 30–36 ayı temel alır. Nihai hedef 12–36 aydır; '
      'daha küçük yaşlar için görevler ayrıca uyarlanmalıdır. '
      'Bu bilgiler yaşa göre beceri beklentisi veya tanı ölçütü değildir.';
  static const scope =
      'Kartlar sentetik videolarda gözlenecek olayları tanımlar; '
      'klinik ölçek, tanı aracı veya doğrulanmış gelişimsel puanlama sistemi değildir.';
  static const windowNotice =
      'Bu süre kayıt planlaması içindir; klinik başarı veya gecikme eşiği değildir. '
      'Daha kısa kayıt kısmi gözlemdir; tam pencerede gözlenmedi diye sunulmaz. '
      'Senaryo veya üretim promptu, davranışın videoda gerçekleştiğini kanıtlamaz.';

  static const all = <BehaviorCard>[
    BehaviorCard(
      id:
          'D01',
      title:
          'İsme tepki verme',
      summary:
          'İsmi söylendikten sonra yetişkine verilen yanıtı gözlemleme.',
      purpose:
          'İsim çağrısından sonra yetişkine yönelmeyi veya ona yönelik sesli yanıtı gözlemek.',
      preparation:
          'Çocuğun başı, çağrı öncesi ve sonrası görünür olsun; çağrı duyulsun ve yetişkinin konumu '
          'bilinsin.',
      instruction:
          'Çocuk oyuncağıyla ilgilenirken yetişkin, çocuğun adını bir kez doğal sesle söyler. '
          'Dokunmaz, el sallamaz veya eşzamanlı başka yönerge vermez.',
      conditions: [
        'Çağrı duyulur; çağıran kişinin konumu bilinir; çocuk çağrıdan önce zaten ona yönelmiş '
        'değildir. Çağrı öncesi ve sonrası kesintisiz görünür.',
        'Çağrı sonrasında yetişkine belirgin yönelme veya açıkça yetişkine yönelik sesli/sözel '
        'yanıt görülür. Baş yönelmesi, sesli yanıt ve yapılan işi durdurma ayrı alt alanlarda '
        'kaydedilir. Yalnızca duraklama, bağlantısı açık değilse belirsiz bırakılır.',
        'Geçerli çağrıdan sonra tanımlı pencerede belirgin yanıt görülmez. Bu sonuç yalnızca bu '
        'denemeye aittir.',
        'Baş döner ancak hedefin yetişkin mi başka bir uyaran mı olduğu anlaşılamaz; sesli '
        'yanıtın muhatabı belirsizdir.',
        'Ses yoktur/anlaşılmaz; çocuk zaten yetişkine dönüktür; çağrıyla aynı anda dokunma veya '
        'başka dikkat çekici uyaran vardır; kritik bölüm kesilmiştir.',
        'Çağrı başlangıcı/bitişi; yanıt başlangıcı; yanıt türü; yönelme hedefi. Gecikme için '
        'referans çağrının bitişidir; adı bitmeden başlayan yanıt ayrıca işaretlenir. İlk '
        'otomatik kapsam yalnızca baş yönelmesi olabilir; bu durumda çıktı \'isme yönelme\' diye '
        'adlandırılır.',
      ],
      pilotWindowSeconds: 10,
    ),
    BehaviorCard(
      id:
          'D02',
      title:
          'Yetişkinin işaret ettiği hedefe yönelme',
      summary:
          'Yetişkinin gösterdiği nesneye dönüp bakmayı gözlemleme.',
      purpose:
          'İşaret edilen doğru hedefe yönelmeyi gözlemek; baş yönünü gerçek bakış hedefiyle aynı '
          'saymamak.',
      preparation:
          'İki sabit nesne, yetişkinin eli ve çocuğun yüzü/başı aynı kayıtta seçilsin. Çocuk '
          'başlangıçta hedefe bakmıyor olsun.',
      instruction:
          'İki sabit nesne görünür. Çocuk başka yere bakarken yetişkin bunlardan birini işaret eder '
          've \'Bak\' der; hedefin adını söylemez. İşaret+bakış ile yalnızca bakış görevleri '
          'karıştırılmaz.',
      conditions: [
        'Yetişkinin eli, hedef ve çocuğun yüzü/başı aynı kayıtta seçilir. Çocuk başlangıçta '
        'hedefe bakmıyordur; hedef kendiliğinden hareket etmez.',
        'İşaret sonrasında çocuk doğru hedefe belirgin biçimde yönelir. Yetişkine tekrar bakması '
        'zorunlu ölçüt değildir.',
        'Geçerli fırsatta hedefe yönelme görülmez; yalnızca yetişkine bakma veya başka nesneye '
        'yönelme ayrı yanıt olarak kaydedilir.',
        'Baş hedef tarafına döner ancak yakın duran iki nesneden hangisine yöneldiği ayırt '
        'edilemez.',
        'Hedef kadraj dışıdır; yetişkinin işareti görülmez; çocuk zaten hedefe bakıyordur; hedef '
        'hareket/sesle kendi başına dikkat çekmiştir.',
        'İşaret başlangıcı; hedef kimliği; ilk yönelme hedefi; gecikme. Baş yönü ile gerçek bakış '
        'hedefi aynı değişken kabul edilmez.',
      ],
      pilotWindowSeconds: 10,
    ),
    BehaviorCard(
      id:
          'D03',
      title:
          'İstemek için işaret etme',
      summary:
          'Ulaşamadığı oyuncağı istemek için işaret etmeyi gözlemleme.',
      purpose:
          'İşaret hareketini isteme bağlamıyla birlikte gözlemek; başka isteme biçimlerini de ayırt '
          'etmek.',
      preparation:
          'Çocuğun ilgilendiği güvenli oyuncak görünür fakat doğrudan erişilemez yerde olsun; '
          'yetişkin erişilebilir olsun.',
      instruction:
          'Güvenli oyuncak görünür fakat doğrudan erişilemez konumdadır. Çocuğun oyuncağa ilgisi '
          'gözlenir; yetişkin erişilebilir ve bekler. Yiyecek/su gibi temel ihtiyaçlar engellenmez; '
          '\'işaret et\' yönergesi verilmez.',
      conditions: [
        'El/parmak, hedef ve yetişkin görünür; nesneye ilgi ve isteme fırsatı vardır. Çocuğun '
        'ilgilenmediği oyuncağa işaret etmemesi geçerli olumsuz deneme sayılmaz.',
        'Hedefe yönelik açık işaret hareketi vardır ve erişilemeyen nesne/iletişim akışı isteme '
        'yorumunu destekler. Sözel isteme olabilir; yetişkine göz teması zorunlu tutulmaz.',
        'Geçerli fırsatta işaret görülmez. Sözel isteme, açık el uzatma veya yetişkini çekme '
        'varsa \'başka isteme biçimi\' kaydedilir; iletişim yok diye etiketlenmez.',
        'Parmak görünmez; uzanma ve işaret ayrılmaz; isteme ile paylaşma bağlamı ayrıştırılamaz.',
        'Nesne erişilebilirdir; çocuk ilgilenmez; el/nesne görünmez; yetişkin çocuğun elini '
        'yönlendirir.',
        'Hedef; işaret başlangıcı; el biçimi; isteme bağlamını destekleyen olaylar; alternatif '
        'iletişim türü. Nesnenin verilmesi tek başına önceden var olan niyeti kanıtlamaz.',
      ],
      pilotWindowSeconds: 20,
    ),
    BehaviorCard(
      id:
          'D04',
      title:
          'Hayali oyun — mış gibi yapma',
      summary:
          'Boş oyuncak fincanla bebeğe içiriyormuş gibi oynamayı gözlemleme.',
      purpose:
          'Boş fincanla bebeğe içirme eylemini canlandıran oyun dizisini gözlemek.',
      preparation:
          'Oyuncak bebek ve boş oyuncak fincan çocuğun erişiminde olsun; el, fincan ve bebeğin yüzü '
          'görünsün.',
      instruction:
          'Oyuncak bebek ve boş oyuncak fincan sunulur. Yetişkin aynı hareketi önceden göstermez, '
          '\'bebeğe içir\' demez; çocuğun oyunu gözlenir.',
      conditions: [
        'Çocuğun oyuncaklara erişimi ve oyun fırsatı vardır. El, fincan ve bebeğin yüzü görünür; '
        'sahne kesintisizdir.',
        'Çocuk boş fincanı bebeğin ağzına götürüp içirme eylemini canlandırır. Sadece nesnelerin '
        'kısa süreli teması yetmez; eylem dizisi hayali kullanımı açıkça desteklemelidir.',
        'Geçerli oyun fırsatında tanımlanan hayali eylem görülmez. Oyuncakları keşfetmesi başka '
        'oyun olarak kaydedilir; hayali oyun becerisi yok sonucuna gidilmez.',
        'Fincan bebeğe yaklaşır ama bunun içirme mi rastlantısal temas mı olduğu belli değildir.',
        'Yetişkin aynı eylemi hemen önce modellemiştir veya açık yönerge vermiştir; kritik '
        'nesneler görünmez; kullanılabilir oyun fırsatı oluşmamıştır.',
        'Eylem başlangıç/bitişi; nesne ve hedef; model/yönerge varlığı; basit hayali '
        'kullanım/nesne yerine koyma alt türü. Otomatik ölçüm için nesne ve el ilişkisi gerekir.',
      ],
      pilotWindowSeconds: 20,
    ),
    BehaviorCard(
      id:
          'D05',
      title:
          'Paylaşmak için elindeki nesneyi gösterme',
      summary:
          'Elindeki oyuncağı paylaşmak için yetişkine göstermeyi gözlemleme.',
      purpose:
          'Nesneyi yetişkinin görüşüne sunmayı; yardım isteme ve teslim etmeden ayırarak gözlemek.',
      preparation:
          'Çocuğun kolayca kullanabildiği oyuncak elinde olsun; yetişkin yakın ve erişilebilir '
          'olsun. Kol ve nesne görünsün.',
      instruction:
          'Çocuk kolayca kullanabildiği bir oyuncakla oynar; yetişkin yakınında ve erişilebilirdir. '
          '\'Bana göster/ver\' demez; yardım gerektiren kapalı kutu kullanılmaz.',
      conditions: [
        'Nesne çocuğun elindedir; yetişkinin konumu bilinir; yardım veya teslim etme talebi '
        'yoktur. Kol ve nesne görünür.',
        'Çocuk nesneyi yetişkinin görüşüne sunar; yönelim, seslenme veya iletişim dizisi paylaşım '
        'yorumunu destekler. Nesneyi mutlaka bırakması veya göz teması kurması gerekmez.',
        'Geçerli fırsatta paylaşım amaçlı gösterme görülmez. Nesneyi yetişkine verme ayrı hareket '
        'olarak kaydedilir.',
        'Nesneyi kaldırır fakat muhatap belli değildir; gösterme, teslim etme ve yardım isteme '
        'ayrıştırılamaz.',
        'Yetişkin nesneyi istemiştir; çocuğun nesneyi tutuşu görünmez; yetişkin erişilebilir '
        'değildir; yardım gereksinimi senaryoyu baskılar.',
        'Nesne kimliği; sunma yönü; başlangıç/bitiş; yetişkin konumu; iletişim ipuçları; nesnenin '
        'elde tutulması/teslim edilmesi.',
      ],
      pilotWindowSeconds: 20,
    ),
    BehaviorCard(
      id:
          'D06',
      title:
          'Basit motor hareketi taklit etme',
      summary:
          'Yetişkinin gösterdiği el çırpma hareketini taklit etmeyi gözlemleme.',
      purpose:
          'Yetişkinin gösterdiği basit hareketin çocuk tarafından aynı temel hareket yapısıyla '
          'tekrarlanmasını gözlemek.',
      preparation:
          'Çocuk başlangıçta el çırpmıyor olsun ve yetişkinin hareketini görebilsin. İkisinin '
          'elleri de görünsün.',
      instruction:
          'Çocuk başlangıçta el çırpmıyorken yetişkin iki kez el çırpar, sonra ellerini indirip '
          'bekler. Sözel davet kullanılırsa ayrı koşul olarak kaydedilir.',
      conditions: [
        'Çocuğun model hareketini görebildiği anlaşılır; iki kişinin elleri görünür; çocuk aynı '
        'hareketi önceden yapmıyordur. Fiziksel yardım yoktur.',
        'Model hareketinden sonra çocuk aynı temel hareket yapısını üretir: ellerin birbirine '
        'yaklaşması ve görünür birleşme/temas. Hız ve tekrar sayısının birebir aynı olması '
        'gerekmez.',
        'Geçerli model sunumundan sonra eşleşen hareket görülmez; farklı hareket ayrı kaydedilir.',
        'Eller örtüşür; hareketin eşleşmesi belirsizdir; çocuk modelden önce de aynı hareketi '
        'yapıyor olabilir.',
        'Çocuk model sunumuna erişememiştir; model elleri görünmez; yetişkin çocuğun ellerini '
        'hareket ettirmiştir.',
        'Model başlangıç/bitişi; çocuk hareketi başlangıcı; gecikme; hareket eşleşmesi; tekrar '
        'sayısı; destek türü. Poz benzerliği tek başına sosyal taklit niyetini kanıtlamaz.',
      ],
      pilotWindowSeconds: 10,
    ),
    BehaviorCard(
      id:
          'D07',
      title:
          'Gülümsemeye karşılık verme',
      summary:
          'Yetişkin gülümsedikten sonra başlayan gülümsemeyi gözlemleme.',
      purpose:
          'Yetişkinin gülümsemesini izleyen yeni gülümseme başlangıcını gözlemek; içsel duygu '
          'çıkarmamak.',
      preparation:
          'Her iki yüz seçilsin. Çocuk yetişkinin yüzüne yönelmiş ve henüz gülümsemiyor olsun.',
      instruction:
          'Çocuk yetişkinin yüzüne yönelmişken yetişkin doğal biçimde gülümser. Aynı anda '
          'gıdıklama, komik oyuncak, sesli şaka veya başka güçlü uyaran kullanılmaz.',
      conditions: [
        'Her iki yüz seçilir; çocuk yetişkinin gülümsemesini görebilir; çocuk zaten '
        'gülümsemiyordur.',
        'Yetişkin gülümsemesinden sonra çocukta görünür gülümseme başlangıcı vardır. \'Zaman '
        'bakımından ilişkili karşılık\' kaydedilir; içsel duygusu kesin olarak çıkarılmaz.',
        'Geçerli ve görünür etkileşimde yeni gülümseme görülmez. Bu, genel sosyal tepki yok '
        'anlamına gelmez.',
        'Ağız hareketinin gülümseme mi konuşma mı olduğu anlaşılmaz; başka uyaranın etkisi '
        'dışlanamaz.',
        'Yüz profilde/örtülüdür; çocuk yetişkini görmemiştir; zaten gülümsüyordur; eşzamanlı '
        'gıdıklama gibi uyaran vardır.',
        'Yetişkin ve çocuk gülümsemesi başlangıç/bitişi; gecikme; yüz görünürlüğü; eşzamanlı '
        'uyaran. Yalnızca ağız köşesi mesafesinden kesin etiket üretilmez.',
      ],
      pilotWindowSeconds: 10,
    ),
    BehaviorCard(
      id:
          'D08',
      title:
          'Jest desteği olmadan tek basamaklı sözel yönergeyi yerine getirme',
      summary:
          'İşaret veya hareket desteği olmadan söylenen tek işi yapmayı gözlemleme.',
      purpose:
          'Yalnız sözel yönergeyle doğru nesnenin yetişkine teslim edilmesini gözlemek.',
      preparation:
          'Araba çocuğun erişiminde olsun; yönerge duyulsun ve yetişkine teslim mümkün olsun. '
          'Dil/görev bilgisi bilinsin.',
      instruction:
          'Araba çocuğun erişimindeyken yetişkin \'Arabayı bana ver\' der. Eliyle arabayı işaret '
          'etmez, isteme için açık el uzatmaz ve hareketi modellemez.',
      conditions: [
        'Yönerge duyulur; dil/görev bilgisi bilinir; doğru nesne erişilebilir ve yetişkine teslim '
        'mümkündür. Çocuk zaten teslim hareketini başlatmamıştır.',
        'Çocuk doğru nesneyi yetişkine teslim eder. Başlama ve tamamlanma ayrı kaydedilir; '
        'nesneyi yalnızca kaldırması tamamlama sayılmaz.',
        'Geçerli yönergede hedef eylem tamamlanmaz. Yanlış nesne, yalnızca başlama veya farklı '
        'eylem ayrı yanıt olarak kaydedilir.',
        'Nesne kimliği ya da teslim anı görünmez; çocuğun eylemi yönergeden önce başlamış '
        'olabilir.',
        'Yönerge anlaşılmaz; hedef erişilemez; yetişkin işaret/model/fiziksel yardım sağlar; '
        'kayıt teslimden önce kesilir.',
        'Yönerge bitişi; eylem başlangıcı ve tamamlanması; seçilen nesne; destek varlığı. '
        'Sonradan jest verilirse ilk jestsiz pencere kapanır ve yeni destekli koşul açılır.',
      ],
      pilotWindowSeconds: 10,
    ),
    BehaviorCard(
      id:
          'D09',
      title:
          'Nesneyi bir kaba yerleştirme',
      summary:
          'Bir bloğu kendiliğinden uygun bir kutunun içine bırakmayı gözlemleme.',
      purpose:
          'Bloğu elle taşıyıp kutunun içine bırakma dizisini gözlemek; yalnız sonuç konumuyla '
          'yetinmemek.',
      preparation:
          'Büyük blok ve bloğun rahatça sığdığı geniş ağızlı, alçak kutu sabit yüzeyde olsun. El, '
          'blok ve kutu ağzı görünsün.',
      instruction:
          'Büyük bir blok ve bloğun rahatça sığdığı geniş ağızlı, alçak bir kutu sabit yüzeyde '
          'sunulur. Yetişkin koyma hareketini önceden göstermez ve “kutunun içine koy” yönergesi '
          'vermez.',
      conditions: [
        'Çocuk nesneye ve kutuya erişebilir; malzemeyle etkileşim fırsatı oluşmuştur. El, blok, '
        'kutu ağzı ve sonuç konumu seçilir. Kutu boş veya yerleştirmeye uygundur.',
        'Çocuk bloğu eliyle kutunun ağzına taşır ve kutunun içine bırakır. El–nesne–kutu ilişkisi '
        'görünür biçimde doğrulanır. Yalnızca kutunun içinde blok görmek yeterli değildir.',
        'Geçerli fırsat ve yeterli kayıt vardır; hedef yerleştirme tamamlanmaz. Bloğu tutma, '
        'kutuya yaklaştırma veya dışarı bırakma ayrı alt eylemler olarak kaydedilir. Sonuç '
        'becerinin yokluğunu göstermez.',
        'Bırakma anı kısa süre örtülür veya bloğun kutunun içine mi arkasına mı düştüğü ayırt '
        'edilemez; rastlantısal düşme ile kontrollü yerleştirme ayrılmaz.',
        'Malzemeye erişim/ilgi ve geçerli etkileşim fırsatı yoktur; kutu uygun değildir; kritik '
        'el–nesne ilişkisi görünmez; yetişkin fiziksel yardım verir; belirgin üretim hatası '
        'vardır. Yönerge veya model verilmişse bu kartın kendiliğinden koşulu yerine ayrı '
        'destekli görev kaydedilir.',
        'Nesneyi tutma, kutuya taşıma ve bırakma zamanları; sonuç konumu; deneme ve tamamlama '
        'sayısı; gözlenebilir süre; yönerge/model/fiziksel destek.',
      ],
      pilotWindowSeconds: 20,
    ),
    BehaviorCard(
      id:
          'D10',
      title:
          'Kalemle kendiliğinden karalama yapma',
      summary:
          'Kalem hareketiyle kâğıtta yeni çizgiler oluşmasını gözlemleme.',
      purpose:
          'Çocuğun kendiliğinden yaptığı kalem hareketine bağlı yeni çizgileri gözlemek.',
      preparation:
          'Sabit kâğıt ve çalışan, kalın, yaşa uygun pastel boya erişilebilir olsun. El, boya ucu, '
          'kâğıt ve oluşan izler görünsün.',
      instruction:
          'Sabit bir kâğıt ve kalın, çalışan, yaşa uygun pastel boya erişilebilir biçimde sunulur. '
          'Yetişkin çizim göstermez, çocuğun elini yönlendirmez ve “çiz” yönergesi vermez. Belirli '
          'bir şekil beklenmez.',
      conditions: [
        'Çocuk malzemeye erişebilir ve kâğıt/kalemle etkileşim fırsatı oluşur. El, boya ucu, '
        'kâğıt ve oluşan izler yeterince görünürdür. Kâğıt başlangıçta boş veya mevcut çizgileri '
        'bilinen durumdadır; kamera ve ışık izleri ayırt etmeye uygundur.',
        'Çocuk boya ucunu kâğıda temas ettirip yüzey üzerinde hareket ettirir; bu harekete bağlı '
        'yeni görünür çizgi oluşur. Tek nokta veya kalemi yalnızca tutma, bu kartın karalama '
        'ölçütünü karşılamaz. Şekil, düzenli çizgi veya belirli tutuş şartı aranmaz.',
        'Geçerli etkileşim fırsatı ve yeterli kayıt vardır; çizgi oluşturan yüzey hareketi '
        'görülmez. Kalemi tutma, nokta yapma, havada hareket ettirme ve kâğıdı inceleme ayrı '
        'kaydedilir; genel çizim becerisi yok sonucuna gidilmez.',
        'El ve kâğıt seçilir ancak yeni izin kalem hareketiyle ilişkisi veya izin gerçekten yeni '
        'olup olmadığı ayrıştırılamaz. Sınırlı örtülmede çizgi oluşumu kesin doğrulanamaz.',
        'Etkileşim fırsatı oluşmamıştır; kalem çalışmaz; kâğıt/kalem erişilemez; kritik bölge '
        'sürekli kadraj dışıdır; yetişkin fiziksel yardım verir; çizgiler kendiliğinden belirir '
        'veya kalem hareketiyle belirgin biçimde uyuşmaz. Yönerge/model varsa ayrı destekli koşul '
        'kaydedilir.',
        'İlk temas ve ilk çizgi başlangıcı; karalama bölümlerinin başlangıç/bitişi; toplam '
        'gözlenebilir süre; yeni çizgi varlığı; el–kalem–kâğıt görünürlüğü; '
        'yönerge/model/fiziksel destek. Her nokta veya yüzey teması karalama sayılmaz.',
      ],
      pilotWindowSeconds: 20,
    ),
  ];
}
