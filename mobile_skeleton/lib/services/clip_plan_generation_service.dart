import '../models/scenario_generation_request.dart';
import '../models/scenario_graph.dart';
import 'scenario_generation_service.dart';

/// Graf ve ona ait bağlamın değişmez istek anlık görüntüsü. İçerik onayı değildir.
class ClipPlanGenerationRequest {
  ClipPlanGenerationRequest({required this.request, required this.graph, required this.planId}) {
    graph.validate();
    if (!RegExp(r'^generated-[A-Za-z0-9_-]+$').hasMatch(planId) ||
        graph.behaviorId != request.behaviorId || graph.cardVersion != request.cardVersion ||
        graph.ageMonths != request.ageMonths) {
      throw const FormatException('Graf ile doğrulanmış üretim isteği uyuşmuyor.');
    }
  }
  final ScenarioGenerationRequest request;
  final ScenarioGraph graph;
  final String planId;
  Map<String, dynamic> toJson() => {
    'request': request.toJson(), 'graph': graph.toJson(), 'planId': planId,
  };
}

abstract interface class ClipPlanGenerationService {
  ScenarioGenerationJob startPlan(ClipPlanGenerationRequest request);
}
