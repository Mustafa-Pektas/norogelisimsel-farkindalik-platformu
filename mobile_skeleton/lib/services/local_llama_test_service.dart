import 'dart:async';
import 'dart:io';

import '../models/local_model_option.dart';

enum LocalLlamaPhase {
  idle,
  loading,
  generating,
  cancelling,
  closing,
  completed,
  cancelled,
  error,
}

class LocalLlamaTestState {
  const LocalLlamaTestState({
    this.phase = LocalLlamaPhase.idle,
    this.text = '',
    this.error,
    this.elapsed = Duration.zero,
    this.generationElapsed = Duration.zero,
    this.diagnostics = const {},
  });
  final LocalLlamaPhase phase;
  final String text;
  final String? error;
  final Duration elapsed;
  final Duration generationElapsed;
  final Map<String, String> diagnostics;
  bool get isBusy => const {
    LocalLlamaPhase.loading,
    LocalLlamaPhase.generating,
    LocalLlamaPhase.cancelling,
    LocalLlamaPhase.closing,
  }.contains(phase);
}

/// Yerel çıkarım isteği ve sınırları; üretilen içeriğin uygunluğunu onaylamaz.
class LocalLlamaTestRequest {
  const LocalLlamaTestRequest({
    required this.id,
    required this.title,
    required this.actionLabel,
    required this.description,
    required this.prompt,
    required this.contextSize,
    required this.maxTokens,
    this.model = LocalModelOption.llama,
  }) : assert(maxTokens > 0),
       assert(contextSize > maxTokens);

  final String id;
  final String title;
  final String actionLabel;
  final String description;
  final String prompt;
  final int contextSize;
  final int maxTokens;
  final LocalModelOption model;

  String get samplingDescription => model == LocalModelOption.qwen3
      ? 'Düşünme kapalı · sıcaklık 0.7 · top-P 0.8 · top-K 20 · min-P 0 · tekrar cezası 1.0 · presence 0'
      : 'Sıcaklık 0.8 · top-P 0.9 · top-K 40 · min-P 0 · tekrar cezası 1.1 · presence 0';

  static const greeting = LocalLlamaTestRequest(
    id: 'local-llama-test',
    title: 'Yerel model testi',
    actionLabel: 'Modeli test et',
    description:
        'Dosyanın indirilmiş olması, metin üretiminin çalıştığını göstermez.',
    prompt: 'Türkçe tek cümleyle merhaba de.',
    contextSize: 512,
    maxTokens: 32,
  );

  // Anlatı metni değil, bu küçük demoda uygulamanın sağladığı metadata.
  // Kimlik oturum içi demo içindir; bu yol kalıcı kayıt oluşturmaz.
  static const d01GraphDemoMetadata = <String, Object>{
    'schemaVersion': '1.0',
    'scenarioId': 'd01-qwen-yerel-demo',
    'title': 'D01 yerel model senaryo taslağı',
    'language': 'tr',
    'ageMonths': 30,
    'behaviorId': 'D01',
    'cardVersion': '0.2',
    'source': 'model_output',
  };

  static const d01GraphDemo = LocalLlamaTestRequest(
    id: 'd01-scenario-graph-demo',
    title: 'Yerel modelden senaryo taslağı',
    actionLabel: 'Qwen ile senaryo taslağı üret',
    description:
        'Cihazdaki mevcut Qwen dosyasını kullanır; model indirmez. '
        'Ham cevap korunur. JSON yapısının geçmesi içerik doğrulaması değildir.',
    model: LocalModelOption.qwen3,
    contextSize: 2048,
    maxTokens: 768,
    prompt: '''D01 kart 0.2 için Türkçe, kısa bir çocuk videosu senaryo taslağı üret.
Yalnız bir JSON nesnesi yaz; Markdown, kod çiti veya ek açıklama yazma.
ScenarioInput sözleşmesi: commonStart metni ve alternatives listesi.
Bu demoda iki alternatif olsun. Her alternatif yalnız title (kısa başlık), continuation (devam metni), ending (açık bitiş metni) alanlarını içersin.
commonStart: 30 aylık Deniz evde oyuncakla oynar ve annesine dönük değildir. Annesi doğal sesle bir kez “Deniz” der. Yetişkin çocuğa dokunmaz, işaret etmez, el sallamaz veya ek yönerge vermez. Bu ortak başlangıçta çocuğun çağrıya tepkisini anlatma.
Birinci continuation: Deniz başını annesine çevirir; ending bu yolun sahnesini bitirir.
İkinci continuation: Deniz annesine dönmeden oyununu sürdürür; ending bu ayrı yolun sahnesini bitirir.
Her anlatı alanında bir kısa cümle kullan. Dallarda yeni çağrı veya ek uyaran ekleme. Bunlar aynı başlangıcın planlanan iki ayrı devamıdır; tanı, risk puanı veya klinik gecikme eşiği yazma.
Sahne kimliği, kenar veya startSceneId üretme.
Şu metadata uygulamaya aittir; bunları yazman gerekmez. Yazarsan aynı değerleri kullan: schemaVersion="1.0", scenarioId="d01-qwen-yerel-demo", title="D01 yerel model senaryo taslağı", language="tr", ageMonths=30, behaviorId="D01", cardVersion="0.2", source="model_output".
Uygulama bu metadata ile senin commonStart ve alternatives içeriğini birleştirir; hiçbir eksik anlatı metnini tamamlamaz.''',
  );

  // Kaynak: proje üst klasöründeki belgeler/Davranis_Kartlari_v02.md, D01.
  static const d01 = LocalLlamaTestRequest(
    id: 'd01-scenario-test',
    title: 'D01 senaryo testi',
    actionLabel: 'D01 senaryosu üret',
    description:
        'D01 · Kart 0.2 · Planlanan alternatif senaryo taslağı. '
        'Gözlenmiş davranış, video kanıtı veya klinik sonuç değildir. '
        'Model cevabının koşullara uygunluğu insan incelemesi bekler.',
    contextSize: 2048,
    maxTokens: 384,
    prompt: d01TurkishPrompt,
  );

  static const d01TurkishPrompt = '''Türkçe bir çocuk videosu taslağı yaz. Yalnızca aşağıdaki üç başlığı kullan, her başlığa bir veya iki kısa cümle yaz:
Başlangıç: 30 aylık Deniz evde oyuncakla oynar ve annesine bakmaz. Annesi dokunmadan ve işaret etmeden bir kez ‘Deniz’ der.
Alternatif A: Deniz başını annesine çevirir.
Alternatif B: Deniz annesine dönmeden oyununa devam eder.
Bunlar aynı başlangıcın iki ayrı devamıdır. JSON veya ek açıklama yazma.
Bu taslağı doğal sahne anlatımına dönüştür.''';

  static const d01Qwen = LocalLlamaTestRequest(
    id: 'd01-qwen3-test',
    title: 'Qwen D01 karşılaştırma',
    actionLabel: 'Qwen ile D01 dene',
    model: LocalModelOption.qwen3,
    description:
        'Aynı sade Türkçe D01 isteği, ayrı Qwen3 modeli. '
        'Planlanan alternatif taslaktır; gözlenmiş davranış veya klinik sonuç değildir.',
    contextSize: 2048,
    maxTokens: 384,
    prompt: d01TurkishPrompt,
  );

  static const qwenCommonStart = LocalLlamaTestRequest(
    id: 'qwen-common-start-test',
    title: 'Qwen — Ortak başlangıç testi',
    actionLabel: 'Ortak başlangıcı dene',
    model: LocalModelOption.qwen3,
    description:
        'Oyuncak ve basit bir eylemle iki cümlelik ev sahnesi. '
        'Yetişkin, konuşma ve çocuk tepkisi istenmez. '
        'Planlanan taslaktır; içeriğin uygunluğu insan incelemesi bekler.',
    contextSize: 2048,
    maxTokens: 160,
    prompt:
        'Evde oyuncakla oynayan 30 aylık bir çocuğu anlatan iki kısa Türkçe cümle yaz. '
        'Bir oyuncak ve onunla yapılan basit bir eylem seç. '
        'Yetişkin, konuşma, isim çağrısı veya çocuğun birine verdiği tepkiyi anlatma.',
  );

  static const d01English = LocalLlamaTestRequest(
    id: 'd01-english-test',
    title: 'D01 İngilizce karşılaştırma',
    actionLabel: 'D01 İngilizce dene',
    description:
        'Aynı D01 taslağı için İngilizce istek ve İngilizce cevap. '
        'Türkçe dil başarımı ile genel talimat takibini karşılaştırmak içindir. '
        'Planlanan alternatiflerdir; gözlenmiş davranış veya klinik sonuç değildir.',
    contextSize: 2048,
    maxTokens: 384,
    prompt: '''Write a draft for a children's video in English. Use only the following three headings, with one or two short sentences under each heading:
Beginning: Deniz, aged 30 months, plays with a toy at home and does not look at his mother. Without touching him or pointing, his mother says ‘Deniz’ once.
Alternative A: Deniz turns his head toward his mother.
Alternative B: Deniz continues playing without turning toward his mother.
These are two separate continuations of the same beginning. Do not write JSON or any extra explanation.
Turn this draft into a natural scene narrative.''',
  );
}

/// Küçük sınır, gerçek native adaptörü indirme/durum yönetiminden ayırır.
/// Üretim uygulamasında yalnızca LlamadartTestRuntime bağlanır; fallback yoktur.
abstract interface class LocalLlamaTestRuntime {
  Map<String, String> get diagnostics;
  Future<void> load(String path);
  Stream<String> generate();
  void cancelGeneration();
  Future<void> dispose();
}

class LocalLlamaTestService {
  LocalLlamaTestService({
    required this.resolveModel,
    required this.createRuntime,
    this.request = LocalLlamaTestRequest.greeting,
  });
  final LocalLlamaTestRequest request;
  final Future<File> Function() resolveModel;
  final LocalLlamaTestRuntime Function(LocalLlamaTestRequest request)
  createRuntime;
  final _updates = StreamController<LocalLlamaTestState>.broadcast();
  LocalLlamaTestState _state = const LocalLlamaTestState();
  LocalLlamaTestState get state => _state;
  Stream<LocalLlamaTestState> get states => _updates.stream;
  bool get canRun => !_disposed && _owner == null;
  // Farklı stüdyo örnekleri de aynı anda ikinci native model açamaz.
  static LocalLlamaTestService? _owner;
  LocalLlamaTestRuntime? _runtime;
  Future<void>? _running;
  Future<void>? _disposing;
  bool _disposed = false;
  bool _cancelRequested = false;
  String? _cancelError;
  Map<String, String> _diagnostics = const {};

  Future<void> run() {
    if (_disposed) return Future.error(StateError('Model testi kapatıldı.'));
    if (_owner != null) {
      return Future.error(
        StateError(
          'Başka bir model testi çalışıyor veya kaynakları kapatılamadı.',
        ),
      );
    }
    _owner = this;
    _cancelRequested = false;
    _cancelError = null;
    _diagnostics = const {};
    return _running = _execute();
  }

  void _emit(
    LocalLlamaPhase phase,
    String text,
    String? error,
    Stopwatch total,
    Stopwatch generation,
  ) {
    _diagnostics = _runtime?.diagnostics ?? _diagnostics;
    _state = LocalLlamaTestState(
      phase: phase,
      text: text,
      error: error,
      elapsed: total.elapsed,
      generationElapsed: generation.elapsed,
      diagnostics: _diagnostics,
    );
    _updates.add(_state);
  }

  Future<void> _execute() async {
    final total = Stopwatch()..start();
    final generation = Stopwatch();
    final text = StringBuffer();
    String? error;
    var cleanupFailed = false;
    _emit(LocalLlamaPhase.loading, '', null, total, generation);
    try {
      final file = await resolveModel();
      if (!await file.exists()) {
        throw const FileSystemException('Model indirilmedi');
      }
      if (_cancelRequested) return;
      final runtime = createRuntime(request);
      _runtime = runtime;
      await runtime.load(file.path);
      if (_cancelRequested) return;
      generation.start();
      _emit(LocalLlamaPhase.generating, '', null, total, generation);
      await for (final chunk in runtime.generate()) {
        if (_cancelRequested) break;
        text.write(chunk);
        _emit(
          LocalLlamaPhase.generating,
          text.toString(),
          null,
          total,
          generation,
        );
      }
      if (!_cancelRequested && text.toString().trim().isEmpty) {
        throw StateError(
          'Model boş cevap üretti; metin üretimi doğrulanamadı.',
        );
      }
    } catch (failure) {
      error = failure.toString();
    } finally {
      generation.stop();
      _emit(LocalLlamaPhase.closing, text.toString(), error, total, generation);
      try {
        await _runtime?.dispose();
      } catch (failure) {
        cleanupFailed = true;
        error =
            '${error == null ? '' : '$error\n'}Kaynaklar kapatılamadı: $failure. '
            'Yeni testten önce uygulamayı tamamen kapatıp açın.';
      }
      _runtime = null;
      if (!cleanupFailed) _owner = null;
      total.stop();
      if (_cancelError != null) error = '${error ?? ''}\n$_cancelError';
      final phase = cleanupFailed || _cancelError != null
          ? LocalLlamaPhase.error
          : _cancelRequested
          ? LocalLlamaPhase.cancelled
          : error != null
          ? LocalLlamaPhase.error
          : LocalLlamaPhase.completed;
      _emit(phase, text.toString(), error, total, generation);
    }
  }

  void cancel() {
    if (!state.isBusy || _cancelRequested) return;
    _cancelRequested = true;
    try {
      _runtime?.cancelGeneration();
    } catch (failure) {
      _cancelError = 'İptal isteği gönderilemedi: $failure';
    }
    _state = LocalLlamaTestState(
      phase: LocalLlamaPhase.cancelling,
      text: state.text,
      error: _cancelError,
      elapsed: state.elapsed,
      generationElapsed: state.generationElapsed,
      diagnostics: state.diagnostics,
    );
    _updates.add(_state);
    // Yükleme anında zorla isolate öldürülmez: load tamamlanınca dispose beklenir.
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    cancel();
    await _running;
    await _updates.close();
  }
}
