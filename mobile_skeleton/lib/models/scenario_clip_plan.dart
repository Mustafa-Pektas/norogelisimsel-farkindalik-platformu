import 'dart:convert';

import 'scenario_graph.dart';

/// Üretim hedefidir; süre veya eylem gerçekleşmiş video kanıtı değildir.
class PlannedClip {
  PlannedClip({
    required this.id,
    required this.sceneId,
    required this.orderInScene,
    required this.targetDurationS,
    required this.plannedAction,
    required this.initialState,
    required this.finalState,
    required this.productionPrompt,
  }) {
    for (final entry in {
      'Klip kimliği': id,
      'Sahne kimliği': sceneId,
      'Planlanan eylem': plannedAction,
      'Başlangıç durumu': initialState,
      'Bitiş durumu': finalState,
      'Üretim promptu': productionPrompt,
    }.entries) {
      _text(entry.value, entry.key);
    }
    if (orderInScene <= 0) {
      throw FormatException('orderInScene pozitif tam sayı olmalıdır ($id).');
    }
    if (!targetDurationS.isFinite ||
        targetDurationS <= 0 ||
        targetDurationS > 8) {
      throw FormatException(
        'Klip süresi 0’dan büyük, en fazla 8 saniye olmalıdır ($id).',
      );
    }
  }

  factory PlannedClip.fromJson(Map<String, dynamic> json) {
    final order = json['orderInScene'];
    final duration = json['targetDurationS'];
    if (order is! int) {
      throw const FormatException('orderInScene tam sayı olmalıdır.');
    }
    if (duration is! num) {
      throw const FormatException('targetDurationS sayı olmalıdır.');
    }
    return PlannedClip(
      id: _string(json, 'id'),
      sceneId: _string(json, 'sceneId'),
      orderInScene: order,
      targetDurationS: duration.toDouble(),
      plannedAction: _string(json, 'plannedAction'),
      initialState: _string(json, 'initialState'),
      finalState: _string(json, 'finalState'),
      productionPrompt: _string(json, 'productionPrompt'),
    );
  }

  final String id;
  final String sceneId;

  /// Sahne içinde 1’den başlayan sıra; JSON listesinin sırasına bağlı değildir.
  final int orderInScene;
  final double targetDurationS;
  final String plannedAction;
  final String initialState;
  final String finalState;
  final String productionPrompt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sceneId': sceneId,
    'orderInScene': orderInScene,
    'targetDurationS': targetDurationS,
    'plannedAction': plannedAction,
    'initialState': initialState,
    'finalState': finalState,
    'productionPrompt': productionPrompt,
  };
}

/// Grafı değiştirmeyen ayrı klip planı. Sahne yolları ve dallar grafın işidir.
/// [validateAgainst] bütün sahnelerin kapsandığını ve referansları denetler.
/// Bu kontroller promptun uygulanabilirliğini veya gerçek video sürekliliğini
/// doğrulamaz; eylem/durum metinleri insan incelemesi gerektirir.
class ScenarioClipPlan {
  ScenarioClipPlan({
    required this.schemaVersion,
    required this.planId,
    required this.scenarioId,
    required this.authoringNote,
    required this.continuityNotes,
    required List<PlannedClip> clips,
  }) : clips = List.unmodifiable(clips) {
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Desteklenmeyen klip planı şema sürümü: $schemaVersion.',
      );
    }
    _text(planId, 'Plan kimliği');
    _text(scenarioId, 'Senaryo kimliği');
    _text(authoringNote, 'Taslak notu');
    _text(continuityNotes, 'Süreklilik notları');
    if (clips.isEmpty) {
      throw const FormatException('Klip planı boş olamaz.');
    }
    final ids = <String>{};
    final orders = <String, Set<int>>{};
    for (final clip in clips) {
      if (!ids.add(clip.id)) {
        throw FormatException('Tekrarlı klip kimliği: ${clip.id}.');
      }
      final sceneOrders = orders.putIfAbsent(clip.sceneId, () => <int>{});
      if (!sceneOrders.add(clip.orderInScene)) {
        throw FormatException(
          'Tekrarlı klip sırası: ${clip.sceneId}/${clip.orderInScene}.',
        );
      }
    }
    for (final entry in orders.entries) {
      for (var order = 1; order <= entry.value.length; order++) {
        if (!entry.value.contains(order)) {
          throw FormatException(
            'Klip sırası 1’den başlayıp kesintisiz ilerlemeli: ${entry.key}.',
          );
        }
      }
    }
  }

  factory ScenarioClipPlan.fromJson(Map<String, dynamic> json) {
    final raw = json['clips'];
    if (raw is! List) {
      throw const FormatException('clips liste olmalıdır.');
    }
    return ScenarioClipPlan(
      schemaVersion: _string(json, 'schemaVersion'),
      planId: _string(json, 'planId'),
      scenarioId: _string(json, 'scenarioId'),
      authoringNote: _string(json, 'authoringNote'),
      continuityNotes: _string(json, 'continuityNotes'),
      clips: [
        for (var i = 0; i < raw.length; i++)
          PlannedClip.fromJson(_object(raw[i], 'clips[$i]')),
      ],
    );
  }

  factory ScenarioClipPlan.fromJsonString(String source) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Klip planı JSON okunamadı: ${error.message}');
    }
    return ScenarioClipPlan.fromJson(_object(decoded, 'Klip planı JSON kökü'));
  }

  static const currentSchemaVersion = '1.0';
  final String schemaVersion;
  final String planId;
  final String scenarioId;
  final String authoringNote;
  final String continuityNotes;
  final List<PlannedClip> clips;

  List<PlannedClip> clipsForScene(String sceneId) => List.unmodifiable(
    clips.where((clip) => clip.sceneId == sceneId).toList()
      ..sort((a, b) => a.orderInScene.compareTo(b.orderInScene)),
  );

  void validateAgainst(ScenarioGraph graph) {
    if (scenarioId != graph.scenarioId) {
      throw FormatException('Klip planı başka senaryoya ait: $scenarioId.');
    }
    final sceneIds = graph.scenes.map((scene) => scene.id).toSet();
    for (final clip in clips) {
      if (!sceneIds.contains(clip.sceneId)) {
        throw FormatException(
          'Klip mevcut olmayan sahneye bağlanıyor: ${clip.id} → ${clip.sceneId}.',
        );
      }
    }
    final missing = sceneIds.difference(
      clips.map((clip) => clip.sceneId).toSet(),
    );
    if (missing.isNotEmpty) {
      throw FormatException(
        'Klip planında eksik sahneler: ${missing.join(', ')}.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'planId': planId,
    'scenarioId': scenarioId,
    'authoringNote': authoringNote,
    'continuityNotes': continuityNotes,
    'clips': [for (final clip in clips) clip.toJson()],
  };

  String toJsonString({bool pretty = false}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());
}

void _text(String value, String field) {
  if (value.trim().isEmpty) throw FormatException('$field boş olamaz.');
}

String _string(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String) throw FormatException('$field metin olmalıdır.');
  return value;
}

Map<String, dynamic> _object(dynamic value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field JSON nesnesi olmalıdır.');
  }
  return value;
}
