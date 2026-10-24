import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/screens/scenario_comparison_dialog.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/services/server_api_service.dart';
import 'package:neuro_awareness_app/services/http_scenario_generation_service.dart';
import 'package:neuro_awareness_app/services/scenario_generation_service.dart';

final input = ScenarioGenerationRequest(behaviorId: 'D01', cardVersion: '0.2', ageMonths: 31,
  sceneContext: 'Deniz evde bloklarla oynar.', additionalInstructions: 'Sabit kamera.');
final protocol = List.filled(64, 'a').join();
class _Server {
  _Server({this.studio = false});
  final bool studio;
  Map<String, dynamic>? _studioRequest;
  Map<String, dynamic> get requestJson => _studioRequest ?? input.toJson();
  final requests = <Map<String, dynamic>>[];
  final arms = <String>[];
  final protocols = <String>[];
  bool failB = false, unauthorized = false, expectNoKey = false;
  int accessKeyReads = 0;
  Completer<http.Response>? gate;
  final random = Random.secure();
  late final key = base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
  Map<String, dynamic> preview(String arm) => {'arm': arm, 'protocolId': protocol, 'model': 'controlled-model',
    'outputContract': 'scenario-input-narrative-v3',
    'settings': {'temperature': 0.2, 'topP': 0.95, 'maxOutputTokens': 16384},
    'sourceMode': 'Kaynak $arm', 'source': {'sourceId': 'Davranis_Kartlari_v02.md', 'cardVersion': '0.2', 'sha256': List.filled(64, 'b').join()},
    'system': 'Tam sistem istemi $arm', 'user': jsonEncode(requestJson)};
  String raw(String arm) => ' \n${jsonEncode({'commonStart': '$arm: Deniz oynar; annesi adını bir kez söyler.',
    'alternatives': [{'title': 'Yönelme', 'continuation': 'Annesine döner.', 'ending': 'Yeni çağrı olmadan biter.'},
      {'title': 'Oyun', 'continuation': 'Oyuna devam eder.', 'ending': 'Yeni çağrı olmadan biter.'}]})}\n ';
  http.Response reply(String arm) => http.Response.bytes(utf8.encode(jsonEncode({
    'success': !(failB && arm == 'B'), 'request': requestJson, 'rawResponse': raw(arm),
    if (failB && arm == 'B') 'error': 'Kontrollü B doğrulama hatası',
    'comparison': preview(arm), 'measurement': {'providerDurationMs': 15, 'endpointDurationMs': 20,
      'promptTokens': null, 'outputTokens': 0},
  })), failB && arm == 'B' ? 502 : 200, headers: {'content-type': 'application/json; charset=utf-8'});
  HttpScenarioGenerationService service() => HttpScenarioGenerationService(resolveServerUrl: () async => 'http://controlled:8000',
    resolveAccessKey: () { accessKeyReads++; return key; }, clientFactory: () => MockClient((sent) async {
      expect(sent.url.path, '/api/compare-scenario');
      expect(sent.headers['Authorization'] ?? sent.headers['authorization'], expectNoKey ? isNull : 'Bearer $key');
      expect(sent.body, isNot(contains(key)));
      final body = jsonDecode(sent.body) as Map<String, dynamic>; requests.add(body);
      if (studio && _studioRequest == null) {
        final received = Map<String, dynamic>.from(body['request'] as Map);
        expect(received['behaviorId'], input.behaviorId);
        expect(received['cardVersion'], input.cardVersion);
        expect(received['ageMonths'], input.ageMonths);
        expect(received['sceneContext'], isA<String>().having((text) => text.isNotEmpty, 'bağlam', isTrue));
        _studioRequest = received;
      }
      expect(body['request'], requestJson);
      final arm = body['arm'] as String;
      if (unauthorized || expectNoKey) return http.Response('Unauthorized', 401);
      if (body['action'] == 'preview') {
        return http.Response.bytes(utf8.encode(jsonEncode({
          'success': true, 'request': requestJson, 'preview': preview(arm),
        })), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      arms.add(arm); protocols.add(body['protocolId'] as String);
      return gate?.future ?? Future.value(reply(arm));
    }));
}
Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target); await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget); await tester.tap(target); await tester.pumpAndSettle();
}
Future<void> _open(WidgetTester tester, _Server server, {bool narrow = false, String initialSelection = 'ALL',
  ScenarioGenerationRequest? request}) async {
  await tester.binding.setSurfaceSize(narrow ? const Size(320, 800) : const Size(1100, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context)
    .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)), child: child!),
    home: Builder(builder: (ctx) => Scaffold(body: TextButton(key: const ValueKey('open-comparison'),
      onPressed: () => showDialog<void>(context: ctx, barrierDismissible: false,
        builder: (_) => ScenarioComparisonDialog(request: request ?? input, service: server.service(),
          initialSelection: initialSelection)), child: const Text('Aç'))))));
  await tap(tester, 'open-comparison');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerApiService.selectedArm = 'B';
  });
  for (final selection in ['A', 'B', 'C', 'ALL']) {
    testWidgets('$selection başlangıç seçimi yalnız belirtilen kolları açık eylemle başlatır', (tester) async {
      final server = _Server();
      await _open(tester, server, initialSelection: selection);
      expect(tester.state<FormFieldState<String>>(find.byKey(const ValueKey('comparison-arms')))
        .value, selection);
      expect(server.requests, isEmpty);
      await tap(tester, 'comparison-preview');
      final expected = selection == 'ALL' ? ['A', 'B', 'C'] : [selection];
      expect(server.requests.map((request) => request['arm']), expected);
      expect(server.arms, isEmpty);
      await tap(tester, 'comparison-start');
      expect(server.arms, expected);
    });
  }
  testWidgets('Sabit istek özeti tüm davranışları, yaşı ve doğrusal düzeni gösterir; A/B/C kaynak farkı açıktır', (tester) async {
    final request = ScenarioGenerationRequest.fromJson({
      'requestVersion': '2.0',
      'behaviors': [
        {'behaviorId': 'D01', 'cardVersion': '0.2'},
        {'behaviorId': 'D02', 'cardVersion': '0.2'},
        {'behaviorId': 'D03', 'cardVersion': '0.2'},
      ],
      'ageMonths': 31,
      'sceneContext': 'Evde oyuncaklarla oyun.',
      'additionalInstructions': 'Sabit kamera.',
      'production': {'structure': 'linear26', 'targetDurationS': 210, 'maxClipDurationS': 8, 'targetSceneCount': 26},
    });
    final server = _Server();
    await _open(tester, server, request: request);
    expect(find.byKey(const ValueKey('comparison-request-summary')), findsOneWidget);
    final behaviorSummary = find.byKey(const ValueKey('comparison-request-behaviors'));
    expect(tester.widget<Text>(behaviorSummary).data, contains('D01 — İsme tepki verme (kart 0.2)'));
    expect(tester.widget<Text>(behaviorSummary).data, contains('D02 — Yetişkinin işaret ettiği hedefe yönelme (kart 0.2)'));
    expect(tester.widget<Text>(behaviorSummary).data, contains('D03 — İstemek için işaret etme (kart 0.2)'));
    expect(find.text('Yaş: 31 ay'), findsOneWidget);
    expect(find.text('Senaryo düzeni: 26 sahnelik doğrusal anlatı'), findsOneWidget);
    expect(find.text('A — Ek kart metni yok; ortak görev ve güvenlik talimatları ile seçili davranış adları korunur.'), findsOneWidget);
    expect(find.text('B — Seçilen bütün davranış kartlarının metni ve ortak kart kuralları eklenir.'), findsOneWidget);
    expect(find.text('C — Kanonik davranış kartı dosyasının tüm içeriği eklenir.'), findsOneWidget);
    expect(find.textContaining('aynı istek, görev, anlatı sözleşmesi, model ve ayarları'), findsOneWidget);
    expect(server.requests, isEmpty);
  });
  testWidgets('Servis anahtarı bir kez alınır; temizlenince gizli geri dönüş ve kalıcı kayıt yoktur', (tester) async {
    final server = _Server();
    await _open(tester, server);
    final keyField = find.byKey(const ValueKey('comparison-team-access-key'));
    expect(tester.widget<TextField>(keyField).controller!.text, server.key);
    expect(server.accessKeyReads, 1);
    await tap(tester, 'comparison-team-access-clear');
    expect(tester.widget<TextField>(keyField).controller!.text, isEmpty);
    server.expectNoKey = true;
    await tap(tester, 'comparison-preview');
    expect(find.textContaining('Ekip erişimi doğrulanamadı'), findsOneWidget);
    expect(tester.widget<TextField>(keyField).controller!.text, isEmpty);
    expect(server.arms, isEmpty);
    expect(server.accessKeyReads, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().map(prefs.get).join(), isNot(contains(server.key)));
  });
  testWidgets('Dialog açılması çağrı başlatmaz; önizleme 0 model, açık başlatma A/B/C ve hatayı korur', (tester) async {
    final server = _Server()..failB = true;
    await _open(tester, server);
    expect(server.requests, isEmpty);
    expect(find.textContaining('en fazla 3 sağlayıcı çağrısı'), findsOneWidget);
    await tap(tester, 'comparison-preview');
    expect(server.requests, hasLength(3)); expect(server.arms, isEmpty);
    final title = find.text('A — Kaynak A'); await tester.ensureVisible(title); await tester.tap(title); await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('comparison-system-A'))).data, 'Tam sistem istemi A');
    await tap(tester, 'comparison-start');
    expect(server.arms, ['A', 'B', 'C']); expect(server.protocols.toSet(), {protocol});
    final errorTitle = find.text('2. B — Hata'); await tester.ensureVisible(errorTitle); await tester.tap(errorTitle); await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('comparison-raw-1'))).data, server.raw('B'));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tap(tester, 'comparison-copy-all');
    final data = jsonDecode(copied!) as Map;
    expect((data['results'] as List).map((r) => r['arm']), ['A', 'B', 'C']);
    expect(data['results'][1]['error'], 'Kontrollü B doğrulama hatası');
    expect(data['results'][1]['rawResponse'], server.raw('B'));
    expect(copied, isNot(contains(server.key)));
  });
  testWidgets('İptal kalan kolları başlatmaz; geç cevap sonucu başarıya çevirmez', (tester) async {
    final server = _Server()..gate = Completer<http.Response>();
    await _open(tester, server); await tap(tester, 'comparison-preview'); await tap(tester, 'comparison-start');
    expect(server.arms, ['A']);
    await tap(tester, 'comparison-cancel');
    expect(find.textContaining('Yerel izleme durduruldu'), findsWidgets);
    server.gate!.complete(server.reply('A')); await tester.pumpAndSettle();
    expect(server.arms, ['A']);
    expect(find.text('1. A — Yerel izleme durduruldu'), findsOneWidget);
    expect(find.text('2. B — Başlatılmadı'), findsOneWidget);
  });
  testWidgets('Tek kol seçimi ve 320 piksel/büyük yazıda ana eylemler erişilir', (tester) async {
    final server = _Server(); await _open(tester, server, narrow: true);
    final dropdown = find.descendant(of: find.byKey(const ValueKey('comparison-arms')), matching: find.byType(DropdownButton<String>));
    await tester.ensureVisible(dropdown); await tester.tap(dropdown); await tester.pumpAndSettle();
    await tester.tap(find.text('B — Seçili kaynak').last); await tester.pumpAndSettle();
    expect(find.textContaining('en fazla 1 sağlayıcı çağrısı'), findsOneWidget);
    await tap(tester, 'comparison-preview'); await tap(tester, 'comparison-start');
    expect(server.arms, ['B']); expect(tester.takeException(), isNull);
    final result = find.byKey(const ValueKey('comparison-result-summary-B'));
    await tester.ensureVisible(result); await tester.pumpAndSettle();
    expect(result, findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('comparison-metric-prompt-tokens-B'))).data, 'Bilinmiyor');
    expect(tester.widget<Text>(find.byKey(const ValueKey('comparison-metric-output-tokens-B'))).data, '0');
    expect(tester.widget<Text>(find.byKey(const ValueKey('comparison-metric-provider-ms-B'))).data, '15');
    expect(tester.takeException(), isNull);
  });
  test('Karşılaştırma 401 erişim hatasıdır; ham cevap veya hazır sonuç üretilmez', () async {
    final server = _Server()..unauthorized = true;
    final job = server.service().startComparison(input, arm: 'A', preview: true);
    await expectLater(job.result, throwsA(isA<ScenarioGenerationFailure>().having((e) => e.message,
      'erişim hatası', contains('Ekip erişimi doğrulanamadı'))));
    await job.dispose(); expect(server.arms, isEmpty);
  });
  testWidgets('Stüdyo karşılaştırma girişinden açılır; oturum anahtarı ve önceki şablon korunur', (tester) async {
    final server = _Server(studio: true);
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: SyntheticVideoStudioScreen(
      initialAgeMonths: input.ageMonths, initialOntologyCode: input.behaviorId,
      comparisonService: server.service())));
    await tester.pumpAndSettle();
    final originalSource = tester.widget<Text>(find.byKey(const ValueKey('studio-template-source'))).data;
    await tap(tester, 'studio-engine-server');
    await tester.enterText(find.byKey(const ValueKey('scenario-request-context')), input.sceneContext);
    await tester.enterText(find.byKey(const ValueKey('scenario-request-instructions')), input.additionalInstructions!);
    await tester.enterText(find.byKey(const ValueKey('studio-team-access-key')), server.key);
    await tester.testTextInput.receiveAction(TextInputAction.done); await tester.pumpAndSettle();
    await tap(tester, 'studio-open-comparison');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('comparison-team-access-key')))
      .controller!.text, server.key);
    expect(server.requests, isEmpty);
    await tap(tester, 'comparison-preview');
    expect(server.requests, hasLength(1));
    expect(server.requests.single['arm'], 'B');
    expect(server.arms, isEmpty);
    await tap(tester, 'comparison-close');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('studio-team-access-key')))
      .controller!.text, server.key);
    await tap(tester, 'studio-engine-local');
    expect(tester.widget<Text>(find.byKey(const ValueKey('studio-template-source'))).data, originalSource);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().map(prefs.get).join(), isNot(contains(server.key)));
  });
}
