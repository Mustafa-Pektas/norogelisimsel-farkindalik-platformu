import '../models/scenario_generation_request.dart';

/// Mobil bağlantı noktası; endpoint/model/kimlik doğrulama sözleşmesi değildir.
abstract interface class ScenarioGenerationService {
  /// İstek başlatma yolu var mı? Başarılı sağlayıcı/model erişimi kanıtı değildir.
  bool get isAvailable;
  String get availabilityMessage;
  ScenarioGenerationJob start(ScenarioGenerationRequest request);
}

abstract interface class ScenarioGenerationJob {
  /// Tam ham cevap; JSON veya içerik doğruluğu garantisi yoktur.
  Future<String> get response;
  /// Başarı yalnız doğrulanmış hizmet iptalidir. HTTP yerel iptali özel hata verir.
  Future<void> cancel();
  /// Yerel kaynakları kapatır; bekleyen response/cancel beklemelerini sonlandırır.
  Future<void> dispose();
}

/// Varsa gerçekten dönen sağlayıcı/ölçüm bilgisi; eski kontrollü işler bunu uydurmaz.
abstract interface class ScenarioGenerationMetadataJob {
  Map<String, dynamic>? get metadata;
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

/// İncelenebilir ham cevap hatada da korunabilir; başarılı üretim sayılmaz.
class ScenarioGenerationFailure implements Exception {
  const ScenarioGenerationFailure(this.message, {this.rawResponse, this.measurement});
  final String message;
  final String? rawResponse;
  final Map<String, dynamic>? measurement;
  @override
  String toString() => message;
}

/// Bağlantı bırakılmıştır; sunucudaki/sağlayıcıdaki işin iptali doğrulanmamıştır.
class ScenarioGenerationCancellationUnconfirmed implements Exception {
  const ScenarioGenerationCancellationUnconfirmed();
}
