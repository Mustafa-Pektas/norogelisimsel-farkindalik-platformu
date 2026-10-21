import 'dart:convert';

/// Planlanan bir sahne; gözlenmiş bir davranış veya video etiketi değildir.
class ScenarioScene {
  ScenarioScene({
    required this.id,
    required this.description,
    this.title,
    this.summary,
  }) {
    _requireText(id, 'Sahne kimliği');
    _requireText(description, 'Sahne açıklaması ($id)');
  }

  factory ScenarioScene.fromJson(Map<String, dynamic> json) {
    return ScenarioScene(
      id: _readString(json, 'id'),
      description: _readString(json, 'description'),
      title: _readOptionalString(json, 'title'),
      summary: _readOptionalString(json, 'summary'),
    );
  }

  final String id;
  final String description;
  // Yalnızca görünüm metinleri; açıklamanın ve olayın yerini almaz.
  final String? title;
  final String? summary;

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    if (title != null) 'title': title,
    if (summary != null) 'summary': summary,
  };
}

/// Bir alternatif devam. Dalı kimin/nasıl seçeceğini belirlemez.
class ScenarioTransition {
  ScenarioTransition({
    required this.fromSceneId,
    required this.toSceneId,
    required this.description,
    this.label,
  }) {
    _requireText(fromSceneId, 'Geçişin kaynak sahne kimliği');
    _requireText(toSceneId, 'Geçişin hedef sahne kimliği');
    _requireText(description, 'Geçiş açıklaması ($fromSceneId → $toSceneId)');
  }

  factory ScenarioTransition.fromJson(Map<String, dynamic> json) {
    return ScenarioTransition(
      fromSceneId: _readString(json, 'fromSceneId'),
      toSceneId: _readString(json, 'toSceneId'),
      description: _readString(json, 'description'),
      label: _readOptionalString(json, 'label'),
    );
  }

  final String fromSceneId;
  final String toSceneId;
  final String description;
  final String? label;

  Map<String, dynamic> toJson() => {
    'fromSceneId': fromSceneId,
    'toSceneId': toSceneId,
    'description': description,
    if (label != null) 'label': label,
  };
}

/// Video promptlarından, analiz sonuçlarından ve Flutter'dan bağımsız taslak.
///
/// Yaş ay cinsindendir. Sahne kimlikleri graf içinde benzersizdir. Referanslar
/// bu kimliklerle birebir eşleşir. Birden fazla yol ve çıkışı olan döngüler
/// desteklenir; bütün sahneler erişilebilir ve bir bitişe ulaşabilir olmalıdır.
/// Bitiş sahneleri terminaldir: bu sahnelerden çıkış geçişi tanımlanmaz.
///
/// Kurucu ve JSON okuyucuları geçersiz veride [FormatException] üretir.
/// Listeler değiştirilemez; kurucudan sonra bağlantılar bozulamaz.
class ScenarioGraph {
  ScenarioGraph({
    required this.schemaVersion,
    required this.scenarioId,
    required this.title,
    required this.language,
    required this.ageMonths,
    required this.behaviorId,
    required this.cardVersion,
    required this.startSceneId,
    required List<ScenarioScene> scenes,
    required List<ScenarioTransition> transitions,
    required List<String> endSceneIds,
    this.authoringNote,
  }) : scenes = List.unmodifiable(scenes),
       transitions = List.unmodifiable(transitions),
       endSceneIds = List.unmodifiable(endSceneIds) {
    validate();
  }

  factory ScenarioGraph.fromJson(Map<String, dynamic> json) {
    final note = json['authoringNote'];
    if (note != null && note is! String) {
      throw const FormatException('authoringNote metin olmalıdır.');
    }
    final age = json['ageMonths'];
    if (age is! int) {
      throw const FormatException('ageMonths ay cinsinden tam sayı olmalıdır.');
    }
    final rawScenes = _readList(json, 'scenes');
    final rawTransitions = _readList(json, 'transitions');
    final rawEnds = _readList(json, 'endSceneIds');
    return ScenarioGraph(
      schemaVersion: _readString(json, 'schemaVersion'),
      scenarioId: _readString(json, 'scenarioId'),
      title: _readString(json, 'title'),
      language: _readString(json, 'language'),
      ageMonths: age,
      behaviorId: _readString(json, 'behaviorId'),
      cardVersion: _readString(json, 'cardVersion'),
      startSceneId: _readString(json, 'startSceneId'),
      scenes: [
        for (var i = 0; i < rawScenes.length; i++)
          ScenarioScene.fromJson(_readObject(rawScenes[i], 'scenes[$i]')),
      ],
      transitions: [
        for (var i = 0; i < rawTransitions.length; i++)
          ScenarioTransition.fromJson(
            _readObject(rawTransitions[i], 'transitions[$i]'),
          ),
      ],
      endSceneIds: [
        for (var i = 0; i < rawEnds.length; i++)
          _readStringValue(rawEnds[i], 'endSceneIds[$i]'),
      ],
      authoringNote: note as String?,
    );
  }

  factory ScenarioGraph.fromJsonString(String source) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('JSON okunamadı: ${error.message}');
    }
    return ScenarioGraph.fromJson(_readObject(decoded, 'Senaryo JSON kökü'));
  }

  static const currentSchemaVersion = '1.0';

  final String schemaVersion;
  final String scenarioId;
  final String title;
  final String language;
  final int ageMonths;
  final String behaviorId;
  final String cardVersion;
  final String startSceneId;
  final List<ScenarioScene> scenes;
  final List<ScenarioTransition> transitions;
  final List<String> endSceneIds;

  /// Örneğin elle hazırlanmış olduğu ve olayların yalnızca planlandığı bilgisi.
  final String? authoringNote;

  void validate() {
    _requireText(schemaVersion, 'Şema sürümü');
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('Desteklenmeyen şema sürümü: $schemaVersion.');
    }
    _requireText(scenarioId, 'Senaryo kimliği');
    _requireText(title, 'Başlık');
    _requireText(language, 'Dil');
    _requireText(behaviorId, 'Davranış kimliği');
    _requireText(cardVersion, 'Davranış kartı sürümü');
    _requireText(startSceneId, 'Başlangıç sahnesi kimliği');
    if (authoringNote != null) _requireText(authoringNote!, 'Taslak notu');
    if (ageMonths <= 0) {
      throw const FormatException('ageMonths pozitif bir tam sayı olmalıdır.');
    }
    if (scenes.isEmpty) {
      throw const FormatException('Graf en az bir sahne içermelidir.');
    }

    final ids = <String>{};
    for (final scene in scenes) {
      if (!ids.add(scene.id)) {
        throw FormatException('Tekrarlı sahne kimliği: ${scene.id}.');
      }
    }
    void requireScene(String id, String context) {
      if (!ids.contains(id)) {
        throw FormatException('$context mevcut bir sahneye bağlanmıyor: $id.');
      }
    }

    requireScene(startSceneId, 'Başlangıç');
    if (endSceneIds.isEmpty) {
      throw const FormatException('En az bir bitiş sahnesi tanımlanmalıdır.');
    }
    final ends = <String>{};
    for (final id in endSceneIds) {
      _requireText(id, 'Bitiş sahnesi kimliği');
      requireScene(id, 'Bitiş');
      if (!ends.add(id)) {
        throw FormatException('Tekrarlı bitiş sahnesi kimliği: $id.');
      }
    }

    final outgoing = {for (final id in ids) id: <String>[]};
    final incoming = {for (final id in ids) id: <String>[]};
    for (var i = 0; i < transitions.length; i++) {
      final transition = transitions[i];
      requireScene(transition.fromSceneId, 'Geçiş[$i] kaynağı');
      requireScene(transition.toSceneId, 'Geçiş[$i] hedefi');
      if (ends.contains(transition.fromSceneId)) {
        throw FormatException(
          'Bitiş sahnesinden çıkış geçişi olamaz: ${transition.fromSceneId}.',
        );
      }
      outgoing[transition.fromSceneId]!.add(transition.toSceneId);
      incoming[transition.toSceneId]!.add(transition.fromSceneId);
    }

    final reached = _reachable([startSceneId], outgoing);
    final unreachable = ids.difference(reached);
    if (unreachable.isNotEmpty) {
      throw FormatException(
        'Başlangıçtan erişilemeyen sahneler: ${unreachable.join(', ')}.',
      );
    }
    final canFinish = _reachable(endSceneIds, incoming);
    final trapped = ids.difference(canFinish);
    if (trapped.isNotEmpty) {
      throw FormatException(
        'Bir bitişe ulaşamayan sahneler: ${trapped.join(', ')}.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'scenarioId': scenarioId,
    'title': title,
    'language': language,
    'ageMonths': ageMonths,
    'behaviorId': behaviorId,
    'cardVersion': cardVersion,
    'startSceneId': startSceneId,
    'scenes': [for (final scene in scenes) scene.toJson()],
    'transitions': [for (final transition in transitions) transition.toJson()],
    'endSceneIds': endSceneIds.toList(),
    if (authoringNote != null) 'authoringNote': authoringNote,
  };

  String toJsonString({bool pretty = false}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());
}

Set<String> _reachable(
  Iterable<String> seeds,
  Map<String, List<String>> adjacency,
) {
  final seen = <String>{};
  final pending = seeds.toList();
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (seen.add(id)) pending.addAll(adjacency[id]!);
  }
  return seen;
}

void _requireText(String value, String field) {
  if (value.trim().isEmpty) {
    throw FormatException('$field boş olamaz.');
  }
}

String _readStringValue(dynamic value, String field) {
  if (value is! String) {
    throw FormatException('$field metin olmalıdır.');
  }
  return value;
}

String _readString(Map<String, dynamic> json, String field) =>
    _readStringValue(json[field], field);

String? _readOptionalString(Map<String, dynamic> json, String field) =>
    json[field] == null ? null : _readStringValue(json[field], field);

List<dynamic> _readList(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! List) {
    throw FormatException('$field liste olmalıdır.');
  }
  return value;
}

Map<String, dynamic> _readObject(dynamic value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field JSON nesnesi olmalıdır.');
  }
  return value;
}
