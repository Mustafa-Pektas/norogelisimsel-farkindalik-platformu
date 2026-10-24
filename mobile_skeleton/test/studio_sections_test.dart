import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  late HttpScenarioGenerationService service;
  int serverRequests = 0;
  String? clipboard;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    serverRequests = 0;
    clipboard = null;
    service = HttpScenarioGenerationService(resolveServerUrl: () async => 'http://controlled:8000',
      clientFactory: () => MockClient((_) async {
        serverRequests++;
        return http.Response('Unexpected request', 500);
      }));
    previousPaths = PathProviderPlatform.instance;
    paths = _NoDocuments();
    PathProviderPlatform.instance = paths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
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
      child: MaterialApp(home: SyntheticVideoStudioScreen(comparisonService: service)),
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

  String testerSource() => (find.byKey(const ValueKey('studio-template-source'))
      .evaluate().single.widget as Text).data!;

  void expectTemplateSource() {
    final source = testerSource();
    expect(source, contains('Hazır şablon; model çıkarımı yapılmadı'));
  }

  Future<void> toggleAdmin(WidgetTester tester) async {
    final title = find.byKey(const ValueKey('studio-admin-title'));
    for (var i = 0; i < 5; i++) {
      await tester.tap(title);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Stüdyo rebuild aynı state ve şablon cevabını korur; sunucu çağrısı başlatmaz', (tester) async {
    final bundle = await mount(tester);
    final state = tester.state(find.byType(SyntheticVideoStudioScreen));
    expectTemplateSource();
    await tap(tester, find.byTooltip('Klinik Protokolü Kopyala (Markdown)'));
    final originalOutput = clipboard;
    expect(originalOutput, contains('Hazır şablon; model çıkarımı yapılmadı'));
    await tester.pumpWidget(DefaultAssetBundle(bundle: bundle,
      child: MaterialApp(home: SyntheticVideoStudioScreen(comparisonService: service))));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(SyntheticVideoStudioScreen)), same(state));
    await tap(tester, find.byTooltip('Klinik Protokolü Kopyala (Markdown)'));
    expect(clipboard, originalOutput);
    expect(serverRequests, 0);
    expect(paths.reads, 0);
    expect(bundle.reads, isEmpty);
    await close(tester);
  });

  testWidgets('Dört gerçek araç Material üzerindedir; sunucu seçimi tek başına çağrı başlatmaz', (tester) async {
    final bundle = await mount(tester);
    final surface = find.byKey(const ValueKey('studio-tools-surface'));
    final material = tester.widget<Material>(surface);
    expect(material.color, Colors.white);
    expect(material.shape, isA<RoundedRectangleBorder>());
    for (final key in ['open-d01-playback', 'open-scenario-content',
      'open-clip-production-plan', 'open-scenario-graph']) {
      final entry = find.descendant(of: surface, matching: find.byKey(ValueKey(key)));
      expect(entry, findsOneWidget);
      expect(tester.widget<ListTile>(entry).onTap, isNotNull);
    }
    expect(find.text('Hazır D01 örneği: videolu dallı oynatma'), findsOneWidget);
    expect(find.text('Yeni taslaklar sabit D01 videolarına bağlı değildir.'), findsOneWidget);
    expectTemplateSource();
    await tap(tester, find.byKey(const ValueKey('studio-engine-server')));
    expect(find.byKey(const ValueKey('studio-open-comparison')), findsOneWidget);
    expect(serverRequests, 0);
    expect(paths.reads, 0);
    expect(bundle.reads, isEmpty);
    await close(tester);
  });

  testWidgets('Beş dokunuş admini açıp kapatır; seçim, anahtar ve iki şablon cevabı korunur', (tester) async {
    await mount(tester);
    final state = tester.state(find.byType(SyntheticVideoStudioScreen));
    await tap(tester, find.byTooltip('Klinik Protokolü Kopyala (Markdown)'));
    final doctorOutput = clipboard;
    await tap(tester, find.byKey(const ValueKey('studio-engine-server')));
    await tester.enterText(find.byKey(const ValueKey('studio-team-access-key')), 'controlled-session-key');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await toggleAdmin(tester);
    expect(find.text('ADMİN'), findsOneWidget);
    expect(find.text('Tür 1: Doktor Protokolü'), findsOneWidget);
    expect(find.text('Tür 2: Video Stüdyosu'), findsOneWidget);
    expect(find.byKey(const ValueKey('unmeasured-validation')), findsOneWidget);
    expect(find.text('Ölçülmedi / doğrulama hizmeti bağlı değil.'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('studio-engine-local')));
    await tap(tester, find.byTooltip('Tüm Video Promptlarını Kopyala (Admin)'));
    final prompts = clipboard;
    expect(prompts, contains('Hazır şablon; model çıkarımı yapılmadı'));
    await tap(tester, find.byKey(const ValueKey('studio-validation-toggle')));
    expect(find.text('Ölçülmedi / doğrulama hizmeti bağlı değil.'), findsNothing);
    await tap(tester, find.byKey(const ValueKey('studio-validation-toggle')));
    expect(find.text('Ölçülmedi / doğrulama hizmeti bağlı değil.'), findsOneWidget);
    await toggleAdmin(tester);
    expect(find.text('ADMİN'), findsNothing);
    expect(tester.state(find.byType(SyntheticVideoStudioScreen)), same(state));
    await tap(tester, find.byKey(const ValueKey('studio-engine-server')));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('studio-team-access-key')))
      .controller!.text, 'controlled-session-key');
    await tap(tester, find.byKey(const ValueKey('studio-engine-local')));
    await tap(tester, find.byTooltip('Klinik Protokolü Kopyala (Markdown)'));
    expect(clipboard, doctorOutput);
    await toggleAdmin(tester);
    await tap(tester, find.byTooltip('Tüm Video Promptlarını Kopyala (Admin)'));
    expect(clipboard, prompts);
    expect(serverRequests, 0);
    expect(paths.reads, 0);
    await close(tester);
  });
  testWidgets('Doğrudan giriş klip planını açmadan ortak ekranda senaryo içeriğiyle başlar', (tester) async {
    final bundle = await mount(tester);
    await tap(tester, find.byKey(const ValueKey('open-scenario-content')));
    expect(find.byType(ScenarioGraphImportScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Senaryo çalışma alanı'), findsOneWidget);
    expect(tester.widget<ScenarioGraphImportScreen>(find.byType(ScenarioGraphImportScreen)).clipPlanService,
      isA<HttpScenarioGenerationService>());
    expect(find.byType(ClipProductionPlanScreen), findsNothing);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('scenario-import-mode-scenario')),
    ).selected, isTrue);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('scenario-import-mode-graph')),
    ).selected, isFalse);
    expect(find.byKey(const ValueKey('scenario-import-model-demo'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('scenario-import-request-form')), findsNothing);
    expect(find.byKey(const ValueKey('scenario-generation-start')), findsNothing);
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
