import 'dart:convert';

import 'scenario_graph.dart';
import 'scenario_age_group.dart';
import 'behavior_cards.dart';

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
    this.voiceoverInstructions,
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
    if (voiceoverInstructions != null) {
      _text(voiceoverInstructions!, 'Seslendirme yönergeleri');
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
      voiceoverInstructions: json['voiceoverInstructions'] == null ? null : _string(json, 'voiceoverInstructions'),
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
  final String? voiceoverInstructions;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sceneId': sceneId,
    'orderInScene': orderInScene,
    'targetDurationS': targetDurationS,
    'plannedAction': plannedAction,
    'initialState': initialState,
    'finalState': finalState,
    'productionPrompt': productionPrompt,
    if (voiceoverInstructions != null) 'voiceoverInstructions': voiceoverInstructions,
  };
}

/// Yalnız D01 için önerilen çağrı bitişi; ölçülmüş video etiketi değildir.
class D01PlannedCall {
  D01PlannedCall({required this.clipId, required this.callEndS}) {
    _text(clipId, 'D01 çağrı klibi');
    if (!callEndS.isFinite || callEndS <= 0) {
      throw const FormatException('D01 çağrı bitişi pozitif sayısal saniye olmalıdır.');
    }
  }
  final String clipId;
  final double callEndS;
  factory D01PlannedCall.fromJson(Map<String, dynamic> json) {
    final end = json['callEndS'];
    if (end is! num || json.keys.any((key) => !['clipId', 'callEndS'].contains(key))) {
      throw const FormatException('D01 çağrı zamanlaması geçersiz.');
    }
    return D01PlannedCall(clipId: _string(json, 'clipId'), callEndS: end.toDouble());
  }
  Map<String, dynamic> toJson() => {'clipId': clipId, 'callEndS': callEndS};
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
    this.visualSuggestions,
    this.ageGroup,
    List<D01PlannedCall>? d01CallTiming,
    required List<PlannedClip> clips,
  }) : d01CallTiming = d01CallTiming == null ? null : List.unmodifiable(d01CallTiming),
       clips = List.unmodifiable(clips) {
    if (schemaVersion != currentSchemaVersion && schemaVersion != ageGroupSchemaVersion) {
      throw FormatException(
        'Desteklenmeyen klip planı şema sürümü: $schemaVersion.',
      );
    }
    _text(planId, 'Plan kimliği');
    _text(scenarioId, 'Senaryo kimliği');
    if ((schemaVersion == ageGroupSchemaVersion) != (ageGroup != null)) {
      throw const FormatException('Klip planı yaş grubu şema sürümüyle uyuşmuyor.');
    }
    _text(authoringNote, 'Taslak notu');
    _text(continuityNotes, 'Süreklilik notları');
    if (visualSuggestions != null) {
      _text(visualSuggestions!, 'Üretilmiş görsel öneriler');
    }
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
    final timing = json['d01CallTiming'];
    if (timing != null && timing is! List) {
      throw const FormatException('d01CallTiming liste olmalıdır.');
    }
    return ScenarioClipPlan(
      d01CallTiming: timing == null ? null : [for (final call in timing as List)
        D01PlannedCall.fromJson(_object(call, 'D01 çağrı'))],
      schemaVersion: _string(json, 'schemaVersion'),
      planId: _string(json, 'planId'),
      scenarioId: _string(json, 'scenarioId'),
      authoringNote: _string(json, 'authoringNote'),
      continuityNotes: _string(json, 'continuityNotes'),
      visualSuggestions: json['visualSuggestions'] == null ? null : _string(json, 'visualSuggestions'),
      ageGroup: json['ageGroup'] == null ? null : ScenarioAgeGroup.fromJson(json['ageGroup']),
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
  static const ageGroupSchemaVersion = '1.1';
  final String schemaVersion;
  final String planId;
  final String scenarioId;
  final String authoringNote;
  final String continuityNotes;
  final String? visualSuggestions;
  final ScenarioAgeGroup? ageGroup;
  final List<PlannedClip> clips;
  final List<D01PlannedCall>? d01CallTiming;

  List<PlannedClip> clipsForScene(String sceneId) => List.unmodifiable(
    clips.where((clip) => clip.sceneId == sceneId).toList()
      ..sort((a, b) => a.orderInScene.compareTo(b.orderInScene)),
  );

  void validateAgainst(ScenarioGraph graph) {
    if (scenarioId != graph.scenarioId) {
      throw FormatException('Klip planı başka senaryoya ait: $scenarioId.');
    }
    if (graph.ageGroup != ageGroup ||
        (graph.ageGroup == null && schemaVersion != currentSchemaVersion) ||
        (graph.ageGroup != null && schemaVersion != ageGroupSchemaVersion)) {
      throw const FormatException('Klip planının yaş grubu grafla uyuşmuyor.');
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
    if (d01CallTiming != null) {
      d01ObservationDurations(graph);
    }
  }

  /// Plan aritmetiğidir; kesintisiz video/gözlem veya içerik onayı değildir.
  /// Eski elle hazırlanmış assetlerde zamanlama yokluğu geriye uyumlu kalır.
  Map<String, double> d01ObservationDurations(ScenarioGraph graph, {bool requireTiming = false}) {
    if (!graph.hasBehavior('D01')) {
      if (d01CallTiming != null) {
        throw const FormatException('D01 zamanlaması başka davranışa uygulanamaz.');
      }
      return {};
    }
    final timing = d01CallTiming;
    if (timing == null) {
      if (requireTiming) {
        throw const FormatException('D01 yapılandırılmış çağrı zamanlaması eksik.');
      }
      return {};
    }
    final card = BehaviorCards.all.firstWhere((card) => card.id == 'D01');
    if (card.cardVersion != graph.behaviors.firstWhere((ref) => ref.behaviorId == 'D01').cardVersion ||
        scenarioId != graph.scenarioId || timing.isEmpty) {
      throw const FormatException('D01 kart/senaryo/zamanlama bilgisi uyuşmuyor.');
    }
    final required = card.pilotWindowSeconds.toDouble();
    final calls = <String, double>{};
    for (final call in timing) {
      final matches = clips.where((clip) => clip.id == call.clipId);
      if (matches.isEmpty || calls.containsKey(call.clipId) || call.callEndS > matches.single.targetDurationS) {
        throw const FormatException('D01 çağrı klibi veya klip içi bitiş zamanı geçersiz.');
      }
      if (!graph.behaviorIdsFor(graph.scenes.firstWhere((scene) => scene.id == matches.single.sceneId)).contains('D01')) {
        throw const FormatException('Çağrı klibi D01 ile ilişkili sahnede olmalıdır.');
      }
      calls[call.clipId] = call.callEndS;
    }
    final result = <String, double>{};
    void walk(String sceneId, List<String> prefix) {
      if (prefix.contains(sceneId)) {
        throw const FormatException('D01 gözlem hesabı döngülü yolları desteklemiyor.');
      }
      final path = [...prefix, sceneId];
      if (!graph.endSceneIds.contains(sceneId)) {
        for (final edge in graph.transitions.where((edge) => edge.fromSceneId == sceneId)) {
          walk(edge.toSceneId, path);
        }
        return;
      }
      if (result.length >= 1000) {
        throw const FormatException('D01 gözlem hesabı için çok fazla yol var.');
      }
      final sequence = [for (final id in path) ...clipsForScene(id)];
      final relevant = path.any((id) => graph.behaviorIdsFor(graph.scenes.firstWhere((scene) => scene.id == id)).contains('D01'));
      if (!relevant) {
        if (sequence.any((clip) => calls.containsKey(clip.id))) {
          throw const FormatException('D01 içermeyen yolda çağrı zamanlaması var.');
        }
        return;
      }
      var count = 0;
      var seconds = 0.0;
      for (final clip in sequence) {
        final end = calls[clip.id];
        if (end != null) {
          count++;
          if (count > 1) {
            throw const FormatException('D01 yolunda birden fazla çağrı var.');
          }
          seconds = clip.targetDurationS - end;
        } else if (count == 1) {
          seconds += clip.targetDurationS;
        }
      }
      if (count != 1) {
        throw const FormatException('D01 yolunda çağrı zamanlaması eksik.');
      }
      final scale = seconds.abs() > required ? seconds.abs() : required;
      final tolerance = 2.220446049250313e-16 * (scale < 1 ? 1 : scale) * sequence.length;
      if (seconds + tolerance < required) {
        throw FormatException('D01 yolunda çağrı sonrası süre yetersiz: ${path.join(' → ')}; $seconds sn, gerekli $required sn (pilot gözlem).');
      }
      result[path.join(' → ')] = seconds;
    }
    walk(graph.startSceneId, []);
    if (result.isEmpty) {
      throw const FormatException('D01 gözlem yolu bulunamadı.');
    }
    return Map.unmodifiable(result);
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'planId': planId,
    'scenarioId': scenarioId,
    if (ageGroup != null) 'ageGroup': ageGroup!.toJson(),
    'authoringNote': authoringNote,
    'continuityNotes': continuityNotes,
    if (visualSuggestions != null) 'visualSuggestions': visualSuggestions,
    if (d01CallTiming != null) 'd01CallTiming': [for (final call in d01CallTiming!) call.toJson()],
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
