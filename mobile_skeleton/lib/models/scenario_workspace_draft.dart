import 'dart:convert';

import 'behavior_cards.dart';
import 'scenario_generation_request.dart';
import 'scenario_generation_result.dart';
import 'scenario_age_group.dart';

/// Yalnız düzenlenebilir çalışma verisi. Graf, iş veya başarı durumu içermez.
class ScenarioWorkspaceDraft {
  ScenarioWorkspaceDraft({required this.inputType, required this.scenarioJson,
    required this.graphJson, required this.ageText, required this.contextText,
    required this.instructionsText, this.behaviorId, this.cardVersion,
    this.generationRaw, this.responseRequest, this.responseScenarioId,
    this.ageGroup,
    this.editorRequest, this.editorScenarioId, this.demoRaw = '',
    this.responseResult, this.editorResult, this.pendingResult,
    this.demoDraft = false, this.demoEdited = false, this.generationEdited = false}) {
    if (inputType != 'scenario' && inputType != 'graph') {
      throw const FormatException('Taslak girdi türü desteklenmiyor.');
    }
    if (behaviorId != null) {
      final cards = BehaviorCards.all.where((card) => card.id == behaviorId);
      if (cards.isEmpty || cards.single.cardVersion != cardVersion) {
        throw const FormatException('Taslağın davranış/kart sürümü güncel değil.');
      }
    } else if (cardVersion != null) {
      throw const FormatException('Taslağın kart kimliği eksik.');
    }
    if ((generationRaw != null) != (responseRequest != null) ||
        (responseRequest != null) != (responseScenarioId != null) ||
        (editorRequest != null) != (editorScenarioId != null) ||
        (demoDraft && editorRequest != null) ||
        responseScenarioId?.trim().isEmpty == true || editorScenarioId?.trim().isEmpty == true) {
      throw const FormatException('Taslağın ham cevap/kaynak ilişkisi geçersiz.');
    }
    if ((responseResult != null && (responseResult!.scenarioId != responseScenarioId ||
        responseResult!.rawResponse != generationRaw ||
        jsonEncode(responseResult!.request.toJson()) != jsonEncode(responseRequest?.toJson()))) ||
        (editorResult != null && (editorResult!.scenarioId != editorScenarioId ||
        jsonEncode(editorResult!.request.toJson()) != jsonEncode(editorRequest?.toJson())))) {
      throw const FormatException('Taslağın üretim kimliği/kaynağı uyuşmuyor.');
    }
  }

  final String inputType;
  final String scenarioJson;
  final String graphJson;
  final String ageText;
  final String contextText;
  final String instructionsText;
  final String? behaviorId;
  final String? cardVersion;
  final String? generationRaw;
  /// New age contract selected for future generation; absent on old drafts.
  final ScenarioAgeGroup? ageGroup;
  final String? responseScenarioId;
  final String? editorScenarioId;
  final ScenarioGenerationRequest? responseRequest;
  final ScenarioGenerationRequest? editorRequest;
  final String demoRaw;
  final bool demoDraft;
  final bool demoEdited;
  final bool generationEdited;
  final ScenarioGenerationResult? responseResult, editorResult, pendingResult;

  String toJsonString() => jsonEncode({
    'version': 1, 'inputType': inputType, 'scenarioJson': scenarioJson, 'graphJson': graphJson,
    'ageText': ageText, 'contextText': contextText, 'instructionsText': instructionsText,
    'behaviorId': behaviorId, 'cardVersion': cardVersion,
    'generationRaw': generationRaw, 'responseRequest': _requestJson(responseRequest),
    'ageGroup': ageGroup?.toJson(),
    'responseScenarioId': responseScenarioId, 'editorRequest': _requestJson(editorRequest),
    'editorScenarioId': editorScenarioId, 'generationEdited': generationEdited,
    'responseResult': responseResult?.toJson(), 'editorResult': editorResult?.toJson(),
    'pendingResult': pendingResult?.toJson(),
    'demoRaw': demoRaw, 'demoSource': 'local_d01_demo',
    'demoDraft': demoDraft, 'demoEdited': demoEdited,
  });

  factory ScenarioWorkspaceDraft.fromJsonString(String text) {
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic> || value['version'] != 1 ||
        value['demoSource'] != 'local_d01_demo') {
      throw const FormatException('Kayıtlı taslak biçimi/sürümü desteklenmiyor.');
    }
    String string(String key) {
      if (value[key] is! String) throw FormatException('Taslak alanı geçersiz: $key.');
      return value[key] as String;
    }
    String? optional(String key) {
      if (!value.containsKey(key) || (value[key] != null && value[key] is! String)) {
        throw FormatException('Taslak alanı geçersiz: $key.');
      }
      return value[key] as String?;
    }
    bool flag(String key) {
      if (value[key] is! bool) throw FormatException('Taslak alanı geçersiz: $key.');
      return value[key] as bool;
    }
    return ScenarioWorkspaceDraft(inputType: string('inputType'), scenarioJson: string('scenarioJson'),
      graphJson: string('graphJson'), ageText: string('ageText'), contextText: string('contextText'),
      instructionsText: string('instructionsText'), behaviorId: optional('behaviorId'),
      cardVersion: optional('cardVersion'), generationRaw: optional('generationRaw'),
      ageGroup: value['ageGroup'] == null ? null : ScenarioAgeGroup.fromJson(value['ageGroup']),
      responseRequest: _readRequest(value['responseRequest']), responseScenarioId: optional('responseScenarioId'),
      editorRequest: _readRequest(value['editorRequest']), editorScenarioId: optional('editorScenarioId'),
      generationEdited: flag('generationEdited'), demoRaw: string('demoRaw'),
      responseResult: _result(value['responseResult']), editorResult: _result(value['editorResult']),
      pendingResult: _result(value['pendingResult']),
      demoDraft: flag('demoDraft'), demoEdited: flag('demoEdited'));
  }
}

ScenarioGenerationResult? _result(Object? value) => value == null ? null :
    ScenarioGenerationResult.fromJson(Map<String, dynamic>.from(value as Map));

Map<String, Object?>? _requestJson(ScenarioGenerationRequest? request) => request?.toJson();

ScenarioGenerationRequest? _readRequest(dynamic value) {
  if (value == null) return null;
  if (value is Map<String,dynamic> && ['2.0', '3.0'].contains(value['requestVersion'])) {
    return ScenarioGenerationRequest.fromJson(value);
  }
  if (value is! Map<String, dynamic> || value['behaviorId'] is! String ||
      value['cardVersion'] is! String || value['ageMonths'] is! int ||
      value['sceneContext'] is! String ||
      (value['additionalInstructions'] != null && value['additionalInstructions'] is! String)) {
    throw const FormatException('Taslağın üretim isteği geçersiz.');
  }
  return ScenarioGenerationRequest(behaviorId: value['behaviorId'] as String,
    cardVersion: value['cardVersion'] as String, ageMonths: value['ageMonths'] as int,
    sceneContext: value['sceneContext'] as String,
    additionalInstructions: value['additionalInstructions'] as String?);
}
