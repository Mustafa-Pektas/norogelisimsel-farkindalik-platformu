import '../models/scenario_graph.dart';
import '../models/scenario_input.dart';

/// Girdiden tek düzeyli dallı veya doğrusal graf üretir; LLM/dosya/ekran kullanmaz.
class ScenarioGraphConverter {
  const ScenarioGraphConverter();

  ScenarioGraph convert(ScenarioInput input) {
    const startId = 'start';
    final scenes = <ScenarioScene>[
      ScenarioScene(
        id: startId,
        title: 'Ortak başlangıç',
        description: input.commonStart,
        behaviorIds: input.commonBehaviorIds,
      ),
    ];
    final transitions = <ScenarioTransition>[];
    final endIds = <String>[];
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
    if (input.structure == 'linear26') {
      scenes.clear(); transitions.clear(); endIds.clear();
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
          '$sourceNote ${input.structure == 'linear26' ? 'Planlanan doğrusal olaylardır' : 'Planlanan alternatiflerdir'}; '
          'gözlenmiş davranış veya video ground_truth değildir. '
          'İçeriğin doğruluğu bu dönüşümle onaylanmaz.'
          '${input.structure == 'linear26' ? '\nGenel anlatı:\n${input.commonStart}' : ''}',
    );
  }
}
