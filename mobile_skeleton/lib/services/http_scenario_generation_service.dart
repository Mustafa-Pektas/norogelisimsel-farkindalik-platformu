import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/scenario_generation_request.dart';
import '../models/scenario_input.dart';
import '../models/scenario_generation_result.dart';
import '../models/scenario_clip_plan.dart';
import 'clip_plan_generation_service.dart';
import 'scenario_generation_service.dart';
import 'server_api_service.dart';

/// Adres yalnız hedefi belirler; kullanılabilir model veya başarılı erişim kanıtı değildir.
class HttpScenarioGenerationService implements ScenarioGenerationService, ClipPlanGenerationService {
  const HttpScenarioGenerationService({this.clientFactory, this.resolveServerUrl, this.resolveAccessKey,
    this.timeout = const Duration(seconds: 100)});

  final http.Client Function()? clientFactory;
  final Future<String> Function()? resolveServerUrl;
  final String? Function()? resolveAccessKey;
  final Duration timeout;

  HttpScenarioGenerationService withAccessKey(String? Function() resolve) =>
      HttpScenarioGenerationService(clientFactory: clientFactory, resolveServerUrl: resolveServerUrl,
        resolveAccessKey: resolve, timeout: timeout);

  @override
  bool get isAvailable => true; // İstek gönderme yolu var; bağlantı sonucu henüz bilinmiyor.
  @override
  String get availabilityMessage =>
      'Sunucudan taslak istenebilir; bağlantı ve model erişimi henüz doğrulanmadı. '
      'İptal yalnız yerel beklemeyi durdurur; sunucudaki üretim sürebilir.';
  @override
  ScenarioGenerationJob start(ScenarioGenerationRequest request) =>
      _HttpScenarioJob(request, clientFactory ?? http.Client.new,
        resolveServerUrl ?? ServerApiService.getBaseUrl, timeout, accessKey: resolveAccessKey?.call());

  @override
  ScenarioGenerationJob startPlan(ClipPlanGenerationRequest request) =>
      _HttpScenarioJob(request.request, clientFactory ?? http.Client.new,
        resolveServerUrl ?? ServerApiService.getBaseUrl, timeout, planRequest: request, accessKey: resolveAccessKey?.call());

  HttpScenarioComparisonJob startComparison(ScenarioGenerationRequest request, {required String arm,
    required bool preview, String? protocolId}) => HttpScenarioComparisonJob._(
      _HttpScenarioJob(request, clientFactory ?? http.Client.new,
        resolveServerUrl ?? ServerApiService.getBaseUrl, timeout, accessKey: resolveAccessKey?.call(),
        comparison: {'arm': arm, 'action': preview ? 'preview' : 'generate',
          ...?(protocolId == null ? null : <String, dynamic>{'protocolId': protocolId})}));
}

/// Aynı anlatı sözleşmesiyle A/B/C; sonuç kullanıcı seçimiyle editöre aktarılır.
class HttpScenarioComparisonJob {
  HttpScenarioComparisonJob._(this._job);
  final _HttpScenarioJob _job;
  late final Future<Map<String, dynamic>> result = _job.response.then((text) =>
    Map<String, dynamic>.from(jsonDecode(text) as Map));
  Future<void> cancel() => _job.cancel();
  Future<void> dispose() => _job.dispose();
}

class _HttpScenarioJob implements ScenarioGenerationJob, ScenarioGenerationMetadataJob {
  _HttpScenarioJob(this.request, this.clientFactory, this.resolveUrl, Duration timeout,
    {this.planRequest, this.accessKey, this.comparison}) {
    _timer = Timer(timeout, () => _fail(const ScenarioGenerationFailure(
      'Sunucudan cevap bekleme süresi doldu; model işinin iptali doğrulanmadı.')));
    unawaited(_run());
  }

  final ScenarioGenerationRequest request;
  final ClipPlanGenerationRequest? planRequest;
  final String? accessKey;
  final Map<String, dynamic>? comparison;
  final http.Client Function() clientFactory;
  final Future<String> Function() resolveUrl;
  final _answer = Completer<String>();
  http.Client? _client;
  Timer? _timer;
  bool _closed = false;
  @override
  Map<String, dynamic>? metadata;

  @override
  Future<String> get response => _answer.future;

  Future<void> _run() async {
    String? receivedRaw;
    try {
      final base = Uri.parse(await resolveUrl());
      if (_closed) return;
      if (!['http', 'https'].contains(base.scheme) || base.host.isEmpty ||
          base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment) {
        throw const ScenarioGenerationFailure('Sunucu adresi geçerli bir HTTP(S) adresi olmalıdır.');
      }
      final route = comparison != null ? 'compare-scenario' : planRequest == null ? 'generate-scenario-input' : 'generate-clip-plan';
      final endpoint = Uri.parse('${base.toString().replaceFirst(RegExp(r'/+$'), '')}/api/$route');
      final client = clientFactory();
      _client = client;
      // Use a local final so Dart can promote the nullable key safely.
      final accessKey = this.accessKey;
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (accessKey != null && accessKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessKey';
      }
      final reply = await client.post(endpoint,
        headers: headers,
        body: jsonEncode(comparison != null ? {'request': request.toJson(), ...comparison!} : planRequest?.toJson() ?? request.toJson()));
      if (_closed) return;
      if (reply.statusCode == 401) {
        throw const ScenarioGenerationFailure('Ekip erişimi doğrulanamadı. Oturum erişim anahtarını kontrol edin.');
      }
      final dynamic body = jsonDecode(utf8.decode(reply.bodyBytes));
      if (body is! Map<String, dynamic>) throw const FormatException('Yanıt nesne değil.');
      final raw = body['rawResponse'];
      if (raw is String) receivedRaw = raw;
      if (reply.statusCode != 200 || body['success'] != true) {
        throw ScenarioGenerationFailure(
          body['error'] is String ? body['error'] as String : 'Sunucu üretim isteğini tamamlayamadı.',
          rawResponse: raw is String ? raw : null,
          measurement: body['measurement'] is Map ? Map<String, dynamic>.from(body['measurement'] as Map) : null);
      }
      if (comparison != null) {
        final preview = comparison!['action'] == 'preview';
        final info = body[preview ? 'preview' : 'comparison'];
        if (!_sameJson(body['request'], request.toJson()) || info is! Map ||
            info['arm'] != comparison!['arm'] || info['protocolId'] is! String ||
            info['outputContract'] != ScenarioGenerationResult.contract ||
            (info['source'] as Map?)?['cardVersion'] != request.cardVersion ||
            (!preview && (info['protocolId'] != comparison!['protocolId'] || raw is! String))) {
          throw const ScenarioGenerationFailure('Karşılaştırma cevabı girdi veya deney koluyla uyuşmuyor.');
        }
        if (!preview) {
          ScenarioInput.fromJsonString(request.prepareInput(raw as String,
            scenarioId: 'transport-validation', edited: false).json);
        }
        if (!_answer.isCompleted) _answer.complete(jsonEncode(body));
        _release();
        return;
      }
      if (planRequest != null) {
        if (!_sameJson(body['input'], planRequest!.toJson())) {
          throw const ScenarioGenerationFailure('Plan cevabı gönderilen graf/istekle uyuşmuyor.');
        }
        if (raw is! String) throw const FormatException('Ham plan cevabı eksik.');
        final plan = ScenarioClipPlan.fromJsonString(raw);
        plan.validateAgainst(planRequest!.graph);
        if (plan.clips.any((clip) => clip.targetDurationS > (request.production?.maxClipDurationS ?? 8))) {
          throw const FormatException('Klip süresi seçilen üst sınırı aşıyor.');
        }
        plan.d01ObservationDurations(planRequest!.graph, requireTiming: true);
        if (plan.planId != planRequest!.planId || plan.visualSuggestions == null ||
            plan.clips.any((clip) => clip.voiceoverInstructions == null)) {
          throw const FormatException('Plan kimliği, görsel öneriler veya seslendirme alanları eksik.');
        }
        if (!_answer.isCompleted) _answer.complete(raw);
        _release();
        return;
      }
      // Yanlış isteğin cevabı doğru isteğe aitmiş gibi etiketlenmez.
      final metadata = body['request'];
      final expected = request.toJson();
      if (!_sameJson(metadata, expected)) {
        throw const ScenarioGenerationFailure('Sunucu cevap metadata’sı gönderilen istekle uyuşmuyor.');
      }
      if (body['outputContract'] != ScenarioGenerationResult.contract) {
        throw ScenarioGenerationFailure('Sunucu üretim sözleşmesi güncel değil; mobil ve backend sürümlerini eşleştirin.',
          rawResponse: raw is String ? raw : null);
      }
      if (raw is! String) throw const FormatException('Ham cevap eksik.');
      try {
        final prepared = request.prepareInput(raw, scenarioId: 'transport-validation', edited: false);
        ScenarioInput.fromJsonString(prepared.json); // Editör/graf güncellenmez.
      } on FormatException catch (error) {
        throw ScenarioGenerationFailure('Sunucu cevabı doğrulanamadı: ${error.message}', rawResponse: raw);
      }
      if (!_answer.isCompleted) _answer.complete(raw);
      this.metadata = {for (final key in ['model', 'settings', 'outputContract', 'measurement', 'behaviorSource'])
        if (body.containsKey(key)) key: body[key]};
      _release();
    } catch (error) {
      if (!_closed) {
        _fail(error is ScenarioGenerationFailure ? error :
          ScenarioGenerationFailure(planRequest != null && error is FormatException
            ? 'Klip planı doğrulanamadı: ${error.message}' : 'Sunucuya ulaşılamadı veya yanıt doğrulanamadı.', rawResponse: receivedRaw));
      }
    }
  }

  void _release() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    final client = _client;
    _client = null;
    client?.close();
  }

  void _fail(ScenarioGenerationFailure error) {
    if (_closed) return;
    if (!_answer.isCompleted) _answer.completeError(error);
    _release();
  }

  @override
  Future<void> cancel() async {
    _fail(const ScenarioGenerationFailure('Yerel cevap takibi durduruldu.'));
    // HTTP bağlantısını bırakmak sağlayıcıdaki model işini iptal etmiş sayılmaz.
    throw const ScenarioGenerationCancellationUnconfirmed();
  }

  @override
  Future<void> dispose() async {
    _fail(const ScenarioGenerationFailure('Üretim oturumu kapatıldı.'));
  }
}

// JSON nesnesindeki anahtar sırası protokolün anlamını değiştirmez.
bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((key) => b.containsKey(key) && _sameJson(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length && Iterable<int>.generate(a.length).every((i) => _sameJson(a[i], b[i]));
  }
  return a == b;
}
