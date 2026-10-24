import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/graph_playback_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
// Mevcut kontrollü platform sınırı; cihaz/model dosyaları açılmaz.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_graph_playback.dart';

class _NoDeviceDocuments extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      throw StateError('Test cihaz/model dizini açmamalı.');
}

class _D01Bundle extends CachingAssetBundle {
  _D01Bundle(this.sources, {this.gate});
  final Map<String, String> sources;
  final Completer<void>? gate;
  final reads = <String>[];

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    reads.add(key);
    if (gate != null) await gate!.future;
    final source = sources[key];
    if (source == null) throw StateError('TEST: asset eksik');
    return source;
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

void main() {
  // Küçük, mevcut JSON fixture'ları; test sırasında async dosya/codec işlemi yok.
  final sources = {
    for (final path in [ClipProductionPlanScreen.d01GraphAssetPath,
      ClipProductionPlanScreen.d01PlanAssetPath]) path: File(path).readAsStringSync(),
  };
  final graph = ScenarioGraph.fromJsonString(sources[ClipProductionPlanScreen.d01GraphAssetPath]!);
  final plan = ScenarioClipPlan.fromJsonString(sources[ClipProductionPlanScreen.d01PlanAssetPath]!);
  late GraphPlaybackHarness harness;
  late PathProviderPlatform previousPaths;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    harness = GraphPlaybackHarness(graph, plan);
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDeviceDocuments();
  });
  tearDown(() { PathProviderPlatform.instance = previousPaths; });

  Future<void> mount(WidgetTester tester, _D01Bundle bundle) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(home: SyntheticVideoStudioScreen(
        playbackVideoStore: harness.store,
        createPlaybackPlayer: harness.create,
      )),
    ));
    await tester.pumpAndSettle();
    expect(bundle.reads, isEmpty);
  }

  Future<void> tap(WidgetTester tester, String key, {bool settle = true}) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(harness.live, 0);
    expect(harness.maximumLive, lessThanOrEqualTo(1));
    expect(harness.store.mutations, 0);
    expect(tester.takeException(), isNull);
  }

  testWidgets('Hazır D01 doğrudan açılır; Başlat öncesi video açılmaz ve ekip yolu gerekmez', (tester) async {
    final bundle = _D01Bundle(sources);
    await mount(tester, bundle);
    final tools = find.byKey(const ValueKey('studio-tools-surface'));
    expect(tester.widget<Material>(tools).color, Colors.white);
    expect(find.descendant(of: tools,
      matching: find.byKey(const ValueKey('open-d01-playback'))), findsOneWidget);
    expect(find.byKey(const ValueKey('open-scenario-graph')), findsOneWidget);
    await tap(tester, 'open-d01-playback');
    final screen = tester.widget<GraphPlaybackScreen>(find.byType(GraphPlaybackScreen));
    expect(screen.graph.toJson(), graph.toJson());
    expect(screen.plan.toJson(), plan.toJson());
    expect(screen.videoStore, same(harness.store));
    expect(find.byType(ClipProductionPlanScreen), findsNothing);
    expect(find.text('D01 videolu örnek'), findsOneWidget);
    expect(find.text('Örnek videoların içeriği ve sürekliliği doğrulanmadı.'), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-playback-start')), findsOneWidget);
    expect(harness.players, isEmpty);
    expect(bundle.reads, [ClipProductionPlanScreen.d01GraphAssetPath,
      ClipProductionPlanScreen.d01PlanAssetPath]);
    await tap(tester, 'graph-playback-start');
    expect(harness.players, hasLength(1));
    expect(harness.players.single.playing, isTrue);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(SyntheticVideoStudioScreen), findsOneWidget);
    expect(harness.players.single.closed, isTrue);
    await close(tester);
  });

  testWidgets('Hızlı iki dokunma tek yükleme/ekran açar; tek geri Stüdyoya döner', (tester) async {
    final gate = Completer<void>();
    final bundle = _D01Bundle(sources, gate: gate);
    await mount(tester, bundle);
    final entry = find.byKey(const ValueKey('open-d01-playback'));
    await tester.ensureVisible(entry);
    final point = tester.getCenter(entry);
    await tester.tapAt(point);
    await tester.tapAt(point); // İkinci gerçek dokunma; callback doğrudan çağrılmaz.
    await tester.pump();
    expect(bundle.reads, hasLength(2));
    expect(tester.widget<ListTile>(find.byKey(
      const ValueKey('open-d01-playback'), skipOffstage: false,
    )).onTap, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(GraphPlaybackScreen), findsOneWidget);
    expect(harness.players, isEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(GraphPlaybackScreen), findsNothing);
    expect(find.byKey(const ValueKey('open-d01-playback')).hitTestable(), findsOneWidget);
    await close(tester);
  });

  for (final failure in ['asset', 'json', 'plan']) {
    testWidgets('$failure yükleme/doğrulama hatası hazırlanma aracına yönlendirmeden gösterilir', (tester) async {
      final changed = Map<String, String>.of(sources);
      switch (failure) {
        case 'asset':
          changed.remove(ClipProductionPlanScreen.d01GraphAssetPath);
        case 'json':
          changed[ClipProductionPlanScreen.d01GraphAssetPath] = '{';
        case 'plan':
          final data = jsonDecode(changed[ClipProductionPlanScreen.d01PlanAssetPath]!) as Map<String, dynamic>;
          changed[ClipProductionPlanScreen.d01PlanAssetPath] = jsonEncode({...data,
            'scenarioId': 'baska-senaryo'});
      }
      await mount(tester, _D01Bundle(changed));
      await tap(tester, 'open-d01-playback');
      expect(find.byKey(const ValueKey('d01-playback-load-error')), findsOneWidget);
      expect(find.byType(GraphPlaybackScreen), findsNothing);
      expect(find.byType(ClipProductionPlanScreen), findsNothing);
      expect(find.textContaining('JSON'), findsNothing);
      expect(find.text('Video seç'), findsNothing);
      expect(harness.players, isEmpty);
      await close(tester);
    });
  }

  for (final lateError in [false, true]) {
    testWidgets('Yüklemede geri çıkış: geç ${lateError ? 'hata' : 'başarı'} ekran açmaz', (tester) async {
      final gate = Completer<void>();
      final bundle = _D01Bundle(sources, gate: gate);
      await mount(tester, bundle);
      await tap(tester, 'open-d01-playback', settle: false);
      // Yalnız rota açılma animasyonu; bekleyen asset'i pumpAndSettle ile bekleme.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      // Pop'tan hemen sonra, kapanış animasyonu sırasında tamamlanır.
      if (lateError) {
        gate.completeError(StateError('TEST: geç yükleme hatası'));
      } else {
        gate.complete();
      }
      await tester.pumpAndSettle();
      expect(find.byType(GraphPlaybackScreen), findsNothing);
      expect(find.byKey(const ValueKey('d01-playback-load-error')), findsNothing);
      expect(find.byKey(const ValueKey('open-d01-playback')).hitTestable(), findsOneWidget);
      expect(harness.players, isEmpty);
      await close(tester);
    });
  }

  for (final failure in ['mapping', 'file', 'read', 'codec']) {
    testWidgets('$failure hatasında mevcut oynatma durur; eşlemeler korunur', (tester) async {
      final firstClip = plan.clipsForScene(graph.startSceneId).first;
      switch (failure) {
        case 'mapping': harness.store.bindings.remove(firstClip.id);
        case 'file': harness.store.missingFile = firstClip.id;
        case 'read': harness.store.readError = true;
        case 'codec': harness.failedClip = firstClip.id;
      }
      final bindings = {for (final entry in harness.store.bindings.entries)
        entry.key: entry.value.toJson()};
      await mount(tester, _D01Bundle(sources));
      await tap(tester, 'open-d01-playback');
      await tap(tester, 'graph-playback-start');
      expect(find.byKey(const ValueKey('graph-playback-error')), findsOneWidget);
      expect(find.textContaining(firstClip.id), findsWidgets);
      expect(find.text('Video seç'), findsNothing);
      expect(find.textContaining('JSON'), findsNothing);
      expect({for (final entry in harness.store.bindings.entries)
        entry.key: entry.value.toJson()}, bindings);
      expect(harness.events.where((event) => event.startsWith('play:')), isEmpty);
      await close(tester);
    });
  }

  testWidgets('Başlat sonrası video açılırken geri çıkış geç oynatmayı engeller', (tester) async {
    final gate = Completer<void>();
    harness.nextOpenGate = gate;
    await mount(tester, _D01Bundle(sources));
    await tap(tester, 'open-d01-playback');
    await tap(tester, 'graph-playback-start', settle: false);
    expect(harness.players, hasLength(1));
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(harness.players.single.closed, isTrue);
    expect(harness.events.where((event) => event.startsWith('play:')), isEmpty);
    expect(find.byType(GraphPlaybackScreen), findsNothing);
    await close(tester);
  });
}
