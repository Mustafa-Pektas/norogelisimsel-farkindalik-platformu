import 'dart:convert';

import 'scenario_graph.dart';
import 'scenario_behavior_ref.dart';
import 'scenario_age_group.dart';

/// Kaynak beyanıdır; modelin çalıştığını veya olayın gözlendiğini doğrulamaz.
enum ScenarioInputSource { manualExample, modelOutput, editedModelOutput }

/// Tek bir alternatifin içeriği. Sahne kimliği veya bağlantı içermez.
class ScenarioInputAlternative {
  ScenarioInputAlternative({
    required this.title,
    required this.continuation,
    required this.ending,
    List<String>? behaviorIds,
  }) : behaviorIds = behaviorIds == null ? null : List.unmodifiable(behaviorIds) {
    _text(title, 'Alternatif başlığı');
    _text(continuation, 'Alternatif devam metni');
    _text(ending, 'Alternatif bitiş metni');
  }

  factory ScenarioInputAlternative.fromJson(Map<String, dynamic> json) {
    _onlyFields(json, const {'title', 'continuation', 'ending', 'behaviorIds'}, 'Alternatif');
    return ScenarioInputAlternative(
      title: _readText(json, 'title'),
      continuation: _readText(json, 'continuation'),
      ending: _readText(json, 'ending'),
      behaviorIds: readScenarioBehaviorIds(json['behaviorIds'], optional: true),
    );
  }

  final String title;
  final String continuation;
  final String ending;
  final List<String>? behaviorIds;
}

class ScenarioNarrativeScene {
  ScenarioNarrativeScene({required this.title, required this.description, required List<String> behaviorIds})
      : behaviorIds = List.unmodifiable(behaviorIds) {
    _text(title, 'Sahne başlığı'); _text(description, 'Sahne anlatısı');
  }
  final String title, description;
  final List<String> behaviorIds;
  factory ScenarioNarrativeScene.fromJson(Map<String,dynamic> value) {
    _onlyFields(value, const {'title','description','behaviorIds'}, 'Anlatı sahnesi');
    return ScenarioNarrativeScene(title: _readText(value,'title'), description: _readText(value,'description'),
      behaviorIds: readScenarioBehaviorIds(value['behaviorIds'])!);
  }
}

/// Tek dallanma veya doğrusal 26 sahne anlatısı; serbest LLM cevabını ayrıştırmaz.
///
/// Bütün anlatı metinleri boşlukları dahil olduğu gibi saklanır. Kontroller
/// yapısaldır; olayların anlamsal doğruluğunu veya D01 uygunluğunu onaylamaz.
class ScenarioInput {
  ScenarioInput({
    required this.schemaVersion,
    required this.scenarioId,
    required this.title,
    required this.language,
    this.ageMonths,
    this.ageGroup,
    required this.behaviorId,
    required this.cardVersion,
    required this.source,
    required this.commonStart,
    required List<ScenarioInputAlternative> alternatives,
    List<ScenarioBehaviorRef>? behaviors, this.structure = 'branched', List<String>? commonBehaviorIds,
    List<ScenarioNarrativeScene> linearScenes = const [],
  }) : alternatives = List.unmodifiable(alternatives), linearScenes = List.unmodifiable(linearScenes),
       commonBehaviorIds = commonBehaviorIds == null ? null : List.unmodifiable(commonBehaviorIds),
       behaviors = List.unmodifiable(behaviors ?? [ScenarioBehaviorRef(behaviorId: behaviorId, cardVersion: cardVersion)]) {
    _text(schemaVersion, 'schemaVersion');
    if (schemaVersion != ScenarioGraph.currentSchemaVersion && schemaVersion != '1.1' && schemaVersion != '1.2') {
      throw FormatException('Desteklenmeyen şema sürümü: $schemaVersion.');
    }
    _text(scenarioId, 'scenarioId');
    _text(title, 'title');
    _text(language, 'language');
    _text(behaviorId, 'behaviorId');
    _text(cardVersion, 'cardVersion');
    for (final ref in this.behaviors) {
      _text(ref.behaviorId, 'Davranış referansı'); _text(ref.cardVersion, 'Kart sürümü');
    }
    _text(commonStart, 'commonStart');
    if (schemaVersion == '1.2') {
      if (ageGroup == null || ageMonths != null) {
        throw const FormatException('1.2 senaryosu yalnız sürümlü ageGroup taşımalıdır.');
      }
    } else if (ageMonths == null || ageMonths! <= 0 || ageGroup != null) {
      throw const FormatException('Eski şema pozitif ageMonths taşımalıdır.');
    }
    if (structure == 'branched' && this.alternatives.isEmpty) {
      throw const FormatException(
        'alternatives en az bir alternatif içermelidir.',
      );
    }
    if (!['branched','linear26'].contains(structure) ||
        (structure == 'linear26' && (!['1.1', '1.2'].contains(schemaVersion) || this.linearScenes.length != 26 || this.alternatives.isNotEmpty)) ||
        (structure == 'branched' && this.linearScenes.isNotEmpty)) {
      throw const FormatException('Anlatı düzeni/sahne sayısı uyuşmuyor; dal uydurulmadı.');
    }
    if (schemaVersion == '1.1' || schemaVersion == '1.2') {
      final selected = this.behaviors.map((ref) => ref.behaviorId).toSet();
      if (selected.length != this.behaviors.length || selected.isEmpty ||
          this.behaviors.first.behaviorId != behaviorId || this.behaviors.first.cardVersion != cardVersion) {
        throw const FormatException('Anlatı davranış listesi uyuşmuyor.');
      }
      final bindings = structure == 'linear26' ? this.linearScenes.map((s) => s.behaviorIds).toList()
        : [commonBehaviorIds, ...this.alternatives.map((a) => a.behaviorIds)];
      final covered = <String>{};
      for (final ids in bindings) {
        if (ids == null || ids.isEmpty || ids.toSet().length != ids.length || !selected.containsAll(ids)) {
          throw const FormatException('Anlatı sahnesinin davranışları eksik/geçersiz.');
        }
        covered.addAll(ids);
      }
      if (!covered.containsAll(selected)) throw const FormatException('Anlatı bütün seçilen davranışları kapsamıyor.');
    } else if (this.behaviors.length != 1 || structure != 'branched') {
      throw const FormatException('Çoklu/doğrusal içerik 1.1 şeması gerektirir.');
    }
  }

  factory ScenarioInput.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (['1.1', '1.2'].contains(schemaVersion) && json['behaviors'] == null) {
      throw FormatException('$schemaVersion senaryo girdisinde davranış referansları zorunludur.');
    }
    _onlyFields(json, const {
      'schemaVersion',
      'scenarioId',
      'title',
      'language',
      'ageMonths',
      'ageGroup',
      'behaviorId',
      'cardVersion',
      'source',
      'commonStart',
      'alternatives',
      'behaviors', 'structure', 'commonBehaviorIds', 'linearScenes',
    }, 'Senaryo girdisi');
    final age = json['ageMonths'];
    final ageGroup = schemaVersion == '1.2' ? ScenarioAgeGroup.fromJson(json['ageGroup']) : null;
    if (schemaVersion == '1.2' && json.containsKey('ageMonths')) {
      throw const FormatException('1.2 şemasında ageMonths kullanılamaz; sürümlü ageGroup gereklidir.');
    }
    if (schemaVersion != '1.2' && age is! int) {
      throw const FormatException('Eski şemada ageMonths eksik veya tam sayı değil.');
    }
    if (schemaVersion != '1.2' && json.containsKey('ageGroup')) {
      throw const FormatException('Eski şemada ageGroup kullanılamaz; ageMonths gereklidir.');
    }
    final sourceText = _readText(json, 'source');
    final source = switch (sourceText) {
      'manual_example' => ScenarioInputSource.manualExample,
      'model_output' => ScenarioInputSource.modelOutput,
      'model_output_edited' => ScenarioInputSource.editedModelOutput,
      _ => throw const FormatException(
        'source manual_example, model_output veya model_output_edited olmalıdır.',
      ),
    };
    final rawAlternatives = json['alternatives'];
    if (rawAlternatives is! List) {
      throw const FormatException('alternatives bir liste olmalıdır.');
    }
    final alternatives = <ScenarioInputAlternative>[];
    for (var i = 0; i < rawAlternatives.length; i++) {
      final entry = _object(rawAlternatives[i], 'alternatives[$i]');
      try {
        alternatives.add(ScenarioInputAlternative.fromJson(entry));
      } on FormatException catch (error) {
        throw FormatException('alternatives[$i]: ${error.message}');
      }
    }
    return ScenarioInput(
      schemaVersion: _readText(json, 'schemaVersion'),
      scenarioId: _readText(json, 'scenarioId'),
      title: _readText(json, 'title'),
      language: _readText(json, 'language'),
      ageMonths: age as int?,
      ageGroup: ageGroup,
      behaviorId: _readText(json, 'behaviorId'),
      cardVersion: _readText(json, 'cardVersion'),
      source: source,
      commonStart: _readText(json, 'commonStart'),
      alternatives: alternatives,
      behaviors: readScenarioBehaviors(json['behaviors']),
      structure: json['structure'] as String? ?? 'branched',
      commonBehaviorIds: readScenarioBehaviorIds(json['commonBehaviorIds'], optional: true),
      linearScenes: [for (final entry in json['linearScenes'] as List? ?? [])
        ScenarioNarrativeScene.fromJson(_object(entry, 'Anlatı sahnesi'))],
    );
  }

  factory ScenarioInput.fromJsonString(String value) {
    dynamic decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException catch (error) {
      throw FormatException('Senaryo JSON okunamadı: ${error.message}');
    }
    return ScenarioInput.fromJson(_object(decoded, 'Senaryo JSON kökü'));
  }

  final String schemaVersion;
  final String scenarioId;
  final String title;
  final String language;
  final int? ageMonths;
  final ScenarioAgeGroup? ageGroup;
  final String behaviorId;
  final String cardVersion;
  final ScenarioInputSource source;
  final String commonStart;
  final List<ScenarioInputAlternative> alternatives;
  final List<ScenarioBehaviorRef> behaviors;
  final String structure;
  final List<String>? commonBehaviorIds;
  final List<ScenarioNarrativeScene> linearScenes;
}

void _text(String value, String field) {
  if (value.trim().isEmpty) {
    throw FormatException('$field boş olamaz.');
  }
}

String _readText(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String) {
    throw FormatException('$field metin olmalıdır ve eksik bırakılamaz.');
  }
  _text(value, field);
  return value;
}

Map<String, dynamic> _object(dynamic value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field bir JSON nesnesi olmalıdır.');
  }
  return value;
}

void _onlyFields(
  Map<String, dynamic> json,
  Set<String> allowed,
  String context,
) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException(
      '$context desteklenmeyen alan içeriyor: ${unknown.join(', ')}.',
    );
  }
}
