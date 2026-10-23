import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/services/graph_playback_controller.dart';

import 'support/fake_graph_playback.dart';

Future<void> atPhase(GraphPlaybackController flow, GraphPlaybackPhase phase) {
  final done = Completer<void>();
  void changed() {
    if (!done.isCompleted && flow.phase == phase) done.complete();
  }
  flow.addListener(changed);
  return done.future.whenComplete(() => flow.removeListener(changed));
}

void main() {
  final graph = ScenarioGraph.fromJsonString(File('assets/scenarios/d01_scenario_graph.json').readAsStringSync());
  final sourcePlan = ScenarioClipPlan.fromJsonString(File('assets/scenarios/d01_clip_plan.json').readAsStringSync());
  // Listeyi ters çevirmek sahne içi sıra numaralarının esas alındığını sınar.
  final plan = ScenarioClipPlan.fromJson({...sourcePlan.toJson(),
    'clips': sourcePlan.clips.reversed.map((clip) => clip.toJson()).toList()});
  late GraphPlaybackHarness harness;
  late GraphPlaybackController flow;
  setUp(() {
    harness = GraphPlaybackHarness(graph, plan);
    flow = harness.controller();
  });
  tearDown(() async {
    await flow.close();
    flow.dispose();
    expect(harness.live, 0);
    expect(harness.maximumLive, lessThanOrEqualTo(1));
    expect(harness.store.mutations, 0);
  });

  Future<void> finishAt(GraphPlaybackPhase phase) async {
    final reached = atPhase(flow, phase);
    harness.players.last.finish();
    await reached;
  }

  Future<List<String>> completeBranch(int branch) async {
    await flow.start();
    await finishAt(GraphPlaybackPhase.choosing);
    final selected = flow.choices[branch];
    final ending = graph.transitions.singleWhere((edge) => edge.fromSceneId == selected.toSceneId).toSceneId;
    final tail = [
      ...plan.clipsForScene(selected.toSceneId),
      ...plan.clipsForScene(ending),
    ];
    await flow.choose(branch);
    for (var i = 0; i < tail.length; i++) {
      expect(flow.clip.id, tail[i].id);
      await finishAt(i == tail.length - 1 ? GraphPlaybackPhase.completed : GraphPlaybackPhase.playing);
    }
    return [
      ...plan.clipsForScene(graph.startSceneId).map((clip) => clip.id),
      ...tail.map((clip) => clip.id),
    ];
  }

  test('Başlatılmadan video yüklenmez; çift Başlat tek oynatıcı oluşturur', () async {
    expect(flow.sceneId, graph.startSceneId);
    expect(flow.phase, GraphPlaybackPhase.ready);
    expect(harness.players, isEmpty);
    await Future.wait([flow.start(), flow.start()]);
    expect(harness.players, hasLength(1));
    expect(flow.phase, GraphPlaybackPhase.playing);
    expect(harness.events.where((event) => event.startsWith('play:')), hasLength(1));
  });

  for (var branch = 0; branch < 2; branch++) {
    test('Dal $branch: tamamlanan yol çift dokunmada bir kez, aynı sırayla ve yeniden seçim sormadan oynar', () async {
      final expected = await completeBranch(branch);
      expect(flow.canReplayCompletedPath, isTrue);
      final oldCallbacks = harness.players.map((player) => player.capturedListener!).toList();
      final phases = <GraphPlaybackPhase>[];
      void changed() => phases.add(flow.phase);
      flow.addListener(changed);
      await Future.wait([flow.replayCompletedPath(), flow.replayCompletedPath()]);
      expect(harness.players.length, expected.length + 1);
      for (var i = 0; i < expected.length; i++) {
        expect(flow.clip.id, expected[i]);
        expect(flow.choices, isEmpty);
        final count = harness.players.length;
        for (final callback in oldCallbacks) { callback(); }
        expect(harness.players.length, count);
        final next = atPhase(flow, i == expected.length - 1
            ? GraphPlaybackPhase.completed : GraphPlaybackPhase.playing);
        final player = harness.players.last;
        player.finish();
        player.finish(); // Aynı bitiş bildirimi ikinci klibi atlatmamalı.
        await next;
      }
      flow.removeListener(changed);
      expect(phases, isNot(contains(GraphPlaybackPhase.choosing)));
      expect(harness.players.map((player) => player.id).toList(), [...expected, ...expected]);
      expect(flow.canReplayCompletedPath, isTrue);
      expect(harness.live, 0);
      for (final player in harness.players) {
        expect(harness.events.where((event) => event == 'closed:${player.id}').length,
            2); // Her klip, iki ayrı geçişte birer kez kapandı.
      }
      // Yeni seçim yolu önceki kararı taşımaz; diğer dal seçilebilir.
      await flow.restart();
      expect(flow.canReplayCompletedPath, isFalse);
      await finishAt(GraphPlaybackPhase.choosing);
      final other = flow.choices[1 - branch];
      await flow.choose(1 - branch);
      expect(flow.sceneId, other.toSceneId);
      expect(harness.players.last.id, plan.clipsForScene(other.toSceneId).first.id);
    });

    test('Dal $branch: klipler sırayla, tek çıkış ve terminal sahne eksiksiz oynatılır', () async {
      await flow.start();
      await finishAt(GraphPlaybackPhase.choosing);
      expect(harness.live, 0);
      final edge = flow.choices[branch];
      await Future.wait([flow.choose(branch), flow.choose(branch)]);
      final sequence = plan.clipsForScene(edge.toSceneId);
      expect(harness.players.last.id, sequence.first.id);
      for (var i = 1; i < sequence.length; i++) {
        await finishAt(GraphPlaybackPhase.playing);
        expect(harness.players.last.id, sequence[i].id);
      }
      final ending = graph.transitions.singleWhere((item) => item.fromSceneId == edge.toSceneId).toSceneId;
      await finishAt(GraphPlaybackPhase.playing);
      expect(flow.sceneId, ending);
      expect(flow.phase, isNot(GraphPlaybackPhase.completed));
      await finishAt(GraphPlaybackPhase.completed);
      expect(harness.players.map((player) => player.id).toList(), [
        ...plan.clipsForScene(graph.startSceneId).map((clip) => clip.id),
        ...sequence.map((clip) => clip.id),
        ...plan.clipsForScene(ending).map((clip) => clip.id),
      ]);
      expect(harness.live, 0);
    });
  }

  test('Yarım yol tekrar oynatılamaz; baştan seçimde kısmi karar taşınmaz', () async {
    await flow.replayCompletedPath();
    expect(harness.players, isEmpty);
    await flow.start();
    expect(flow.canReplayCompletedPath, isFalse);
    await finishAt(GraphPlaybackPhase.choosing);
    await flow.choose(0);
    final count = harness.players.length;
    await flow.replayCompletedPath();
    expect(harness.players.length, count);
    expect(flow.canReplayCompletedPath, isFalse);
    await flow.restart();
    await finishAt(GraphPlaybackPhase.choosing);
    expect(flow.choices, hasLength(2));
  });

  test('Ekran oturumu kapanınca tamamlanan yol yeni controller içine taşınmaz', () async {
    await completeBranch(1);
    expect(flow.canReplayCompletedPath, isTrue);
    await flow.close();
    expect(flow.canReplayCompletedPath, isFalse);
    flow.dispose();
    flow = harness.controller();
    expect(flow.phase, GraphPlaybackPhase.ready);
    expect(flow.canReplayCompletedPath, isFalse);
    await flow.start();
    await finishAt(GraphPlaybackPhase.choosing);
    expect(flow.choices, hasLength(2));
  });

  for (final mode in ['mapping', 'file', 'codec']) {
    test('Tekrarda $mode hatası yolu tamamlamaz; eksik/bozuk klip atlanmaz', () async {
      final sequence = await completeBranch(0);
      final missing = sequence[2];
      if (mode == 'mapping') harness.store.bindings.remove(missing);
      if (mode == 'file') harness.store.missingFile = missing;
      if (mode == 'codec') harness.failedClip = missing;
      await flow.replayCompletedPath();
      await finishAt(GraphPlaybackPhase.playing);
      await finishAt(GraphPlaybackPhase.error);
      expect(flow.clip.id, missing);
      expect(flow.error, contains(missing));
      expect(flow.canReplayCompletedPath, isFalse);
      final count = harness.players.length;
      await flow.replayCompletedPath();
      expect(harness.players.length, count);
      expect(harness.players.skip(sequence.length).map((p) => p.id).toList(),
          mode == 'codec' ? sequence.take(3).toList() : sequence.take(2).toList());
    });
  }

  test('Bitiş videosu kapanmadan yol tamamlanmış ve tekrar oynatılabilir sayılmaz', () async {
    await flow.start();
    await finishAt(GraphPlaybackPhase.choosing);
    final selected = flow.choices.first;
    await flow.choose(0);
    for (var i = 0; i < plan.clipsForScene(selected.toSceneId).length; i++) {
      await finishAt(GraphPlaybackPhase.playing);
    }
    final finalPlayer = harness.players.last;
    // Kapanış sürerken henüz başarı/tekrar eylemi verilmez.
    final gate = Completer<void>();
    addTearDown(() { if (!gate.isCompleted) gate.complete(); });
    finalPlayer.closeGate = gate;
    final reached = atPhase(flow, GraphPlaybackPhase.completed);
    finalPlayer.finish();
    await finalPlayer.closeStarted.future;
    expect(flow.phase, GraphPlaybackPhase.loading);
    expect(flow.canReplayCompletedPath, isFalse);
    gate.complete();
    await reached;
    expect(flow.canReplayCompletedPath, isTrue);
  });

  for (final action in ['background', 'close']) {
    test('Tekrar yüklenirken $action: geç açılış otomatik oynatmaz, kaynaklar kapanır', () async {
      await flow.close();
      flow.dispose();
      final created = Completer<FakeGraphPlayer>();
      var armed = false;
      flow = GraphPlaybackController(graph: graph, plan: plan, videoStore: harness.store,
        prepareNextClip: false, createPlayer: (file) {
          final player = harness.create(file);
          if (armed && !created.isCompleted) created.complete(player);
          return player;
        });
      await completeBranch(1);
      final gate = Completer<void>();
      addTearDown(() { if (!gate.isCompleted) gate.complete(); });
      harness.nextOpenGate = gate;
      armed = true;
      final loading = flow.replayCompletedPath();
      final player = await created.future;
      final plays = harness.events.where((event) => event.startsWith('play:')).length;
      if (action == 'close') {
        await flow.close();
        expect(player.closed, isTrue);
      } else {
        await flow.suspend();
      }
      gate.complete();
      await loading;
      expect(harness.events.where((event) => event.startsWith('play:')).length, plays);
      if (action == 'background') {
        flow.resume();
        expect(flow.phase, GraphPlaybackPhase.paused);
        expect(player.playing, isFalse);
        await flow.togglePlayback();
        expect(player.playing, isTrue);
      } else {
        expect(flow.phase, GraphPlaybackPhase.closed);
        expect(flow.canReplayCompletedPath, isFalse);
      }
    });
  }

  test('Çift bitiş ve eski oynatıcı olayı ikinci klibi atlatmaz', () async {
    await flow.start();
    await finishAt(GraphPlaybackPhase.choosing);
    await flow.choose(0);
    final old = harness.players.last;
    final staleCallback = old.capturedListener!;
    final gate = Completer<void>();
    addTearDown(() { if (!gate.isCompleted) gate.complete(); });
    old.closeGate = gate;
    old.finish();
    old.finish();
    await old.closeStarted.future;
    expect(flow.phase, GraphPlaybackPhase.loading);
    final count = harness.players.length;
    staleCallback();
    expect(harness.players.length, count);
    final next = atPhase(flow, GraphPlaybackPhase.playing);
    gate.complete();
    await next;
    staleCallback();
    expect(harness.players.length, count + 1);
    expect(flow.clip.orderInScene, 2);
  });

  for (final mode in ['mapping', 'file', 'codec', 'index']) {
    test('$mode eksik/hatalı video akışı durdurur, atlanmaz ve eşleme yazılmaz', () async {
      final id = flow.clip.id;
      switch (mode) {
        case 'mapping':
          harness.store.bindings.remove(id);
          break;
        case 'file':
          harness.store.missingFile = id;
          break;
        case 'codec':
          harness.failedClip = id;
          break;
        case 'index':
          harness.store.readError = true;
          break;
      }
      await flow.start();
      expect(flow.phase, GraphPlaybackPhase.error);
      expect(flow.error, contains(graph.startSceneId));
      expect(flow.error, contains(id));
      expect(flow.clip.id, id);
      expect(harness.players.length, mode == 'codec' ? 1 : 0);
      if (mode != 'mapping') expect(harness.store.bindings, contains(id));
    });
  }

  test('Baştan başlatma mevcut oynatıcıyı kapatır ve ortak başlangıca döner', () async {
    await flow.start();
    await finishAt(GraphPlaybackPhase.choosing);
    await flow.choose(1);
    final previous = harness.players.last;
    await Future.wait([flow.restart(), flow.restart()]);
    expect(previous.closed, isTrue);
    expect(flow.sceneId, graph.startSceneId);
    expect(flow.clip.orderInScene, 1);
    expect(flow.phase, GraphPlaybackPhase.playing);
    expect(harness.players, hasLength(3));
  });

  test('Dalın ikinci klibi eksikse bitişe atlanmaz', () async {
    await flow.start();
    await finishAt(GraphPlaybackPhase.choosing);
    final branch = flow.choices.first.toSceneId;
    await flow.choose(0);
    final missing = plan.clipsForScene(branch)[1].id;
    harness.store.bindings.remove(missing);
    await finishAt(GraphPlaybackPhase.error);
    expect(flow.clip.id, missing);
    expect(flow.error, contains(missing));
    expect(harness.players, hasLength(2));
    await harness.players.last.closeStarted.future;
    expect(harness.live, 0);
  });

  test('Arka plan duraklatır; geri dönüş otomatik oynatmaz', () async {
    await flow.start();
    await flow.suspend();
    expect(flow.phase, GraphPlaybackPhase.paused);
    expect(harness.players.single.playing, isFalse);
    final plays = harness.events.where((event) => event.startsWith('play:')).length;
    flow.resume();
    expect(flow.phase, GraphPlaybackPhase.paused);
    expect(harness.events.where((event) => event.startsWith('play:')).length, plays);
    await flow.togglePlayback();
    expect(harness.players.single.playing, isTrue);
    await flow.togglePlayback();
    expect(harness.players.single.playing, isFalse);
  });

  test('Yükleme sırasında arka plana geçiş sonrasında video kendiliğinden başlamaz', () async {
    final gate = Completer<void>();
    harness.nextOpenGate = gate;
    final loading = flow.start();
    await harness.playerCreated.future;
    await flow.suspend();
    gate.complete();
    await loading;
    expect(flow.phase, GraphPlaybackPhase.paused);
    expect(harness.events.where((event) => event.startsWith('play:')), isEmpty);
    flow.resume();
    expect(harness.players.single.playing, isFalse);
  });

  test('Yükleme sırasında çıkış eski kaynağı kapatır; geç yükleme oynatmaz', () async {
    final gate = Completer<void>();
    harness.nextOpenGate = gate;
    final loading = flow.start();
    await harness.playerCreated.future;
    await flow.close();
    expect(harness.live, 0);
    gate.complete();
    await loading;
    expect(flow.phase, GraphPlaybackPhase.closed);
    expect(harness.events.where((event) => event.startsWith('play:')), isEmpty);
  });

  test('Dosya yolu beklenirken çıkış sonrasında oynatıcı oluşturulmaz', () async {
    final gate = Completer<File>();
    harness.store.fileGate = gate.future;
    final loading = flow.start();
    await harness.store.fileRequested.future;
    await flow.close();
    gate.complete(File('TEST_ONLY/late.mov'));
    await loading;
    expect(harness.players, isEmpty);
  });
}
