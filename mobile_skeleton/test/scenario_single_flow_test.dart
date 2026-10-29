import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/models/scenario_generation_result.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/models/scenario_age_group.dart';
import 'package:neuro_awareness_app/models/scenario_workspace_draft.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/services/http_scenario_generation_service.dart';
import 'package:neuro_awareness_app/services/scenario_draft_store.dart';
import 'package:neuro_awareness_app/services/server_api_service.dart';

final _request = ScenarioGenerationRequest(behaviorId: 'D01', cardVersion: '0.2', ageGroup: ScenarioAgeGroup.months24To36,
  sceneContext: '  Deniz evde küplerle oynar.  ', additionalInstructions: 'Sabit kamera.');
final _protocol = List.filled(64, 'a').join();
String _raw(String arm) => ' \n${jsonEncode({
  'structure': 'branched', 'commonBehaviorIds': ['D01'],
  'commonStart': '$arm: Deniz oynar; annesi bir kez Deniz der.',
  'alternatives': [
    {'behaviorIds': ['D01'], 'title': 'Yönelme', 'continuation': 'Annesine döner.', 'ending': 'Tekrar çağrı olmadan biter.'},
    {'behaviorIds': ['D01'], 'title': 'Oyun', 'continuation': 'Oyuna devam eder.', 'ending': 'Tekrar çağrı olmadan biter.'},
  ],
})}\n ';

class _Store extends ScenarioDraftStore {
  ScenarioWorkspaceDraft? value;
  @override
  Future<ScenarioWorkspaceDraft?> load() async => value;
  @override
  Future<void> save(ScenarioWorkspaceDraft draft) async {
    value = ScenarioWorkspaceDraft.fromJsonString(draft.toJsonString());
  }
  @override
  Future<void> delete() async { value = null; }
}

class _Server {
  final bodies = <Map<String, dynamic>>[], paths = <String>[];
  static const key = 'controlled-session-only';
  Map<String, dynamic> info(String arm) => {
    'arm': arm, 'protocolId': _protocol, 'model': 'controlled-model',
    'outputContract': ScenarioGenerationResult.contract,
    'settings': {'temperature': 0.2, 'topP': 0.95, 'maxOutputTokens': 16384},
    'sourceMode': 'Kaynak $arm',
    'source': {'sourceId': 'Davranis_Kartlari_v02.md', 'cardVersion': '0.2', 'sha256': List.filled(64, 'b').join()},
    'system': 'Kontrollü sistem istemi $arm', 'user': jsonEncode(_request.toJson()),
  };
  HttpScenarioGenerationService service() => HttpScenarioGenerationService(
    resolveServerUrl: () async => 'http://controlled:8000',
    clientFactory: () => MockClient((sent) async {
      expect(sent.headers['Authorization'] ?? sent.headers['authorization'], 'Bearer $key');
      expect(sent.body, isNot(contains(key)));
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      bodies.add(body); paths.add(sent.url.path);
      Map<String, dynamic> reply;
      if (sent.url.path == '/api/generate-scenario-input') {
        expect(body, _request.toJson());
        reply = {'success': true, 'request': body, 'rawResponse': _raw('normal'),
          'model': 'controlled-model', 'outputContract': ScenarioGenerationResult.contract,
          'settings': info('A')['settings'], 'measurement': {'requestId': 'normal-job', 'outputTokens': null}};
      } else if (sent.url.path == '/api/compare-scenario') {
        expect(body['request'], _request.toJson());
        final arm = body['arm'] as String;
        reply = {'success': true, 'request': body['request'],
          if (body['action'] == 'preview') 'preview': info(arm)
          else ...{'comparison': info(arm), 'rawResponse': _raw(arm),
            'measurement': {'requestId': 'job-$arm', 'promptTokens': null, 'outputTokens': 0}}};
      } else {
        expect(sent.url.path, '/api/generate-clip-plan');
        expect(body['request'], _request.toJson());
        final graph = body['graph'] as Map<String, dynamic>;
        final plan = {'schemaVersion': '1.1', 'ageGroup': _request.ageGroup!.toJson(), 'planId': body['planId'], 'scenarioId': graph['scenarioId'],
          'authoringNote': 'İncelenmemiş taslak.', 'continuityNotes': 'Aynı çocuk, ortam, oyuncak ve kamera.',
          'visualSuggestions': 'Üretilmiş öneri: açık renk kıyafet.',
          'd01CallTiming': [{'clipId': 'clip-${graph['startSceneId']}', 'callEndS': 3}],
          'clips': [for (final scene in graph['scenes'] as List) {
            'id': 'clip-${scene['id']}', 'sceneId': scene['id'], 'orderInScene': 1,
            'targetDurationS': 8, 'plannedAction': scene['description'],
            'initialState': 'Başlangıç', 'finalState': 'Bitiş',
            'productionPrompt': '  Tam prompt ${scene['id']}  ',
            'voiceoverInstructions': 'Ayrı ses yönergesi.',
          }]};
        reply = {'success': true, 'input': body, 'rawResponse': jsonEncode(plan)};
      }
      return http.Response.bytes(utf8.encode(jsonEncode(reply)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target); await tester.pumpAndSettle();
}
Future<void> _field(WidgetTester tester, String key, String text) async {
  final target = find.byKey(ValueKey(key)); await tester.ensureVisible(target);
  await tester.enterText(target, text); await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}
String _editor(WidgetTester tester) => tester.widget<TextField>(
  find.byKey(const ValueKey('scenario-import-json'))).controller!.text;
Future<void> _size(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() { SharedPreferences.setMockInitialValues({}); ServerApiService.selectedArm = 'ALL'; });
  test('Sonuç kimliği tek cevaba aittir; kayıt aynı kimliği ve bilinmeyen ölçümü korur', () {
    final result = ScenarioGenerationResult.fromServer(_request, {'rawResponse': _raw('A')});
    final restored = ScenarioGenerationResult.fromJson(jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>);
    expect(restored.scenarioId, result.scenarioId); expect(restored.rawResponse, _raw('A'));
    expect(restored.request.toJson(), _request.toJson()); expect(restored.model, isNull);
    expect(restored.measurement, isNull);
    expect(ScenarioGenerationResult.fromServer(_request, {'rawResponse': _raw('A')}).scenarioId,
      isNot(result.scenarioId));
    expect(() => ScenarioGenerationResult.fromServer(_request, {
      'rawResponse': _raw('A'), 'outputContract': 'linear-26-v1',
    }), throwsFormatException);
  });
  test('Yeni metadata bulunmayan v1 taslak okunur; ham ve editör ayrı kalır', () {
    final legacy = ScenarioWorkspaceDraft(inputType: 'scenario', scenarioJson: 'düzenlenmiş', graphJson: '',
      ageText: '', contextText: '', instructionsText: '', generationRaw: _raw('A'),
      responseRequest: ScenarioGenerationRequest(behaviorId: 'D01', cardVersion: '0.2',
        ageMonths: 31, sceneContext: _request.sceneContext), responseScenarioId: 'legacy-id');
    final json = jsonDecode(legacy.toJsonString()) as Map<String, dynamic>;
    for (final key in ['responseResult', 'editorResult', 'pendingResult']) { json.remove(key); }
    final restored = ScenarioWorkspaceDraft.fromJsonString(jsonEncode(json));
    expect(restored.scenarioJson, 'düzenlenmiş'); expect(restored.generationRaw, _raw('A'));
    expect(restored.responseScenarioId, 'legacy-id'); expect(restored.responseResult, isNull);
  });
  testWidgets('320px büyük yazı: motor, kol ve tek form eylemleri gizlenmeden erişilir', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final server = _Server();
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)), child: child!),
      home: SyntheticVideoStudioScreen(initialOntologyCode: 'D01', initialAgeMonths: 31,
        comparisonService: server.service(), scenarioDraftStore: _Store())));
    await tester.pumpAndSettle(); await _tap(tester, 'studio-engine-server');
    for (final key in ['studio-arm-A', 'studio-arm-B', 'studio-arm-C']) { await _tap(tester, key); }
    for (final key in ['studio-open-comparison', 'scenario-request-age', 'scenario-request-context',
      'scenario-request-instructions', 'scenario-request-validate', 'studio-generate-scenario']) {
      final target = find.byKey(ValueKey(key)); await tester.ensureVisible(target);
      expect(target.hitTestable(), findsOneWidget);
    }
    expect(server.bodies, isEmpty); expect(tester.takeException(), isNull); await _close(tester);
  });
  testWidgets('Gelen sonuç dolu taslağı onaysız ezmez; düzenlenmiş JSON, kaynak ve kimlik yeniden açılır', (tester) async {
    await _size(tester);
    final store = _Store()..value = ScenarioWorkspaceDraft(inputType: 'graph', scenarioJson: 'eski senaryo',
      graphJson: '{"eski":"graf"}', ageText: '', contextText: '', instructionsText: '');
    final result = ScenarioGenerationResult.fromServer(_request, {'rawResponse': _raw('B'),
      'comparison': _Server().info('B'), 'measurement': {'outputTokens': null}});
    await tester.pumpWidget(MaterialApp(home: ScenarioGraphImportScreen(draftStore: store, incomingResult: result)));
    await tester.pumpAndSettle(); final previous = _editor(tester);
    await _tap(tester, 'scenario-accept-result');
    await tester.tap(find.text('Taslağı koru')); await tester.pumpAndSettle();
    expect(_editor(tester), previous); expect(store.value!.graphJson, previous);
    await _tap(tester, 'scenario-accept-result'); await tester.tap(find.text('Aktar')); await tester.pumpAndSettle();
    final edited = jsonDecode(_editor(tester)) as Map<String, dynamic>;
    expect(edited['scenarioId'], result.scenarioId); edited['commonStart'] = '  Ekibin düzenlemesi  ';
    await _field(tester, 'scenario-import-json', jsonEncode(edited)); await _tap(tester, 'scenario-import-validate');
    await _tap(tester, 'scenario-draft-save');
    final saved = store.value!;
    expect(saved.responseResult!.toJson(), result.toJson()); expect(saved.editorResult!.scenarioId, result.scenarioId);
    expect(saved.generationRaw, result.rawResponse); expect(saved.generationEdited, isTrue);
    expect(saved.toJsonString(), isNot(contains(_Server.key)));
    final before = _editor(tester); await _close(tester);
    await tester.pumpWidget(MaterialApp(home: ScenarioGraphImportScreen(draftStore: store)));
    await tester.pumpAndSettle(); expect(_editor(tester), before);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    await _tap(tester, 'scenario-import-validate'); expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
    expect(ScenarioInput.fromJsonString(_editor(tester)).source, ScenarioInputSource.editedModelOutput); await _close(tester);
  });
  testWidgets('Tek form normal ve A/B/C için aynıdır; seçilen sonuç çağrısız editöre, aynı kimlikle plana gider', (tester) async {
    await _size(tester); final server = _Server(), store = _Store();
    await tester.pumpWidget(MaterialApp(home: SyntheticVideoStudioScreen(initialOntologyCode: 'D01', initialAgeMonths: 31,
      comparisonService: server.service(), scenarioDraftStore: store)));
    await tester.pumpAndSettle(); expect(server.bodies, isEmpty);
    await _tap(tester, 'studio-engine-server');
    await _field(tester, 'scenario-request-context', _request.sceneContext);
    await _field(tester, 'scenario-request-instructions', _request.additionalInstructions!);
    await _field(tester, 'studio-team-access-key', _Server.key);
    await _tap(tester, 'studio-generate-scenario');
    expect(server.paths, ['/api/generate-scenario-input']);
    await _tap(tester, 'studio-continue-result'); await _tap(tester, 'scenario-accept-result');
    final normalId = ScenarioInput.fromJsonString(_editor(tester)).scenarioId;
    expect(server.paths, hasLength(1));
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    await _tap(tester, 'scenario-import-exit');
    await _tap(tester, 'studio-open-comparison'); expect(server.paths, hasLength(1));
    await _tap(tester, 'comparison-preview');
    expect(server.bodies.skip(1).map((body) => body['request']), everyElement(_request.toJson()));
    expect(server.bodies.skip(1).map((body) => body['action']), everyElement('preview'));
    await _tap(tester, 'comparison-start');
    expect(server.bodies.where((body) => body['action'] == 'generate').map((body) => body['arm']), ['A', 'B', 'C']);
    final calls = server.paths.length;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') { copied = (call.arguments as Map)['text'] as String; }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _tap(tester, 'comparison-copy-all');
    final trials = (jsonDecode(copied!) as Map)['results'] as List;
    expect(trials.map((trial) => trial['selectedResult']['scenarioId']).toSet(), hasLength(3));
    expect(trials.map((trial) => trial['selectedResult']['scenarioId']), isNot(contains(normalId)));
    for (var i = 0; i < 3; i++) {
      expect(trials[i]['selectedResult']['rawResponse'], _raw(['A', 'B', 'C'][i]));
      expect(trials[i]['selectedResult']['request'], _request.toJson());
    }
    expect(copied, isNot(contains(_Server.key)));
    Future<void> openTrial(int index) async {
      final header = find.descendant(of: find.byKey(ValueKey('comparison-result-$index')), matching: find.byType(ListTile));
      await tester.ensureVisible(header); await tester.tap(header); await tester.pumpAndSettle();
      await _tap(tester, 'comparison-continue-$index'); await _tap(tester, 'scenario-accept-result');
    }
    await openTrial(0); final id = ScenarioInput.fromJsonString(_editor(tester)).scenarioId;
    expect(id, trials[0]['selectedResult']['scenarioId']);
    expect(id, isNot(normalId)); expect(server.paths, hasLength(calls));
    final chosen = tester.widget<ScenarioGraphImportScreen>(find.byType(ScenarioGraphImportScreen)).incomingResult!;
    expect(chosen.arm, 'A'); expect(chosen.rawResponse, _raw('A')); expect(chosen.protocolId, _protocol);
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle(); await _tap(tester, 'scenario-import-exit');
    // Önceki açık başlığın altındaki aynı düğme; aynı deneme için yeni kimlik/çağrı yok.
    await _tap(tester, 'comparison-continue-0'); await _tap(tester, 'scenario-accept-result');
    expect(ScenarioInput.fromJsonString(_editor(tester)).scenarioId, id); expect(server.paths, hasLength(calls));
    await _tap(tester, 'scenario-import-validate'); await _tap(tester, 'scenario-request-clip-plan');
    expect(server.paths.last, '/api/generate-clip-plan');
    expect((server.bodies.last['graph'] as Map)['scenarioId'], id);
    await _tap(tester, 'scenario-view-clip-plan');
    final plan = tester.widget<ClipProductionPlanScreen>(find.byType(ClipProductionPlanScreen));
    expect(plan.providedPlan!.graph.scenarioId, id); expect(plan.sourceContext!['scenarioId'], id);
    expect(plan.sourceContext!['rawResponse'], _raw('A')); expect(plan.sourceContext!['arm'], 'A');
    expect(plan.sourceContext.toString(), isNot(contains(_Server.key)));
    expect(find.byKey(const ValueKey('open-d01-playback')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().map(prefs.get).join(), isNot(contains(_Server.key))); await _close(tester);
  });
}
