import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/models/scenario_generation_result.dart';
import 'package:neuro_awareness_app/services/http_scenario_generation_service.dart';
import 'package:neuro_awareness_app/services/scenario_generation_service.dart';
import 'package:neuro_awareness_app/services/server_api_service.dart';

class _Http extends http.BaseClient {
  final started = Completer<http.BaseRequest>();
  final reply = Completer<http.StreamedResponse>();
  int sends = 0;
  int closes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    ++sends;
    started.complete(request);
    return reply.future;
  }
  @override
  void close() { ++closes; }
}
http.StreamedResponse response(Object body, {int status = 200}) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(body))), status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final request = ScenarioGenerationRequest(behaviorId: 'D02', cardVersion: '0.2',
    ageMonths: 24, sceneContext: '  Evde iki oyuncak  ', additionalInstructions: ' Sabit kamera ');
  final raw = ' \n${jsonEncode({
    'commonStart': '  Ham ortak başlangıç  ',
    'alternatives': [{'title': 'Devam', 'continuation': ' Ham devam ', 'ending': ' Ham bitiş '}],
  })}\n ';
  Map<String, Object?> envelope() => {
    'success': true, 'rawResponse': raw, 'request': request.toJson(),
    'validation': 'structure_only', 'outputContract': ScenarioGenerationResult.contract,
  };
  HttpScenarioGenerationService service(_Http client, {Duration timeout = const Duration(seconds: 100)}) =>
      HttpScenarioGenerationService(clientFactory: () => client,
        resolveServerUrl: () async => 'http://localhost:8000', timeout: timeout);

  test('Mevcut kayıtlı adres kullanılır; ayar varlığı model erişimi kanıtı değildir', () async {
    SharedPreferences.setMockInitialValues({});
    final before = ServerApiService.baseUrl;
    addTearDown(() { ServerApiService.baseUrl = before; });
    await ServerApiService.setBaseUrl('localhost:8123');
    final client = _Http();
    final adapter = HttpScenarioGenerationService(clientFactory: () => client);
    expect(adapter.availabilityMessage, contains('henüz doğrulanmadı'));
    final job = adapter.start(request);
    final answer = expectLater(job.response, completion(raw));
    final sent = await client.started.future;
    expect(sent.url.toString(), 'http://localhost:8123/api/generate-scenario-input');
    client.reply.complete(response(envelope()));
    await answer;
    await job.dispose();
    expect(client.closes, 1);
  });

  test('HTTP: sabit istek alanları ve tam ham cevap; tek POST ve tek close', () async {
    final client = _Http();
    final job = service(client).start(request);
    final answer = expectLater(job.response, completion(raw));
    final sent = (await client.started.future) as http.Request;
    expect(jsonDecode(sent.body), request.toJson());
    expect(sent.method, 'POST');
    expect(sent.body, isNot(contains('riskProfile')));
    client.reply.complete(response(envelope()));
    await answer;
    await job.dispose();
    await job.dispose();
    expect(client.sends, 1);
    expect(client.closes, 1);
  });

  for (final mode in ['bad-json', 'bad-content', 'metadata', 'protocol', 'http', 'transport']) {
    test('HTTP $mode: hata; şablon/başarı/tekrar yok', () async {
      final client = _Http();
      final job = service(client).start(request);
      final answer = expectLater(job.response, throwsA(isA<ScenarioGenerationFailure>()));
      await client.started.future;
      switch (mode) {
        case 'bad-json':
          client.reply.complete(http.StreamedResponse(Stream.value(utf8.encode('{bozuk')), 200));
        case 'bad-content':
          client.reply.complete(response({...envelope(), 'rawResponse': '{"commonStart":"Eksik"}'}));
        case 'metadata':
          client.reply.complete(response({...envelope(), 'request': {...request.toJson(), 'ageMonths': 30}}));
        case 'protocol':
          client.reply.complete(response({...envelope(), 'outputContract': 'scenario-input-narrative-v2'}));
        case 'http':
          client.reply.complete(response({'success': false, 'error': 'Yapılandırma eksik'}, status: 503));
        case 'transport':
          client.reply.completeError(http.ClientException('Kontrollü bağlantı hatası'));
      }
      await answer;
      await job.dispose();
      expect(client.sends, 1);
      expect(client.closes, 1);
    });
  }

  test('Backend geçersiz ham cevabı hatayla döndürür; inceleme için metin korunur', () async {
    final client = _Http();
    final job = service(client).start(request);
    final answer = expectLater(job.response, throwsA(isA<ScenarioGenerationFailure>()
      .having((e) => e.rawResponse, 'rawResponse', ' \n{bozuk\n ')));
    await client.started.future;
    client.reply.complete(response({'success': false, 'error': 'Çıktı geçersiz',
      'rawResponse': ' \n{bozuk\n '}, status: 502));
    await answer;
    expect(client.closes, 1);
  });

  test('Zaman sınırı tamamlanmayan HTTP beklemesini bırakır; geç cevap uygulanmaz', () async {
    final client = _Http();
    final job = service(client, timeout: Duration.zero).start(request);
    final answer = expectLater(job.response, throwsA(isA<ScenarioGenerationFailure>()
      .having((e) => e.message, 'message', contains('süresi doldu'))));
    await client.started.future;
    await answer;
    expect(client.closes, 1);
    client.reply.complete(response(envelope()));
    await client.reply.future;
    await job.dispose();
    expect(client.closes, 1);
  });

  test('İptal yerel isteği kapatır; doğrulanmış sunucu iptali sayılmaz, geç cevap reddedilir', () async {
    final client = _Http();
    final job = service(client).start(request);
    final answer = expectLater(job.response, throwsA(isA<ScenarioGenerationFailure>()));
    await client.started.future;
    await expectLater(job.cancel(), throwsA(isA<ScenarioGenerationCancellationUnconfirmed>()));
    await answer;
    client.reply.complete(response(envelope()));
    await client.reply.future;
    await job.dispose();
    expect(client.closes, 1);
    expect(client.sends, 1);
  });

  test('Adres yüklenirken dispose: yerel cevap tamamlanır; geç yükleme HTTP başlatmaz', () async {
    final url = Completer<String>();
    var clients = 0;
    final job = HttpScenarioGenerationService(resolveServerUrl: () => url.future,
      clientFactory: () { ++clients; return _Http(); }).start(request);
    final answer = expectLater(job.response, throwsA(isA<ScenarioGenerationFailure>()));
    await job.dispose();
    await answer;
    url.complete('http://localhost:8000');
    await url.future;
    expect(clients, 0);
  });
}
