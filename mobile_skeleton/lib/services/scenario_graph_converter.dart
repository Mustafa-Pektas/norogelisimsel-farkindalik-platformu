import '../models/scenario_graph.dart';
import '../models/scenario_input.dart';

/// Girdi içeriğinden tek düzeyli graf üretir; LLM, dosya veya ekran kullanmaz.
class ScenarioGraphConverter {
  const ScenarioGraphConverter();

  ScenarioGraph convert(ScenarioInput input) {
    const startId = 'start';
    final scenes = <ScenarioScene>[
      ScenarioScene(
        id: startId,
        title: 'Ortak başlangıç',
        description: input.commonStart,
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
        ),
        ScenarioScene(
          id: endingId,
          title: 'Bitiş: ${alternative.title}',
          description: alternative.ending,
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
      behaviorId: input.behaviorId,
      cardVersion: input.cardVersion,
      startSceneId: startId,
      scenes: scenes,
      transitions: transitions,
      endSceneIds: endIds,
      authoringNote:
          '$sourceNote Planlanan alternatiflerdir; '
          'gözlenmiş davranış veya video ground_truth değildir. '
          'İçeriğin doğruluğu bu dönüşümle onaylanmaz.',
    );
  }
}
