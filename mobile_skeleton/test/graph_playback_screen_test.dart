import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/graph_playback_screen.dart';

import 'support/fake_graph_playback.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.sources);
  final Map<String, String> sources;
  @override
  Future<String> loadString(String key, {bool cache = true}) async => sources[key]!;
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

void main() {
  final sources = {
    for (final path in [ClipProductionPlanScreen.d01GraphAssetPath,
        ClipProductionPlanScreen.d01PlanAssetPath]) path: File(path).readAsStringSync(),
  };
  final graph = ScenarioGraph.fromJsonString(sources[ClipProductionPlanScreen.d01GraphAssetPath]!);
  final plan = ScenarioClipPlan.fromJsonString(sources[ClipProductionPlanScreen.d01PlanAssetPath]!);
  late GraphPlaybackHarness harness;
  setUp(() { harness = GraphPlaybackHarness(graph, plan); });

  Widget screen() => GraphPlaybackScreen(graph: graph, plan: plan,
      videoStore: harness.store, createPlayer: harness.create);

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: screen()));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    harness.players.last.finish();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(harness.live, 0);
    expect(harness.maximumLive, lessThanOrEqualTo(1));
    expect(harness.store.mutations, 0);
    expect(tester.takeException(), isNull);
  }

  testWidgets('Giriş yalnız mevcut debug üretim alanından ayrı ekranı açar', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(DefaultAssetBundle(bundle: _Bundle(sources),
      child: MaterialApp(home: ClipProductionPlanScreen(videoStore: harness.store))));
    await tester.pumpAndSettle();
    await tap(tester, 'open-graph-playback');
    expect(find.byType(GraphPlaybackScreen), findsOneWidget);
    expect(find.text('Geliştirici denemesi; video içeriği ve sürekliliği doğrulanmadı'), findsOneWidget);
    expect(find.text('Başlat'), findsOneWidget);
    expect(harness.players, isEmpty);
    await unmount(tester);
  });

  for (var branch = 0; branch < 2; branch++) {
    testWidgets('Dal $branch kullanıcı seçimiyle oynar ve bitiş klibinden sonra tamamlanır', (tester) async {
      await mount(tester);
      expect(harness.players, isEmpty);
      await tap(tester, 'graph-playback-start');
      // Hedef süre çoktan geçse de bitiş olayı olmadan klip değişmemeli.
      await tester.pump(const Duration(seconds: 30));
      expect(harness.players, hasLength(1));
      expect(find.text('Senaryo tamamlandı'), findsNothing);
      await finish(tester);
      final choices = graph.transitions.where((edge) => edge.fromSceneId == graph.startSceneId).toList();
      for (final edge in choices) {
        expect(find.text(edge.description), findsOneWidget);
      }
      expect(harness.live, 0);
      await tap(tester, 'graph-playback-choice:$branch');
      final scene = choices[branch].toSceneId;
      final clips = plan.clipsForScene(scene);
      expect(harness.players.last.id, clips.first.id);
      for (var i = 1; i < clips.length; i++) {
        await finish(tester);
        expect(harness.players.last.id, clips[i].id);
      }
      await finish(tester); // Tek çıkış terminal sahneye otomatik ilerler.
      expect(find.text('Senaryo tamamlandı'), findsNothing);
      await finish(tester);
      expect(find.text('Senaryo tamamlandı'), findsOneWidget);
      await tap(tester, 'graph-playback-restart');
      expect(harness.players.last.id, plan.clipsForScene(graph.startSceneId).first.id);
      expect(find.text('Senaryo tamamlandı'), findsNothing);
      await unmount(tester);
    });
  }

  testWidgets('Eksik klip kimlikleriyle gösterilir, atlanmaz ve eşlemesi silinmez', (tester) async {
    final clip = plan.clipsForScene(graph.startSceneId).first;
    harness.store.missingFile = clip.id;
    await mount(tester);
    await tap(tester, 'graph-playback-start');
    expect(find.textContaining('Kayıtlı video dosyası bulunamadı.'), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const ValueKey('graph-playback-error'))).data!;
    expect(error, contains(graph.startSceneId));
    expect(error, contains(clip.id));
    expect(harness.store.bindings, contains(clip.id));
    expect(harness.players, isEmpty);
    await unmount(tester);
  });

  testWidgets('Arka plan duraklatır; dönüşte yalnız kullanıcı tekrar oynatır', (tester) async {
    await mount(tester);
    await tap(tester, 'graph-playback-start');
    final player = harness.players.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(player.playing, isFalse);
    final playCount = harness.events.where((event) => event.startsWith('play:')).length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Devam et'), findsOneWidget);
    expect(harness.events.where((event) => event.startsWith('play:')).length, playCount);
    await tap(tester, 'graph-playback-toggle');
    expect(player.playing, isTrue);
    await tap(tester, 'graph-playback-toggle');
    expect(player.playing, isFalse);
    await unmount(tester);
  });

  testWidgets('Yükleme sırasında geri çıkış kaynakları kapatır; geç sonuç oynatmaz', (tester) async {
    final gate = Completer<void>();
    harness.nextOpenGate = gate;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen()));
      }, child: const Text('Grafı aç')),
    ))));
    await tester.tap(find.text('Grafı aç'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('graph-playback-start')));
    await tester.pump();
    expect(find.text('Video yükleniyor…'), findsOneWidget);
    expect(harness.players, hasLength(1));
    await tester.pageBack();
    await tester.pump();
    expect(harness.live, 0);
    expect(harness.players.single.playing, isFalse);
    gate.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(harness.events.where((event) => event.startsWith('play:')), isEmpty);
    await unmount(tester);
  });

  testWidgets('Oynatma hatası akışı durdurup mevcut oynatıcıyı kapatır', (tester) async {
    await mount(tester);
    await tap(tester, 'graph-playback-start');
    harness.players.single.fail();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('oynatma hatası oluştu.'), findsOneWidget);
    expect(harness.live, 0);
    expect(find.byKey(const ValueKey('graph-playback-toggle')), findsNothing);
    await unmount(tester);
  });
}
