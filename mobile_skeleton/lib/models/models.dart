enum AwarenessLevel {
  green,
  yellow,
  red,
  inconclusive;

  String get label {
    switch (this) {
      case AwarenessLevel.green:
        return 'Tipik (Belirgin Gösterge Gözlenmedi)';
      case AwarenessLevel.yellow:
        return 'Takip (Gelişimsel Takip Önerilir)';
      case AwarenessLevel.red:
        return 'Risk (Klinik İnceleme Önerilir)';
      case AwarenessLevel.inconclusive:
        return 'Belirsiz (Görüntü Kalitesi / Oklüzyon)';
    }
  }

  String get shortTag {
    switch (this) {
      case AwarenessLevel.green:
        return 'Tipik';
      case AwarenessLevel.yellow:
        return 'Takip';
      case AwarenessLevel.red:
        return 'Risk';
      case AwarenessLevel.inconclusive:
        return 'Belirsiz';
    }
  }
}

class BehaviorFinding {
  final String code;
  final String name;
  final bool detected;
  final double? latencySec;
  final String evidenceTimeframe;
  final AwarenessLevel level;
  final String explanation;

  const BehaviorFinding({
    required this.code,
    required this.name,
    required this.detected,
    this.latencySec,
    required this.evidenceTimeframe,
    required this.level,
    required this.explanation,
  });

  int get startSec {
    try {
      final parts = evidenceTimeframe.split('–');
      final timeParts = parts[0].trim().split(':');
      return (int.tryParse(timeParts[0]) ?? 0) * 60 + (int.tryParse(timeParts[1]) ?? 0);
    } catch (_) {
      return 0;
    }
  }

  int get endSec {
    try {
      final parts = evidenceTimeframe.split('–');
      if (parts.length > 1) {
        final timeParts = parts[1].trim().split(':');
        return (int.tryParse(timeParts[0]) ?? 0) * 60 + (int.tryParse(timeParts[1]) ?? 0);
      }
    } catch (_) {}
    return startSec + 4;
  }
}

class AnalysisReport {
  final String videoTitle;
  final AwarenessLevel overallLevel;
  final List<BehaviorFinding> findings;
  final String plainLanguageSummary;
  final DateTime analyzedAt;

  const AnalysisReport({
    required this.videoTitle,
    required this.overallLevel,
    required this.findings,
    required this.plainLanguageSummary,
    required this.analyzedAt,
  });
}

class HealthCenter {
  final String name;
  final String department;
  final String city;
  final String phone;
  final String address;

  const HealthCenter({
    required this.name,
    required this.department,
    required this.city,
    required this.phone,
    required this.address,
  });
}
