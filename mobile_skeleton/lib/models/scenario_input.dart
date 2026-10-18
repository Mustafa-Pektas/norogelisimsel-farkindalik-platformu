import 'dart:convert';

import 'scenario_graph.dart';

/// Kaynak beyanıdır; modelin çalıştığını veya olayın gözlendiğini doğrulamaz.
enum ScenarioInputSource { manualExample, modelOutput, editedModelOutput }

/// Tek bir alternatifin içeriği. Sahne kimliği veya bağlantı içermez.
class ScenarioInputAlternative {
  ScenarioInputAlternative({
    required this.title,
    required this.continuation,
    required this.ending,
  }) {
    _text(title, 'Alternatif başlığı');
    _text(continuation, 'Alternatif devam metni');
    _text(ending, 'Alternatif bitiş metni');
  }

  factory ScenarioInputAlternative.fromJson(Map<String, dynamic> json) {
    _onlyFields(json, const {'title', 'continuation', 'ending'}, 'Alternatif');
    return ScenarioInputAlternative(
      title: _readText(json, 'title'),
      continuation: _readText(json, 'continuation'),
      ending: _readText(json, 'ending'),
    );
  }

  final String title;
  final String continuation;
  final String ending;
}

/// Tek dallanma düzeyli senaryo girdisi; serbest LLM cevabını ayrıştırmaz.
///
/// Bütün anlatı metinleri boşlukları dahil olduğu gibi saklanır. Kontroller
/// yapısaldır; olayların anlamsal doğruluğunu veya D01 uygunluğunu onaylamaz.
class ScenarioInput {
  ScenarioInput({
    required this.schemaVersion,
    required this.scenarioId,
    required this.title,
    required this.language,
    required this.ageMonths,
    required this.behaviorId,
    required this.cardVersion,
    required this.source,
    required this.commonStart,
    required List<ScenarioInputAlternative> alternatives,
  }) : alternatives = List.unmodifiable(alternatives) {
    _text(schemaVersion, 'schemaVersion');
    if (schemaVersion != ScenarioGraph.currentSchemaVersion) {
      throw FormatException('Desteklenmeyen şema sürümü: $schemaVersion.');
    }
    _text(scenarioId, 'scenarioId');
    _text(title, 'title');
    _text(language, 'language');
    _text(behaviorId, 'behaviorId');
    _text(cardVersion, 'cardVersion');
    _text(commonStart, 'commonStart');
    if (ageMonths <= 0) {
      throw const FormatException('ageMonths pozitif bir tam sayı olmalıdır.');
    }
    if (this.alternatives.isEmpty) {
      throw const FormatException(
        'alternatives en az bir alternatif içermelidir.',
      );
    }
  }

  factory ScenarioInput.fromJson(Map<String, dynamic> json) {
    _onlyFields(json, const {
      'schemaVersion',
      'scenarioId',
      'title',
      'language',
      'ageMonths',
      'behaviorId',
      'cardVersion',
      'source',
      'commonStart',
      'alternatives',
    }, 'Senaryo girdisi');
    final age = json['ageMonths'];
    if (age is! int) {
      throw const FormatException('ageMonths ay cinsinden tam sayı olmalıdır.');
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
      ageMonths: age,
      behaviorId: _readText(json, 'behaviorId'),
      cardVersion: _readText(json, 'cardVersion'),
      source: source,
      commonStart: _readText(json, 'commonStart'),
      alternatives: alternatives,
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
  final int ageMonths;
  final String behaviorId;
  final String cardVersion;
  final ScenarioInputSource source;
  final String commonStart;
  final List<ScenarioInputAlternative> alternatives;
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
