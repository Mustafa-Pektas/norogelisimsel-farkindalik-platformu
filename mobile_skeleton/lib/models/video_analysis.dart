/// Mobil bağlantı sözleşmesi; bir sunucu API'si veya analiz yöntemi değildir.
enum VideoSourceKind { asset, file }

class VideoAnalysisRequest {
  const VideoAnalysisRequest({
    required this.requestId,
    required this.videoId,
    required this.sourceKind,
    required this.source,
    required this.duration,
    this.ageMonths,
  });

  final String requestId;
  final String videoId;
  final VideoSourceKind sourceKind;
  final String source;
  final Duration duration;
  /// Kullanıcı beyanı; null bilinmiyor demektir, klinik yorum içermez.
  final int? ageMonths;
}

enum ObservationStatus {
  observed('Gözlendi'),
  notObserved('Gözlenmedi'),
  uncertain('Belirsiz'),
  notAssessable('Değerlendirilemedi');

  const ObservationStatus(this.label);
  final String label;
}

class AnalysisEvidence {
  const AnalysisEvidence({required this.startSeconds, required this.endSeconds,
    required this.timeSource});
  final double startSeconds;
  final double endSeconds;
  /// Örneğin ölçülmüş medya zamanı veya kare/FPS nominal zamanı.
  final String timeSource;

  bool isValidFor(Duration duration) =>
      startSeconds.isFinite && endSeconds.isFinite &&
      startSeconds >= 0 && endSeconds > startSeconds &&
      endSeconds <= duration.inMicroseconds / Duration.microsecondsPerSecond &&
      timeSource.trim().isNotEmpty;
}

class AnalysisConfidence {
  const AnalysisConfidence({required this.value, required this.scale,
    required this.meaning, required this.source});
  final double value;
  final String scale;
  final String meaning;
  final String source;

  bool get isDescribed => value.isFinite && scale.trim().isNotEmpty &&
      meaning.trim().isNotEmpty && source.trim().isNotEmpty;
}

class VideoBehaviorResult {
  const VideoBehaviorResult({required this.behaviorId, required this.cardVersion,
    required this.status, required this.explanation, this.evidence, this.confidence});
  final String behaviorId;
  final String cardVersion;
  final ObservationStatus status;
  final String explanation;
  final AnalysisEvidence? evidence;
  final AnalysisConfidence? confidence;
}

class VideoAnalysisResult {
  VideoAnalysisResult({required this.requestId, required this.videoId,
    required List<VideoBehaviorResult> findings}) : findings = List.unmodifiable(findings);
  final String requestId;
  final String videoId;
  final List<VideoBehaviorResult> findings;
}

enum VideoAnalysisPhase { sending, processing, completed, error, cancelled }

class VideoAnalysisEvent {
  const VideoAnalysisEvent({required this.requestId, required this.phase,
    this.result, this.message});
  final String requestId;
  final VideoAnalysisPhase phase;
  final VideoAnalysisResult? result;
  final String? message;
}
