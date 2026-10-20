import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/local_model_option.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/services/local_llama_test_service.dart';
import 'package:neuro_awareness_app/widgets/local_llama_test_card.dart';
// Mevcut platform test sınırı; cihaz/model dizini açılmaz.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _NoDocuments extends PathProviderPlatform {
  int reads = 0;
  @override
  Future<String?> getApplicationDocumentsPath() async {
    reads++;
    throw StateError('Bölüm testi cihaz dosyalarına erişmemeli.');
  }
}

class _StudioBundle extends CachingAssetBundle {
  _StudioBundle(this.sources);
  final Map<String, String> sources;
  final reads = <String>[];
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    reads.add(key);
    if (!sources.containsKey(key)) throw StateError('Beklenmeyen asset: $key');
    return sources[key]!;
  }
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

// Yalnız UI yaşam döngüsü: bu metinler gerçek model cevabı değildir.
class _ControlledService extends LocalLlamaTestService {
  _ControlledService() : super(
    resolveModel: () async => throw StateError('Model dosyası açılmamalı.'),
    createRuntime: (_) => throw StateError('Native motor başlatılmamalı.'),
  );
  final _events = StreamController<LocalLlamaTestState>.broadcast();
  final _done = Completer<void>();
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
  @override
  Future<void> run() async {
    runs++;
    _current = const LocalLlamaTestState(
      phase: LocalLlamaPhase.generating, text: 'TEST KISMİ CEVAP',
    );
    _events.add(_current);
    await _done.future;
  }
  void finish() {
    _current = const LocalLlamaTestState(
      phase: LocalLlamaPhase.completed, text: 'TEST TAM HAM CEVAP',
    );
    _events.add(_current);
    _done.complete();
  }
  @override
  void cancel() {
    cancellations++;
    if (!_done.isCompleted) _done.complete();
  }
  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    disposals++;
    if (_current.isBusy) cancel();
    await _events.close();
  }
}

void main() {
  // Var olan küçük JSON fixture'ları yalnız test tanımında salt okunur alınır.
  final fixtures = {
    for (final path in [ScenarioGraphScreen.d01AssetPath,
      ClipProductionPlanScreen.d01PlanAssetPath]) path: File(path).readAsStringSync(),
  };
  late PathProviderPlatform previousPaths;
  late _NoDocuments paths;
  setUp(() {
    previousPaths = PathProviderPlatform.instance;
    paths = _NoDocuments();
    PathProviderPlatform.instance = paths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    PathProviderPlatform.instance = previousPaths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<_StudioBundle> mount(WidgetTester tester,
      {LocalLlamaTestService? service}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bundle = _StudioBundle(fixtures);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(home: SyntheticVideoStudioScreen(
        modelTestService: service,
      )),
    ));
    await tester.pumpAndSettle();
    return bundle;
  }

  Future<void> tap(WidgetTester tester, Finder finder, {bool settle = true}) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  List<LocalLlamaTestService> services(WidgetTester tester) =>
      tester.widgetList<LocalLlamaTestCard>(
        find.byType(LocalLlamaTestCard, skipOffstage: false),
      ).map((card) => card.service).toList();

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  void expectNoLegacyTemplate() {
    expect(find.text('Eski şablon araçları', skipOffstage: false), findsNothing);
    for (final key in ['studio-template-examples', 'generate-template-scenario',
      'template-scenario-loading', 'template-scenario-title',
      'template-scenario-source', 'show-template-clip-details']) {
      expect(find.byKey(ValueKey(key), skipOffstage: false), findsNothing);
    }
    expect(find.byTooltip('Senaryoyu Kopyala', skipOffstage: false), findsNothing);
    expect(find.byTooltip('Şablon JSON’unu kopyala', skipOffstage: false), findsNothing);
  }

  testWidgets('Stüdyo yeniden kurulunca eski şablon işi başlamaz; teknik servisler korunur', (tester) async {
    final service = _ControlledService();
    final bundle = await mount(tester, service: service);
    final studio = tester.state(find.byType(SyntheticVideoStudioScreen));
    final original = services(tester);
    final reads = paths.reads;
    expectNoLegacyTemplate();
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(home: SyntheticVideoStudioScreen(modelTestService: service)),
    ));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(SyntheticVideoStudioScreen)), same(studio));
    expectNoLegacyTemplate();
    final updated = services(tester);
    expect(updated, hasLength(original.length));
    for (var i = 0; i < original.length; i++) {
      expect(updated[i], same(original[i]));
    }
    expect(paths.reads, reads);
    expect(bundle.reads, isEmpty);
    expect(service.runs, 0);
    expect(service.cancellations, 0);
    expect(service.disposals, 0);
    await close(tester);
    expect(service.disposals, 1);
  });

  testWidgets('Hazır örnek ayrıdır; hazırlama debug bölümünde, teknik denemeler kapalıdır', (tester) async {
    final service = _ControlledService();
    final bundle = await mount(tester, service: service);
    expect(kDebugMode, isTrue); // Widget testi release görünürlüğü kanıtı değildir.
    expect(find.text('Simülasyon ve Eğitim'), findsOneWidget);
    final preparation = find.byKey(const ValueKey('studio-content-preparation'));
    expect(preparation, kDebugMode ? findsOneWidget : findsNothing);
    expect(find.text('İçerik hazırlama'), findsOneWidget);
    final section = tester.widget<ExpansionTile>(preparation);
    expect(section.initiallyExpanded, isTrue);
    expect(section.maintainState, isTrue);
    expect(find.textContaining('Kimlik doğrulaması sağlamaz'), findsOneWidget);
    final entry = find.byKey(const ValueKey('open-scenario-content'));
    expect(entry, findsOneWidget);
    for (final key in ['open-scenario-content', 'open-clip-production-plan',
      'studio-technical-tests']) {
      expect(find.descendant(of: preparation, matching: find.byKey(ValueKey(key))),
          findsOneWidget);
    }
    expect(find.descendant(of: preparation,
      matching: find.byKey(const ValueKey('open-scenario-graph'))), findsNothing);
    expect(find.byKey(const ValueKey('open-d01-playback')), findsOneWidget);
    expect(find.descendant(of: preparation,
      matching: find.byKey(const ValueKey('open-d01-playback'))), findsNothing);
    expect(tester.getTopLeft(entry).dy,
        greaterThan(tester.getTopLeft(find.text('Hazır D01 örneği')).dy));
    for (final key in ['studio-technical-tests']) {
      final tile = tester.widget<ExpansionTile>(find.byKey(ValueKey(key)));
      expect(tile.initiallyExpanded, isFalse);
      expect(tile.maintainState, isTrue);
    }
    expect(find.byType(LocalLlamaTestCard), findsNothing);
    expect(services(tester), hasLength(5));
    expectNoLegacyTemplate();
    expect(find.byKey(const ValueKey('generate-template-scenario')), findsNothing);
    expect(find.byTooltip('Senaryoyu Kopyala'), findsNothing);
    expect(find.byTooltip('Şablon JSON’unu kopyala'), findsNothing);
    expect(find.text('Örnek akışı görüntüle'), findsOneWidget);
    expect(find.text('Klip planı ve videolu deneme'), findsOneWidget);
    expect(find.textContaining('hazır D01 klip planına ve videolarına bağlı değildir'), findsOneWidget);
    expect(bundle.reads, isEmpty);
    expect(service.runs, 0);
    await close(tester);
    expect(service.disposals, 1);
  });

  testWidgets('Başlığa beş dokunuş gizli mod açmaz; hazırlama kapanınca yalnız örnek kalır', (tester) async {
    final service = _ControlledService();
    await mount(tester, service: service);
    final original = services(tester);
    expect(tester.widget<AppBar>(find.byType(AppBar)).title, isA<Text>());
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Simülasyon ve Eğitim'));
    }
    await tester.pumpAndSettle();
    expect(find.text('ADMİN'), findsNothing);
    expect(find.textContaining('Admin alanı açıldı'), findsNothing);
    expect(find.textContaining('Doktor Moduna'), findsNothing);
    expect(find.byKey(const ValueKey('show-template-clip-details')), findsNothing);
    final reads = paths.reads;
    await tap(tester, find.text('İçerik hazırlama'));
    expect(find.byKey(const ValueKey('open-scenario-content')), findsNothing);
    expect(find.byKey(const ValueKey('open-clip-production-plan')), findsNothing);
    expect(find.text('Teknik model denemeleri'), findsNothing);
    expect(find.text('Eski şablon araçları'), findsNothing);
    expect(find.byKey(const ValueKey('open-scenario-graph')), findsOneWidget);
    final hidden = services(tester);
    expect(hidden, hasLength(original.length));
    for (var i = 0; i < original.length; i++) {
      expect(hidden[i], same(original[i]));
    }
    await tap(tester, find.text('İçerik hazırlama'));
    expect(find.byKey(const ValueKey('open-scenario-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-clip-production-plan')), findsOneWidget);
    expect(paths.reads, reads);
    expect(service.runs, 0);
    expect(service.cancellations, 0);
    expect(service.disposals, 0);
    await close(tester);
    expect(service.disposals, 1);
  });


  testWidgets('Doğrudan giriş klip planını açmadan ortak ekranda senaryo içeriğiyle başlar', (tester) async {
    final bundle = await mount(tester);
    await tap(tester, find.byKey(const ValueKey('open-scenario-content')));
    expect(find.byType(ScenarioGraphImportScreen), findsOneWidget);
    expect(find.byType(ClipProductionPlanScreen), findsNothing);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('scenario-import-mode-scenario')),
    ).selected, isTrue);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('scenario-import-mode-graph')),
    ).selected, isFalse);
    final modelDemo = find.byKey(const ValueKey('scenario-import-model-demo'));
    expect(tester.widget<ExpansionTile>(modelDemo).initiallyExpanded, isFalse);
    expect(find.byKey(ValueKey('${LocalLlamaTestRequest.d01GraphDemo.id}-start')), findsNothing);
    await tap(tester, modelDemo);
    expect(find.byKey(ValueKey('${LocalLlamaTestRequest.d01GraphDemo.id}-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(bundle.reads, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing); // Boş ekranda F04 onay istemez.
    expect(find.byType(SyntheticVideoStudioScreen), findsOneWidget);
    await close(tester);
  });

  testWidgets('Hazır D01 girişleri aynı örnek grafı ve klip/video alanını açar', (tester) async {
    final bundle = await mount(tester);
    await tap(tester, find.byKey(const ValueKey('open-scenario-graph')));
    expect(find.byType(ScenarioGraphScreen), findsOneWidget);
    expect(find.textContaining('Elle hazırlanmış örnek'), findsOneWidget);
    expect(bundle.reads, [ScenarioGraphScreen.d01AssetPath]);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('open-clip-production-plan')));
    expect(find.byType(ClipProductionPlanScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('open-graph-playback')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-scenario-graph-import')), findsNothing);
    expect(find.byType(ScenarioGraphImportScreen), findsNothing);
    expect(bundle.reads, containsAll([
      ClipProductionPlanScreen.d01GraphAssetPath,
      ClipProductionPlanScreen.d01PlanAssetPath,
    ]));
    await close(tester);
  });

  testWidgets('Teknik bölüm kapatılınca işlem sürer; servisler, seçim ve ham cevap korunur', (tester) async {
    final service = _ControlledService();
    await mount(tester, service: service);
    final original = services(tester);
    await tap(tester, find.text('Teknik model denemeleri'));
    expect(find.byType(LocalLlamaTestCard), findsNWidgets(5));
    expect(find.byKey(const ValueKey('start-d01-evaluation')), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('comparison-model-selector')));
    await tap(tester, find.text('MiniCPM5-1B-Turkish Q4_K_M').last);
    final reads = paths.reads;
    await tap(tester, find.byKey(ValueKey('${service.request.id}-start')), settle: false);
    expect(service.state.isBusy, isTrue);
    expect(find.text('TEST KISMİ CEVAP'), findsOneWidget);
    await tap(tester, find.text('Teknik model denemeleri'), settle: false);
    expect(find.byType(LocalLlamaTestCard), findsNothing);
    expect(service.state.isBusy, isTrue);
    expect(service.runs, 1);
    expect(service.cancellations, 0);
    expect(service.disposals, 0);
    await tap(tester, find.text('İçerik hazırlama'), settle: false);
    expect(find.byKey(const ValueKey('open-scenario-content')), findsNothing);
    expect(service.state.isBusy, isTrue);
    expect(service.state.text, 'TEST KISMİ CEVAP');
    expect(service.cancellations, 0);
    expect(service.disposals, 0);
    service.finish();
    await tester.pumpAndSettle();
    await tap(tester, find.text('İçerik hazırlama'));
    await tap(tester, find.text('Teknik model denemeleri'));
    await tap(tester, find.byKey(const ValueKey('open-scenario-content')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LocalLlamaTestCard), findsNWidgets(5));
    expect(service.state.phase, LocalLlamaPhase.completed);
    expect(find.text('TEST TAM HAM CEVAP'), findsOneWidget);
    expect(tester.state<FormFieldState<LocalModelOption>>(
      find.byKey(const ValueKey('comparison-model-selector')),
    ).value, LocalModelOption.miniCpmTurkish);
    final reopened = services(tester);
    for (var i = 0; i < original.length; i++) {
      expect(reopened[i], same(original[i]));
    }
    expect(paths.reads, reads);
    expect(service.runs, 1);
    await close(tester);
    expect(service.disposals, 1);
    expect(service.cancellations, 0);
  });
}
