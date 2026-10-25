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
  _D01Bundle(this.sources, {this.gate, this.videoAssets = const {}});
  final Map<String, String> sources;
  final Completer<void>? gate;
  final Set<String> videoAssets;
  final reads = <String>[];
  final videoAssetReads = <String>[];

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    reads.add(key);
    if (gate != null) await gate!.future;
    final source = sources[key];
    if (source == null) throw StateError('TEST: asset eksik');
    return source;
  }

  @override
  Future<ByteData> load(String key) async {
    videoAssetReads.add(key);
    if (!videoAssets.contains(key)) throw StateError('TEST: bundled video asset missing');
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    return ByteData.view(bytes.buffer);
  }
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

  Future<void> close(WidgetTester tester, {
    int expectedStoreMutations = 0,
    int maximumAllowedLivePlayers = 1,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(harness.live, 0);
    expect(harness.maximumLive, lessThanOrEqualTo(maximumAllowedLivePlayers));
    expect(harness.playing, 0);
    expect(harness.maximumPlaying, lessThanOrEqualTo(1));
    expect(harness.store.mutations, expectedStoreMutations);
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

  testWidgets('Yeni D01/D02 graf, plan ve video dosyaları paket asset listesinde bulunur; kurmaca yaş 36 aydır', (tester) async {
    for (final example in [d01NameTurningExample, d02PointingDirectionExample]) {
      final graphJson = await rootBundle.loadString(example.graphAssetPath);
      final planJson = await rootBundle.loadString(example.planAssetPath);
      final exampleGraph = ScenarioGraph.fromJsonString(graphJson);
      final examplePlan = ScenarioClipPlan.fromJsonString(planJson);
      examplePlan.validateAgainst(exampleGraph);
      expect(exampleGraph.ageMonths, 36);
      expect(exampleGraph.authoringNote, contains('36 ay'));
      expect(exampleGraph.authoringNote, contains('kaynak videodan yaş doğrulanmamıştır'));
      expect(examplePlan.authoringNote, contains('36 ay'));
      expect(examplePlan.authoringNote, contains('kaynak videodan yaş doğrulanmamıştır'));
      for (final assetPath in example.videoAssetsByClipId.values) {
        final asset = await rootBundle.load(assetPath);
        expect(asset.lengthInBytes, greaterThan(0), reason: assetPath);
      }
    }
  });

  void addBundledExampleTest({
    required BundledGraphPlaybackExample example,
    required String entryKey,
    required String branchLabel,
    required int choiceIndex,
    required String firstClipId,
    required String secondClipId,
  }) {
    testWidgets('${example.id}: paket videoları mevcut dallı oynatıcı ve seçilmiş yol tekrarıyla kullanılır', (tester) async {
      final graphSource = File(example.graphAssetPath).readAsStringSync();
      final planSource = File(example.planAssetPath).readAsStringSync();
      final exampleGraph = ScenarioGraph.fromJsonString(graphSource);
      final examplePlan = ScenarioClipPlan.fromJsonString(planSource);
      examplePlan.validateAgainst(exampleGraph);
      harness = GraphPlaybackHarness(exampleGraph, examplePlan);
      harness.store.bindings.clear(); // İlk kullanım: asset eşlemeleri henüz yok.
      final bundle = _D01Bundle(
        {
          ...sources,
          example.graphAssetPath: graphSource,
          example.planAssetPath: planSource,
        },
        videoAssets: example.videoAssetsByClipId.values.toSet(),
      );
      await mount(tester, bundle);
      expect(find.byKey(ValueKey(entryKey)), findsOneWidget);
      await tap(tester, entryKey);

      final screen = tester.widget<GraphPlaybackScreen>(find.byType(GraphPlaybackScreen));
      expect(screen.graph.scenarioId, exampleGraph.scenarioId);
      expect(screen.plan.planId, examplePlan.planId);
      expect(screen.videoStore, same(harness.store));
      expect(screen.title, example.title);
      expect(screen.notice, example.notice);
      expect(bundle.reads, [example.graphAssetPath, example.planAssetPath]);
      expect(bundle.videoAssetReads, example.videoAssetsByClipId.values.toList());
      expect(harness.store.bundledAssetCopies.keys.toSet(),
          examplePlan.clips.map((clip) => clip.id).toSet());
      expect(harness.store.mutations, examplePlan.clips.length);
      expect(harness.players, isEmpty); // Eşleme sırasında/ekran açılışında video player açılmaz.

      await tap(tester, 'graph-playback-start');
      expect(find.textContaining(exampleGraph.startSceneId), findsOneWidget);
      expect(harness.players, hasLength(1));
      expect(harness.players.single.playing, isTrue);
      harness.players.single.finish();
      await tester.pumpAndSettle();
      expect(find.text('Bir devam seçin:'), findsOneWidget);
      expect(find.text(branchLabel), findsOneWidget);

      await tap(tester, 'graph-playback-choice:$choiceIndex');
      await tester.pumpAndSettle();
      expect(find.textContaining(firstClipId), findsOneWidget);
      // Son yaratılan player bir sonraki klibin sessiz hazırlığı olabilir.
      final selectedFirstPlayer = harness.latestPlayerForClip(firstClipId);
      expect(selectedFirstPlayer.playing, isTrue);
      selectedFirstPlayer.finish();
      await tester.pumpAndSettle();
      expect(find.textContaining(secondClipId), findsOneWidget);
      expect(find.text('Bir devam seçin:'), findsNothing); // Dalın ikinci klibi otomatik gelir.
      harness.latestPlayerForClip(secondClipId).finish();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('graph-playback-completed')), findsOneWidget);
      expect(find.byKey(const ValueKey('graph-playback-replay-path')), findsOneWidget);

      await tap(tester, 'graph-playback-replay-path');
      await tester.pumpAndSettle();
      expect(find.textContaining(exampleGraph.startSceneId), findsOneWidget);
      final replayStartPlayer = harness.latestPlayerForClip(examplePlan.clipsForScene(exampleGraph.startSceneId).single.id);
      expect(replayStartPlayer.playing, isTrue);
      replayStartPlayer.finish();
      await tester.pumpAndSettle();
      expect(find.text('Bir devam seçin:'), findsNothing); // Tekrar aynı dalı otomatik izler.
      expect(find.textContaining(firstClipId), findsOneWidget);
      final replayFirstPlayer = harness.latestPlayerForClip(firstClipId);
      expect(replayFirstPlayer.playing, isTrue);
      replayFirstPlayer.finish();
      await tester.pumpAndSettle();
      expect(find.textContaining(secondClipId), findsOneWidget);
      final replaySecondPlayer = harness.latestPlayerForClip(secondClipId);
      expect(replaySecondPlayer.playing, isTrue);
      replaySecondPlayer.finish();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('graph-playback-completed')), findsOneWidget);
      expect(harness.players.length, 6);
      expect(harness.store.mutations, examplePlan.clips.length);
      expect(harness.maximumLive, lessThanOrEqualTo(2));
      expect(harness.maximumPlaying, lessThanOrEqualTo(1));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final loadedAssetCount = bundle.videoAssetReads.length;
      await tap(tester, entryKey);
      expect(bundle.videoAssetReads, hasLength(loadedAssetCount));
      expect(harness.store.mutations, examplePlan.clips.length);
      expect(harness.players, hasLength(6));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await close(
        tester,
        expectedStoreMutations: examplePlan.clips.length,
        maximumAllowedLivePlayers: 2,
      );
    });
  }

  addBundledExampleTest(
    example: d01NameTurningExample,
    entryKey: 'open-d01-name-turning-playback',
    branchLabel: 'Oyuna devam',
    choiceIndex: 1,
    firstClipId: 'd01_name_play_1',
    secondClipId: 'd01_name_play_2',
  );
  addBundledExampleTest(
    example: d02PointingDirectionExample,
    entryKey: 'open-d02-pointing-playback',
    branchLabel: 'Raf yönüne dönme',
    choiceIndex: 0,
    firstClipId: 'd02_point_shelf_1',
    secondClipId: 'd02_point_shelf_2',
  );

  for (final example in [d01NameTurningExample, d02PointingDirectionExample]) {
    testWidgets('${example.id}: geri çıkış sırasında geç asset cevabı oynatıcı açmaz', (tester) async {
      final graphSource = File(example.graphAssetPath).readAsStringSync();
      final planSource = File(example.planAssetPath).readAsStringSync();
      final exampleGraph = ScenarioGraph.fromJsonString(graphSource);
      final examplePlan = ScenarioClipPlan.fromJsonString(planSource);
      harness = GraphPlaybackHarness(exampleGraph, examplePlan);
      harness.store.bindings.clear();
      final gate = Completer<void>();
      final bundle = _D01Bundle({
        ...sources,
        example.graphAssetPath: graphSource,
        example.planAssetPath: planSource,
      }, gate: gate, videoAssets: example.videoAssetsByClipId.values.toSet());
      await mount(tester, bundle);
      await tap(tester, example.id == d01NameTurningExample.id
          ? 'open-d01-name-turning-playback' : 'open-d02-pointing-playback', settle: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(GraphPlaybackScreen), findsNothing);
      expect(harness.players, isEmpty);
      expect(bundle.videoAssetReads, isEmpty);
      expect(harness.store.mutations, 0);
      await close(tester);
    });
  }

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
