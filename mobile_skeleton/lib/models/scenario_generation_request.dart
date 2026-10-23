import 'dart:convert';

import 'behavior_cards.dart';
import 'scenario_graph.dart';

/// Üretim girdisi; ScenarioInput çıktısı veya içerik onayı değildir.
class ScenarioGenerationRequest {
  ScenarioGenerationRequest({required this.behaviorId, required this.cardVersion,
    required this.ageMonths, required this.sceneContext, this.additionalInstructions}) {
    final matches = BehaviorCards.all.where((card) => card.id == behaviorId);
    if (matches.isEmpty || matches.single.cardVersion != cardVersion) {
      throw const FormatException('Davranış kimliği/kart sürümü geçerli değil.');
    }
    if (ageMonths < 12 || ageMonths > 36) {
      throw const FormatException('12–36 arasında tam ay girin.');
    }
    if (sceneContext.trim().isEmpty) {
      throw const FormatException('Sahne/ortam bağlamını girin.');
    }
  }

  final String behaviorId;
  final String cardVersion;
  final int ageMonths;
  final String sceneContext;
  final String? additionalInstructions;
  BehaviorCard get card => BehaviorCards.all.firstWhere((card) => card.id == behaviorId);

  Map<String, Object?> toJson() => {
    'behaviorId': behaviorId, 'cardVersion': cardVersion, 'ageMonths': ageMonths,
    'sceneContext': sceneContext, 'additionalInstructions': additionalInstructions,
  };

  /// Yalnız dış JSON çiti/tek sarmalayıcı açılır; anlatı onarılmaz/tamamlanmaz.
  /// Uygulamanın eklediği metadata isteğe aittir; mevcut çelişki ezilmez.
  ({String json, String? normalization}) prepareInput(String raw, {
    required String scenarioId, required bool edited,
  }) {
    var text = raw.trim();
    final changes = <String>[];
    final fence = RegExp(r'^```json[ \t]*\r?\n([\s\S]*?)\r?\n```$',
      caseSensitive: false).firstMatch(text);
    if (fence != null && fence.end == text.length) {
      text = fence.group(1)!;
      changes.add('Dış Markdown JSON çiti kaldırıldı.');
    }
    var decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Cevap bir JSON nesnesi olmalıdır.');
    }
    if (decoded.containsKey('scenarioInput')) {
      if (decoded.length != 1 || decoded['scenarioInput'] is! Map<String, dynamic>) {
        throw const FormatException('scenarioInput tek bir nesne sarmalayıcısı olmalıdır.');
      }
      decoded = decoded['scenarioInput'] as Map<String, dynamic>;
      changes.add('Tek scenarioInput sarmalayıcısı açıldı.');
    }
    final metadata = <String, Object>{
      'schemaVersion': ScenarioGraph.currentSchemaVersion,
      'scenarioId': scenarioId,
      'title': '${card.title} senaryo taslağı',
      'language': 'tr', 'behaviorId': behaviorId,
      'cardVersion': cardVersion, 'ageMonths': ageMonths,
    };
    for (final entry in metadata.entries) {
      if (decoded.containsKey(entry.key) && decoded[entry.key] != entry.value) {
        throw FormatException('${entry.key} doğrulanmış istekle uyuşmuyor; değiştirilmedi.');
      }
    }
    if (decoded.containsKey('source') && decoded['source'] != 'model_output' &&
        !(edited && decoded['source'] == 'model_output_edited')) {
      throw const FormatException('Cevabın kaynak beyanı üretim isteğiyle uyuşmuyor.');
    }
    return (
      json: const JsonEncoder.withIndent('  ').convert({
        ...decoded, ...metadata, 'source': edited ? 'model_output_edited' : 'model_output',
      }),
      normalization: changes.isEmpty ? null : 'Biçim normalizasyonu: ${changes.join(' ')} '
          'Ham cevap ve anlatı metinleri değiştirilmedi.',
    );
  }
}
