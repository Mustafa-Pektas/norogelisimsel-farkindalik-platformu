import 'dart:convert';

import 'scenario_generation_request.dart';
import 'scenario_input.dart';

/// Tek bir gerçek cevabın kimliği. Ham cevap düzenlenmiş editör metni değildir.
class ScenarioGenerationResult {
  ScenarioGenerationResult({required this.scenarioId, required this.request,
    required this.rawResponse, this.arm, this.model, this.protocolId, this.outputContract,
    Map<String, dynamic>? settings, Map<String, dynamic>? measurement,
    Map<String, dynamic>? behaviorSource})
      : settings = _copy(settings), measurement = _copy(measurement), behaviorSource = _copy(behaviorSource) {
    if (scenarioId.trim().isEmpty || (arm != null && !['A', 'B', 'C'].contains(arm))) {
      throw const FormatException('Üretim sonucu kimliği veya deney kolu geçersiz.');
    }
    if (outputContract != null && outputContract != contract && outputContract != 'scenario-input-narrative-v2') {
      throw const FormatException('Üretim sonucu eski veya farklı bir anlatı sözleşmesine ait.');
    }
    if (outputContract == 'scenario-input-narrative-v2' && request.extended) {
      throw const FormatException('Eski protokol çoklu davranış/doğrusal düzen için kullanılamaz.');
    }
    ScenarioInput.fromJsonString(request.prepareInput(rawResponse,
      scenarioId: scenarioId, edited: false).json);
  }

  static int _sequence = 0;
  static String newId() => 'generated-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
  static const contract = 'scenario-input-narrative-v3';

  factory ScenarioGenerationResult.fromServer(ScenarioGenerationRequest request,
      Map<String, dynamic> body) {
    final raw = body['rawResponse'];
    if (raw is! String) throw const FormatException('Ham senaryo cevabı eksik.');
    final info = body['comparison'] is Map
        ? Map<String, dynamic>.from(body['comparison'] as Map) : body;
    if (info['outputContract'] != null && info['outputContract'] != contract) {
      throw const FormatException('Gelen sonuç eski üretim protokolüne ait; yeni sonuç olarak kabul edilmedi.');
    }
    return ScenarioGenerationResult(scenarioId: newId(), request: request, rawResponse: raw,
      arm: info['arm'] as String?, model: info['model'] as String?,
      protocolId: info['protocolId'] as String?, outputContract: info['outputContract'] as String?,
      settings: _map(info['settings']), measurement: _map(body['measurement']),
      behaviorSource: _map(info['source'] ?? body['behaviorSource']));
  }

  factory ScenarioGenerationResult.fromJson(Map<String, dynamic> json) {
    if (json['source'] != 'model_output' || json['scenarioId'] is! String ||
        json['rawResponse'] is! String || json['request'] is! Map) {
      throw const FormatException('Kayıtlı üretim sonucu/kaynak ilişkisi geçersiz.');
    }
    return ScenarioGenerationResult(scenarioId: json['scenarioId'] as String,
      request: ScenarioGenerationRequest.fromJson(Map<String, dynamic>.from(json['request'] as Map)),
      rawResponse: json['rawResponse'] as String, arm: json['arm'] as String?, model: json['model'] as String?,
      protocolId: json['protocolId'] as String?, outputContract: json['outputContract'] as String?,
      settings: _map(json['settings']), measurement: _map(json['measurement']),
      behaviorSource: _map(json['behaviorSource']));
  }

  final String scenarioId;
  final ScenarioGenerationRequest request;
  final String rawResponse;
  final String? arm, model, protocolId, outputContract;
  final Map<String, dynamic>? settings, measurement, behaviorSource;

  Map<String, dynamic> toJson() => {
    'scenarioId': scenarioId, 'request': request.toJson(), 'rawResponse': rawResponse,
    'source': 'model_output', 'arm': arm, 'model': model, 'protocolId': protocolId,
    'outputContract': outputContract, 'settings': settings, 'measurement': measurement,
    'behaviorSource': behaviorSource,
  };

  String get summary => 'Senaryo: $scenarioId · ${request.behaviors.map((ref) => ref.behaviorId).join(', ')} / ${request.ageMonths} ay · '
      'Kol: ${arm ?? 'normal üretim'} · Model: ${model ?? 'Bilinmiyor'}';
}

Map<String, dynamic>? _map(Object? value) => value == null ? null :
    Map<String, dynamic>.from(value as Map);
Map<String, dynamic>? _copy(Map<String, dynamic>? value) => value == null ? null :
    Map.unmodifiable(jsonDecode(jsonEncode(value)) as Map<String, dynamic>);
