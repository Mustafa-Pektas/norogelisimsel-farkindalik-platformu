import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_awareness_app/services/http_scenario_generation_service.dart';
import 'package:neuro_awareness_app/models/behavior_cards.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_screen.dart';
import 'package:neuro_awareness_app/services/scenario_graph_converter.dart';
import 'package:neuro_awareness_app/services/scenario_generation_service.dart';

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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final example = jsonDecode(
    File(ScenarioGraphImportScreen.d01InputAssetPath).readAsStringSync(),
  ) as Map<String, dynamic>;
  final content = jsonEncode({
    'commonStart': example['commonStart'],
    'alternatives': example['alternatives'],
  });

  Future<void> mount(WidgetTester tester, _NoAssets bundle, {
    ScenarioGenerationService generationService = const UnavailableScenarioGenerationService(),
    Size size = const Size(1100, 1000), double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ScenarioGraphImportScreen(generationService: generationService)),
    ));
    await tester.pumpAndSettle();
    await tap(tester, 'scenario-import-mode-scenario');
  }

  String editor(WidgetTester tester) => tester.widget<TextField>(
    find.byKey(const ValueKey('scenario-import-json')),
  ).controller!.text;

  List<String?> summaryTexts(WidgetTester tester) => tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('scenario-import-summary')),
      matching: find.byType(Text),
    ),
  ).map((text) => text.data).toList();

  Future<void> requestText(WidgetTester tester, String field, String value) async {
    final target = find.byKey(ValueKey('scenario-request-$field'));
    await tester.ensureVisible(target);
    await tester.enterText(target, value);
    await tester.pump();
  }

  String requestValue(WidgetTester tester, String field) => tester.widget<TextField>(
    find.byKey(ValueKey('scenario-request-$field')),
  ).controller!.text;

  Future<void> selectBehavior(WidgetTester tester, String id) async {
    final card = BehaviorCards.all.firstWhere((card) => card.id == id);
    await tap(tester, 'scenario-request-behavior');
    final item = find.text(card.title).last;
    await tester.scrollUntilVisible(item, 100, scrollable: find.byType(Scrollable).last);
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  Future<void> mountRoute(WidgetTester tester, {
    ScenarioGenerationService generationService = const UnavailableScenarioGenerationService(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: _NoAssets(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-import'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ScenarioGraphImportScreen(generationService: generationService),
              )),
              child: const Text('İçe aktarmayı aç'),
            ),
          ),
        ),
      ),
    ));
    await tap(tester, 'open-import');
  }

  Future<void> appBarBack(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
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

  testWidgets('İstek formu mevcut on kartı kullanır; sürüm otomatik, yaş boş ve alanlar zorunludur', (tester) async {

    final bundle = _NoAssets();
    await mount(tester, bundle);
    final section = find.byKey(const ValueKey('scenario-import-request-form'));
    expect(tester.widget<ExpansionTile>(section).initiallyExpanded, isFalse);
    expect(tester.widget<ExpansionTile>(section).maintainState, isTrue);
    await tap(tester, 'scenario-import-request-form');
    final field = find.byKey(const ValueKey('scenario-request-behavior'));
    final dropdown = tester.widget<DropdownButton<BehaviorCard>>(find.descendant(
      of: field, matching: find.byType(DropdownButton<BehaviorCard>),
    ));
    expect(dropdown.items!.map((item) => item.value!.id),
        BehaviorCards.all.map((card) => card.id));
    for (var i = 0; i < dropdown.items!.length; i++) {
      expect(dropdown.items![i].value, same(BehaviorCards.all[i]));
      expect((dropdown.items![i].child as Text).data, BehaviorCards.all[i].title);
    }
    expect(tester.state<FormFieldState<BehaviorCard>>(field).value, isNull);
    expect(requestValue(tester, 'age'), isEmpty);
    await tap(tester, 'scenario-request-validate');
    expect(find.text('Hedef davranış seçin.'), findsOneWidget);
    expect(find.text('12–36 arasında tam ay girin.'), findsOneWidget);
    expect(find.text('Sahne/ortam bağlamını girin.'), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-request-summary')), findsNothing);
    await selectBehavior(tester, 'D10');
    final card = BehaviorCards.all.last;
    expect(tester.state<FormFieldState<BehaviorCard>>(field).value, same(card));
    expect(tester.widget<Text>(find.byKey(
      const ValueKey('scenario-request-card-version'),
    )).data, 'Kart sürümü: ${card.cardVersion}');
    await requestText(tester, 'context', '   ');
    await tap(tester, 'scenario-request-validate');
    expect(find.text('Sahne/ortam bağlamını girin.'), findsOneWidget);
    await requestText(tester, 'context', 'Evde masa başında.');
    for (final value in ['11', '37', '-1', '12.5', 'abc']) {
      await requestText(tester, 'age', value);
      await tap(tester, 'scenario-request-validate');
      expect(requestValue(tester, 'age'), value);
      expect(find.text('12–36 arasında tam ay girin.'), findsOneWidget);
      expect(find.byKey(const ValueKey('scenario-request-summary')), findsNothing);
    }
    for (final value in ['12', '36']) {
      await requestText(tester, 'age', value);
      await tap(tester, 'scenario-request-validate');
      expect(find.text('Karakter yaşı: $value ay'), findsOneWidget);
      expect(find.text('Davranış: ${card.title}'), findsOneWidget);
      expect(find.text('Bu yaş için görev uyarlaması gerekli.'),
          value == '12' ? findsOneWidget : findsNothing);
    }
    expect(requestValue(tester, 'instructions'), isEmpty);

    expect(editor(tester), isEmpty);
    expect(bundle.reads, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('İstek özeti düzenlemede geçersizleşir; mevcut JSON ve graf değişmez', (tester) async {

    final bundle = _NoAssets();
    await mount(tester, bundle);
    final json = jsonEncode(example);
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), json);
    await tap(tester, 'scenario-import-validate');
    final summary = summaryTexts(tester);
    await tap(tester, 'scenario-import-view');
    final originalGraph = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen)).graph;
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, 'scenario-import-request-form');
    await selectBehavior(tester, 'D02');
    await requestText(tester, 'age', '31');
    await requestText(tester, 'context', '  Evde oyuncakların yanında.  ');
    await tap(tester, 'scenario-request-validate');
    expect(find.byKey(const ValueKey('scenario-request-summary')), findsOneWidget);
    expect(find.text('Bağlam:   Evde oyuncakların yanında.  '), findsOneWidget);
    for (final edit in [
      ('instructions', '  Gün ışığı kullan.  '),
      ('context', 'Aynı odada yerde.'),
      ('age', '32'),
    ]) {
      await requestText(tester, edit.$1, edit.$2);
      expect(find.byKey(const ValueKey('scenario-request-summary')), findsNothing);
      await tap(tester, 'scenario-request-validate');
      expect(find.byKey(const ValueKey('scenario-request-summary')), findsOneWidget);
    }
    expect(find.text('Ek yönerge:   Gün ışığı kullan.  '), findsOneWidget);
    await selectBehavior(tester, 'D01');
    expect(find.byKey(const ValueKey('scenario-request-summary')), findsNothing);
    await tap(tester, 'scenario-request-validate');
    expect(find.text('Davranış: ${BehaviorCards.all.first.title}'), findsOneWidget);
    expect(editor(tester), json);
    expect(summaryTexts(tester), summary);

    await tap(tester, 'scenario-import-view');
    expect(tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen)).graph,
        same(originalGraph));
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(requestValue(tester, 'age'), '32');
    expect(find.byKey(const ValueKey('scenario-request-summary')), findsOneWidget);
    expect(bundle.reads, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Tür/bölüm değişimi formu korur; yalnız form taslağı da F04 onayı ister', (tester) async {

    await mountRoute(tester);
    await tap(tester, 'scenario-import-mode-scenario');
    await tap(tester, 'scenario-import-request-form');
    await selectBehavior(tester, 'D03');
    await requestText(tester, 'age', '30');
    await requestText(tester, 'context', 'Oturma odasında.');
    await requestText(tester, 'instructions', 'Sabit kamera.');
    await tap(tester, 'scenario-request-validate');
    await tap(tester, 'scenario-import-request-form');
    await tap(tester, 'scenario-import-request-form');
    expect(requestValue(tester, 'age'), '30');
    expect(find.byKey(const ValueKey('scenario-request-summary')), findsOneWidget);
    await tap(tester, 'scenario-import-mode-graph');
    expect(editor(tester), isEmpty);
    expect(find.byKey(const ValueKey('scenario-import-request-form')), findsNothing);
    await appBarBack(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, 'scenario-import-stay');
    await tap(tester, 'scenario-import-mode-scenario');
    await tap(tester, 'scenario-import-request-form');
    expect(requestValue(tester, 'age'), '30');
    expect(requestValue(tester, 'context'), 'Oturma odasında.');
    expect(requestValue(tester, 'instructions'), 'Sabit kamera.');
    expect(tester.state<FormFieldState<BehaviorCard>>(find.byKey(
      const ValueKey('scenario-request-behavior'),
    )).value!.id, 'D03');
    expect(find.byKey(const ValueKey('scenario-request-summary')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, 'scenario-import-stay');
    expect(requestValue(tester, 'context'), 'Oturma odasında.');
    await appBarBack(tester);
    await tap(tester, 'scenario-import-exit');
    expect(find.byType(ScenarioGraphImportScreen), findsNothing);

  });

  for (final field in ['age', 'context', 'instructions']) {
    testWidgets('Yalnız $field girilmiş istek F04 ile korunur; temizlenince boş çıkış serbesttir', (tester) async {

      await mountRoute(tester);
      await tap(tester, 'scenario-import-mode-scenario');
      await tap(tester, 'scenario-import-request-form');
      final value = field == 'age' ? '27' : 'Kısmi ekip taslağı';
      await requestText(tester, field, value);
      await appBarBack(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tap(tester, 'scenario-import-stay');
      expect(requestValue(tester, field), value);
      expect(editor(tester), isEmpty);

      await requestText(tester, field, '');
      await appBarBack(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ScenarioGraphImportScreen), findsNothing);

    });
  }

  Future<void> generationTap(WidgetTester tester, String key) async {
    final target = key == 'scenario-import-request-form'
        ? find.descendant(of: find.byKey(ValueKey(key)), matching: find.text('Senaryo üretim isteği'))
        : find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> fillGeneration(WidgetTester tester) async {
    await generationTap(tester, 'scenario-import-request-form');
    await selectBehavior(tester, 'D02');
    await requestText(tester, 'age', '24');
    await requestText(tester, 'context', '  Evde oyun alanı  ');
    await requestText(tester, 'instructions', '  Sade ortam  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await generationTap(tester, 'scenario-request-validate');
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

  testWidgets('Üretim hizmeti bağlı değilken form doğrulanır ama üretim başlatılamaz', (tester) async {

    await mount(tester, _NoAssets());
    await fillGeneration(tester);
    expect(find.text('Senaryo üretim hizmeti henüz bağlı değil.'), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-generation-start')), findsNothing);
    expect(find.byKey(const ValueKey('scenario-generation-raw')), findsNothing);
    expect(editor(tester), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Üretim cevabı ayrı korunur; mevcut graf yalnız bilinçli aktarımda değişir', (tester) async {
    final service = _GenerationService();

    await mount(tester, _NoAssets(), generationService: service);
    final old = jsonEncode(example);
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), old);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await generationTap(tester, 'scenario-import-validate');
    final previous = summaryTexts(tester);
    await fillGeneration(tester);
    await generationTap(tester, 'scenario-generation-start');
    final sent = service.requests.single;
    expect(sent.behaviorId, 'D02');
    expect(sent.cardVersion, '0.2');
    expect(sent.ageMonths, 24);
    expect(sent.sceneContext, '  Evde oyun alanı  ');
    expect(sent.additionalInstructions, '  Sade ortam  ');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-request-age'))).readOnly, isTrue);
    await tester.tap(find.byKey(const ValueKey('scenario-generation-start')));
    await tester.pumpAndSettle();
    expect(service.jobs, hasLength(1));
    final raw = ' \n$content\n ';
    service.jobs.single.answer.complete(raw);
    await tester.pumpAndSettle();
    expect(editor(tester), old);
    expect(summaryTexts(tester), previous);
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, raw);
    expect(service.jobs.single.disposals, 1);
    await generationTap(tester, 'scenario-generation-transfer');
    await tester.tap(find.text('Taslağı koru'));
    await tester.pumpAndSettle();
    expect(editor(tester), old);
    expect(summaryTexts(tester), previous);
    await generationTap(tester, 'scenario-generation-transfer');
    await tester.tap(find.text('Aktar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    var input = ScenarioInput.fromJsonString(editor(tester));
    expect(input.ageMonths, 24);
    expect(input.behaviorId, 'D02');
    expect(input.source, ScenarioInputSource.modelOutput);
    expect(input.scenarioId, isNot('d01-qwen-yerel-demo'));
    await generationTap(tester, 'scenario-import-validate');
    final edited = jsonDecode(editor(tester)) as Map<String, dynamic>;
    edited['commonStart'] = '  Ekibin değiştirdiği başlangıç  ';
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), jsonEncode(edited));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await generationTap(tester, 'scenario-import-validate');
    input = ScenarioInput.fromJsonString(editor(tester));
    expect(input.source, ScenarioInputSource.editedModelOutput);
    expect(input.commonStart, '  Ekibin değiştirdiği başlangıç  ');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, raw);
    final conflicting = jsonDecode(editor(tester)) as Map<String, dynamic>;
    conflicting['ageMonths'] = 30;
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), jsonEncode(conflicting));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await generationTap(tester, 'scenario-import-validate');
    expect(find.textContaining('ageMonths doğrulanmış istekle uyuşmuyor'), findsOneWidget);
    expect((jsonDecode(editor(tester)) as Map<String, dynamic>)['ageMonths'], 30);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final failure in ['start', 'response', 'metadata', 'cancel']) {
    testWidgets('Üretim $failure hatası taslağı korur ve başarı sayılmaz', (tester) async {
      final service = _GenerationService()..failStart = failure == 'start';
      await mount(tester, _NoAssets(), generationService: service);
      await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), '{"önceki": true}');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await fillGeneration(tester);
      await generationTap(tester, 'scenario-generation-start');
      if (failure != 'start') {
        final job = service.jobs.single;
        switch (failure) {
          case 'response': job.answer.completeError(StateError('Kontrollü hata'));
          case 'metadata': job.answer.complete(jsonEncode({
            ...(jsonDecode(content) as Map<String, dynamic>), 'ageMonths': 30,
          }));
          case 'cancel':
            job.failCancel = true;
            await generationTap(tester, 'scenario-generation-cancel');
        }
        await tester.pumpAndSettle();
        if (failure == 'metadata') {
          await generationTap(tester, 'scenario-generation-transfer');
          await tester.tap(find.text('Aktar'));
          await tester.pumpAndSettle();
          expect(find.textContaining('ageMonths doğrulanmış istekle uyuşmuyor'), findsOneWidget);
        }
        expect(job.disposals, 1);
      }
      expect(find.byKey(const ValueKey('scenario-generation-error')), findsOneWidget);
      expect(editor(tester), '{"önceki": true}');
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }



  testWidgets('HTTP adaptörü mevcut formu ve bilinçli aktarımı kullanır; kendiliğinden çağrı/graf yoktur', (tester) async {
    var calls = 0;
    final raw = ' \n$content\n ';
    final adapter = HttpScenarioGenerationService(resolveServerUrl: () async => 'http://localhost:8000',
      clientFactory: () => MockClient((request) async {
        ++calls;
        expect(request.url.path, '/api/generate-scenario-input');
        final sent = jsonDecode(request.body) as Map<String, dynamic>;
        expect(sent['behaviorId'], 'D02');
        expect(sent['cardVersion'], '0.2');
        expect(sent['ageMonths'], 24);
        return http.Response.bytes(utf8.encode(jsonEncode({
          'success': true, 'rawResponse': raw, 'request': sent, 'validation': 'structure_only',
        })), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }));
    await mount(tester, _NoAssets(), generationService: adapter);
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), jsonEncode(example));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    final previous = editor(tester);
    await fillGeneration(tester);
    expect(calls, 0);
    await generationTap(tester, 'scenario-generation-start');
    expect(calls, 1);
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, raw);
    expect(editor(tester), previous);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    await generationTap(tester, 'scenario-generation-transfer');
    await tester.tap(find.text('Taslağı koru'));
    await tester.pumpAndSettle();
    expect(editor(tester), previous);
    await generationTap(tester, 'scenario-generation-transfer');
    await tester.tap(find.text('Aktar'));
    await tester.pumpAndSettle();
    await generationTap(tester, 'scenario-import-validate');
    final input = ScenarioInput.fromJsonString(editor(tester));
    expect(input.behaviorId, 'D02');
    expect(input.ageMonths, 24);
    expect(input.commonStart, example['commonStart']);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });


  for (final outcome in ['success', 'error']) {
    testWidgets('Üretim düğmesi: dar ekranda işlem ve $outcome geri bildirimi aynı yerde görünür', (tester) async {
      final response = Completer<http.Response>();
      var calls = 0;
      Map<String, dynamic>? sent;
      final adapter = HttpScenarioGenerationService(
        resolveServerUrl: () async => 'http://localhost:8000',
        clientFactory: () => MockClient((request) {
          ++calls;
          expect(request.url.path, '/api/generate-scenario-input');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return response.future;
        }),
      );
      await mount(tester, _NoAssets(), generationService: adapter,
        size: const Size(320, 800), textScale: 1.5);
      await fillGeneration(tester);
      final start = find.byKey(const ValueKey('scenario-generation-start'));
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      expect(start.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
      await tester.tap(start); // Gerçek callback; doğrudan servis/metot çağrılmaz.
      await tester.pump();
      expect(calls, 1);
      expect(sent!['behaviorId'], 'D02');
      expect(sent!['ageMonths'], 24);
      final status = find.byKey(const ValueKey('scenario-generation-status'));
      final error = find.byKey(const ValueKey('scenario-generation-error'));
      final cancel = find.byKey(const ValueKey('scenario-generation-cancel'));
      expect(status.hitTestable(), findsOneWidget);
      expect(cancel.hitTestable(), findsOneWidget);
      expect(find.descendant(of: start, matching: find.text('Yanıt bekleniyor…')), findsOneWidget);
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      // Başlatmadan sonra durum için yukarı kaydırma yapılmaz.
      expect(find.descendant(of: find.byKey(const ValueKey('scenario-import-request-form')),
        matching: status), findsOneWidget);
      response.complete(http.Response.bytes(utf8.encode(jsonEncode(outcome == 'success'
        ? {'success': true, 'rawResponse': content, 'request': sent}
        : {'success': false, 'error': 'Kontrollü sunucu hatası'})),
        outcome == 'success' ? 200 : 503,
        headers: {'content-type': 'application/json; charset=utf-8'}));
      await tester.pumpAndSettle();
      expect(status.hitTestable(), findsOneWidget);
      if (outcome == 'error') {
        expect(error.hitTestable(), findsOneWidget);
        expect(find.text('Kontrollü sunucu hatası'), findsOneWidget);
      } else {
        expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, content);
      }
      expect(editor(tester), isEmpty);
      expect(calls, 1);
      await generationTap(tester, 'scenario-import-request-form');
      expect(status, findsOneWidget); // Kapalı formda tek kopya ana alandadır.
      expect(error, outcome == 'error' ? findsOneWidget : findsNothing);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Geçersiz sunucu ham cevabı inceleme için kalır; taslak/graf sessizce değiştirilmez', (tester) async {
    final service = _GenerationService();
    await mount(tester, _NoAssets(), generationService: service);
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), jsonEncode(example));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await generationTap(tester, 'scenario-import-validate');
    final before = editor(tester);
    final summary = summaryTexts(tester);
    await fillGeneration(tester);
    await generationTap(tester, 'scenario-generation-start');
    const raw = ' \n{bozuk ham cevap\n ';
    service.jobs.single.answer.completeError(const ScenarioGenerationFailure('Model JSON geçersiz.', rawResponse: raw));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, raw);
    expect(find.text('Üretim hatası'), findsOneWidget);
    expect(editor(tester), before);
    expect(summaryTexts(tester), summary);
    expect(service.requests, hasLength(1));
    expect(service.jobs.single.disposals, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('HTTP yerel iptali sunucuda doğrulanmış iptal gibi gösterilmez', (tester) async {
    final service = _GenerationService();
    await mount(tester, _NoAssets(), generationService: service);
    await fillGeneration(tester);
    await generationTap(tester, 'scenario-generation-start');
    final job = service.jobs.single..localCancelOnly = true..completeOnDispose = false;
    await generationTap(tester, 'scenario-generation-cancel');
    expect(find.text('Yerel bekleme durduruldu.'), findsOneWidget);
    expect(find.textContaining('Sunucudaki model işinin iptali doğrulanmadı'), findsOneWidget);
    expect(find.text('Üretim iptal edildi.'), findsNothing);
    job.answer.complete(content);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scenario-generation-raw')), findsNothing);
    expect(editor(tester), isEmpty);
    expect(job.disposals, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Üretim iptali ve yeni istekte geç cevap eski taslağı ezmez', (tester) async {
    final service = _GenerationService();
    await mount(tester, _NoAssets(), generationService: service);
    await fillGeneration(tester);
    await generationTap(tester, 'scenario-generation-start');
    final first = service.jobs.single..completeOnDispose = false;
    first.cancelGate = Completer<void>();
    await generationTap(tester, 'scenario-generation-cancel');
    expect(first.cancellations, 1);
    expect(first.disposals, 0);
    expect(find.text('İptal bekleniyor'), findsOneWidget);
    first.cancelGate!.complete();
    await tester.pumpAndSettle();
    expect(first.disposals, 1);
    expect(find.text('Üretim iptal edildi.'), findsOneWidget);
    await generationTap(tester, 'scenario-generation-start');
    service.jobs.last.answer.complete(content);
    await tester.pumpAndSettle();
    first.answer.complete('ESKİ İSTEĞİN GEÇ CEVABI');
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, content);
    expect(editor(tester), isEmpty);
    expect(first.disposals, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Üretim iptali beklerken F04 kal taslağı korur; çıkış yerel kaynakları bir kez kapatır', (tester) async {
    final service = _GenerationService();

    await mountRoute(tester, generationService: service);
    await tap(tester, 'scenario-import-mode-scenario');
    await fillGeneration(tester);
    await generationTap(tester, 'scenario-generation-start');
    final job = service.jobs.single;
    job.cancelGate = Completer<void>();
    await generationTap(tester, 'scenario-generation-cancel');
    await appBarBack(tester);
    await tap(tester, 'scenario-import-stay');
    expect(job.disposals, 0);
    expect(job.cancelGate!.isCompleted, isFalse);
    expect(requestValue(tester, 'age'), '24');
    await appBarBack(tester);
    await tap(tester, 'scenario-import-exit');
    expect(job.cancellations, 1);
    expect(job.disposals, 1);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Üretim ham cevabı 320 piksel büyük yazıda sınırlıdır; bölüm kapanınca kaybolmaz', (tester) async {
    final service = _GenerationService();
    await mount(tester, _NoAssets(), generationService: service,
      size: const Size(320, 800), textScale: 2);
    await fillGeneration(tester);
    await generationTap(tester, 'scenario-generation-start');
    // Bölümü kapatmak işi durdurmaz; iptal ana alanda erişilebilirdir.
    await generationTap(tester, 'scenario-import-request-form');
    expect(service.jobs.single.cancellations, 0);
    expect(find.byKey(const ValueKey('scenario-generation-cancel')), findsOneWidget);
    final raw = ' \n${List.filled(80, 'Uzun ham cevap').join('\n')}\n ';
    service.jobs.single.answer.complete(raw);
    await tester.pumpAndSettle();
    await generationTap(tester, 'scenario-import-request-form');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, raw);
    await generationTap(tester, 'scenario-generation-transfer');
    expect(find.byKey(const ValueKey('scenario-generation-error')), findsOneWidget);
    expect(editor(tester), isEmpty);
    await generationTap(tester, 'scenario-import-validate');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Süren hizmette çift geri tek onay açar; kalmak işi korur ve çıkış bir kez kapatır', (tester) async {
    final service = _GenerationService();
    await mountRoute(tester, generationService: service);
    await tap(tester, 'scenario-import-mode-scenario');
    await fillGeneration(tester);
    await generationTap(tester, 'scenario-generation-start');
    final job = service.jobs.single;
    expect(editor(tester), isEmpty);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-request-age'))).readOnly, isTrue);
    await generationTap(tester, 'scenario-import-request-form');
    expect(find.byKey(const ValueKey('scenario-generation-cancel')), findsOneWidget);
    expect(job.cancellations, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(job.disposals, 0);
    await appBarBack(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, 'scenario-import-stay');
    expect(job.cancellations, 0);
    expect(job.disposals, 0);
    await generationTap(tester, 'scenario-import-request-form');
    expect(requestValue(tester, 'age'), '24');
    await appBarBack(tester);
    await tap(tester, 'scenario-import-exit');
    expect(find.byType(ScenarioGraphImportScreen), findsNothing);
    expect(job.cancellations, 1);
    expect(job.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Graf görüntüleme taslağı terk etmez; ham cevap, düzenlenmiş JSON ve aynı graf korunur', (tester) async {
    final service = _GenerationService();
    await mountRoute(tester, generationService: service);
    await tap(tester, 'scenario-import-mode-scenario');
    await fillGeneration(tester);
    await generationTap(tester, 'scenario-generation-start');
    final raw = ' \n$content\n ';
    service.jobs.single.answer.complete(raw);
    await tester.pumpAndSettle();
    await generationTap(tester, 'scenario-generation-transfer');
    final edited = jsonDecode(editor(tester)) as Map<String, dynamic>;
    edited['commonStart'] = '  Ekibin düzenlediği başlangıç  ';
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), jsonEncode(edited));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await generationTap(tester, 'scenario-import-validate');
    final before = editor(tester);
    await generationTap(tester, 'scenario-import-view');
    final graph = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen)).graph;
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await appBarBack(tester);
    await tap(tester, 'scenario-import-stay');
    expect(editor(tester), before);
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, raw);
    await generationTap(tester, 'scenario-import-view');
    expect(tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen)).graph, same(graph));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await appBarBack(tester);
    await tap(tester, 'scenario-import-exit');
    expect(service.jobs.single.disposals, 1);
  });

  testWidgets('Uzun hizmet ham cevabı sınırlıdır; gerçek kopyalama düğmesi tam ham metni alır', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final service = _GenerationService();
    await mount(tester, _NoAssets(), generationService: service,
      size: const Size(320, 800), textScale: 2);
    await fillGeneration(tester);
    await generationTap(tester, 'scenario-generation-start');
    final raw = ' \n${List.filled(80, 'Ham cevabın uzun satırı').join('\n')}\n ';
    service.jobs.single.answer.complete(raw);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), 'AYRI EDİTÖR TASLAĞI');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await generationTap(tester, 'scenario-generation-copy-raw');
    expect(copied, raw);
    expect(copied, isNot(editor(tester)));
    final bounds = tester.widgetList<ConstrainedBox>(find.ancestor(
      of: find.byKey(const ValueKey('scenario-generation-raw')), matching: find.byType(ConstrainedBox)));
    expect(bounds.any((box) => box.constraints.maxHeight == 240), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final formatted in [
    ('Çitsiz', content),
    ('Çitli', '```json\n$content\n```'),
    ('Sarmalı', jsonEncode({'scenarioInput': jsonDecode(content)})),
    ('Çit ve sarmalayıcı', '```json\n${jsonEncode({'scenarioInput': jsonDecode(content)})}\n```'),
  ]) {
    testWidgets('${formatted.$1}: hizmet ham cevabı korunur; yalnız biçim ve istek metadata’sı hazırlanır', (tester) async {
      final service = _GenerationService();
      await mount(tester, _NoAssets(), generationService: service);
      await fillGeneration(tester);
      await generationTap(tester, 'scenario-generation-start');
      service.jobs.single.answer.complete(formatted.$2);
      await tester.pumpAndSettle();
      expect(editor(tester), isEmpty);
      await generationTap(tester, 'scenario-generation-transfer');
      await generationTap(tester, 'scenario-import-validate');
      final input = ScenarioInput.fromJsonString(editor(tester));
      expect(input.commonStart, example['commonStart']);
      expect(input.alternatives.map((a) => a.continuation),
        (example['alternatives'] as List).map((a) => a['continuation']));
      expect(input.alternatives.map((a) => a.ending),
        (example['alternatives'] as List).map((a) => a['ending']));
      expect(input.behaviorId, 'D02');
      expect(input.ageMonths, 24);
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, formatted.$2);
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
      expect(service.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final invalid in [
    'Cevap:\n```json\n$content\n```', '```json\n$content\n```\nBitti.',
    '```json\n$content\n```\n```json\n$content\n```', '```json\n$content',
    '{"scenarioInput": {"commonStart": "Eksik",}}',
    '{"scenarioInput": "Metin"}',
    jsonEncode({'scenarioInput': jsonDecode(content), 'extra': 'Ek'}),
    jsonEncode({'scenarioInput': {'scenarioInput': jsonDecode(content)}}),
    '{"commonStart": "Eksik anlatı"}',
  ]) {
    testWidgets('Geçersiz hizmet cevabı onarılmaz/tamamlanmaz: $invalid', (tester) async {
      final service = _GenerationService();
      await mount(tester, _NoAssets(), generationService: service);
      await fillGeneration(tester);
      await generationTap(tester, 'scenario-generation-start');
      service.jobs.single.answer.complete(invalid);
      await tester.pumpAndSettle();
      await generationTap(tester, 'scenario-generation-transfer');
      await generationTap(tester, 'scenario-import-validate');
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, invalid);
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('scenario-import-view'))).onPressed, isNull);
      expect(service.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

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
Future<void> tap(WidgetTester tester, String key, {bool settle = true}) async {
  final sectionTitle = switch (key) {
    'scenario-import-format-details' => 'Biçim ve kaynak ayrıntıları',
    'scenario-import-request-form' => 'Senaryo üretim isteği',
    _ => null,
  };
  final target = sectionTitle == null ? find.byKey(ValueKey(key)) : find.descendant(
    of: find.byKey(ValueKey(key)), matching: find.text(sectionTitle),
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    // Açılır bölüm animasyonu; süren modelin progress animasyonunu bekleme.
    await tester.pump(const Duration(milliseconds: 300));
  }
}
