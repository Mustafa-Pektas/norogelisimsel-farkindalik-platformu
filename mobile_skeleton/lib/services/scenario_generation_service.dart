import '../models/scenario_generation_request.dart';

/// Mobil bağlantı noktası; endpoint/model/kimlik doğrulama sözleşmesi değildir.
abstract interface class ScenarioGenerationService {
  bool get isAvailable;
  String get availabilityMessage;
  ScenarioGenerationJob start(ScenarioGenerationRequest request);
}

abstract interface class ScenarioGenerationJob {
  /// Tam ham cevap; JSON veya içerik doğruluğu garantisi yoktur.
  Future<String> get response;
  /// Tamamlanması hizmetin iptali kabul ettiğini, hata kabul etmediğini bildirir.
  Future<void> cancel();
  /// Yerel kaynakları kapatır; bekleyen response/cancel beklemelerini sonlandırır.
  Future<void> dispose();
}

class UnavailableScenarioGenerationService implements ScenarioGenerationService {
  const UnavailableScenarioGenerationService();
  @override
  bool get isAvailable => false;
  @override
  String get availabilityMessage => 'Senaryo üretim hizmeti henüz bağlı değil.';
  @override
  ScenarioGenerationJob start(ScenarioGenerationRequest request) =>
      throw StateError('Senaryo üretim hizmeti bağlı değil.');
}
