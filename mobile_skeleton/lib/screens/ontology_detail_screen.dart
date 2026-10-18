import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../models/behavior_cards.dart';
import 'scenario_graph_import_screen.dart';

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
      title: Text(card.id),
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
          const Text('Bilgilendirme amaçlıdır; tanı veya puanlama yapılmaz.'),
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
          if (card.id == 'D01') ...[
            const Text(
              '30 aylık Deniz için sabit demo; oluşan akış hazır videolara bağlı değildir.',
              key: ValueKey('d01-demo-scope'),
            ),
            const SizedBox(height: 10),
            if (kDebugMode)
              FilledButton.icon(
                key: const ValueKey('open-d01-model-demo'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ScenarioGraphImportScreen(
                      initialScenarioContent: true,
                    ),
                  ),
                ),
                icon: const Icon(Icons.edit_note),
                label: const Text('D01 model demosunu aç (30 ay)'),
              )
            else
              const Text('Model demosu yalnız debug geliştirici derlemesinde görünür.'),
          ] else
            const Text(
              'Bu davranış için modelden üretim veya video bağlantısı henüz yok.',
              key: ValueKey('behavior-not-connected'),
            ),
          const SizedBox(height: 14),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            color: Colors.white,
            child: ExpansionTile(
              key: ValueKey('behavior-observation-rules:${card.id}'),
              title: const Text('Ayrıntılı gözlem kuralları'),
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
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            color: Colors.white,
            child: ExpansionTile(
              key: ValueKey('behavior-technical-info:${card.id}'),
              title: const Text('Teknik bilgiler'),
              initiallyExpanded: false,
              maintainState: true,
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              childrenPadding: const EdgeInsets.all(16),
              children: [
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
                if (card.id == 'D01')
                  const Text(
                    'Mevcut D01 model demosu 30 aylık Deniz ile sınırlıdır. '
                    'Şablon yaşı bu demoyu değiştirmez. Oluşan graf hazır D01 '
                    'klip planına veya videolarına bağlı değildir.',
                    key: ValueKey('d01-demo-technical-scope'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
