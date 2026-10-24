import 'package:flutter/material.dart';
import '../models/scenario_input.dart';
import '../models/scenario_generation_request.dart';
import '../services/scenario_graph_converter.dart';

/// Modelin anlatısıdır; görsel prompt, video ölçümü veya içerik onayı değildir.
class ScenarioNarrativeCards extends StatelessWidget {
  const ScenarioNarrativeCards({super.key, required this.input, this.request});
  final ScenarioInput input;
  final ScenarioGenerationRequest? request;
  @override
  Widget build(BuildContext context) {
    final graph = const ScenarioGraphConverter().convert(input);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(color: const Color(0xFFEAF3FF), child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(input.structure == 'linear26' ? 'Doğrusal senaryo · 26 sahne' : 'Alternatifli senaryo',
            style: Theme.of(context).textTheme.titleMedium),
          Text('Oluşturulan: ${graph.scenes.length} sahne · ${graph.transitions.length} bağlantı',
            key: const ValueKey('narrative-scene-count')),
          if (request?.production != null) Text('Hedef: ${request!.production!.targetDurationS} sn'
            '${request!.linear ? ' · 26 sahne' : ''} · klip başına en fazla ${request!.production!.maxClipDurationS} sn'),
          const Text('Sahneler planlanan olaylardır. Süre, görsel prompt ve ayrı seslendirme sonraki klip planında hazırlanır.'),
        ]))),
      if (input.structure == 'linear26') Padding(padding: const EdgeInsets.all(12), child: SelectableText(input.commonStart)),
      for (var index = 0; index < graph.scenes.length; index++) Card(
        key: ValueKey('narrative-scene:${graph.scenes[index].id}'),
        child: ExpansionTile(maintainState: true,
          title: Text('${index + 1}. ${graph.scenes[index].title ?? graph.scenes[index].id}'),
          subtitle: Text('Davranışlar: ${graph.behaviorIdsFor(graph.scenes[index]).join(', ')}'
            '${input.structure == 'linear26' ? ' · Düzen hedefi: ${index < 6 ? 'Başlangıç' : index < 17 ? 'İşlem/gözlem' : 'Kapanış'}' : ''}'
            '${graph.endSceneIds.contains(graph.scenes[index].id) ? ' · Bitiş' : ''}'),
          childrenPadding: const EdgeInsets.all(16), children: [
            Align(alignment: Alignment.centerLeft, child: SelectableText(graph.scenes[index].description)),
          ])),
    ]);
  }
}
