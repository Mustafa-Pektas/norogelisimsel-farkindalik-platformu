import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/services/http_scenario_generation_service.dart';
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

  Future<_StudioBundle> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bundle = _StudioBundle(fixtures);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(home: const SyntheticVideoStudioScreen()),
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

  testWidgets('Stüdyo rebuild aynı state’i korur; model ve şablon işi başlatmaz', (tester) async {
    final bundle = await mount(tester);
    final state = tester.state(find.byType(SyntheticVideoStudioScreen));
    await tester.pumpWidget(DefaultAssetBundle(bundle: bundle,
      child: const MaterialApp(home: SyntheticVideoStudioScreen())));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(SyntheticVideoStudioScreen)), same(state));
    expectNoLegacyTemplate();
    expect(find.text('Teknik model denemeleri', skipOffstage: false), findsNothing);
    expect(paths.reads, 0);
    expect(bundle.reads, isEmpty);
    await close(tester);
  });

  testWidgets('Hazır örnek ayrıdır; hazırlama debug bölümünde, yerel model araçları yoktur', (tester) async {

    final bundle = await mount(tester);
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
    expect(find.descendant(of: entry, matching: find.text('Senaryo ve graf hazırlama')), findsOneWidget);
    expect(find.text('Sunucudan taslak isteyin; yanıtı inceleyip grafa dönüştürün.'), findsOneWidget);
    for (final key in ['open-scenario-content', 'open-clip-production-plan']) {
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
    expect(find.byKey(const ValueKey('studio-technical-tests'), skipOffstage: false), findsNothing);
    expectNoLegacyTemplate();
    expect(find.byKey(const ValueKey('generate-template-scenario')), findsNothing);
    expect(find.byTooltip('Senaryoyu Kopyala'), findsNothing);
    expect(find.byTooltip('Şablon JSON’unu kopyala'), findsNothing);
    expect(find.text('Örnek akışı görüntüle'), findsOneWidget);
    expect(find.text('D01 klipleri ve video eşleme'), findsOneWidget);
    expect(find.textContaining('hazır D01 klip planına ve videolarına bağlı değildir'), findsOneWidget);
    expect(bundle.reads, isEmpty);

    await close(tester);

  });

  testWidgets('Başlığa beş dokunuş gizli mod açmaz; hazırlama kapanınca yalnız örnek kalır', (tester) async {

    await mount(tester);

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
    await tap(tester, find.text('İçerik hazırlama'));
    expect(find.byKey(const ValueKey('open-scenario-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-clip-production-plan')), findsOneWidget);
    expect(paths.reads, reads);

    await close(tester);

  });

  testWidgets('Doğrudan giriş klip planını açmadan ortak ekranda senaryo içeriğiyle başlar', (tester) async {
    final bundle = await mount(tester);
    await tap(tester, find.byKey(const ValueKey('open-scenario-content')));
    expect(find.byType(ScenarioGraphImportScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Senaryo çalışma alanı'), findsOneWidget);
    expect(tester.widget<ScenarioGraphImportScreen>(find.byType(ScenarioGraphImportScreen)).generationService,
      isA<HttpScenarioGenerationService>());
    expect(find.byType(ClipProductionPlanScreen), findsNothing);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('scenario-import-mode-scenario')),
    ).selected, isTrue);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('scenario-import-mode-graph')),
    ).selected, isFalse);
    expect(find.byKey(const ValueKey('scenario-import-model-demo'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('scenario-import-request-form')), findsOneWidget);
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

}
