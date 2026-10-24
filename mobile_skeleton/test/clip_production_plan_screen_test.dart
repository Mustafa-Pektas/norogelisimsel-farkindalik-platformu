import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    expect(find.textContaining('“Grafı dene” kontrolü yalnız debug derlemesinde görünür'), findsOneWidget);
    expect(find.textContaining('Bu görünürlük kullanıcı yetkilendirmesi değildir'), findsOneWidget);
    expect(find.textContaining('Normal release sürümünde Stüdyo girişi bulunmaz'), findsNothing);
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

  testWidgets('Sahne ve klip sayıları ayrıdır; dallı plan süresini her yol için hedeften ayrı gösterir', (tester) async {
    final durationGraph = ScenarioGraph(
      schemaVersion: '1.0', scenarioId: 'multi-duration', title: 'Çok yollu plan', language: 'tr',
      ageMonths: 31, behaviorId: 'D02', cardVersion: '0.2', startSceneId: 'start',
      scenes: [
        ScenarioScene(id: 'start', title: 'Ortak', description: 'Ortak sahne.'),
        ScenarioScene(id: 'a', title: 'A yolu', description: 'A devamı.'),
        ScenarioScene(id: 'b', title: 'B yolu', description: 'B devamı.'),
      ],
      transitions: [
        ScenarioTransition(fromSceneId: 'start', toSceneId: 'a', label: 'Alternatif A', description: 'A açıklaması.'),
        ScenarioTransition(fromSceneId: 'start', toSceneId: 'b', label: 'Alternatif B', description: 'B açıklaması.'),
      ],
      endSceneIds: ['a', 'b'],
    );
    List<PlannedClip> clips(String sceneId, int total) {
      final result = <PlannedClip>[];
      var remaining = total;
      while (remaining > 0) {
        final duration = remaining > 8 ? 8 : remaining;
        result.add(PlannedClip(id: '$sceneId-${result.length + 1}', sceneId: sceneId,
          orderInScene: result.length + 1, targetDurationS: duration.toDouble(),
          plannedAction: 'Planlanan eylem.', initialState: 'Başlangıç.', finalState: 'Bitiş.',
          productionPrompt: 'Üretim yönergesi.'));
        remaining -= duration;
      }
      return result;
    }
    final durationPlan = ScenarioClipPlan(schemaVersion: '1.0', planId: 'duration-plan',
      scenarioId: durationGraph.scenarioId, authoringNote: 'İncelenmemiş plan.',
      continuityNotes: 'Süreklilik önerisi.', clips: [
        ...clips('start', 8), ...clips('a', 194), ...clips('b', 186),
      ]);
    final source = {'source': 'test', 'request': {'production': {'targetDurationS': 210, 'maxClipDurationS': 8}}};
    await tester.pumpWidget(_app(_PlanBundle(read), home: ClipProductionPlanScreen(
      providedPlan: (graph: durationGraph, plan: durationPlan), sourceContext: source,
      videoStore: _EmptyVideoStore())));
    await tester.pumpAndSettle();
    expect(find.text('3 sahne · 50 klip kaydı · zorunlu klip üst sınırı 8 sn'), findsOneWidget);
    expect(find.textContaining('Dalların süreleri birbirine eklenmez.'), findsOneWidget);
    expect(find.byKey(const ValueKey('clip-plan-duration-target')), findsOneWidget);
    final paths = find.byKey(const ValueKey('clip-plan-path-durations'));
    await tester.ensureVisible(paths); await tester.tap(paths); await tester.pumpAndSettle();
    expect(find.textContaining('Planlanan yol toplamı: 202 sn · hedef 210 sn · fark −8 sn'), findsOneWidget);
    expect(find.textContaining('Planlanan yol toplamı: 194 sn · hedef 210 sn · fark −16 sn'), findsOneWidget);
    expect(find.textContaining('388 sn'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('26 sahne ve 26 klip ayrı sayılır; 210 sn hedefe karşı 202 sn plan ve −8 sn fark gösterilir', (tester) async {
    final linearGraph = ScenarioGraph(schemaVersion: '1.0', scenarioId: 'linear-26-duration',
      title: 'Doğrusal örnek', language: 'tr', ageMonths: 31, behaviorId: 'D02', cardVersion: '0.2',
      startSceneId: 's1', scenes: [for (var i = 1; i <= 26; i++)
        ScenarioScene(id: 's$i', title: 'Sahne $i', description: 'Planlanan sahne $i.')],
      transitions: [for (var i = 1; i < 26; i++) ScenarioTransition(
        fromSceneId: 's$i', toSceneId: 's${i + 1}', description: 'Sıradaki sahne.')],
      endSceneIds: ['s26']);
    final linearPlan = ScenarioClipPlan(schemaVersion: '1.0', planId: 'linear-26-plan',
      scenarioId: linearGraph.scenarioId, authoringNote: 'İncelenmemiş plan.', continuityNotes: 'Süreklilik önerisi.',
      clips: [for (var i = 1; i <= 26; i++) PlannedClip(id: 'clip-$i', sceneId: 's$i',
        orderInScene: 1, targetDurationS: i == 26 ? 2 : 8, plannedAction: 'Planlanan eylem.',
        initialState: 'Başlangıç.', finalState: 'Bitiş.', productionPrompt: 'Üretim yönergesi.')]);
    await tester.pumpWidget(_app(_PlanBundle(read), home: ClipProductionPlanScreen(
      providedPlan: (graph: linearGraph, plan: linearPlan),
      sourceContext: {'request': {'production': {'targetDurationS': 210, 'maxClipDurationS': 8}}},
      videoStore: _EmptyVideoStore())));
    await tester.pumpAndSettle();
    expect(find.text('26 sahne · 26 klip kaydı · zorunlu klip üst sınırı 8 sn'), findsOneWidget);
    final total = find.textContaining('Planlanan yol toplamı: 202 sn · hedef 210 sn · fark −8 sn');
    await tester.ensureVisible(total);
    expect(total, findsOneWidget);
    expect(find.textContaining('208 sn'), findsNothing);
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
    final scene = find.byKey(const ValueKey('clip-scene:oyuncakla_oyun'));
    final sceneTitle = find.descendant(of: scene, matching: find.text('Oyuncakla oyun'));
    await tester.ensureVisible(sceneTitle);
    await tester.pumpAndSettle();
    expect(sceneTitle.hitTestable(), findsOneWidget);
    await tester.tap(sceneTitle);
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

  testWidgets('Mevcut Stüdyo girişi D01 grafına bağlı klip üretim planını açar', (tester) async {
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDeviceDirectories();
    addTearDown(() => PathProviderPlatform.instance = previousPaths);
    final reads = <String>[];
    await tester.pumpWidget(_app(_PlanBundle((key) async {
      reads.add(key);
      return read(key);
    }), home: const SyntheticVideoStudioScreen()));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('open-clip-production-plan'));
    expect(entry, findsOneWidget);
    expect(tester.widget<ListTile>(entry).onTap, isNotNull);
    expect(find.descendant(of: entry,
      matching: find.text('Hazır D01 klip planı ve video eşleme')), findsOneWidget);
    expect(reads, isEmpty);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ClipProductionPlanScreen), findsOneWidget);
    final screen = tester.widget<ClipProductionPlanScreen>(find.byType(ClipProductionPlanScreen));
    expect(screen.graphAssetPath, ClipProductionPlanScreen.d01GraphAssetPath);
    expect(screen.planAssetPath, ClipProductionPlanScreen.d01PlanAssetPath);
    expect(reads, [ClipProductionPlanScreen.d01GraphAssetPath,
      ClipProductionPlanScreen.d01PlanAssetPath]);
    expect(plan.scenarioId, graph.scenarioId);
    expect(find.textContaining('Video eşlemeleri okunamadı.'), findsOneWidget);
    for (final scene in graph.scenes) {
      expect(find.byKey(ValueKey('clip-scene:${scene.id}')), findsOneWidget);
    }
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
