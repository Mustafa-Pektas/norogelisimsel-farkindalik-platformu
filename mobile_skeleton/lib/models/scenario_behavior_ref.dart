/// Kart içeriğinin kopyası değil; senaryo içindeki kimlik/sürüm referansıdır.
class ScenarioBehaviorRef {
  const ScenarioBehaviorRef({required this.behaviorId, required this.cardVersion});
  final String behaviorId;
  final String cardVersion;
  factory ScenarioBehaviorRef.fromJson(Map<String, dynamic> json) {
    if (json.length != 2 || json['behaviorId'] is! String || json['cardVersion'] is! String ||
        (json['behaviorId'] as String).trim().isEmpty || (json['cardVersion'] as String).trim().isEmpty) {
      throw const FormatException('Davranış kimliği/sürümü geçersiz.');
    }
    return ScenarioBehaviorRef(behaviorId: json['behaviorId'] as String, cardVersion: json['cardVersion'] as String);
  }
  Map<String, dynamic> toJson() => {'behaviorId': behaviorId, 'cardVersion': cardVersion};
}

List<ScenarioBehaviorRef>? readScenarioBehaviors(Object? value) {
  if (value == null) return null;
  if (value is! List || value.isEmpty) throw const FormatException('Davranış listesi boş olamaz.');
  final result = value.map((entry) {
    if (entry is! Map<String,dynamic>) throw const FormatException('Davranış referansı nesne olmalıdır.');
    return ScenarioBehaviorRef.fromJson(entry);
  }).toList();
  if (result.map((entry) => entry.behaviorId).toSet().length != result.length) {
    throw const FormatException('Tekrarlı davranış kimliği.');
  }
  return result;
}

List<String>? readScenarioBehaviorIds(Object? value, {bool optional = false}) {
  if (value == null && optional) return null;
  if (value is! List || value.isEmpty || value.any((id) => id is! String || id.trim().isEmpty) ||
      value.toSet().length != value.length) {
    throw const FormatException('Davranış kimlikleri boş olmayan, tekrarsız metin listesi olmalıdır.');
  }
  return List.unmodifiable(value.cast<String>());
}
