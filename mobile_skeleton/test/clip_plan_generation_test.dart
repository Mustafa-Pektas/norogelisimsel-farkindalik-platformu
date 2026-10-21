import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/models/scenario_workspace_draft.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/services/clip_plan_generation_service.dart';
import 'package:neuro_awareness_app/services/http_scenario_generation_service.dart';
import 'package:neuro_awareness_app/services/scenario_draft_store.dart';
import 'package:neuro_awareness_app/services/scenario_generation_service.dart';
import 'package:neuro_awareness_app/services/scenario_graph_converter.dart';

final request = ScenarioGenerationRequest(behaviorId: 'D01', cardVersion: '0.2',
  ageMonths: 31, sceneContext: 'Deniz evde küplerle oynuyor.', additionalInstructions: 'Sabit kamera.');
final content = jsonEncode({
  'commonStart': '  Deniz oynar.  ',
  'alternatives': [
    {'title': 'Yönelme', 'continuation': 'Annesine döner.', 'ending': 'İlk bitiş.'},
    {'title': 'Oyun', 'continuation': 'Oynar.', 'ending': 'İkinci bitiş.'},
  ],
});
final editor = request.prepareInput(content, scenarioId: 'new-story', edited: false).json;
final graph = const ScenarioGraphConverter().convert(ScenarioInput.fromJsonString(editor));

Map<String, dynamic> planJson(ClipPlanGenerationRequest input) => {
  'schemaVersion': '1.0', 'planId': input.planId, 'scenarioId': input.graph.scenarioId,
  'authoringNote': 'İncelenmemiş üretim taslağı.', 'continuityNotes': ' Aynı çocuk ve ortam. ',
  'visualSuggestions': 'Üretilmiş görsel öneri: krem kıyafet.',
  'd01CallTiming': [<String, dynamic>{'clipId': '${input.graph.startSceneId}-1', 'callEndS': 3}],
  'clips': [for (final scene in input.graph.scenes) for (var order = 1; order <= 2; order++) {
    'id': '${scene.id}-$order', 'sceneId': scene.id, 'orderInScene': order, 'targetDurationS': 6,
    'plannedAction': scene.description, 'initialState': ' Önce ', 'finalState': ' Sonra ',
    'productionPrompt': '  Tam görsel prompt ${scene.id}-$order  ',
    'voiceoverInstructions': '  Ayrı ses ${scene.id}-$order  ',
  }],
};
Map<String, dynamic> shortPlan(ClipPlanGenerationRequest input, double endingDuration) {
  final value = planJson(input);
  value['authoringNote'] = 'Gözlem penceresi tamamlandı.'; // İddia, süre kontrolü değildir.
  value['clips'] = [for (final raw in value['clips'] as List)
    if (raw['orderInScene'] == 1) {...(raw as Map<String, dynamic>),
      'targetDurationS': raw['sceneId'] == input.graph.startSceneId ? 4 :
        input.graph.endSceneIds.contains(raw['sceneId']) ? endingDuration : 5,
    }];
  return value;
}
ClipPlanGenerationRequest inputFor(String planId) => ClipPlanGenerationRequest(request: request, graph: graph, planId: planId);

class _DraftStore extends ScenarioDraftStore {
  @override
  Future<ScenarioWorkspaceDraft?> load() async => ScenarioWorkspaceDraft(
    inputType: 'scenario', scenarioJson: editor, graphJson: '', ageText: '31',
    contextText: request.sceneContext, instructionsText: request.additionalInstructions!,
    behaviorId: request.behaviorId, cardVersion: request.cardVersion,
    generationRaw: content, responseRequest: request, responseScenarioId: graph.scenarioId,
    editorRequest: request, editorScenarioId: graph.scenarioId,
  );
}
class _Job implements ScenarioGenerationJob {
  final answer = Completer<String>();
  final cancelGate = Completer<void>();
  int disposals = 0, cancellations = 0;
  @override
  Future<String> get response => answer.future;
  @override
  Future<void> cancel() async { ++cancellations; await cancelGate.future; }
  @override
  Future<void> dispose() async { ++disposals; } // Bekleyen iptalden bağımsız.
}
class _Plans implements ClipPlanGenerationService {
  final requests = <ClipPlanGenerationRequest>[];
  final jobs = <_Job>[];
  @override
  ScenarioGenerationJob startPlan(ClipPlanGenerationRequest request) {
    requests.add(request); final job = _Job(); jobs.add(job); return job;
  }
}
class _NoAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => throw StateError('Yeni plan sabit D01 asseti okumamalı: $key');
}

Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
Future<void> mount(WidgetTester tester, ClipPlanGenerationService service,
    {Size size = const Size(1100, 1000), double scale = 1}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(DefaultAssetBundle(bundle: _NoAssets(), child: MaterialApp(
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: Builder(builder: (context) => Scaffold(body: TextButton(
      key: const ValueKey('open'), child: const Text('Aç'), onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ScenarioGraphImportScreen(
          draftStore: _DraftStore(), clipPlanService: service))),
    ))),
  )));
  await tap(tester, 'open');
  await tap(tester, 'scenario-import-validate');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Plan istek/graf metadata eşleşmesi ve ayrı ses/görsel alanları kayıpsızdır', () {
    final input = inputFor('generated-test-1');
    final plan = ScenarioClipPlan.fromJson(planJson(input));
    plan.validateAgainst(graph);
    expect(ScenarioClipPlan.fromJsonString(plan.toJsonString()).toJson(), planJson(input));
    final text = planPromptText(graph, plan);
    for (final c in plan.clips) {
      expect(text, contains(c.productionPrompt)); expect(text, contains(c.voiceoverInstructions!));
    }
    expect(() => ClipPlanGenerationRequest(request: ScenarioGenerationRequest(
      behaviorId: 'D01', cardVersion: '0.2', ageMonths: 30, sceneContext: 'Ev'),
      graph: graph, planId: 'generated-test-2'), throwsFormatException);
  });

  for (final mode in ['success', 'metadata', 'missing-scene', 'duration', 'http', 'broken', 'short-window', 'missing-timing', 'call-time']) {
    test('HTTP plan $mode: doğru endpoint; hata örnek başarıya dönmez', () async {
      final input = inputFor('generated-http');
      var calls = 0;
      String? raw;
      final client = MockClient((sent) async {
        ++calls;
        expect(sent.url.path, '/api/generate-clip-plan');
        expect(jsonDecode(sent.body), input.toJson());
        final plan = mode == 'short-window' ? shortPlan(input, 3) : planJson(input);
        if (mode == 'missing-timing') plan.remove('d01CallTiming');
        if (mode == 'call-time') (plan['d01CallTiming'] as List).first['callEndS'] = 7;
        if (mode == 'missing-scene') (plan['clips'] as List).removeWhere((c) => c['sceneId'] == graph.startSceneId);
        if (mode == 'duration') (plan['clips'] as List).first['targetDurationS'] = 9;
        raw = mode == 'broken' ? '{bozuk' : ' \n${jsonEncode(plan)}\n ';
        return http.Response.bytes(utf8.encode(jsonEncode({
          'success': mode != 'http', 'rawResponse': raw, 'error': 'Kontrollü hata',
          'input': mode == 'metadata' ? {...input.toJson(), 'planId': 'other'} : input.toJson(),
        })), mode == 'http' ? 502 : 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });
      final service = HttpScenarioGenerationService(clientFactory: () => client, resolveServerUrl: () async => 'http://controlled:8000');
      final job = service.startPlan(input);
      if (mode == 'success') { expect(await job.response, raw); }
      else { await expectLater(job.response, throwsA(isA<ScenarioGenerationFailure>())); }
      await job.dispose(); expect(calls, 1);
    });
  }
  test('D01 çağrı-sonrası süre: 9 reddedilir, her dalda tam 10 kabul edilir', () {
    final input = inputFor('generated-timing');
    final short = ScenarioClipPlan.fromJson(shortPlan(input, 3));
    expect(() => short.validateAgainst(graph), throwsA(isA<FormatException>().having(
      (e) => e.message, 'açıklama', contains('9.0 sn, gerekli 10.0 sn'))));
    final enough = ScenarioClipPlan.fromJson(shortPlan(input, 4));
    enough.validateAgainst(graph);
    expect(enough.d01ObservationDurations(graph).values, everyElement(10));
    expect(enough.d01ObservationDurations(graph), hasLength(2));
    expect(ScenarioClipPlan.fromJsonString(enough.toJsonString()).toJson(), enough.toJson());
    final oneShort = shortPlan(input, 4);
    ((oneShort['clips'] as List).last as Map<String, dynamic>)['targetDurationS'] = 3;
    expect(() => ScenarioClipPlan.fromJson(oneShort).validateAgainst(graph), throwsFormatException);
  });
  test('D01 zamanları sayısal ve klip içinde olmalı; eski plansız-zamanlama yolu korunur', () {
    final input = inputFor('generated-times');
    for (final end in [0, -1, 4.01, '3', null]) {
      final value = shortPlan(input, 4);
      (value['d01CallTiming'] as List).first['callEndS'] = end;
      expect(() => ScenarioClipPlan.fromJson(value).validateAgainst(graph), throwsFormatException);
    }
    for (final calls in [[], [{'clipId': 'missing', 'callEndS': 3}],
      [{'clipId': '${graph.startSceneId}-1', 'callEndS': 3}, {'clipId': '${graph.startSceneId}-1', 'callEndS': 3}]]) {
      final value = shortPlan(input, 4); value['d01CallTiming'] = calls;
      expect(() => ScenarioClipPlan.fromJson(value).validateAgainst(graph), throwsFormatException);
    }
    final legacyJson = shortPlan(input, 3)..remove('d01CallTiming');
    final legacy = ScenarioClipPlan.fromJson(legacyJson);
    legacy.validateAgainst(graph); // Eski JSON'u yeni zamanlamayla yeniden etiketlemez.
    expect(() => legacy.d01ObservationDurations(graph, requireTiming: true), throwsFormatException);
  });
  testWidgets('9 saniyelik plan hazır gösterilmez; tam ham cevap inceleme için kalır', (tester) async {
    final service = _Plans(); await mount(tester, service);
    await tap(tester, 'scenario-request-clip-plan');
    final raw = ' \n${jsonEncode(shortPlan(service.requests.single, 3))}\n ';
    service.jobs.single.answer.complete(raw);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scenario-view-clip-plan')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('clip-plan-error'))).data, contains('9.0 sn'));
    final header = find.text('Klip planının tam ham cevabı');
    await tester.ensureVisible(header); await tester.tap(header); await tester.pumpAndSettle();
    expect(tester.widgetList<SelectableText>(find.byType(SelectableText)).map((widget) => widget.data), contains(raw));
    expect(service.jobs.single.disposals, 1);
  });

  test('HTTP iptal ve timeout: geç cevap reddedilir, sunucu iptali iddia edilmez', () async {
    for (final cancel in [false, true]) {
      final gate = Completer<http.Response>(), started = Completer<void>();
      final input = inputFor('generated-late');
      final client = MockClient((_) { started.complete(); return gate.future; });
      final service = HttpScenarioGenerationService(clientFactory: () => client,
        resolveServerUrl: () async => 'http://controlled:8000',
        timeout: cancel ? const Duration(seconds: 100) : Duration.zero);
      final job = service.startPlan(input);
      final response = expectLater(job.response, throwsA(isA<ScenarioGenerationFailure>()));
      await started.future;
      if (cancel) await expectLater(job.cancel(), throwsA(isA<ScenarioGenerationCancellationUnconfirmed>()));
      await response;
      gate.complete(http.Response.bytes(utf8.encode(jsonEncode({'success': true, 'rawResponse': jsonEncode(planJson(input)), 'input': input.toJson()})), 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
      await job.dispose();
    }
  });

  testWidgets('Gerçek düğme → HTTP → aynı plan ekranı; JSON ve promptlar tam kopyalanır, D01 deposu yok', (tester) async {
    final pending = Completer<http.Response>();
    Map<String, dynamic>? sentBody;
    String? raw;
    final client = MockClient((sent) { sentBody = jsonDecode(sent.body) as Map<String, dynamic>; return pending.future; });
    await mount(tester, HttpScenarioGenerationService(clientFactory: () => client, resolveServerUrl: () async => 'http://controlled:8000'));
    await tap(tester, 'scenario-request-clip-plan');
    expect(sentBody!['graph'], graph.toJson()); expect(sentBody!['request'], request.toJson());
    final input = inputFor(sentBody!['planId'] as String);
    raw = ' \n${jsonEncode(planJson(input))}\n ';
    pending.complete(http.Response.bytes(utf8.encode(jsonEncode({'success': true, 'rawResponse': raw, 'input': sentBody})), 200,
      headers: {'content-type': 'application/json; charset=utf-8'}));
    await tester.pumpAndSettle();
    final unchanged = tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text;
    await tap(tester, 'scenario-view-clip-plan');
    expect(find.byType(ClipProductionPlanScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('open-graph-playback')), findsNothing);
    expect(find.text('Video seç'), findsNothing);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tap(tester, 'export-plan-json'); expect(clipboard, raw);
    await tap(tester, 'export-plan-prompts');
    for (final c in ScenarioClipPlan.fromJsonString(raw).clips) {
      expect(clipboard, contains(c.productionPrompt)); expect(clipboard, contains(c.voiceoverInstructions!));
    }
    await tap(tester, 'clip-scene:${graph.startSceneId}');
    final firstClip = ScenarioClipPlan.fromJsonString(raw).clips.first;
    await tester.ensureVisible(find.text(firstClip.voiceoverInstructions!)); await tester.pumpAndSettle();
    expect(find.text(firstClip.voiceoverInstructions!), findsOneWidget);
    await tap(tester, 'copy-clip-prompt:${firstClip.id}');
    expect(clipboard, firstClip.productionPrompt);
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text, unchanged);
  });

  testWidgets('Çift başlatma, iptal/geç cevap ve F04; bekleyen hizmet iptali dispose engellemez', (tester) async {
    final service = _Plans(); await mount(tester, service);
    await tap(tester, 'scenario-request-clip-plan');
    final button = tester.widget<OutlinedButton>(find.byKey(const ValueKey('scenario-request-clip-plan')));
    expect(button.onPressed, isNull); expect(service.jobs, hasLength(1));
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, 'scenario-import-stay'); expect(service.jobs.single.disposals, 0);
    await tap(tester, 'cancel-clip-plan');
    expect(service.jobs.single.disposals, 1);
    service.jobs.single.answer.complete(jsonEncode(planJson(service.requests.single)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scenario-view-clip-plan')), findsNothing);
    await tap(tester, 'scenario-request-clip-plan');
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    await tap(tester, 'scenario-import-exit');
    expect(service.jobs.last.disposals, 1); expect(service.jobs.first.disposals, 1);
    for (final job in service.jobs) {
      job.cancelGate.complete();
      if (!job.answer.isCompleted) job.answer.completeError(StateError('Kapanış'));
    }
    await tester.pump();
  });
  testWidgets('320 piksel/büyük yazı: plan hata ve yeniden istek eylemleri erişilir', (tester) async {
    final service = _Plans(); await mount(tester, service, size: const Size(320, 900), scale: 1.8);
    await tap(tester, 'scenario-request-clip-plan');
    service.jobs.single.answer.completeError(const ScenarioGenerationFailure('Kontrollü sunucu hatası'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('clip-plan-error'))); await tester.pumpAndSettle();
    expect(find.text('Kontrollü sunucu hatası'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('scenario-request-clip-plan'))); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scenario-request-clip-plan')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
