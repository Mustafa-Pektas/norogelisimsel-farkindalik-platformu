/// Versioned age-band contract shared by scenario generation and graph data.
/// Boundaries are half-open except for the final band's inclusive upper bound.
class ScenarioAgeGroup {
  const ScenarioAgeGroup._({required this.id, required this.label,
    required this.minMonths, required this.maxMonths, required this.includesMax});

  static const contractVersion = '1.0';
  static const months12To18 = ScenarioAgeGroup._(
    id: '12_18', label: '12–18 ay', minMonths: 12, maxMonths: 18, includesMax: false);
  static const months18To24 = ScenarioAgeGroup._(
    id: '18_24', label: '18–24 ay', minMonths: 18, maxMonths: 24, includesMax: false);
  static const months24To36 = ScenarioAgeGroup._(
    id: '24_36', label: '24–36 ay', minMonths: 24, maxMonths: 36, includesMax: true);
  static const values = [months12To18, months18To24, months24To36];

  final String id;
  final String label;
  final int minMonths;
  final int maxMonths;
  final bool includesMax;

  bool contains(int months) => months >= minMonths &&
      (includesMax ? months <= maxMonths : months < maxMonths);

  Map<String, Object?> toJson() => {
    'contractVersion': contractVersion,
    'id': id,
  };

  static ScenarioAgeGroup fromId(String id) => values.firstWhere(
    (group) => group.id == id,
    orElse: () => throw const FormatException('ageGroup.id yaş grubu kimliği desteklenmiyor.'),
  );

  static ScenarioAgeGroup fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value.length != 2 ||
        value['contractVersion'] != contractVersion || value['id'] is! String) {
      throw const FormatException('ageGroup sözleşmesi eksik veya desteklenmiyor; contractVersion ve id gereklidir.');
    }
    return fromId(value['id'] as String);
  }

  /// Migrates an existing exact age without changing the stored historical value.
  static ScenarioAgeGroup? fromLegacyMonths(int? months) {
    if (months == null || months < 12 || months > 36) return null;
    return values.firstWhere((group) => group.contains(months));
  }

  @override
  bool operator ==(Object other) => other is ScenarioAgeGroup &&
      other.id == id && contractVersion == ScenarioAgeGroup.contractVersion;

  @override
  int get hashCode => Object.hash(contractVersion, id);
}
