import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/screens/graph_playback_screen.dart';
import 'package:neuro_awareness_app/services/graph_playback_controller.dart';

import 'support/fake_graph_playback.dart';

void main() {
  final graph = ScenarioGraph.fromJsonString(File('assets/scenarios/d01_scenario_graph.json').readAsStringSync());
  final plan = ScenarioClipPlan.fromJsonString(File('assets/scenarios/d01_clip_plan.json').readAsStringSync());
  final branches = graph.transitions.where((edge) => edge.fromSceneId == graph.startSceneId).toList();

  Future<void> finishTo(GraphPlaybackController flow, GraphPlaybackPhase phase, {bool twice = false}) {
    final reached = Completer<void>();
    final player = flow.player! as FakeGraphPlayer;
    void changed() {
      if (!reached.isCompleted && flow.phase == phase &&
          (phase != GraphPlaybackPhase.playing || !identical(flow.player, player))) {
        reached.complete();
      }
    }
    flow.addListener(changed);
    player.finish();
    if (twice) player.finish();
    return reached.future.whenComplete(() => flow.removeListener(changed));
  }

  List<String> route(int branch) {
    final middle = branches[branch].toSceneId;
    final ending = graph.transitions.singleWhere((edge) => edge.fromSceneId == middle).toSceneId;
    return [for (final scene in [graph.startSceneId, middle, ending])
      ...plan.clipsForScene(scene).map((clip) => clip.id)];
  }

  group('Üretimde varsayılan tek-klip önden hazırlama', () {
    late GraphPlaybackHarness harness;
    late GraphPlaybackController flow;
    setUp(() {
      harness = GraphPlaybackHarness(graph, plan);
      // Varsayılan açık ayar: eski testlerdeki soğuk yolun yanında bu yol da sınanır.
      flow = GraphPlaybackController(graph: graph, plan: plan, videoStore: harness.store, createPlayer: harness.create);
    });
    tearDown(() async {
      await flow.close();
      flow.dispose();
      expect(harness.live, 0);
      expect(harness.maximumLive, lessThanOrEqualTo(2));
      expect(harness.store.mutations, 0);
      for (final player in harness.players) {
        expect(player.closed, isTrue);
      }
    });

    Future<void> selectBranch(int branch) async {
      await flow.start();
      await flow.pendingPreparation;
      expect(harness.players, hasLength(1)); // Seçilmemiş iki daldan hiçbiri hazırlanmaz.
      await finishTo(flow, GraphPlaybackPhase.choosing);
      expect(harness.live, 0);
      await flow.choose(branch);
      await flow.pendingPreparation;
    }

    for (var branch = 0; branch < 2; branch++) {
      test('Dal $branch: tek sessiz hazırlık, gerçek bitişte sıcak geçiş ve aynı yolun tekrarı', () async {
        final expected = route(branch);
        await selectBranch(branch);
        final active = flow.player! as FakeGraphPlayer;
        final prepared = harness.players.last;
        expect(active.id, expected[1]);
        expect(prepared.id, expected[2]);
        expect(prepared.playing, isFalse);
        expect(prepared.opened.isCompleted, isTrue);
        expect(harness.events, isNot(contains('play:${prepared.id}')));
        expect(active.playing, isTrue);
        expect(harness.live, 2);
        final stale = active.capturedListener!;
        final phases = <GraphPlaybackPhase>[];
        void changed() => phases.add(flow.phase);
        flow.addListener(changed);
        await finishTo(flow, GraphPlaybackPhase.playing, twice: true);
        flow.removeListener(changed);
        expect(flow.player, same(prepared));
        expect(phases, isNot(contains(GraphPlaybackPhase.loading)));
        expect(harness.events.indexOf('open:${prepared.id}'), lessThan(harness.events.indexOf('closing:${active.id}')));
        expect(harness.events.indexOf('closed:${active.id}'), lessThan(harness.events.indexOf('play:${prepared.id}')));
        final count = harness.players.length;
        stale(); stale();
        expect(harness.players.length, count);
        for (var i = 2; i < expected.length; i++) {
          expect(flow.clip.id, expected[i]);
          await flow.pendingPreparation;
          await finishTo(flow, i == expected.length - 1 ? GraphPlaybackPhase.completed : GraphPlaybackPhase.playing);
        }
        expect(harness.players.map((p) => p.id).toList(), expected);
        expect(flow.canReplayCompletedPath, isTrue);
        await Future.wait([flow.replayCompletedPath(), flow.replayCompletedPath()]);
        await flow.pendingPreparation;
        expect(harness.players.last.id, expected[1]); // Kayıtlı dal, ortak klip sırasında hazırlanır.
        for (var i = 0; i < expected.length; i++) {
          expect(flow.clip.id, expected[i]);
          expect(flow.choices, isEmpty);
          await flow.pendingPreparation;
          await finishTo(flow, i == expected.length - 1 ? GraphPlaybackPhase.completed : GraphPlaybackPhase.playing);
        }
        expect(harness.players.map((p) => p.id).toList(), [...expected, ...expected]);
        expect(harness.live, 0);
      });
    }

    for (final failure in ['mapping', 'file', 'codec', 'prepared-error']) {
      test('$failure: hazırlama hatası mevcut klibi kesmez; sıra gelince açık hata olur', () async {
        final target = route(0)[2];
        if (failure == 'mapping') harness.store.bindings.remove(target);
        if (failure == 'file') harness.store.missingFile = target;
        if (failure == 'codec') harness.failedClip = target;
        await selectBranch(0);
        final active = flow.player! as FakeGraphPlayer;
        if (failure == 'prepared-error') harness.players.last.fail();
        expect(active.playing, isTrue);
        expect(flow.phase, GraphPlaybackPhase.playing);
        expect(flow.error, isNull);
        await finishTo(flow, GraphPlaybackPhase.error);
        expect(flow.clip.id, target);
        expect(flow.error, contains(target));
        expect(flow.canReplayCompletedPath, isFalse);
        expect(harness.events, isNot(contains('play:$target')));
      });
    }

    test('Hazırlama yetişmezse gerçek bitişe kadar mevcut klip oynar; sonra açılış beklenir', () async {
      final target = route(0)[2];
      final gate = Completer<void>(), created = Completer<FakeGraphPlayer>();
      addTearDown(() { if (!gate.isCompleted) gate.complete(); });
      harness.openGates[target] = gate;
      harness.onCreate = (player) { if (player.id == target) created.complete(player); };
      await flow.start(); await finishTo(flow, GraphPlaybackPhase.choosing);
      await flow.choose(0);
      final prepared = await created.future;
      expect(flow.phase, GraphPlaybackPhase.playing);
      expect((flow.player! as FakeGraphPlayer).playing, isTrue);
      expect(prepared.playing, isFalse);
      final transition = finishTo(flow, GraphPlaybackPhase.playing);
      expect(flow.phase, GraphPlaybackPhase.loading);
      expect(harness.events, isNot(contains('play:$target')));
      gate.complete();
      await transition;
      expect(flow.player, same(prepared));
    });

    test('Bekleyen geçişte arka plana gidip hemen dönmek geç açılışı otomatik oynatmaz', () async {
      final target = route(0)[2];
      final gate = Completer<void>(), created = Completer<FakeGraphPlayer>();
      addTearDown(() { if (!gate.isCompleted) gate.complete(); });
      harness.openGates[target] = gate;
      harness.onCreate = (player) { if (player.id == target) created.complete(player); };
      await flow.start(); await finishTo(flow, GraphPlaybackPhase.choosing);
      await flow.choose(0);
      final prepared = await created.future;
      final transition = finishTo(flow, GraphPlaybackPhase.paused);
      expect(flow.phase, GraphPlaybackPhase.loading);
      await flow.suspend();
      flow.resume(); // Açılış tamamlanmadan geri gelinir.
      gate.complete();
      await transition;
      expect(flow.player, same(prepared));
      expect(prepared.playing, isFalse);
      expect(harness.events, isNot(contains('play:$target')));
      await flow.togglePlayback();
      expect(prepared.playing, isTrue);
    });

    for (final action in ['restart', 'close']) {
      test('$action: bekleyen hazırlık kaynakları kapatılır, geç açılış uygulanmaz', () async {
        final target = route(1)[2];
        final gate = Completer<void>(), created = Completer<FakeGraphPlayer>();
        addTearDown(() { if (!gate.isCompleted) gate.complete(); });
        harness.openGates[target] = gate;
        harness.onCreate = (p) { if (p.id == target && !created.isCompleted) created.complete(p); };
        await flow.start(); await finishTo(flow, GraphPlaybackPhase.choosing);
        await flow.choose(1);
        final prepared = await created.future;
        final pending = flow.pendingPreparation;
        final stale = (flow.player! as FakeGraphPlayer).capturedListener!;
        if (action == 'restart') { await flow.restart(); } else { await flow.close(); }
        expect(prepared.closed, isTrue);
        final count = harness.players.length;
        gate.complete();
        await pending;
        stale();
        expect(harness.players.length, count);
        expect(harness.events, isNot(contains('play:$target')));
        if (action == 'restart') {
          expect(flow.clip.id, route(1).first);
          await finishTo(flow, GraphPlaybackPhase.choosing);
          expect(flow.choices, hasLength(2));
        } else {
          expect(harness.live, 0);
          expect(flow.phase, GraphPlaybackPhase.closed);
        }
      });
    }

    test('Hazır klip beklerken yeniden seçim eski iki kaynağı kapatır', () async {
      await selectBranch(0);
      final active = flow.player! as FakeGraphPlayer;
      final prepared = harness.players.last;
      await flow.restart();
      expect(active.closed, isTrue);
      expect(prepared.closed, isTrue);
      expect(harness.live, 1);
      expect(harness.events, isNot(contains('play:${prepared.id}')));
      await finishTo(flow, GraphPlaybackPhase.choosing);
      expect(flow.choices, hasLength(2));
    });

    test('Sıcak geçişte kapanış beklerken çıkış, iki kaynağı da bir kez kapatır', () async {
      await selectBranch(0);
      final active = flow.player! as FakeGraphPlayer;
      final prepared = harness.players.last;
      final gate = Completer<void>();
      addTearDown(() { if (!gate.isCompleted) gate.complete(); });
      active.closeGate = gate;
      active.finish();
      await active.closeStarted.future;
      expect(flow.controlsBusy, isTrue);
      final closing = flow.close();
      await prepared.closeStarted.future;
      expect(prepared.closed, isTrue);
      gate.complete();
      await closing;
      expect(flow.phase, GraphPlaybackPhase.closed);
      expect(harness.live, 0);
      expect(harness.events, isNot(contains('play:${prepared.id}')));
      expect(harness.events.where((e) => e == 'closed:${active.id}'), hasLength(1));
      expect(harness.events.where((e) => e == 'closed:${prepared.id}'), hasLength(1));
    });

    test('Arka planda hazır klip başlatılmaz; dönüş ve bitiş olayı kullanıcıyı bekler', () async {
      await selectBranch(0);
      final active = flow.player! as FakeGraphPlayer;
      final prepared = harness.players.last;
      await flow.suspend();
      active.finish();
      expect(prepared.playing, isFalse);
      expect(flow.phase, GraphPlaybackPhase.paused);
      final plays = harness.events.where((e) => e.startsWith('play:')).length;
      flow.resume();
      expect(harness.events.where((e) => e.startsWith('play:')).length, plays);
      final advanced = Completer<void>();
      void changed() {
        if (!advanced.isCompleted && identical(flow.player, prepared) && flow.phase == GraphPlaybackPhase.playing) {
          advanced.complete();
        }
      }
      flow.addListener(changed);
      await flow.togglePlayback();
      await advanced.future;
      flow.removeListener(changed);
      expect(prepared.playing, isTrue);
    });
  });

  testWidgets('Varsayılan ekranda hazır klip bitişten önce oynamaz, sıcak geçişte yükleme ekranı çıkmaz', (tester) async {
    final harness = GraphPlaybackHarness(graph, plan);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: GraphPlaybackScreen(
      graph: graph, plan: plan, videoStore: harness.store, createPlayer: harness.create)));
    Future<void> tap(String key) async {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target); await tester.tap(target); await tester.pumpAndSettle();
    }
    await tap('graph-playback-start');
    expect(harness.players, hasLength(1));
    harness.players.single.finish(); await tester.pumpAndSettle();
    await tap('graph-playback-choice:0');
    final active = harness.players.singleWhere((p) => p.playing);
    final prepared = harness.players.last;
    expect(prepared.playing, isFalse);
    expect(prepared.id, route(0)[2]);
    expect(find.text('Video yükleniyor…'), findsNothing);
    active.finish(); await tester.pumpAndSettle();
    expect(prepared.playing, isTrue);
    expect(find.text('Video yükleniyor…'), findsNothing);
    expect(find.byKey(const ValueKey('fake-graph-video')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle();
    expect(harness.live, 0);
    expect(harness.maximumLive, lessThanOrEqualTo(2));
    expect(harness.store.mutations, 0);
    expect(tester.takeException(), isNull);
  });
}
