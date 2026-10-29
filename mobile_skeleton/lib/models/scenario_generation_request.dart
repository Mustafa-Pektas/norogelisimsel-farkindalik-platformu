import 'dart:convert';

import 'behavior_cards.dart';
import 'scenario_graph.dart';
import 'scenario_behavior_ref.dart';
import 'scenario_age_group.dart';

class ScenarioProductionSettings {
  ScenarioProductionSettings({required this.structure, required this.targetDurationS, required this.maxClipDurationS}) {
    if (!['branched', 'linear26'].contains(structure) || targetDurationS <= 0 ||
        maxClipDurationS <= 0 || maxClipDurationS > 8) {
      throw const FormatException('Üretim hedefi geçersiz; klipler en fazla 8 saniye olabilir.');
    }
  }
  final String structure;
  final int targetDurationS, maxClipDurationS;
  Map<String, dynamic> toJson() => {'structure': structure, 'targetDurationS': targetDurationS,
    'maxClipDurationS': maxClipDurationS, if (structure == 'linear26') 'targetSceneCount': 26};
  factory ScenarioProductionSettings.fromJson(Map<String, dynamic> value) {
    if (value['structure'] is! String || value['targetDurationS'] is! int || value['maxClipDurationS'] is! int ||
        value.keys.any((key) => !['structure','targetDurationS','maxClipDurationS','targetSceneCount'].contains(key)) ||
        (value['structure'] == 'linear26' ? value['targetSceneCount'] != 26 : value.containsKey('targetSceneCount'))) {
      throw const FormatException('Üretim hedefi alanları geçersiz.');
    }
    return ScenarioProductionSettings(structure: value['structure'] as String,
      targetDurationS: value['targetDurationS'] as int, maxClipDurationS: value['maxClipDurationS'] as int);
  }
}

/// Üretim girdisi; ScenarioInput çıktısı veya içerik onayı değildir.
class ScenarioGenerationRequest {
  ScenarioGenerationRequest({required this.behaviorId, required this.cardVersion,
    this.ageMonths, this.ageGroup, required this.sceneContext, this.additionalInstructions,
    List<ScenarioBehaviorRef>? behaviors, this.production, this._extendedContract = false})
      : behaviors = List.unmodifiable(behaviors ?? [ScenarioBehaviorRef(behaviorId: behaviorId, cardVersion: cardVersion)]) {
    if ((ageMonths == null) == (ageGroup == null)) {
      throw const FormatException('Tek bir yaş grubu veya geçmiş tam ay değeri gerekli.');
    }
    final matches = BehaviorCards.all.where((card) => card.id == behaviorId);
    if (matches.isEmpty || matches.single.cardVersion != cardVersion) {
      throw const FormatException('Davranış kimliği/kart sürümü geçerli değil.');
    }
    if (ageMonths != null && (ageMonths! < 12 || ageMonths! > 36)) {
      throw const FormatException('12–36 arasında tam ay girin.');
    }
    if (sceneContext.trim().isEmpty) {
      throw const FormatException('Sahne/ortam bağlamını girin.');
    }
    if (this.behaviors.isEmpty || this.behaviors.first.behaviorId != behaviorId ||
        this.behaviors.first.cardVersion != cardVersion ||
        this.behaviors.map((ref) => ref.behaviorId).toSet().length != this.behaviors.length) {
      throw const FormatException('Davranış listesi/uyumluluk alanları uyuşmuyor.');
    }
    for (final ref in this.behaviors) {
      if (!BehaviorCards.all.any((card) => card.id == ref.behaviorId && card.cardVersion == ref.cardVersion)) {
        throw const FormatException('Seçilen davranış/kart sürümü güncel değil.');
      }
    }
  }

  final String behaviorId;
  final String cardVersion;
  /// Historical v1/v2 requests retain their exact age; new requests use ageGroup.
  final int? ageMonths;
  final ScenarioAgeGroup? ageGroup;
  String get ageDescription => ageGroup?.label ?? '${ageMonths!} ay (eski istek)';
  final String sceneContext;
  final String? additionalInstructions;
  final List<ScenarioBehaviorRef> behaviors;
  final ScenarioProductionSettings? production;
  final bool _extendedContract;
  bool get extended => ageGroup != null || _extendedContract || behaviors.length > 1 || production != null;
  bool get linear => production?.structure == 'linear26';
  List<BehaviorCard> get cards => [for (final ref in behaviors)
    BehaviorCards.all.firstWhere((card) => card.id == ref.behaviorId)];
  factory ScenarioGenerationRequest.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('requestVersion') && !['2.0', '3.0'].contains(json['requestVersion'])) {
      throw const FormatException('Üretim isteği sürümü desteklenmiyor.');
    }
    if (json['requestVersion'] == '3.0') {
      final refs = readScenarioBehaviors(json['behaviors']);
      if (refs == null || json.keys.any((key) => !['requestVersion','behaviors','ageGroup','sceneContext','additionalInstructions','production'].contains(key)) ||
          json['sceneContext'] is! String ||
          (json['additionalInstructions'] != null && json['additionalInstructions'] is! String)) {
        throw const FormatException('Üretim isteği v3 alanları geçersiz.');
      }
      return ScenarioGenerationRequest(behaviorId: refs.first.behaviorId, cardVersion: refs.first.cardVersion,
        behaviors: refs, ageGroup: ScenarioAgeGroup.fromJson(json['ageGroup']), sceneContext: json['sceneContext'] as String,
        additionalInstructions: json['additionalInstructions'] as String?,
        production: json['production'] == null ? null : ScenarioProductionSettings.fromJson(Map<String,dynamic>.from(json['production'] as Map)));
    }
    if (json['requestVersion'] == '2.0') {
      final refs = readScenarioBehaviors(json['behaviors']);
      if (refs == null || json.keys.any((key) => !['requestVersion','behaviors','ageMonths','sceneContext','additionalInstructions','production'].contains(key)) ||
          json['ageMonths'] is! int || json['sceneContext'] is! String ||
          (json['additionalInstructions'] != null && json['additionalInstructions'] is! String)) {
        throw const FormatException('Üretim isteği v2 alanları geçersiz.');
      }
      return ScenarioGenerationRequest(behaviorId: refs.first.behaviorId, cardVersion: refs.first.cardVersion,
        behaviors: refs, extendedContract: true, ageMonths: json['ageMonths'] as int, sceneContext: json['sceneContext'] as String,
        additionalInstructions: json['additionalInstructions'] as String?,
        production: json['production'] == null ? null : ScenarioProductionSettings.fromJson(Map<String,dynamic>.from(json['production'] as Map)));
    }
    if (json.keys.any((key) => !['behaviorId','cardVersion','ageMonths','sceneContext','additionalInstructions'].contains(key)) ||
        json['behaviorId'] is! String || json['cardVersion'] is! String ||
        json['ageMonths'] is! int || json['sceneContext'] is! String ||
        (json['additionalInstructions'] != null && json['additionalInstructions'] is! String)) {
      throw const FormatException('Üretim isteği alanları geçersiz.');
    }
    return ScenarioGenerationRequest(behaviorId: json['behaviorId'] as String,
      cardVersion: json['cardVersion'] as String, ageMonths: json['ageMonths'] as int,
      sceneContext: json['sceneContext'] as String,
      additionalInstructions: json['additionalInstructions'] as String?);
  }
  BehaviorCard get card => BehaviorCards.all.firstWhere((card) => card.id == behaviorId);

  Map<String, Object?> toJson() => ageGroup != null ? {
    'requestVersion': '3.0', 'behaviors': behaviors.map((ref) => ref.toJson()).toList(),
    'ageGroup': ageGroup!.toJson(), 'sceneContext': sceneContext, 'additionalInstructions': additionalInstructions,
    if (production != null) 'production': production!.toJson(),
  } : extended ? {
    'requestVersion': '2.0', 'behaviors': behaviors.map((ref) => ref.toJson()).toList(),
    'ageMonths': ageMonths, 'sceneContext': sceneContext, 'additionalInstructions': additionalInstructions,
    if (production != null) 'production': production!.toJson(),
  } : {
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
      'schemaVersion': ageGroup != null ? '1.2' : extended ? '1.1' : ScenarioGraph.currentSchemaVersion,
      'scenarioId': scenarioId,
      'title': '${cards.map((card) => card.title).join(' / ')} senaryo taslağı',
      'language': 'tr', 'behaviorId': behaviorId,
      'cardVersion': cardVersion,
      if (ageGroup != null) 'ageGroup': ageGroup!.toJson() else 'ageMonths': ageMonths!,
    };
    if (extended) {
      final expected = behaviors.map((ref) => ref.toJson()).toList();
      if (decoded.containsKey('behaviors') && jsonEncode(decoded['behaviors']) != jsonEncode(expected)) {
        throw const FormatException('Davranış listesi doğrulanmış istekle uyuşmuyor.');
      }
      decoded = {...decoded, 'behaviors': expected};
      if (decoded['structure'] != (linear ? 'linear26' : 'branched')) {
        throw const FormatException('Anlatının üretim düzeni istekle uyuşmuyor.');
      }
      final allowed = behaviors.map((ref) => ref.behaviorId).toSet();
      final seen = <String>{};
      void binding(Object? value) {
        if (value is! List || value.isEmpty || value.toSet().length != value.length ||
            value.any((id) => id is! String || !allowed.contains(id))) {
          throw const FormatException('Sahne/davranış ilişkisi eksik veya geçersiz.');
        }
        seen.addAll(value.cast<String>());
      }
      if (linear) {
        final scenes = decoded['linearScenes'];
        if (scenes is! List || scenes.length != 26) throw const FormatException('Doğrusal düzen tam 26 sahne gerektirir.');
        for (final scene in scenes) { binding((scene as Map)['behaviorIds']); }
      } else {
        binding(decoded['commonBehaviorIds']);
        if (decoded['alternatives'] is! List) throw const FormatException('Alternatifler eksik.');
        for (final alternative in decoded['alternatives'] as List) { binding((alternative as Map)['behaviorIds']); }
      }
      if (!seen.containsAll(allowed)) throw const FormatException('Seçilen davranışların tümü anlatıda kapsanmalı.');
    }
    for (final entry in metadata.entries) {
      if (decoded.containsKey(entry.key) && jsonEncode(decoded[entry.key]) != jsonEncode(entry.value)) {
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
