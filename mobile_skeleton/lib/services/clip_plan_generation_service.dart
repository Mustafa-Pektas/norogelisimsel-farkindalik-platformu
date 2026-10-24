import 'dart:convert';
import '../models/scenario_generation_request.dart';
import '../models/scenario_graph.dart';
import 'scenario_generation_service.dart';

/// Graf ve ona ait bağlamın değişmez istek anlık görüntüsü. İçerik onayı değildir.
class ClipPlanGenerationRequest {
  ClipPlanGenerationRequest({required this.request, required this.graph, required this.planId}) {
    graph.validate();
    if (!RegExp(r'^generated-[A-Za-z0-9_-]+$').hasMatch(planId) ||
        graph.behaviorId != request.behaviorId || graph.cardVersion != request.cardVersion ||
        graph.ageMonths != request.ageMonths || (request.extended && graph.schemaVersion != '1.1') ||
        jsonEncode(graph.behaviors.map((ref) => ref.toJson()).toList()) !=
          jsonEncode(request.behaviors.map((ref) => ref.toJson()).toList())) {
      throw const FormatException('Graf ile doğrulanmış üretim isteği uyuşmuyor.');
    }
    if (request.linear && (graph.scenes.length != 26 || graph.scenes.any((scene) =>
        graph.transitions.where((edge) => edge.fromSceneId == scene.id).length > 1))) {
      throw const FormatException('İstekteki 26 sahnelik doğrusal düzen ile graf uyuşmuyor.');
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
