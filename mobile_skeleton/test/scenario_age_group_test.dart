import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_age_group.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/services/scenario_graph_converter.dart';

void main() {
  test('Sürümlü kimlikler ve eski ay eşlemesi sınırları nettir', () {
    expect(ScenarioAgeGroup.months12To18.toJson(), {'contractVersion': '1.0', 'id': '12_18'});
    expect(ScenarioAgeGroup.fromLegacyMonths(11), isNull);
    expect(ScenarioAgeGroup.fromLegacyMonths(12), ScenarioAgeGroup.months12To18);
    expect(ScenarioAgeGroup.fromLegacyMonths(17), ScenarioAgeGroup.months12To18);
    expect(ScenarioAgeGroup.fromLegacyMonths(18), ScenarioAgeGroup.months18To24);
    expect(ScenarioAgeGroup.fromLegacyMonths(23), ScenarioAgeGroup.months18To24);
    expect(ScenarioAgeGroup.fromLegacyMonths(24), ScenarioAgeGroup.months24To36);
    expect(ScenarioAgeGroup.fromLegacyMonths(36), ScenarioAgeGroup.months24To36);
    expect(ScenarioAgeGroup.fromLegacyMonths(37), isNull);
    expect(() => ScenarioAgeGroup.fromJson({'contractVersion': '2.0', 'id': '12_18'}), throwsFormatException);
    expect(() => ScenarioAgeGroup.fromJson({'contractVersion': '1.0', 'id': 'unknown'}), throwsFormatException);
  });

  test('Yeni üretim isteği geçerli bir yaş grubu ister ve tekil ay alanını reddeder', () {
    final valid = ScenarioGenerationRequest(behaviorId: 'D01', cardVersion: '0.2',
      ageGroup: ScenarioAgeGroup.months18To24, sceneContext: 'Evde oyun.').toJson();
    expect(() => ScenarioGenerationRequest.fromJson({...valid, 'ageGroup': null}), throwsFormatException);
    expect(() => ScenarioGenerationRequest.fromJson({...valid,
      'ageGroup': {'contractVersion': '1.0', 'id': '18_24', 'ageMonths': 18}}), throwsFormatException);
    expect(() => ScenarioGenerationRequest.fromJson({...valid, 'ageMonths': 18}), throwsFormatException);
    expect(() => ScenarioGenerationRequest(behaviorId: 'D01', cardVersion: '0.2',
      sceneContext: 'Evde oyun.'), throwsFormatException);
  });

  for (final group in ScenarioAgeGroup.values) {
    test('${group.id}: istek → anlatı → graf → klip planı metadata uyumu', () {
      final request = ScenarioGenerationRequest(behaviorId: 'D02', cardVersion: '0.2',
        ageGroup: group, sceneContext: 'Evde oyun.');
      expect(ScenarioGenerationRequest.fromJson(request.toJson()).ageGroup, group);
      expect(request.toJson().containsKey('ageMonths'), isFalse);
      final raw = jsonEncode({
        'structure': 'branched', 'commonStart': 'Ortak başlangıç.',
        'commonBehaviorIds': ['D02'],
        'alternatives': [
          {'title': 'Devam', 'continuation': 'Devam.', 'ending': 'Bitiş.', 'behaviorIds': ['D02']},
        ],
      });
      final input = ScenarioInput.fromJsonString(request.prepareInput(raw,
        scenarioId: 'scenario-${group.id}', edited: false).json);
      expect(input.schemaVersion, '1.2');
      expect(input.ageGroup, group);
      expect(input.ageMonths, isNull);
      final graph = const ScenarioGraphConverter().convert(input);
      final restoredGraph = ScenarioGraph.fromJsonString(graph.toJsonString());
      expect(restoredGraph.ageGroup, group);
      expect(restoredGraph.ageMonths, isNull);
      final plan = ScenarioClipPlan(schemaVersion: '1.1', planId: 'generated-${group.id}',
        scenarioId: graph.scenarioId, ageGroup: group, authoringNote: 'İncelenecek plan.',
        continuityNotes: 'Karakter ve ortam aynı kalmalı.',
        clips: [for (final scene in graph.scenes) PlannedClip(id: 'clip-${scene.id}',
          sceneId: scene.id, orderInScene: 1, targetDurationS: 4, plannedAction: scene.description,
          initialState: 'Önce.', finalState: 'Sonra.', productionPrompt: 'Üretim önerisi.')]);
      plan.validateAgainst(restoredGraph);
      final restoredPlan = ScenarioClipPlan.fromJsonString(plan.toJsonString());
      restoredPlan.validateAgainst(restoredGraph);
      expect(restoredPlan.ageGroup, group);
      expect(() => ScenarioClipPlan(schemaVersion: '1.1', planId: 'generated-other',
        scenarioId: graph.scenarioId, ageGroup: ScenarioAgeGroup.values.firstWhere((candidate) => candidate != group),
        authoringNote: 'Not.', continuityNotes: 'Not.', clips: plan.clips).validateAgainst(restoredGraph),
        throwsFormatException);
    });
  }

  test('Önceden paketlenmiş D01/D02 graf ve plan örnekleri eski ay şemasıyla okunur', () {
    const pairs = [
      ('assets/scenarios/d01_scenario_graph.json', 'assets/scenarios/d01_clip_plan.json', 30),
      ('assets/scenarios/d01_name_turning_graph.json', 'assets/scenarios/d01_name_turning_clip_plan.json', 36),
      ('assets/scenarios/d02_pointing_direction_graph.json', 'assets/scenarios/d02_pointing_direction_clip_plan.json', 36),
    ];
    for (final (graphPath, planPath, savedAge) in pairs) {
      final graph = ScenarioGraph.fromJsonString(File(graphPath).readAsStringSync());
      expect(graph.ageGroup, isNull);
      expect(graph.ageMonths, savedAge);
      final plan = ScenarioClipPlan.fromJsonString(File(planPath).readAsStringSync());
      expect(plan.schemaVersion, '1.0');
      plan.validateAgainst(graph);
    }
  });
}
