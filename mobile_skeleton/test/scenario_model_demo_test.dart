import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/behavior_cards.dart';
import 'package:neuro_awareness_app/models/local_model_option.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_screen.dart';
import 'package:neuro_awareness_app/services/local_llama_test_service.dart';
import 'package:neuro_awareness_app/services/scenario_graph_converter.dart';
import 'package:neuro_awareness_app/services/scenario_generation_service.dart';
import 'package:neuro_awareness_app/widgets/local_llama_test_card.dart';

// Yalnız UI akışını sınar. Bu cevaplar gerçek model sonucu değildir.
// Model/native motor ve cihazdaki kayıtlar kullanılmaz; asset fixture'ı salt okunur.
class _DemoService extends LocalLlamaTestService {
  _DemoService(this.output, {this.failure, this.hold = false}) : super(
    request: LocalLlamaTestRequest.d01GraphDemo,
    resolveModel: () async => throw StateError('Test dosya açmamalı.'),
    createRuntime: (_) => throw StateError('Test native motor açmamalı.'),
  );

  final String output;
  final String? failure;
  final bool hold;
  final _events = StreamController<LocalLlamaTestState>.broadcast();
  final _gate = Completer<void>();
  LocalLlamaTestState _current = const LocalLlamaTestState();
  int runs = 0;
  int cancellations = 0;
  int disposals = 0;
  bool _closed = false;

  @override
  LocalLlamaTestState get state => _current;
  @override
  Stream<LocalLlamaTestState> get states => _events.stream;
  @override
  bool get canRun => !_closed && !_current.isBusy;

  void _emit(LocalLlamaPhase phase, {String text = '', String? error}) {
    _current = LocalLlamaTestState(phase: phase, text: text, error: error);
    _events.add(_current);
  }

  @override
  Future<void> run() async {
    if (!canRun) throw StateError('İkinci çağrı kabul edilmemeli.');
    runs++;
    _emit(LocalLlamaPhase.loading);
    if (hold) {
      _emit(LocalLlamaPhase.generating, text: output);
      await _gate.future;
      return;
    }
    _emit(failure == null ? LocalLlamaPhase.completed : LocalLlamaPhase.error,
        text: output, error: failure);
  }

  @override
  void cancel() {
    cancellations++;
    _emit(LocalLlamaPhase.cancelled, text: output);
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    disposals++;
    if (_current.isBusy) {
      cancel();
    }
    if (!_gate.isCompleted) _gate.complete();
    await _events.close();
  }
}

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
    throw StateError('Model demosu sabit graf/plan asseti okumamalı.');
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
  const request = LocalLlamaTestRequest.d01GraphDemo;

  Future<void> mount(WidgetTester tester, _DemoService service, _NoAssets bundle, {
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
        home: ScenarioGraphImportScreen(scenarioService: service, generationService: generationService)),
    ));
    await tester.pumpAndSettle();
    await tap(tester, 'scenario-import-mode-scenario');
    expect(service.runs, 0);
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

  void expectRaw(WidgetTester tester, String raw) {
    expect(tester.widget<SelectableText>(
      find.byKey(ValueKey('${request.id}-response')),
    ).data, raw);
  }

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

  Future<void> mountRoute(WidgetTester tester, _DemoService service, {
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
                builder: (_) => ScenarioGraphImportScreen(scenarioService: service,
                  generationService: generationService),
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
      final service = _DemoService('');
      await mountRoute(tester, service);
      if (systemBack) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      } else {
        await appBarBack(tester);
      }
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ScenarioGraphImportScreen), findsNothing);
      expect(find.byKey(const ValueKey('open-import')), findsOneWidget);
      expect(service.disposals, 1);
      expect(service.runs, 0);
    });
  }

  testWidgets('AppBar ve sistem geri: kalmak metni ve doğrulama hatasını korur', (tester) async {
    final service = _DemoService('');
    await mountRoute(tester, service);
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
    expect(service.disposals, 0);

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
    expect(service.disposals, 0);

    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), '');
    await tester.pump();
    await appBarBack(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.disposals, 1);
  });

  testWidgets('Diğer giriş türündeki taslak korunur; temizlenen etkin kopya çıkışı engellemez', (tester) async {
    final service = _DemoService('');
    await mountRoute(tester, service);
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
    expect(service.disposals, 1);
  });

  testWidgets('Grafı açmak çıkış değildir; kalmak ham cevap, düzenlenen JSON ve aynı grafı korur', (tester) async {
    final service = _DemoService(content);
    await mountRoute(tester, service);
    await tap(tester, 'scenario-import-mode-scenario');
    await tap(tester, '${request.id}-start');
    final edited = jsonDecode(editor(tester)) as Map<String, dynamic>;
    edited['commonStart'] = '${edited['commonStart']} Kullanıcının sahne notu.';
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), jsonEncode(edited));
    await tap(tester, 'scenario-import-validate');
    final savedJson = editor(tester);
    expect(ScenarioInput.fromJsonString(savedJson).source,
        ScenarioInputSource.editedModelOutput);
    final summary = summaryTexts(tester);
    await tap(tester, 'scenario-import-view');
    expect(find.byType(AlertDialog), findsNothing);
    final viewer = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
    final graph = viewer.graph!;
    final sourceLabel = viewer.sourceLabel;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await appBarBack(tester);
    await tap(tester, 'scenario-import-stay');
    expectRaw(tester, content);
    expect(editor(tester), savedJson);
    expect(summaryTexts(tester), summary);
    expect(service.disposals, 0);
    expect(service.runs, 1);
    await tap(tester, 'scenario-import-view');
    final reopened = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
    expect(reopened.graph, same(graph));
    expect(reopened.sourceLabel, sourceLabel);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await appBarBack(tester);
    await tap(tester, 'scenario-import-exit');
    expect(find.byType(ScenarioGraphImportScreen), findsNothing);
    expect(service.disposals, 1);
    expect(service.runs, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Yalnız ham kısmi cevap da çıkış onayı ister; hata ve boş editör korunur', (tester) async {
    const raw = 'KISMİ HAM CEVAP';
    final service = _DemoService(raw, failure: 'Kontrollü hata');
    await mountRoute(tester, service);
    await tap(tester, 'scenario-import-mode-scenario');
    await tap(tester, '${request.id}-start');
    expect(editor(tester), isEmpty);
    final error = tester.widget<Text>(
      find.byKey(const ValueKey('scenario-import-error')),
    ).data;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, 'scenario-import-stay');
    expectRaw(tester, raw);
    expect(editor(tester), isEmpty);
    expect(tester.widget<Text>(
      find.byKey(const ValueKey('scenario-import-error')),
    ).data, error);
    expect(service.disposals, 0);
    await appBarBack(tester);
    await tap(tester, 'scenario-import-exit');
    expect(service.disposals, 1);
  });

  testWidgets('Boş cevaplı süren üretimde çift geri tek onay açar; yalnız bilinçli çıkış kapatır', (tester) async {
    final service = _DemoService('', hold: true);
    await mountRoute(tester, service);
    await tap(tester, 'scenario-import-mode-scenario');
    await tap(tester, 'scenario-import-model-demo');
    final start = find.byKey(ValueKey('${request.id}-start'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    expect(editor(tester), isEmpty);
    expect(service.state.text, isEmpty);
    expect(service.state.isBusy, isTrue);
    await tap(tester, 'scenario-import-model-demo', settle: false);
    expect(find.byType(LocalLlamaTestCard), findsNothing);
    final back = find.byType(BackButton);
    expect(back.hitTestable(), findsOneWidget);
    await tester.tap(back);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    // Modal açılınca ikinci geri alttaki AppBar'a gitmez; yalnız modalı kapatır.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ScenarioGraphImportScreen), findsOneWidget);
    expect(service.cancellations, 0);
    expect(service.disposals, 0);
    expect(service.state.isBusy, isTrue);
    expect(editor(tester), isEmpty);
    expect(service.state.text, isEmpty);
    // Ana rotaya yönelen sonraki sistem geri yeniden yalnız bir onay açar.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scenario-import-stay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.cancellations, 0);
    expect(service.disposals, 0);
    expect(service.state.isBusy, isTrue);
    expect(editor(tester), isEmpty);
    expect(service.state.text, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scenario-import-exit')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(ScenarioGraphImportScreen), findsNothing);
    expect(service.cancellations, 1);
    expect(service.disposals, 1);
    expect(service.runs, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('İlk görünümde JSON eylemleri önce, ayrıntılar ve model demosu kapalıdır', (tester) async {
    final service = _DemoService(content);
    final bundle = _NoAssets();
    await mount(tester, service, bundle);
    for (final key in ['scenario-import-format-details', 'scenario-import-model-demo']) {
      final tile = tester.widget<ExpansionTile>(find.byKey(ValueKey(key)));
      expect(tile.initiallyExpanded, isFalse);
      expect(tile.maintainState, isTrue);
      expect(tester.getTopLeft(find.byKey(const ValueKey('scenario-import-validate'))).dy,
          lessThan(tester.getTopLeft(find.byKey(ValueKey(key))).dy));
    }
    expect(find.byKey(const ValueKey('scenario-import-session')), findsOneWidget);
    expect(find.textContaining('Taslağı bu cihazda saklamak için'), findsOneWidget);
    expect(find.textContaining('D01 demo metadata’sını uygulama sağlar:'), findsNothing);
    expect(find.byKey(ValueKey('${request.id}-start')), findsNothing);
    expect(find.byType(LocalLlamaTestCard), findsNothing);
    await tap(tester, 'scenario-import-format-details');
    expect(find.textContaining('D01 demo metadata’sını uygulama sağlar:'), findsOneWidget);
    expect(find.text(ScenarioGraphImportScreen.sourceDisclaimer), findsOneWidget);
    await tap(tester, 'scenario-import-format-details');
    await tap(tester, 'scenario-import-model-demo');
    expect(find.byKey(ValueKey('${request.id}-start')), findsOneWidget);
    expect(service.runs, 0);
    expect(bundle.reads, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(service.disposals, 1);
  });

  testWidgets('Kapalı model bölümünde durum ve iptal erişilir; servis ve ham cevap korunur', (tester) async {
    const raw = 'KONTROLLÜ KISMİ HAM CEVAP';
    final service = _DemoService(raw, hold: true);
    await mount(tester, service, _NoAssets());
    const edited = '{"kullanıcı": "taslağı"}';
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), edited);
    await tap(tester, 'scenario-import-model-demo');
    final cardService = tester.widget<LocalLlamaTestCard>(find.byType(LocalLlamaTestCard)).service;
    final start = find.byKey(ValueKey('${request.id}-start'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    expect(service.state.isBusy, isTrue);
    await tap(tester, 'scenario-import-model-demo', settle: false);
    expect(find.byType(LocalLlamaTestCard), findsNothing);
    expect(service.state.text, raw);
    expect(editor(tester), edited);
    expect(find.text('Model: Metin üretiliyor'), findsOneWidget);
    expect(service.cancellations, 0);
    expect(service.disposals, 0);
    await tap(tester, 'scenario-import-model-demo', settle: false);
    expect(tester.widget<LocalLlamaTestCard>(find.byType(LocalLlamaTestCard)).service,
        same(cardService));
    expectRaw(tester, raw);
    await tap(tester, 'scenario-import-model-demo', settle: false);
    final cancel = find.byKey(const ValueKey('scenario-import-model-cancel'));
    await tester.ensureVisible(cancel);
    expect(cancel.hitTestable(), findsOneWidget);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(service.cancellations, 1);
    expect(service.runs, 1);
    expect(service.disposals, 0);
    expect(service.state.text, raw);
    expect(editor(tester), edited);
    await tap(tester, 'scenario-import-model-demo');
    expectRaw(tester, raw);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(service.disposals, 1);
  });

  testWidgets('Uzun ham cevap sınırlı alandadır; kopyalama editör yerine tam ham cevabı alır', (tester) async {
    final raw = ' \n${jsonEncode({
      ...(jsonDecode(content) as Map<String, dynamic>),
      'commonStart': List.filled(80, 'Kontrollü uzun sahne metni.').join('\n'),
    })}\n ';
    final service = _DemoService(raw);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester, service, _NoAssets());
    await tap(tester, '${request.id}-start');
    expectRaw(tester, raw);
    final modelScroll = find.byKey(const ValueKey('scenario-import-model-scroll'));
    expect(tester.getSize(modelScroll).height, lessThanOrEqualTo(420));
    expect(tester.getTopLeft(find.byKey(const ValueKey('scenario-import-view'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('scenario-import-model-demo'))).dy));
    final card = tester.widget<LocalLlamaTestCard>(find.byType(LocalLlamaTestCard));
    expect(card.service, same(service));
    expect(card.service.request, same(request));
    expect(find.text('CPU · ${request.contextSize} token bağlam · En fazla ${request.maxTokens} yeni token'),
        findsOneWidget);
    final prompt = find.text('Modele gönderilen istek');
    await tester.ensureVisible(prompt);
    await tester.tap(prompt);
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((widget) =>
        widget is SelectableText && widget.data == request.prompt), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), '{"düzenlendi": true}');
    // Metin alanının odak/caret kaydırması, düğmeye yapılan kaydırmayı
    // sonraki karede geri almadan önce kullanıcı düzenlemeyi bitirsin.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final copyRaw = find.byKey(const ValueKey('scenario-import-copy-raw'));
    expect(tester.widget<OutlinedButton>(copyRaw).onPressed, isNotNull);
    await tester.ensureVisible(copyRaw);
    await tester.pumpAndSettle();
    expect(copyRaw.hitTestable(), findsOneWidget);
    await tester.tap(copyRaw);
    await tester.pumpAndSettle();
    expect(copied, raw);
    expect(editor(tester), '{"düzenlendi": true}');
    expectRaw(tester, raw);
    expect(service.runs, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Yerel istek mevcut on kartı kullanır; sürüm otomatik, yaş boş ve alanlar zorunludur', (tester) async {
    final service = _DemoService(content);
    final bundle = _NoAssets();
    await mount(tester, service, bundle);
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
    expect(service.request, same(request));
    expect(service.request.prompt, contains('30 aylık Deniz'));
    expect(service.runs, 0);
    expect(editor(tester), isEmpty);
    expect(bundle.reads, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('İstek özeti düzenlemede geçersizleşir; mevcut JSON ve graf değişmez', (tester) async {
    final service = _DemoService(content);
    final bundle = _NoAssets();
    await mount(tester, service, bundle);
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
    expect(service.state.text, isEmpty);
    expect(service.runs, 0);
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
    final service = _DemoService(content);
    await mountRoute(tester, service);
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
    expect(service.disposals, 1);
    expect(service.runs, 0);
  });

  for (final field in ['age', 'context', 'instructions']) {
    testWidgets('Yalnız $field girilmiş istek F04 ile korunur; temizlenince boş çıkış serbesttir', (tester) async {
      final service = _DemoService(content);
      await mountRoute(tester, service);
      await tap(tester, 'scenario-import-mode-scenario');
      await tap(tester, 'scenario-import-request-form');
      final value = field == 'age' ? '27' : 'Kısmi ekip taslağı';
      await requestText(tester, field, value);
      await appBarBack(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tap(tester, 'scenario-import-stay');
      expect(requestValue(tester, field), value);
      expect(editor(tester), isEmpty);
      expect(service.runs, 0);
      expect(service.disposals, 0);
      await requestText(tester, field, '');
      await appBarBack(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ScenarioGraphImportScreen), findsNothing);
      expect(service.disposals, 1);
    });
  }

  testWidgets('Model çalışırken istek formu kilitlidir; açıp kapamak ham cevabı silmez', (tester) async {
    final service = _DemoService('KISMİ HAM CEVAP', hold: true);
    await mount(tester, service, _NoAssets());
    await tap(tester, 'scenario-import-request-form');
    await selectBehavior(tester, 'D04');
    await requestText(tester, 'age', '30');
    await requestText(tester, 'context', 'Evde oyun köşesinde.');
    await tap(tester, 'scenario-request-validate');
    await tap(tester, 'scenario-import-request-form');
    await tap(tester, 'scenario-import-model-demo');
    final start = find.byKey(ValueKey('${request.id}-start'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    await tap(tester, 'scenario-import-model-demo', settle: false);
    await tap(tester, 'scenario-import-request-form', settle: false);
    expect(tester.widget<DropdownButtonFormField<BehaviorCard>>(find.byKey(
      const ValueKey('scenario-request-behavior'),
    )).onChanged, isNull);
    for (final field in ['age', 'context', 'instructions']) {
      expect(tester.widget<TextField>(find.byKey(ValueKey('scenario-request-$field'))).readOnly,
          isTrue);
    }
    expect(tester.widget<FilledButton>(find.byKey(
      const ValueKey('scenario-request-validate'),
    )).onPressed, isNull);
    expect(requestValue(tester, 'age'), '30');
    expect(find.byKey(const ValueKey('scenario-request-summary')), findsOneWidget);
    expect(service.state.text, 'KISMİ HAM CEVAP');
    expect(service.runs, 1);
    expect(service.cancellations, 0);
    expect(editor(tester), isEmpty);
    await tap(tester, 'scenario-import-model-cancel');
    expect(service.cancellations, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(service.disposals, 1);
  });

  test('Demo isteği mevcut Qwen, CPU runtime sınırları ve içerik sözleşmesini kullanır', () {
    expect(request.model, LocalModelOption.qwen3);
    expect(request.contextSize, 2048);
    expect(request.maxTokens, 768);
    expect(request.prompt, contains('commonStart'));
    expect(request.prompt, contains('continuation'));
    expect(request.prompt, contains('ending'));
    expect(request.prompt, contains('Markdown, kod çiti veya ek açıklama yazma'));
    expect(request.prompt, contains('Sahne kimliği, kenar veya startSceneId üretme'));
  });

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

  testWidgets('Üretim hizmeti bağlı değilken form doğrulanır ama üretim ve yerel model çağrılmaz', (tester) async {
    final local = _DemoService(content);
    await mount(tester, local, _NoAssets());
    await fillGeneration(tester);
    expect(find.text('Senaryo üretim hizmeti henüz bağlı değil.'), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-generation-start')), findsNothing);
    expect(find.byKey(const ValueKey('scenario-generation-raw')), findsNothing);
    expect(editor(tester), isEmpty);
    expect(local.runs, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Üretim cevabı ayrı korunur; mevcut graf yalnız bilinçli aktarımda değişir', (tester) async {
    final service = _GenerationService();
    final local = _DemoService(content);
    await mount(tester, local, _NoAssets(), generationService: service);
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
    expect(input.scenarioId, isNot(LocalLlamaTestRequest.d01GraphDemoMetadata['scenarioId']));
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
    expect(local.runs, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final failure in ['start', 'response', 'metadata', 'cancel']) {
    testWidgets('Üretim $failure hatası taslağı korur ve başarı sayılmaz', (tester) async {
      final service = _GenerationService()..failStart = failure == 'start';
      await mount(tester, _DemoService(content), _NoAssets(), generationService: service);
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

  testWidgets('Üretim iptali ve yeni istekte geç cevap eski taslağı ezmez', (tester) async {
    final service = _GenerationService();
    await mount(tester, _DemoService(content), _NoAssets(), generationService: service);
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
    final local = _DemoService(content);
    await mountRoute(tester, local, generationService: service);
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
    expect(local.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Üretim ham cevabı 320 piksel büyük yazıda sınırlıdır; bölüm kapanınca kaybolmaz', (tester) async {
    final service = _GenerationService();
    await mount(tester, _DemoService(content), _NoAssets(), generationService: service,
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

  testWidgets('Tek kullanıcı çağrısı: ham cevap korunur, metadata eklenir ve graf açılır', (tester) async {
    final service = _DemoService(' \n$content\n');
    final bundle = _NoAssets();
    await mount(tester, service, bundle);
    await tap(tester, '${request.id}-start');
    expect(service.runs, 1);
    expectRaw(tester, ' \n$content\n');
    expect(find.byKey(const ValueKey('scenario-import-normalization')), findsNothing);
    final input = ScenarioInput.fromJsonString(editor(tester));
    expect(input.commonStart, example['commonStart']);
    expect(input.scenarioId, LocalLlamaTestRequest.d01GraphDemoMetadata['scenarioId']);
    expect(input.source, ScenarioInputSource.modelOutput);
    expect(input.alternatives[0].continuation, example['alternatives'][0]['continuation']);
    expect(input.alternatives[1].ending, example['alternatives'][1]['ending']);
    expect(find.text('Alternatif: 2'), findsOneWidget);
    await tap(tester, 'scenario-import-view');
    final viewer = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
    expect(viewer.graph!.scenes.length, 5);
    expect(viewer.graph!.transitions.length, 4);
    expect(viewer.graph!.scenes.first.description, example['commonStart']);
    expect(viewer.sourceLabel, contains('(model_output)'));
    expect(find.text(ScenarioGraphScreen.importedSourceLabel), findsNothing);
    expect(bundle.reads, isEmpty);
    expect(service.runs, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(service.disposals, 1);
  });

  // Baş/son boşluk ve satır sonları da anlatının parçası olarak korunmalı.
  final formatFields = {
    'commonStart': ' \n${example['commonStart']}\n ',
    'alternatives': [
      for (final alternative in example['alternatives'])
        {
          'title': ' ${alternative['title']} ',
          'continuation': ' \n${alternative['continuation']}\n ',
          'ending': ' ${alternative['ending']} ',
        },
    ],
  };
  final formatContent = jsonEncode(formatFields);
  final wrapped = jsonEncode({'scenarioInput': formatFields});
  for (final formatted in [
    ('JSON çiti', '```json\n$formatContent\n```', true, false),
    ('Tek sarmalayıcı', wrapped, false, true),
    ('Çit ve sarmalayıcı', ' \r\n```json\r\n$wrapped\r\n```\r\n ', true, true),
  ]) {
    testWidgets('${formatted.$1}: yalnız biçim açılır, ham cevap ve bütün anlatılar korunur', (tester) async {
      final service = _DemoService(formatted.$2);
      await mount(tester, service, _NoAssets());
      await tap(tester, '${request.id}-start');
      expectRaw(tester, formatted.$2);
      expect(find.byKey(const ValueKey('scenario-import-error')), findsNothing);
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
      final normalized = jsonDecode(editor(tester)) as Map<String, dynamic>;
      expect(normalized['commonStart'], formatFields['commonStart']);
      expect(normalized['alternatives'], formatFields['alternatives']);
      expect(normalized.containsKey('scenarioInput'), isFalse);
      final input = ScenarioInput.fromJson(normalized);
      expect(input.source, ScenarioInputSource.modelOutput);
      expect(input.scenarioId, LocalLlamaTestRequest.d01GraphDemoMetadata['scenarioId']);
      expect(find.byKey(const ValueKey('scenario-import-normalization')), findsOneWidget);
      await tap(tester, 'scenario-import-format-details');
      final notice = tester.widget<Text>(
        find.byKey(const ValueKey('scenario-import-normalization-details')),
      ).data!;
      expect(notice.contains('JSON çiti kaldırıldı'), formatted.$3);
      expect(notice.contains('scenarioInput sarmalayıcısı açıldı'), formatted.$4);
      // Editördeki normalleştirilmiş kopya tekrar doğrulanabilir; çıkarım yok.
      await tap(tester, 'scenario-import-validate');
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
      expectRaw(tester, formatted.$2);
      expect(service.runs, 1);
      await tap(tester, 'scenario-import-view');
      final graph = tester.widget<ScenarioGraphScreen>(
        find.byType(ScenarioGraphScreen),
      ).graph!;
      expect(graph.scenes.first.description, input.commonStart);
      for (var index = 0; index < input.alternatives.length; index++) {
        expect(graph.scenes[1 + 2 * index].description,
            input.alternatives[index].continuation);
        expect(graph.scenes[2 + 2 * index].description,
            input.alternatives[index].ending);
      }
      expect(graph.validate, returnsNormally);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final invalid in [
    ('Ön açıklama', 'Cevap:\n```json\n$content\n```'),
    ('Son açıklama', '```json\n$content\n```\nBitti.'),
    ('İki kod bloğu', '```json\n$content\n```\n```json\n$content\n```'),
    ('Eksik çit', '```json\n$content'),
    ('Bozuk JSON', '```json\n{"scenarioInput": {"commonStart": "Eksik",}}\n```'),
    ('Yan alanlı sarmalayıcı', jsonEncode({'scenarioInput': jsonDecode(content), 'extra': 'Ek metin'})),
    ('Nesne olmayan sarmalayıcı', '{"scenarioInput": "Metin"}'),
    ('İç içe sarmalayıcı', jsonEncode({'scenarioInput': jsonDecode(wrapped)})),
    ('Eksik anlatı', '{"commonStart":"Sadece ortak metin."}'),
    ('Çitli ve sarmalı eksik anlatı', '```json\n{"scenarioInput":{"commonStart":"Sadece ortak metin."}}\n```'),
    ('Eksik dal', jsonEncode({'commonStart': example['commonStart'],
      'alternatives': [example['alternatives'][0]]})),
  ]) {
    testWidgets('${invalid.$1}: hata gösterilir; içerik tamamlanmaz ve tekrar denenmez', (tester) async {
      final service = _DemoService(invalid.$2);
      await mount(tester, service, _NoAssets());
      await tap(tester, '${request.id}-start');
      expectRaw(tester, invalid.$2);
      expect(find.byKey(const ValueKey('scenario-import-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
      expect(tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('scenario-import-view')),
      ).onPressed, isNull);
      expect(service.runs, 1);
      if (invalid.$1 == 'Bozuk JSON') expect(editor(tester), invalid.$2);
      if (invalid.$1 == 'Eksik anlatı') {
        expect(jsonDecode(editor(tester)).containsKey('alternatives'), isFalse);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Kullanıcı düzeltmesi ham cevabı değiştirmez; kaynak graf notunda da ayrılır', (tester) async {
    const raw = '{"commonStart":"Eksik taslak"}';
    final service = _DemoService(raw);
    await mount(tester, service, _NoAssets());
    await tap(tester, '${request.id}-start');
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), content);
    await tester.pump();
    await tap(tester, 'scenario-import-validate');
    final input = ScenarioInput.fromJsonString(editor(tester));
    expect(input.source, ScenarioInputSource.editedModelOutput);
    expectRaw(tester, raw);
    expect(service.runs, 1);
    await tap(tester, 'scenario-import-view');
    final viewer = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
    expect(viewer.sourceLabel, contains('(model_output_edited)'));
    expect(viewer.graph!.authoringNote, contains('kullanıcı tarafından düzenlenmiş'));
    expect(viewer.graph!.scenes.first.description, example['commonStart']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Model hatası kısmi cevabı korur; şablon veya graf üretmez', (tester) async {
    final service = _DemoService('KISMİ TEST METNİ', failure: 'Model indirilmedi');
    await mount(tester, service, _NoAssets());
    await tap(tester, '${request.id}-start');
    expectRaw(tester, 'KISMİ TEST METNİ');
    expect(find.textContaining('Modelden taslak alınamadı: Model indirilmedi'), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(editor(tester), isEmpty);
    expect(service.runs, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Üretim sırasında düzenleme kilitli; iptal kısmi cevabı grafa taşımaz', (tester) async {
    final service = _DemoService('KISMİ', hold: true);
    await mount(tester, service, _NoAssets());
    await tap(tester, 'scenario-import-model-demo');
    final start = find.byKey(ValueKey('${request.id}-start'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    expect(tester.widget<TextField>(
      find.byKey(const ValueKey('scenario-import-json')),
    ).readOnly, isTrue);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    final cancel = find.byKey(ValueKey('${request.id}-cancel'));
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(service.cancellations, 1);
    expect(find.textContaining('kısmi cevap grafa aktarılmadı'), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expectRaw(tester, 'KISMİ');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(service.disposals, 1);
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

  testWidgets('Üretim sürerken ekran kapanırsa servis bırakılır; geç sonuç uygulanmaz', (tester) async {
    final service = _DemoService('KISMİ', hold: true);
    await mount(tester, service, _NoAssets());
    await tap(tester, 'scenario-import-model-demo');
    final start = find.byKey(ValueKey('${request.id}-start'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(service.disposals, 1);
    expect(service.runs, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> tap(WidgetTester tester, String key, {bool settle = true}) async {
  if (key == '${LocalLlamaTestRequest.d01GraphDemo.id}-start' &&
      find.byKey(ValueKey(key)).evaluate().isEmpty) {
    // Model başlatma testleri kapalı demo bölümünü gerçek kontrolle açar.
    await tap(tester, 'scenario-import-model-demo');
  }
  final sectionTitle = switch (key) {
    'scenario-import-model-demo' => 'Modelden taslak al — D01, 30 ay',
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
