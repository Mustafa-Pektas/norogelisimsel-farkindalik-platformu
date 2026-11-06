import '../models/scenario_graph.dart';
import '../models/scenario_input.dart';

/// Girdiden tek düzeyli dallı veya doğrusal graf üretir; LLM/dosya/ekran kullanmaz.
class ScenarioGraphConverter {
  const ScenarioGraphConverter();

  ScenarioGraph convert(ScenarioInput input) {
    const startId = 'start';
    final scenes = <ScenarioScene>[];
    final transitions = <ScenarioTransition>[];
    final endIds = <String>[];

    if (input.structure == 'linear26') {
      for (var i = 0; i < input.linearScenes.length; i++) {
        final narrative = input.linearScenes[i];
        final id = i == 0 ? startId : 'scene_${i + 1}';
        scenes.add(ScenarioScene(id: id, title: narrative.title, description: narrative.description,
          behaviorIds: narrative.behaviorIds));
        if (i > 0) {
          transitions.add(ScenarioTransition(fromSceneId: scenes[i - 1].id,
            toSceneId: id, description: narrative.title));
        }
      }
      endIds.add(scenes.last.id);
    } else if (input.stages != null && input.stages!.length >= 2) {
      // Çoklu davranış sıralı aşamalı karar ağacı (Aşama 1 -> Aşama 2 -> ... -> Aşama N -> Klinik Bitişler)
      scenes.add(ScenarioScene(
        id: startId,
        title: 'Ortak başlangıç',
        description: input.commonStart,
        behaviorIds: input.commonBehaviorIds ?? input.behaviors.map((r) => r.behaviorId).toList(),
      ));

      // N aşamalı karar ağacı için seviye seviye genişletme (BFS)
      var currentParents = [
        (id: startId, pathSummary: <String>[], outcomeKey: '')
      ];

      for (var sIdx = 0; sIdx < input.stages!.length; sIdx++) {
        final stage = input.stages![sIdx];
        final nextLevel = <({String id, List<String> pathSummary, String outcomeKey})>[];

        for (final parent in currentParents) {
          for (final b in stage.branches) {
            final isTyp = b.branchType == 'typical';
            final outcomeKey = '${parent.outcomeKey}${isTyp ? '+' : '-'}${stage.behaviorId}';
            final nodeId = sIdx == 0
                ? 'stage1_${b.branchType}'
                : '${parent.id}_to_${stage.behaviorId}_${b.branchType}';

            final contextPrefix = sIdx == 0
                ? ''
                : 'Önceki adım (${parent.pathSummary.last}) sonrasında:\n';

            scenes.add(ScenarioScene(
              id: nodeId,
              title: '${stage.title}: ${b.title}',
              description: '$contextPrefix${stage.prompt}\n\n${b.continuation}${b.ending == null ? '' : '\n${b.ending}'}',
              behaviorIds: [stage.behaviorId],
            ));

            transitions.add(ScenarioTransition(
              fromSceneId: parent.id,
              toSceneId: nodeId,
              label: b.title,
              description: b.continuation,
            ));

            nextLevel.add((
              id: nodeId,
              pathSummary: [...parent.pathSummary, '${stage.behaviorId}: ${b.title}'],
              outcomeKey: outcomeKey,
            ));
          }
        }
        currentParents = nextLevel;
      }

      // Son aşamadaki yaprak düğümlerden klinik bitiş sahnelerine geçişler
      for (var i = 0; i < currentParents.length; i++) {
        final leaf = currentParents[i];
        final endingId = 'ending_${leaf.id}';

        final matches = input.alternatives.where((a) => a.outcomeKey == leaf.outcomeKey).toList();
        if (matches.length != 1) {
          throw FormatException('outcomeKey için tek bitiş bulunamadı: ${leaf.outcomeKey}.');
        }
        final endingDesc = matches.single.ending;

        scenes.add(ScenarioScene(
          id: endingId,
          title: 'Bitiş: ${leaf.outcomeKey}',
          description: endingDesc,
          behaviorIds: input.behaviors.map((r) => r.behaviorId).toList(),
        ));

        transitions.add(ScenarioTransition(
          fromSceneId: leaf.id,
          toSceneId: endingId,
          label: 'Klinik Sonuç',
          description: endingDesc,
        ));

        endIds.add(endingId);
      }
    } else {
      // Tek düzeyli dallanma (Tek davranış veya stages tanımlanmamış durumlar)
      scenes.add(ScenarioScene(
        id: startId,
        title: 'Ortak başlangıç',
        description: input.commonStart,
        behaviorIds: input.commonBehaviorIds,
      ));
      for (var i = 0; i < input.alternatives.length; i++) {
        final alternative = input.alternatives[i];
        final continuationId = 'alternative_${i + 1}';
        final endingId = 'ending_${i + 1}';
        scenes.addAll([
          ScenarioScene(
            id: continuationId,
            title: alternative.title,
            description: alternative.continuation,
            behaviorIds: alternative.behaviorIds,
          ),
          ScenarioScene(
            id: endingId,
            title: 'Bitiş: ${alternative.title}',
            description: alternative.ending,
            behaviorIds: alternative.behaviorIds,
          ),
        ]);
        transitions.addAll([
          ScenarioTransition(
            fromSceneId: startId,
            toSceneId: continuationId,
            label: alternative.title,
            description: alternative.continuation,
          ),
          ScenarioTransition(
            fromSceneId: continuationId,
            toSceneId: endingId,
            label: 'Bitiş',
            description: alternative.ending,
          ),
        ]);
        endIds.add(endingId);
      }
    }
    final sourceNote = switch (input.source) {
      ScenarioInputSource.manualExample => 'Elle hazırlanmış örnek senaryo.',
      ScenarioInputSource.modelOutput =>
        'Kaynak beyanı: gerçek model çıktısı; bu servis çıkarım çalıştırmaz.',
      ScenarioInputSource.editedModelOutput =>
        'Kaynak beyanı: kullanıcı tarafından düzenlenmiş model taslağı; '
        'değiştirilmemiş ham model cevabı değildir.',
    };
    // Kurucu mevcut grafın bağlantı/erişilebilirlik/bitiş kurallarını doğrular.
    return ScenarioGraph(
      schemaVersion: input.schemaVersion,
      scenarioId: input.scenarioId,
      title: input.title,
      language: input.language,
      ageMonths: input.ageMonths,
      ageGroup: input.ageGroup,
      behaviorId: input.behaviorId,
      cardVersion: input.cardVersion,
      behaviors: input.behaviors,
      startSceneId: startId,
      scenes: scenes,
      transitions: transitions,
      endSceneIds: endIds,
      authoringNote:
          '$sourceNote ${input.structure == 'linear26' ? 'Planlanan doğrusal olaylardır' : (input.stages != null && input.stages!.length >= 2 ? 'Planlanan çok aşamalı sıralı gözlem grafıdır' : 'Planlanan alternatiflerdir')}; '
          'gözlenmiş davranış veya video ground_truth değildir. '
          'İçeriğin doğruluğu bu dönüşümle onaylanmaz.'
          '${input.structure == 'linear26' ? '\nGenel anlatı:\n${input.commonStart}' : ''}',
    );
  }
}
