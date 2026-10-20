import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../models/behavior_cards.dart';

/// Mevcut ayrıntı ekranı; güncel kart okur, eski ONT şablonlarına yönlendirmez.
class OntologyDetailScreen extends StatelessWidget {
  const OntologyDetailScreen({super.key, required this.card});

  final BehaviorCard card;

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8FAFC),
    appBar: AppBar(
      title: Text(
        card.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 17),
      ),
      backgroundColor: const Color(0xFF0F172A),
      foregroundColor: Colors.white,
    ),
    body: SingleChildScrollView(
      key: ValueKey('behavior-detail:${card.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(card.title, key: const ValueKey('behavior-detail-title'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Bu bilgiler davranışları tanımak içindir; tanı veya '
            'yaşa göre gelişim değerlendirmesi değildir.',
          ),
          const SizedBox(height: 14),
          _section('Amaç', [
            Text(card.purpose, key: const ValueKey('behavior-purpose')),
          ]),
          _section('Hazırlık', [
            Text(card.preparation, key: const ValueKey('behavior-preparation')),
          ]),
          _section('Yapılacak işlem', [
            Text(card.instruction, key: const ValueKey('behavior-instruction')),
          ]),
          if (kDebugMode)
            Card(
              margin: const EdgeInsets.only(bottom: 14),
              color: Colors.white,
              child: ExpansionTile(
                key: ValueKey('behavior-team-details:${card.id}'),
                title: const Text('Ekip için gözlem ayrıntıları'),
                subtitle: const Text(
                  'Yalnız debug derlemede görünür; yetkilendirme değildir.',
                ),
                initiallyExpanded: false,
                maintainState: true,
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  const Text('Bunlar gözlem kurallarıdır; bu ekranda bir sonuç hesaplanmaz.'),
                  for (var i = 0; i < card.conditions.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(BehaviorCards.conditionLabels[i],
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(card.conditions[i],
                              key: ValueKey('behavior-condition:${card.id}:$i')),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text('Kart sürümü: ${card.cardVersion} · Kaynak: ${BehaviorCards.sourceName}'),
                  const SizedBox(height: 12),
                  const Text(BehaviorCards.scope),
                  const SizedBox(height: 8),
                  const Text(BehaviorCards.ageScope),
                  const SizedBox(height: 14),
                  _section('Pilot gözlem penceresi', [
                    Text(
                      card.pilotWindowSeconds == 10
                          ? 'Uyaran veya gösterilen hareket tamamlandıktan sonra 10 saniyelik '
                              'kesintisiz gözlem planlanır. Uyaran sırasında başlayan yanıtlar da kaydedilir.'
                          : 'Koşullar hazır olduktan sonra 20 saniyelik gözlem fırsatı planlanır. '
                              'Malzemeye ilgi ve erişim ayrıca dikkate alınır.',
                      key: const ValueKey('behavior-window'),
                    ),
                    const SizedBox(height: 8),
                    const Text(BehaviorCards.windowNotice),
                  ]),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
