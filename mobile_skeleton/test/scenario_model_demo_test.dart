import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/behavior_cards.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/models/scenario_age_group.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_screen.dart';
import 'package:neuro_awareness_app/services/scenario_graph_converter.dart';
import 'package:neuro_awareness_app/services/scenario_generation_service.dart';

import 'package:neuro_awareness_app/models/scenario_generation_result.dart';
import 'package:neuro_awareness_app/services/scenario_draft_store.dart';
import 'package:neuro_awareness_app/models/scenario_workspace_draft.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';

// Kontrollü hizmet; gerçek ağ, yerel model veya video motoru kullanılmaz.
class _GenerationService implements ScenarioGenerationService {
  final requests = <ScenarioGenerationRequest>[];
  final jobs = <_GenerationJob>[];
  bool failStart = false;
  @override
  bool get isAvailable => true;
  @override
  String get availabilityMessage => 'Kontrollü üretim hizmeti';
  @override
  ScenarioGenerationJob start(ScenarioGenerationRequest request) {
    if (failStart) throw StateError('Kontrollü başlangıç hatası');
    requests.add(request);
    final job = _GenerationJob();
    jobs.add(job);
    return job;
  }
}

class _GenerationJob implements ScenarioGenerationJob {
  final answer = Completer<String>();
  Completer<void>? cancelGate;
  bool failCancel = false;
  bool localCancelOnly = false;
  bool completeOnDispose = true;
  int cancellations = 0;
  int disposals = 0;
  @override
  Future<String> get response => answer.future;
  @override
  Future<void> cancel() async {
    ++cancellations;
    final gate = cancelGate;
    if (gate != null) await gate.future;
    if (localCancelOnly) throw const ScenarioGenerationCancellationUnconfirmed();
    if (failCancel) throw StateError('Kontrollü iptal hatası');
  }
  @override
  Future<void> dispose() async {
    ++disposals;
    final gate = cancelGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    if (completeOnDispose && !answer.isCompleted) {
      answer.completeError(StateError('İş kapatıldı'));
    }
  }
}

class _NoAssets extends CachingAssetBundle {
  final reads = <String>[];
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    reads.add(key);
    throw StateError('Senaryo çalışma alanı sabit graf/plan asseti okumamalı.');
  }
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

class _MemoryStore extends ScenarioDraftStore {
  ScenarioWorkspaceDraft? value;
  @override
  Future<ScenarioWorkspaceDraft?> load() async => value;
  @override
  Future<void> save(ScenarioWorkspaceDraft draft) async { value = draft; }
  @override
  Future<void> delete() async { value = null; }
}
Future<void> tap(WidgetTester tester, String key, {bool settle = true}) async {
  final title = switch (key) {
    'studio-result-details' => 'Tam ham cevap ve üretim kaynağı',
    'studio-error-raw-details' => 'Başarısız isteğin ham cevabı',
    'scenario-generation-raw-details' => 'Ham cevap ve kaynak',
    'scenario-request-rules' => 'Kaynak ve kullanım sınırları',
    _ => null,
  };
  final root = find.byKey(ValueKey(key));
  final target = title == null ? root : find.descendant(of: root, matching: find.text(title));
  await tester.ensureVisible(target); expect(target.hitTestable(), findsOneWidget); await tester.tap(target);
  if (settle) { await tester.pumpAndSettle(); }
  else { await tester.pump(); await tester.pump(const Duration(milliseconds: 300)); }
}
void main() {
  String? copied;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  final example = jsonDecode(File(ScenarioGraphImportScreen.d01InputAssetPath).readAsStringSync()) as Map<String, dynamic>;
  final content = jsonEncode({'commonStart': example['commonStart'], 'alternatives': example['alternatives']});
  String outputFor(ScenarioGenerationRequest request) {
    if (request.ageGroup == null) return content;
    final value = jsonDecode(content) as Map<String, dynamic>;
    value['structure'] = 'branched';
    final ids = request.behaviors.map((ref) => ref.behaviorId).toList();
    value['commonBehaviorIds'] = ids;
    value['alternatives'] = (value['alternatives'] as List).map((entry) => {
      ...Map<String, dynamic>.from(entry as Map), 'behaviorIds': ids,
    }).toList();
    return jsonEncode(value);
  }
  final request = ScenarioGenerationRequest(behaviorId: 'D02', cardVersion: '0.2', ageMonths: 24, sceneContext: '  Evde  ', additionalInstructions: 'Sade ortam.');
  String editor(WidgetTester tester) => tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text;
  Future<void> field(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(ValueKey(key)); await tester.ensureVisible(finder); await tester.enterText(finder, value);
    await tester.testTextInput.receiveAction(TextInputAction.done); await tester.pump();
  }
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
  }
  Future<void> mountRoute(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000)); addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      key: const ValueKey('open-import'), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => ScenarioGraphImportScreen(draftStore: _MemoryStore()))), child: const Text('Aç'))))));
    await tap(tester, 'open-import');
  }
  Future<void> appBarBack(WidgetTester tester) async { await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle(); }
  Future<void> studio(WidgetTester tester, ScenarioGenerationService service, {String behavior = 'D02', bool route = false,
    _MemoryStore? store}) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000)); addTearDown(() => tester.binding.setSurfaceSize(null));
    final screen = SyntheticVideoStudioScreen(initialOntologyCode: behavior,
      generationService: service, scenarioDraftStore: store ?? _MemoryStore());
    await tester.pumpWidget(DefaultAssetBundle(bundle: _NoAssets(), child: MaterialApp(home: route
      ? Builder(builder: (context) => Scaffold(body: TextButton(key: const ValueKey('open-studio'),
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen)), child: const Text('Aç'))))
      : screen)));
    await tester.pumpAndSettle(); if (route) await tap(tester, 'open-studio'); await tap(tester, 'studio-engine-server');
  }
  Future<void> selectAgeGroup(WidgetTester tester, String id) async {
    final chip = find.byKey(ValueKey('scenario-age-group-$id'));
    await tester.ensureVisible(chip); await tester.tap(chip); await tester.pump();
  }
  Future<void> configure(WidgetTester tester) async {
    await selectAgeGroup(tester, '18_24'); await field(tester, 'scenario-request-context', '  Evde  ');
    await field(tester, 'scenario-request-instructions', 'Sade ortam.'); await tap(tester, 'scenario-request-validate');
  }
  Future<void> workspace(WidgetTester tester, String raw, {bool narrow = false}) async {
    await tester.binding.setSurfaceSize(narrow ? const Size(320, 800) : const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = ScenarioGenerationResult.fromServer(request, {'rawResponse': raw});
    await tester.pumpWidget(DefaultAssetBundle(bundle: _NoAssets(), child: MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)), child: child!),
      home: ScenarioGraphImportScreen(initialScenarioContent: true, incomingResult: result, draftStore: _MemoryStore()))));
    await tester.pumpAndSettle(); expect(editor(tester), isEmpty); await tap(tester, 'scenario-accept-result');
    expect(ScenarioInput.fromJsonString(editor(tester)).scenarioId, result.scenarioId);
  }
  for (final systemBack in [false, true]) {
    testWidgets('Boş ekranda ${systemBack ? 'sistem' : 'AppBar'} geri onaysız çıkar', (tester) async {

      await mountRoute(tester);
      if (systemBack) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      } else {
        await appBarBack(tester);
      }
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ScenarioGraphImportScreen), findsNothing);
      expect(find.byKey(const ValueKey('open-import')), findsOneWidget);

    });
  }

  testWidgets('AppBar ve sistem geri: kalmak metni ve doğrulama hatasını korur', (tester) async {

    await mountRoute(tester);
    const text = '{"Eksik": "Kullanıcı taslağı"}';
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), text);
    await tap(tester, 'scenario-import-validate');
    final error = tester.widget<Text>(
      find.byKey(const ValueKey('scenario-import-error')),
    ).data;

    await appBarBack(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.byKey(const ValueKey('scenario-import-stay')),
    ).autofocus, isTrue);
    await tap(tester, 'scenario-import-stay');
    expect(editor(tester), text);
    expect(tester.widget<Text>(
      find.byKey(const ValueKey('scenario-import-error')),
    ).data, error);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    // Diyalogdayken ikinci geri yalnız diyaloğu kapatır; taslak terk edilmez.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(editor(tester), text);
    expect(tester.widget<Text>(
      find.byKey(const ValueKey('scenario-import-error')),
    ).data, error);

    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), '');
    await tester.pump();
    await appBarBack(tester);
    expect(find.byType(AlertDialog), findsNothing);

  });

  testWidgets('Diğer giriş türündeki taslak korunur; temizlenen etkin kopya çıkışı engellemez', (tester) async {

    await mountRoute(tester);
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), 'Graf taslağı');
    await tap(tester, 'scenario-import-mode-scenario');
    expect(editor(tester), isEmpty);
    await appBarBack(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, 'scenario-import-stay');
    await tap(tester, 'scenario-import-mode-graph');
    expect(editor(tester), 'Graf taslağı');
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), '');
    await tester.pump();
    await appBarBack(tester);
    expect(find.byType(AlertDialog), findsNothing);

  });

  for (final card in BehaviorCards.all) {
    final id=card.id, version=card.cardVersion;
    testWidgets('Tek Stüdyo formu $id ve doğru kart sürümünü taşır; otomatik çağrı yoktur', (tester) async {
      final service=_GenerationService(); await studio(tester,service,behavior:id);
      expect(service.requests,isEmpty); await tap(tester, 'scenario-request-rules');
      expect(find.text('${card.title} · Kart sürümü: $version'),findsOneWidget);
      await tap(tester, 'scenario-request-rules');
      await configure(tester); await tap(tester,'studio-generate-scenario',settle:false);
      expect(service.requests.single.behaviorId,id); expect(service.requests.single.cardVersion,version);
      expect(service.requests.single.ageGroup,ScenarioAgeGroup.months18To24);
      expect(service.requests.single.ageMonths,isNull); expect(service.requests.single.sceneContext,'  Evde  ');
      expect(service.requests.single.additionalInstructions,'Sade ortam.');
      service.jobs.single.answer.complete(outputFor(service.requests.single)); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('studio-continue-result')),findsOneWidget);
      await close(tester); expect(service.jobs.single.disposals,1);
    });
  }
  testWidgets('Yaş grubu seçilmeden üretim başlamaz', (tester) async {
    final service = _GenerationService(); await studio(tester, service);
    await field(tester, 'scenario-request-context', 'Ev');
    await tap(tester, 'scenario-request-validate');
    expect(find.byKey(const ValueKey('scenario-request-error')), findsOneWidget);
    await tap(tester, 'studio-generate-scenario', settle: false);
    expect(service.requests, isEmpty); await close(tester);
  });
  for (final group in ScenarioAgeGroup.values) {
    testWidgets('${group.label} normal üretim isteği ve graf metadata\'sına aynen taşınır', (tester) async {
      final service = _GenerationService(); await studio(tester, service);
      await selectAgeGroup(tester, group.id);
      await field(tester, 'scenario-request-context', 'Ev');
      await tap(tester, 'scenario-request-validate');
      await tap(tester, 'studio-generate-scenario', settle: false);
      final request = service.requests.single;
      expect(request.ageGroup, group); expect(request.ageMonths, isNull);
      expect(request.toJson()['ageGroup'], group.toJson());
      service.jobs.single.answer.complete(outputFor(request)); await tester.pumpAndSettle();
      await tap(tester, 'studio-continue-result'); await tap(tester, 'scenario-accept-result');
      final input = ScenarioInput.fromJsonString(editor(tester));
      expect(input.ageGroup, group); expect(input.ageMonths, isNull);
      await close(tester);
    });
  }
  for (final age in [12, 17, 18, 23, 24, 36]) {
    testWidgets('Eski $age ay taslağı açılır ve yeni istekte doğru gruba eşlenir; kayıtlı ay değişmez', (tester) async {
      final store = _MemoryStore()..value = ScenarioWorkspaceDraft(inputType: 'scenario',
        scenarioJson: '', graphJson: '', ageText: '$age', contextText: '', instructionsText: '');
      final service = _GenerationService(); await studio(tester, service, store: store);
      final expected = ScenarioAgeGroup.fromLegacyMonths(age)!;
      expect(tester.widget<ChoiceChip>(find.byKey(ValueKey('scenario-age-group-${expected.id}'))).selected, isTrue);
      await field(tester, 'scenario-request-context', 'Eski taslaktan devam.');
      await tap(tester, 'scenario-request-validate');
      await tap(tester, 'studio-generate-scenario', settle: false);
      expect(service.requests.single.ageGroup, expected);
      expect(service.requests.single.ageMonths, isNull);
      expect(store.value!.ageText, '$age');
      await close(tester);
    });
  }
  for (final ageText in ['', '11', '37', '18.5', 'unknown']) {
    testWidgets('Eksik/geçersiz eski yaş "$ageText" seçim üretmez; kullanıcı yaş grubunu seçebilir', (tester) async {
      final store = _MemoryStore()..value = ScenarioWorkspaceDraft(inputType: 'scenario',
        scenarioJson: '', graphJson: '', ageText: ageText, contextText: '', instructionsText: '');
      final service = _GenerationService(); await studio(tester, service, store: store);
      expect(find.byKey(const ValueKey('scenario-age-group-12_18')), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('scenario-age-group-12_18'))).selected, isFalse);
      await field(tester, 'scenario-request-context', 'Ortam');
      await tap(tester, 'studio-generate-scenario', settle: false);
      expect(service.requests, isEmpty);
      expect(store.value!.ageText, ageText);
      await selectAgeGroup(tester, '12_18');
      await tap(tester, 'studio-generate-scenario', settle: false);
      expect(service.requests.single.ageGroup, ScenarioAgeGroup.months12To18);
      expect(store.value!.ageText, ageText);
      await close(tester);
    });
  }
  for (final name in ['age-group','context','instructions']) {
    testWidgets('Yalnız $name değişmiş form F04 ile korunur; temizlenince boş çıkış serbesttir', (tester) async {
      await studio(tester,_GenerationService(),route:true);
      if (name == 'age-group') {
        await selectAgeGroup(tester, '24_36'); await appBarBack(tester); await tap(tester,'studio-exit-stay');
        expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('scenario-age-group-24_36'))).selected, isTrue);
      } else {
        const value='Taslak'; await field(tester,'scenario-request-$name',value);
        await appBarBack(tester); await tap(tester,'studio-exit-stay');
        expect(tester.widget<TextField>(find.byKey(ValueKey('scenario-request-$name'))).controller!.text,value);
        await field(tester,'scenario-request-$name',''); await appBarBack(tester);
        expect(find.byType(SyntheticVideoStudioScreen),findsNothing);
      }
      await close(tester);
    });
  }
  testWidgets('Özet düzenlemede geçersizleşir; tür/admin değişimi formu ve kaynağı korur', (tester) async {
    final service=_GenerationService(); await studio(tester,service); await configure(tester);
    expect(find.byKey(const ValueKey('scenario-request-summary')),findsOneWidget);
    await field(tester,'scenario-request-context','Yeni bağlam');
    expect(find.byKey(const ValueKey('scenario-request-summary')),findsNothing);
    for(var i=0;i<10;i++){await tester.tap(find.byKey(const ValueKey('studio-admin-title')));await tester.pump();}
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-request-context'))).controller!.text,'Yeni bağlam');
    expect(service.requests,isEmpty); await close(tester);
  });
  testWidgets('Hizmet bağlı değilken hazır sonuç veya üretim başarısı yoktur', (tester) async {
    await studio(tester,const UnavailableScenarioGenerationService());await configure(tester);
    await tap(tester,'studio-generate-scenario',settle:false);await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scenario-generation-error')),findsOneWidget);
    expect(find.byKey(const ValueKey('studio-continue-result')),findsNothing);await close(tester);
  });
  testWidgets('Çift başlatma tek iş açar; cevap ayrıdır ve seçmek yeni çağrı yapmaz', (tester) async {
    final service=_GenerationService();await studio(tester,service);await configure(tester);
    final button=find.byKey(const ValueKey('studio-generate-scenario'));await tester.ensureVisible(button);
    final point=tester.getCenter(button);await tester.tapAt(point);await tester.tapAt(point);
    await tester.pump();await tester.pump(const Duration(milliseconds:300));expect(service.jobs,hasLength(1));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-request-context'))).readOnly,isTrue);
    final raw=' \n${outputFor(service.requests.single)}\n ';service.jobs.single.answer.complete(raw);await tester.pumpAndSettle();
    await tap(tester,'studio-result-details');await tap(tester,'studio-copy-result-raw');expect(copied,raw);
    await tester.tap(find.byTooltip('Sunucu ham cevabını kopyala')); await tester.pumpAndSettle(); expect(copied,raw);
    await tap(tester,'studio-continue-result');expect(editor(tester),isEmpty);await tap(tester,'scenario-accept-result');
    expect(service.requests,hasLength(1));expect(find.byKey(const ValueKey('scenario-import-summary')),findsNothing);
    await tap(tester,'scenario-import-validate');expect(find.byKey(const ValueKey('scenario-import-summary')),findsOneWidget);
    await close(tester);expect(service.jobs.single.disposals,1);
  });
  for(final failure in ['start','response','invalid']) {
    testWidgets('Üretim $failure hatası başarı olmaz; ham hata ve önceki araçlar korunur', (tester) async {
      final service=_GenerationService()..failStart=failure=='start';await studio(tester,service);await configure(tester);
      await tap(tester,'studio-generate-scenario',settle:false);
      if(failure=='response')service.jobs.single.answer.completeError(const ScenarioGenerationFailure('Kontrollü hata',rawResponse:' bozuk ham '));
      if(failure=='invalid')service.jobs.single.answer.complete(' bozuk ham ');
      await tester.pumpAndSettle();expect(find.byKey(const ValueKey('scenario-generation-error')),findsOneWidget);
      expect(find.byKey(const ValueKey('studio-continue-result')),findsNothing);
      if(failure!='start'){await tap(tester,'studio-error-raw-details');
        expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-error-raw'))).data,' bozuk ham ');
        expect(service.jobs.single.disposals,1);}
      await close(tester);
    });
  }
  for(final localOnly in [false,true]) {
    testWidgets('İptal türü $localOnly başarılı üretim değildir; tek dispose ve geç cevap reddi korunur', (tester) async {
      final service=_GenerationService();await studio(tester,service);await configure(tester);await tap(tester,'studio-generate-scenario',settle:false);
      final job=service.jobs.single..localCancelOnly=localOnly..failCancel=!localOnly..completeOnDispose=false;
      await tap(tester,'studio-cancel-generation');expect(job.cancellations,1);expect(job.disposals,1);
      expect(find.textContaining(localOnly?'iptali doğrulanmadı':'İptal isteği başarısız'),findsWidgets);
      job.answer.complete(outputFor(service.requests.single));await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('studio-continue-result')),findsNothing);await close(tester);
    });
  }
  testWidgets('Geç eski cevap yeni sonucu ve kimliğini ezmez', (tester) async {
    final service=_GenerationService();await studio(tester,service);await configure(tester);await tap(tester,'studio-generate-scenario',settle:false);
    final old=service.jobs.single..completeOnDispose=false;await tap(tester,'studio-cancel-generation');
    await tap(tester,'studio-generate-scenario',settle:false);service.jobs.last.answer.complete(outputFor(service.requests.last));await tester.pumpAndSettle();
    final summary=tester.widget<Text>(find.byKey(const ValueKey('studio-result-summary'))).data;
    old.answer.complete(outputFor(service.requests.first));await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('studio-result-summary'))).data,summary);
    expect(service.jobs.map((job)=>job.disposals),[1,1]);await close(tester);
  });
  testWidgets('Süren işte çift geri tek onay açar; kalmak işi korur ve bekleyen iptalde çıkış tek dispose yapar', (tester) async {
    final service=_GenerationService();await studio(tester,service,route:true);await configure(tester);await tap(tester,'studio-generate-scenario',settle:false);
    final job=service.jobs.single..cancelGate=Completer<void>()..completeOnDispose=false;
    await tester.binding.handlePopRoute();await tester.pump();await tester.pump(const Duration(milliseconds:300));
    expect(find.byType(AlertDialog),findsOneWidget);
    await tester.binding.handlePopRoute();await tester.pump();await tester.pump(const Duration(milliseconds:300));
    expect(find.byType(AlertDialog),findsNothing);expect(job.disposals,0);
    await tester.tap(find.byType(BackButton));await tester.pump();await tester.pump(const Duration(milliseconds:300));
    await tap(tester,'studio-exit-stay',settle:false);expect(job.cancellations,0);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-request-context'))).controller!.text,'  Evde  ');
    await tap(tester,'studio-cancel-generation',settle:false);expect(job.disposals,1);
    await appBarBack(tester);await tap(tester,'studio-exit-confirm');
    job.answer.complete(outputFor(service.requests.single));await tester.pumpAndSettle();expect(job.cancellations,1);expect(job.disposals,1);
    expect(find.byType(SyntheticVideoStudioScreen),findsNothing);await close(tester);
  });
  testWidgets('Graf görüntüleme ham cevap, düzenlenmiş kaynak, JSON ve aynı kimliği korur', (tester) async {
    await workspace(tester,content);final edited=jsonDecode(editor(tester)) as Map<String,dynamic>;
    final id=edited['scenarioId'];edited['commonStart']='  Ekibin düzenlediği başlangıç  ';
    await field(tester,'scenario-import-json',jsonEncode(edited));await tap(tester,'scenario-import-validate');
    final before=editor(tester);await tap(tester,'scenario-import-view');
    final graph=tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen)).graph!;
    expect(graph.scenarioId,id);expect(graph.authoringNote,contains('düzenlenmiş'));expect(find.byType(AlertDialog),findsNothing);
    await appBarBack(tester);expect(editor(tester),before);await tap(tester,'scenario-generation-raw-details');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data,content);await close(tester);
  });
  testWidgets('320px büyük yazı: ham cevap sınırlı alanda, tam ham kopya ve JSON eylemleri erişilir', (tester) async {
    final value=jsonDecode(content) as Map<String,dynamic>;value['commonStart']=List.filled(150,' Uzun anlatı. ').join();
    final raw=' \n${jsonEncode(value)}\n ';await workspace(tester,raw,narrow:true);await tap(tester,'scenario-generation-raw-details');
    expect(tester.getSize(find.byWidgetPredicate((w)=>w is SizedBox && w.height==240)).height,240);
    await tap(tester,'scenario-generation-copy-raw');expect(copied,raw);
    final field=find.byKey(const ValueKey('scenario-import-json'));await tester.ensureVisible(field);expect(field.hitTestable(),findsOneWidget);
    expect(tester.takeException(),isNull);await close(tester);
  });
  final fence='\u0060\u0060\u0060json', endFence='\u0060\u0060\u0060';
  for(final raw in [content,'$fence\n$content\n$endFence',jsonEncode({'scenarioInput':jsonDecode(content)}),
    '$fence\n${jsonEncode({'scenarioInput':jsonDecode(content)})}\n$endFence']) {
    testWidgets('Normalizasyon tüm anlatıları ve ham cevabı değiştirmeden korur: $raw', (tester) async {
      await workspace(tester,raw);await tap(tester,'scenario-import-validate');final input=ScenarioInput.fromJsonString(editor(tester));
      expect(input.commonStart,example['commonStart']);
      expect(input.alternatives.map((a)=>a.continuation),(example['alternatives'] as List).map((a)=>a['continuation']));
      expect(input.alternatives.map((a)=>a.ending),(example['alternatives'] as List).map((a)=>a['ending']));
      expect(input.behaviorId,'D02');expect(input.ageMonths,24);await tap(tester,'scenario-generation-raw-details');
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data,raw);await close(tester);
    });
  }
  for(final invalid in ['Cevap:\n$fence\n$content\n$endFence','$fence\n$content\n$endFence\nBitti.',
    '$fence\n$content\n$endFence\n$fence\n$content\n$endFence','$fence\n$content',
    '{"scenarioInput":{"commonStart":"Eksik",}}','{"scenarioInput":"Metin"}',
    jsonEncode({'scenarioInput':jsonDecode(content),'extra':'Ek'}),jsonEncode({'scenarioInput':{'scenarioInput':jsonDecode(content)}}),
    '{"commonStart":"Eksik anlatı"}']) {
    testWidgets('Bozuk/eksik cevap onarılmaz; ham hata korunur ve devam verilmez: $invalid', (tester) async {
      final service=_GenerationService();await studio(tester,service);await configure(tester);await tap(tester,'studio-generate-scenario',settle:false);
      service.jobs.single.answer.complete(invalid);await tester.pumpAndSettle();expect(find.byKey(const ValueKey('studio-continue-result')),findsNothing);
      await tap(tester,'studio-error-raw-details');
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-error-raw'))).data,invalid);
      expect(service.requests,hasLength(1));expect(service.jobs.single.disposals,1);await close(tester);
    });
  }
  test('Üretim isteği çıktıdan ayrıdır; kimlik/sürüm/yaş sınırı ve metadata çelişkisi doğrulanır', () {
    ScenarioGenerationRequest make({String id = 'D02', String version = '0.2', int age = 24}) =>
        ScenarioGenerationRequest(behaviorId: id, cardVersion: version, ageMonths: age,
          sceneContext: 'Ev');
    for (final age in [12, 36]) { expect(make(age: age).ageMonths, age); }
    for (final age in [11, 37]) { expect(() => make(age: age), throwsFormatException); }
    expect(() => make(id: 'ONT-01'), throwsFormatException);
    expect(() => make(version: '0.1'), throwsFormatException);
    final request = make();
    for (final field in ['ageMonths', 'behaviorId', 'cardVersion']) {
      final value = field == 'ageMonths' ? 30 : field == 'behaviorId' ? 'D01' : '0.1';
      expect(() => request.prepareInput(jsonEncode({
        ...(jsonDecode(content) as Map<String, dynamic>), field: value,
      }), scenarioId: 'test', edited: false), throwsFormatException);
    }
    final normalized = request.prepareInput('```json\n{"scenarioInput": $content}\n```',
      scenarioId: 'test', edited: false);
    final input = ScenarioInput.fromJsonString(normalized.json);
    expect(input.behaviorId, 'D02');
    expect(input.ageMonths, 24);
    expect(input.commonStart, example['commonStart']);
    expect(normalized.normalization, isNotNull);
    expect(const ScenarioGraphConverter().convert(input).scenarioId, 'test');
    final varied = request.prepareInput(jsonEncode({
      'commonStart': '  Değiştirilmemiş başlangıç  ',
      'alternatives': List.filled(3, (example['alternatives'] as List).first),
    }), scenarioId: 'three', edited: false);
    expect(ScenarioInput.fromJsonString(varied.json).alternatives, hasLength(3));
    expect(const ScenarioGraphConverter().convert(ScenarioInput.fromJsonString(varied.json)).scenarioId,
      'three');
  });

  test('Düzenlenmiş kaynak mevcut sözleşme ve dönüştürücüyle korunur', () {
    final input = ScenarioInput.fromJson({
      ...example,
      'source': 'model_output_edited',
    });
    final graph = const ScenarioGraphConverter().convert(input);
    expect(graph.authoringNote, contains('değiştirilmemiş ham model cevabı değildir'));
    expect(graph.validate, returnsNormally);
  });

}
