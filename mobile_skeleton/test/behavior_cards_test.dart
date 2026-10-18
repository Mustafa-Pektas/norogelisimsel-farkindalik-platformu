import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/behavior_cards.dart';
import 'package:neuro_awareness_app/models/scenarios_data.dart';

// Beklentiler Davranis_Kartlari_v02.md başlıkları ve ayırt edici koşullarındandır.
void main() {
  const names = {
    'D01': 'İsme tepki verme',
    'D02': 'Yetişkinin işaret ettiği hedefe yönelme',
    'D03': 'İstemek için işaret etme',
    'D04': 'Hayali oyun — mış gibi yapma',
    'D05': 'Paylaşmak için elindeki nesneyi gösterme',
    'D06': 'Basit motor hareketi taklit etme',
    'D07': 'Gülümsemeye karşılık verme',
    'D08': 'Jest desteği olmadan tek basamaklı sözel yönergeyi yerine getirme',
    'D09': 'Nesneyi bir kaba yerleştirme',
    'D10': 'Kalemle kendiliğinden karalama yapma',
  };

  test('Katalog tam on benzersiz D kartıdır; kimlik, ad ve sürüm güncel kaynağa uyar', () {
    expect(BehaviorCards.all, hasLength(10));
    expect(BehaviorCards.all.map((card) => card.id).toList(), names.keys.toList());
    expect(BehaviorCards.all.map((card) => card.id).toSet(), hasLength(10));
    for (final card in BehaviorCards.all) {
      expect(card.title, names[card.id]);
      expect(card.cardVersion, '0.2');
      expect(card.summary.trim(), isNotEmpty);
      expect(card.purpose.trim(), isNotEmpty);
      expect(card.preparation.trim(), isNotEmpty);
      expect(card.instruction.trim(), isNotEmpty);
      expect(card.conditions, hasLength(6));
      expect(card.conditions.length, BehaviorCards.conditionLabels.length);
    }
  });

  test('Yeni katalog eski ONT şablon kimliklerini değiştirmez veya yeniden etiketlemez', () {
    expect(ScenariosRepository.allScenarios.map((scenario) => scenario.code).toList(),
        List.generate(12, (i) => 'ONT-${(i + 1).toString().padLeft(2, '0')}'));
    expect(BehaviorCards.all.map((card) => card.id).toSet().intersection(
      ScenariosRepository.allScenarios.map((scenario) => scenario.code).toSet(),
    ), isEmpty);
  });

  test('Pilot pencereleri kayıttaki teknik sürelerdir; klinik eşik veya yaş normu değildir', () {
    expect(BehaviorCards.all.where((card) => card.pilotWindowSeconds == 10)
        .map((card) => card.id).toList(), ['D01', 'D02', 'D06', 'D07', 'D08']);
    expect(BehaviorCards.all.where((card) => card.pilotWindowSeconds == 20)
        .map((card) => card.id).toList(), ['D03', 'D04', 'D05', 'D09', 'D10']);
    expect(BehaviorCards.windowNotice, contains('klinik başarı veya gecikme eşiği değildir'));
    expect(BehaviorCards.windowNotice, contains('Daha kısa kayıt kısmi gözlemdir'));
    expect(BehaviorCards.ageScope, contains('30–36 ay'));
    expect(BehaviorCards.ageScope, contains('daha küçük yaşlar için görevler ayrıca uyarlanmalıdır'));
  });

  test('Benzer adlı eski görevler yerine her D kartının ayırt edici koşulu korunur', () {
    final cards = {for (final card in BehaviorCards.all) card.id: card};
    expect(cards['D01']!.instruction, contains('bir kez doğal sesle söyler'));
    expect(cards['D01']!.instruction, contains('Dokunmaz, el sallamaz'));
    expect(cards['D01']!.conditions[0], contains('çağrıdan önce zaten ona yönelmiş değildir'));
    expect(cards['D01']!.conditions[5], contains('referans çağrının bitişidir'));

    expect(cards['D02']!.instruction, contains("'Bak' der; hedefin adını söylemez"));
    expect(cards['D02']!.instruction, contains('İki sabit nesne'));
    expect(cards['D02']!.conditions[1], contains('Yetişkine tekrar bakması zorunlu ölçüt değildir'));

    expect(cards['D03']!.instruction, contains("'işaret et' yönergesi verilmez"));
    expect(cards['D03']!.conditions[0], contains('ilgilenmediği oyuncağa işaret etmemesi geçerli olumsuz deneme sayılmaz'));
    expect(cards['D03']!.conditions[1], contains('yetişkine göz teması zorunlu tutulmaz'));

    expect(cards['D04']!.instruction, contains('Oyuncak bebek ve boş oyuncak fincan'));
    expect(cards['D04']!.instruction, contains("'bebeğe içir' demez"));

    expect(cards['D05']!.instruction, contains("'Bana göster/ver' demez"));
    expect(cards['D05']!.conditions[1], contains('Nesneyi mutlaka bırakması veya göz teması kurması gerekmez'));

    expect(cards['D06']!.instruction, contains('yetişkin iki kez el çırpar'));
    expect(cards['D06']!.conditions[1], contains('Hız ve tekrar sayısının birebir aynı olması gerekmez'));

    expect(cards['D07']!.instruction, contains('yetişkin doğal biçimde gülümser'));
    expect(cards['D07']!.instruction, contains('gıdıklama, komik oyuncak, sesli şaka'));
    expect(cards['D07']!.conditions[0], contains('çocuk zaten gülümsemiyordur'));

    expect(cards['D08']!.instruction, contains("'Arabayı bana ver' der"));
    expect(cards['D08']!.instruction, contains('isteme için açık el uzatmaz ve hareketi modellemez'));
    expect(cards['D08']!.conditions[1], contains('nesneyi yalnızca kaldırması tamamlama sayılmaz'));

    expect(cards['D09']!.instruction, contains('geniş ağızlı, alçak bir kutu'));
    expect(cards['D09']!.instruction, contains('“kutunun içine koy” yönergesi vermez'));
    expect(cards['D09']!.conditions[1], contains('Yalnızca kutunun içinde blok görmek yeterli değildir'));

    expect(cards['D10']!.instruction, contains('çocuğun elini yönlendirmez ve “çiz” yönergesi vermez'));
    expect(cards['D10']!.instruction, contains('Belirli bir şekil beklenmez'));
    expect(cards['D10']!.conditions[1], contains('Tek nokta veya kalemi yalnızca tutma'));
  });
}
