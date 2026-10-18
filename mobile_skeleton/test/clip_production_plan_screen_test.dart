import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/services/clip_video_store.dart';
// Kurulu path_provider bağımlılığının test arayüzü; yeni paket gerektirmez.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Plan/UI testleri cihaz belge dizinine veya gerçek dosya sistemine bağlı değildir.
class _EmptyVideoStore extends ClipVideoStore {
  _EmptyVideoStore() : super(documentsDirectory: () async {
    throw StateError('Plan testi gerçek belge dizinine erişmemeli.');
  });

  @override
  Future<Map<String, ClipVideoBinding>> loadPlan(String planId) async => {};
}

// Stüdyo rotası varsayılan depoyu oluşturur. Bu gezinme testinde cihaz
// dizini bilinçli olarak yoktur; eşleme hatası planın gösterimini engellememeli.
class _NoDeviceDirectories extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => null;
}

class _PlanBundle extends CachingAssetBundle {
  _PlanBundle(this.read);
  final Future<String> Function(String) read;

  @override
  Future<String> loadString(String key, {bool cache = true}) => read(key);

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

Widget _app(AssetBundle bundle, {Widget? home, double scale = 1}) =>
    DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home ?? ClipProductionPlanScreen(videoStore: _EmptyVideoStore()),
      ),
    );

void main() {
  final graphText = File(ClipProductionPlanScreen.d01GraphAssetPath).readAsStringSync();
  final planText = File(ClipProductionPlanScreen.d01PlanAssetPath).readAsStringSync();
  final graph = ScenarioGraph.fromJsonString(graphText);
  final plan = ScenarioClipPlan.fromJsonString(planText);
  Future<String> read(String key) async => switch (key) {
    ClipProductionPlanScreen.d01GraphAssetPath => graphText,
    ClipProductionPlanScreen.d01PlanAssetPath => planText,
    _ => throw FlutterError('Beklenmeyen test asset yolu: $key'),
  };

  testWidgets('Tek asset doğrulanır; ortak sahneler ve alternatifler ayrı, tekil gösterilir', (tester) async {
    expect(File('examples/d01_clip_plan.json').existsSync(), isFalse);
    expect(File('pubspec.yaml').readAsLinesSync().map((line) => line.trim()),
        contains('- ${ClipProductionPlanScreen.d01PlanAssetPath}'));
    final pending = Completer<String>();
    await tester.pumpWidget(_app(_PlanBundle((key) =>
        key == ClipProductionPlanScreen.d01PlanAssetPath ? pending.future : read(key))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(planText);
    await tester.pumpAndSettle();
    expect(find.text('Elle hazırlanmış üretim planıdır; video veya gözlem kanıtı değildir'), findsOneWidget);
    expect(find.text('Ortak sahneler · iki dal için tek kez'), findsOneWidget);
    expect(find.text('Alternatif: A · Yönelme'), findsOneWidget);
    expect(find.text('Alternatif: B · Oyuna devam'), findsOneWidget);
    for (final scene in graph.scenes) {
      expect(find.byKey(ValueKey('clip-scene:${scene.id}')), findsOneWidget);
    }
    final scene = find.byKey(const ValueKey('clip-scene:yetiskine_yonelme'));
    await tester.ensureVisible(scene);
    await tester.tap(find.descendant(of: scene, matching: find.text('Çağrı ve yönelme')));
    await tester.pumpAndSettle();
    final sequence = plan.clipsForScene('yetiskine_yonelme');
    expect(tester.getTopLeft(find.byKey(ValueKey('production-clip:${sequence.first.id}'))).dy,
        lessThan(tester.getTopLeft(find.byKey(ValueKey('production-clip:${sequence.last.id}'))).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Klip eylemi ve durumları tam gösterilir; yalnız tam prompt panoya kopyalanır', (tester) async {
    String? copied;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(_app(_PlanBundle(read)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oyuncakla oyun'));
    await tester.pumpAndSettle();
    final clip = plan.clipsForScene('oyuncakla_oyun').single;
    for (final value in [clip.plannedAction, clip.initialState, clip.finalState, clip.productionPrompt]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('1. klip · Hedef süre: 6.0 sn'), findsOneWidget);
    final copy = find.byKey(ValueKey('copy-clip-prompt:${clip.id}'));
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, clip.productionPrompt);
    expect(find.text('Üretim promptu kopyalandı.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dosya ve graf bağlantı hataları anlaşılır gösterilir; yeniden yükleme çalışır', (tester) async {
    var fail = true;
    final invalid = jsonDecode(planText) as Map<String, dynamic>;
    invalid['scenarioId'] = 'baska-senaryo';
    await tester.pumpWidget(_app(_PlanBundle((key) async =>
        key == ClipProductionPlanScreen.d01PlanAssetPath && fail ? jsonEncode(invalid) : await read(key))));
    await tester.pumpAndSettle();
    expect(find.text('Klip üretim planı açılamadı.'), findsOneWidget);
    expect(find.textContaining('başka senaryoya'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    for (final scene in graph.scenes) {
      expect(find.byKey(ValueKey('clip-scene:${scene.id}')), findsOneWidget);
    }
    await tester.pumpWidget(_app(_PlanBundle((_) => Future.error(FlutterError('Test: dosya yok')))));
    await tester.pumpAndSettle();
    expect(find.text('Örnek dosyaları okunamadı. Tekrar deneyebilirsiniz.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Debug Stüdyo girişi üretim planını açar ve yetkilendirme olmadığını belirtir', (tester) async {
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDeviceDirectories();
    addTearDown(() => PathProviderPlatform.instance = previousPaths);
    expect(kDebugMode, isTrue); // Widget testi debug; gerçek release derlemesi değildir.
    await tester.pumpWidget(_app(_PlanBundle(read), home: const SyntheticVideoStudioScreen()));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('open-clip-production-plan'));
    expect(find.text('Hazır D01 örneği'), findsOneWidget);
    expect(find.text('Klip planı ve videolu deneme'), findsOneWidget);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ClipProductionPlanScreen), findsOneWidget);
    expect(find.textContaining('gerçek kullanıcı yetkilendirmesi değildir'), findsOneWidget);
    expect(find.textContaining('Video eşlemeleri okunamadı.'), findsOneWidget);
    expect(find.byKey(const ValueKey('clip-scene:oyuncakla_oyun')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dar ekranda büyük yazı ile klip ayrıntıları kaydırılabilir', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(_PlanBundle(read), scale: 2));
    await tester.pumpAndSettle();
    final scene = find.byKey(const ValueKey('clip-scene:oyuncakla_oyun'));
    await tester.ensureVisible(scene);
    await tester.tap(find.descendant(of: scene, matching: find.text('Oyuncakla oyun')));
    await tester.pumpAndSettle();
    final copy = find.byKey(const ValueKey('copy-clip-prompt:d01_oyun_01'));
    await tester.ensureVisible(copy);
    expect(copy.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
