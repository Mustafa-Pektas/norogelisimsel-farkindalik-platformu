import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/scenario_behavior_ref.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/models/scenario_generation_result.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/models/scenario_workspace_draft.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/services/scenario_generation_service.dart';
import 'package:neuro_awareness_app/services/scenario_graph_converter.dart';
import 'package:neuro_awareness_app/services/scenario_draft_store.dart';
import 'package:neuro_awareness_app/services/clip_plan_generation_service.dart';
import 'package:neuro_awareness_app/services/http_scenario_generation_service.dart';

final _refs = ['D01','D02','D03'].map((id) => ScenarioBehaviorRef(behaviorId: id, cardVersion: '0.2')).toList();
ScenarioGenerationRequest _request({bool linear = false}) => ScenarioGenerationRequest(
  behaviorId: 'D01', cardVersion: '0.2', behaviors: _refs, ageMonths: 31, sceneContext: '  Evde oyun.  ',
  production: linear ? ScenarioProductionSettings(structure: 'linear26', targetDurationS: 210, maxClipDurationS: 8) : null);
String _raw(ScenarioGenerationRequest request) => ' \n${jsonEncode({
  'structure': request.linear ? 'linear26' : 'branched', 'commonStart': '  Ortak anlatı.  ',
  if (request.linear) 'linearScenes': [for (var i = 0; i < 26; i++) {
    'title': 'Sahne ${i + 1}', 'description': '  Sahne anlatısı ${i + 1}.  ',
    'behaviorIds': [request.behaviors[i % request.behaviors.length].behaviorId],
  }] else 'commonBehaviorIds': request.behaviors.map((ref) => ref.behaviorId).toList(),
  'alternatives': request.linear ? [] : [for (final ref in request.behaviors) {
    'title': '${ref.behaviorId} devamı', 'continuation': '  Devam ${ref.behaviorId}.  ',
    'ending': 'Bitiş ${ref.behaviorId}.', 'behaviorIds': [ref.behaviorId],
  }],
})}\n ';
class _Store extends ScenarioDraftStore {
  ScenarioWorkspaceDraft? value;
  @override
  Future<ScenarioWorkspaceDraft?> load() async => value;
  @override
  Future<void> save(ScenarioWorkspaceDraft draft) async { value = ScenarioWorkspaceDraft.fromJsonString(draft.toJsonString()); }
  @override
  Future<void> delete() async { value = null; }
}
class _Job implements ScenarioGenerationJob {
  _Job(this.raw);
  final String raw;
  int disposals = 0;
  @override
  Future<String> get response async => raw;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async { disposals++; }
}
class _Generation implements ScenarioGenerationService {
  final requests = <ScenarioGenerationRequest>[];
  @override
  bool get isAvailable => true;
  @override
  String get availabilityMessage => 'Kontrollü hizmet';
  @override
  ScenarioGenerationJob start(ScenarioGenerationRequest request) {
    requests.add(request); return _Job(_raw(request));
  }
}
class _Plans implements ClipPlanGenerationService {
  final requests = <ClipPlanGenerationRequest>[];
  @override
  ScenarioGenerationJob startPlan(ClipPlanGenerationRequest request) {
    requests.add(request);
    return _Job(jsonEncode({'schemaVersion': '1.0', 'planId': request.planId, 'scenarioId': request.graph.scenarioId,
      'authoringNote': 'İncelenmedi.', 'continuityNotes': 'Aynı karakter ve ortam.', 'visualSuggestions': 'Üretilmiş görsel öneri.',
      'd01CallTiming': [{'clipId': 'clip-start', 'callEndS': 3}],
      'clips': [for (final scene in request.graph.scenes) {
        'id': 'clip-${scene.id}', 'sceneId': scene.id, 'orderInScene': 1, 'targetDurationS': 8,
        'plannedAction': scene.description, 'initialState': 'Önce', 'finalState': 'Sonra',
        'productionPrompt': '  Tam görsel prompt ${scene.id}  ', 'voiceoverInstructions': 'Ayrı ses yönergesi.',
      }],
    }));
  }
}
Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key)); await tester.ensureVisible(target);
  expect(target.hitTestable(), findsOneWidget); await tester.tap(target); await tester.pumpAndSettle();
}
Future<void> _field(WidgetTester tester, String key, String value) async {
  final target = find.byKey(ValueKey(key)); await tester.ensureVisible(target); await tester.enterText(target,value);
  await tester.testTextInput.receiveAction(TextInputAction.done); await tester.pump();
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? copied;
  setUp(() {
    SharedPreferences.setMockInitialValues({}); copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') { copied = (call.arguments as Map)['text'] as String; }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  test('Çoklu istek/girdi/graf/taslak bütün kartları ve ham metni korur; v1/v2 eski kayıt okunur', () {
    final request = _request();
    expect(ScenarioGenerationRequest.fromJson(jsonDecode(jsonEncode(request.toJson())) as Map<String,dynamic>).toJson(), request.toJson());
    final result = ScenarioGenerationResult.fromServer(request, {'rawResponse': _raw(request)});
    final input = ScenarioInput.fromJsonString(request.prepareInput(result.rawResponse, scenarioId: result.scenarioId, edited: false).json);
    final graph = const ScenarioGraphConverter().convert(input);
    expect(graph.behaviors.map((ref) => ref.behaviorId), ['D01','D02','D03']);
    expect(graph.scenes.expand(graph.behaviorIdsFor).toSet(), {'D01','D02','D03'});
    expect(ScenarioGraph.fromJson(graph.toJson()).toJson(), graph.toJson());
    final draft = ScenarioWorkspaceDraft(inputType: 'scenario', scenarioJson: request.prepareInput(result.rawResponse,
      scenarioId: result.scenarioId, edited: false).json, graphJson: '', ageText: '31', contextText: request.sceneContext,
      instructionsText: '', generationRaw: result.rawResponse, responseRequest: request, responseScenarioId: result.scenarioId,
      responseResult: result, editorRequest: request, editorScenarioId: result.scenarioId, editorResult: result);
    final restored = ScenarioWorkspaceDraft.fromJsonString(draft.toJsonString());
    expect(restored.responseRequest!.toJson(), request.toJson()); expect(restored.responseResult!.scenarioId, result.scenarioId);
    expect(restored.generationRaw, result.rawResponse); expect(restored.scenarioJson, draft.scenarioJson);
    final legacy = ScenarioGenerationRequest(behaviorId: 'D01', cardVersion: '0.2', ageMonths: 30, sceneContext: 'Ev');
    final oldRaw = jsonEncode({'commonStart': 'Başlangıç', 'alternatives': [{'title':'Devam','continuation':'Oyun','ending':'Bitiş'}]});
    final old = ScenarioGenerationResult(scenarioId: 'legacy-record', request: legacy,
      rawResponse: oldRaw, outputContract: 'scenario-input-narrative-v2');
    expect(ScenarioGenerationResult.fromJson(old.toJson()).rawResponse, oldRaw);
    expect(() => ScenarioGenerationResult.fromServer(legacy, old.toJson()), throwsFormatException);
    expect(legacy.toJson().containsKey('requestVersion'), isFalse);
  });
  test('26 gerçek anlatı sahnesi doğrusal grafa dönüşür; metinler ve sıra korunur, dal eklenmez', () {
    final request = _request(linear: true), raw = _raw(_request(linear: true));
    final input = ScenarioInput.fromJsonString(request.prepareInput(raw, scenarioId: 'linear', edited: false).json);
    final graph = const ScenarioGraphConverter().convert(input);
    expect(graph.scenes, hasLength(26)); expect(graph.transitions, hasLength(25)); expect(input.alternatives, isEmpty);
    for (var i = 0; i < 26; i++) {
      expect(graph.scenes[i].description, '  Sahne anlatısı ${i + 1}.  ');
      expect(graph.transitions.where((edge) => edge.fromSceneId == graph.scenes[i].id).length, i == 25 ? 0 : 1);
    }
    final invalid = jsonDecode(raw) as Map<String,dynamic>; (invalid['linearScenes'] as List).removeLast();
    expect(() => request.prepareInput(jsonEncode(invalid), scenarioId: 'linear', edited: false), throwsFormatException);
    expect(() => request.prepareInput('{"title":"Eski","scenes":[]}', scenarioId: 'linear', edited: false), throwsFormatException);
  });
  test('Eksik davranış ilişkisi ve üretim hedefi reddedilir; seçimi ilk karta düşürmez', () {
    final request = _request(), value = jsonDecode(_raw(_request())) as Map<String,dynamic>;
    value['commonBehaviorIds'] = ['D01']; value['alternatives'] = [(value['alternatives'] as List).first];
    expect(() => request.prepareInput(jsonEncode(value), scenarioId: 'missing', edited: false), throwsFormatException);
    expect(() => ScenarioProductionSettings(structure: 'linear26', targetDurationS: 210, maxClipDurationS: 9), throwsFormatException);
  });
  test('Normal ve A/B/C HTTP bütün seçimleri aynı değişmez istekten taşır; anahtar body/export içinde değildir', () async {
    final request = _request();
    final bodies = <Map<String,dynamic>>[];
    final protocol = List.filled(64,'a').join();
    final service = HttpScenarioGenerationService(resolveServerUrl: () async => 'http://controlled:8000',
      resolveAccessKey: () => 'controlled-session-only', clientFactory: () => MockClient((sent) async {
        expect(sent.headers['Authorization'] ?? sent.headers['authorization'], 'Bearer controlled-session-only');
        expect(sent.body, isNot(contains('controlled-session-only')));
        final body = jsonDecode(sent.body) as Map<String,dynamic>; bodies.add(body);
        final compare = sent.url.path.endsWith('compare-scenario');
        expect(compare ? body['request'] : body, request.toJson());
        final info = {'arm': body['arm'], 'protocolId': protocol, 'outputContract': ScenarioGenerationResult.contract,
          'source': {'cardVersion': '0.2', 'behaviors': request.behaviors.map((ref) => ref.toJson()).toList()}};
        return http.Response.bytes(utf8.encode(jsonEncode({'success': true, 'request': request.toJson(),
          if (body['action'] == 'preview') 'preview': info else ...{
            'rawResponse': _raw(request), if (compare) 'comparison': info
            else 'outputContract': ScenarioGenerationResult.contract,
          }})), 200, headers: {'content-type':'application/json; charset=utf-8'});
      }));
    final normal = service.start(request); expect(await normal.response, _raw(request)); await normal.dispose();
    for (final arm in ['A','B','C']) {
      final preview = service.startComparison(request, arm: arm, preview: true); await preview.result; await preview.dispose();
      final job = service.startComparison(request, arm: arm, preview: false, protocolId: protocol);
      expect((await job.result)['rawResponse'], _raw(request)); await job.dispose();
    }
    expect(bodies, hasLength(7)); expect(request.behaviors, hasLength(3));
  });
  for (final linear in [false,true]) {
    testWidgets('Tek form çoklu seçim ve $linear düzenini aktif sahne/prompt planına taşır', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100,1000)); addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _Generation(), plans = _Plans(), store = _Store();
      await tester.pumpWidget(MaterialApp(home: SyntheticVideoStudioScreen(generationService: service,
        clipPlanService: plans, scenarioDraftStore: store)));
      await tester.pumpAndSettle(); await _tap(tester,'studio-engine-server');
      await _field(tester,'scenario-request-age','31'); await _field(tester,'scenario-request-context','  Evde oyun.  ');
      if (linear) {
        await _tap(tester,'scenario-structure-linear26');
        expect(find.byKey(const ValueKey('scenario-production-duration-capacity-note')), findsOneWidget);
        expect(find.textContaining('en az 27 klip gerekir'), findsOneWidget);
      }
      expect(service.requests,isEmpty); await _tap(tester,'studio-generate-scenario');
      expect(service.requests.single.behaviors.map((ref) => ref.behaviorId), ['D01','D02','D03']);
      expect(service.requests.single.linear, linear);
      if (linear) {
        expect(service.requests.single.production!.targetDurationS, 210);
        expect(service.requests.single.production!.maxClipDurationS, 8);
      }
      expect(find.byKey(ValueKey('narrative-scene:${linear ? 'scene_26' : 'alternative_3'}')),findsOneWidget);
      await _tap(tester,'studio-continue-result'); await _tap(tester,'scenario-accept-result');
      await _tap(tester,'scenario-import-validate');
      expect(find.text('Davranışlar: D01 (0.2), D02 (0.2), D03 (0.2)'), findsOneWidget);
      final graphView = find.text('Grafı görüntüle'); await tester.ensureVisible(graphView);
      await tester.tap(graphView); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scenario-graph-behavior-summary')), findsOneWidget);
      expect(find.textContaining('Davranışlar: D01, D02, D03'), findsOneWidget);
      await tester.pageBack(); await tester.pumpAndSettle();
      await _tap(tester,'scenario-draft-save');
      expect(store.value!.responseRequest!.behaviors,hasLength(3));
      final editor = tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text;
      expect(ScenarioInput.fromJsonString(editor).behaviors,hasLength(3));
      await _tap(tester,'scenario-request-clip-plan'); expect(plans.requests,hasLength(1));
      expect(plans.requests.single.graph.scenes.length,linear ? 26 : 7);
      await _tap(tester,'scenario-view-clip-plan');
      final screen = tester.widget<ClipProductionPlanScreen>(find.byType(ClipProductionPlanScreen));
      expect(screen.providedPlan!.graph.scenarioId,store.value!.editorScenarioId);
      expect((screen.sourceContext!['request'] as Map)['behaviors'],hasLength(3));
      final title = find.descendant(of:find.byKey(const ValueKey('clip-scene:start')),matching:find.byType(ListTile));
      await tester.ensureVisible(title); await tester.tap(title); await tester.pumpAndSettle();
      await _tap(tester,'copy-clip-prompt:clip-start');
      expect(copied,'  Tam görsel prompt start  ');
      expect(find.text('Ayrı seslendirme yönergeleri'),findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle(); expect(tester.takeException(),isNull);
    });
  }
  testWidgets('320px iki kat yazı: yaş rozeti alana değmez; hata alanın yanında, düzenler erişilir', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320,800)); addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _Generation();
    await tester.pumpWidget(MaterialApp(builder:(context,child) => MediaQuery(
      data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(2)),child:child!),
      home:SyntheticVideoStudioScreen(generationService:service)));
    await tester.pumpAndSettle(); await _tap(tester,'studio-engine-server');
    final age = find.byKey(const ValueKey('scenario-request-age')); await tester.ensureVisible(age);
    expect(tester.getRect(age).top,greaterThan(tester.getRect(find.text('12–36 ay')).bottom));
    await _field(tester,'scenario-request-age','11');
    expect(find.text('12–36 arasında tam ay girin.'),findsOneWidget);
    await _field(tester,'scenario-request-age','31'); expect(find.text('12–36 arasında tam ay girin.'),findsNothing);
    for (final mode in ['linear26','branched']) { await _tap(tester,'scenario-structure-$mode'); }
    await tester.ensureVisible(find.byKey(const ValueKey('studio-generate-scenario')));
    expect(find.byKey(const ValueKey('studio-generate-scenario')).hitTestable(),findsOneWidget);
    expect(service.requests,isEmpty); expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle();
  });
}
