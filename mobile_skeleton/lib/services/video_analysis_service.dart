import '../models/video_analysis.dart';

/// Her iş kendi akışını ve kaynaklarını taşır. Servis ekranın mülkiyetinde değildir.
abstract interface class VideoAnalysisService {
  bool get isAvailable;
  String get scopeDescription;
  VideoAnalysisJob start(VideoAnalysisRequest request);
}

abstract interface class VideoAnalysisJob {
  /// Abonelikten itibaren bildirim verir; completed aynı istek/video kimliklerini taşır.
  Stream<VideoAnalysisEvent> get events;
  /// Future tamamlanması hizmetin iptali kabul ettiğini bildirir.
  Future<void> cancel();
  /// Yerel kaynakları kapatır; devam eden cancel Future'ını da sonlandırmalıdır.
  Future<void> dispose();
}

class UnavailableVideoAnalysisService implements VideoAnalysisService {
  const UnavailableVideoAnalysisService();
  @override
  bool get isAvailable => false;
  @override
  String get scopeDescription => 'Otomatik analiz hizmeti henüz bağlı değil.';
  @override
  VideoAnalysisJob start(VideoAnalysisRequest request) =>
      throw StateError('Analiz hizmeti bağlı değil.');
}
