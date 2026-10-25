import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/services/clip_video_store.dart';
import 'package:neuro_awareness_app/services/graph_playback_controller.dart';

// Bellek içi test sınırları: galeri, path_provider, dosya veya codec çalıştırmaz.
class FakeGraphStore extends ClipVideoStore {
  FakeGraphStore(ScenarioClipPlan plan) : super(documentsDirectory: () async {
    throw StateError('Graf testi gerçek belge dizinine erişmemeli.');
  }) {
    for (var i = 0; i < plan.clips.length; i++) {
      final clip = plan.clips[i];
      bindings[clip.id] = ClipVideoBinding(planId: plan.planId, clipId: clip.id,
          relativePath: 'clip_videos/import_TEST$i/video.mov', fileName: '${clip.id}.mov');
    }
  }

  final bindings = <String, ClipVideoBinding>{};
  String? missingFile;
  bool readError = false;
  Future<File>? fileGate;
  final fileRequested = Completer<void>();
  int mutations = 0;
  final bundledAssetCopies = <String, Uint8List>{};

  @override
  Future<Map<String, ClipVideoBinding>> loadPlan(String planId) async {
    if (readError) throw const FormatException('TEST: corrupt index');
    return {for (final entry in bindings.entries)
      if (entry.value.planId == planId) entry.key: entry.value};
  }

  @override
  Future<bool> fileExists(ClipVideoBinding binding) async => binding.clipId != missingFile;

  @override
  Future<File> fileFor(ClipVideoBinding binding) async {
    if (!fileRequested.isCompleted) fileRequested.complete();
    final gate = fileGate;
    if (gate != null) return await gate;
    return File('TEST_ONLY_DOCUMENTS/${binding.clipId}.mov');
  }

  @override
  Future<ClipVideoAttachResult> attach({required String planId, required String clipId,
      required File source, required String fileName}) async {
    mutations++;
    throw StateError('Graf oynatma eşleme yazmamalı.');
  }

  @override
  Future<ClipVideoAttachResult> attachBytes({required String planId,
      required String clipId, required Uint8List bytes, required String fileName}) async {
    mutations++;
    bundledAssetCopies[clipId] = Uint8List.fromList(bytes);
    final binding = ClipVideoBinding(
      planId: planId,
      clipId: clipId,
      relativePath: 'clip_videos/import_BUNDLED_$clipId/video.mp4',
      fileName: fileName,
    );
    bindings[clipId] = binding;
    return (binding: binding, warning: null);
  }

  @override
  Future<String?> remove({required String planId, required String clipId}) async {
    mutations++;
    throw StateError('Graf oynatma eşleme silmemeli.');
  }
}

class FakeGraphPlayer extends GraphClipPlayer {
  FakeGraphPlayer(this.id, this.events, this.onClosed, this.onPlayingChanged);
  final String id;
  final List<String> events;
  final VoidCallback onClosed;
  final void Function(bool playing) onPlayingChanged;
  Completer<void>? openGate;
  Completer<void>? closeGate;
  final opened = Completer<void>();
  final closeStarted = Completer<void>();
  VoidCallback? capturedListener;
  bool failOpen = false;
  bool closed = false;
  bool playing = false;
  @override
  bool completed = false;
  @override
  String? error;

  @override
  void addListener(VoidCallback listener) {
    capturedListener = listener;
    super.addListener(listener);
  }

  @override
  Future<void> open() async {
    events.add('open:$id');
    opened.complete();
    final gate = openGate;
    if (gate != null) await gate.future;
    if (failOpen) throw StateError('TEST: codec failure');
  }

  @override
  Future<void> play() async {
    if (closed) throw StateError('Kapalı oynatıcı kullanıldı.');
    if (!playing) {
      playing = true;
      onPlayingChanged(true);
    }
    events.add('play:$id');
  }

  @override
  Future<void> pause() async {
    if (closed) throw StateError('Kapalı oynatıcı kullanıldı.');
    if (playing) {
      playing = false;
      onPlayingChanged(false);
    }
    events.add('pause:$id');
  }

  void finish() { completed = true; notifyListeners(); }
  void fail() { error = 'TEST: playback failure'; notifyListeners(); }

  @override
  Future<void> close() async {
    if (closed) return;
    events.add('closing:$id');
    if (!closeStarted.isCompleted) closeStarted.complete();
    final gate = closeGate;
    if (gate != null) await gate.future;
    closed = true;
    if (playing) {
      playing = false;
      onPlayingChanged(false);
    }
    events.add('closed:$id');
    onClosed();
    super.dispose();
  }

  @override
  Widget buildView() => const AspectRatio(
    aspectRatio: 16 / 9,
    child: SizedBox(key: ValueKey('fake-graph-video')),
  );
}

class GraphPlaybackHarness {
  GraphPlaybackHarness(this.graph, this.plan) : store = FakeGraphStore(plan);
  final ScenarioGraph graph;
  final ScenarioClipPlan plan;
  final FakeGraphStore store;
  final players = <FakeGraphPlayer>[];
  final events = <String>[];
  final playerCreated = Completer<void>();
  Completer<void>? nextOpenGate;
  final openGates = <String, Completer<void>>{};
  void Function(FakeGraphPlayer)? onCreate;
  String? failedClip;
  int live = 0;
  int maximumLive = 0;
  int playing = 0;
  int maximumPlaying = 0;

  /// Önden hazırlanan başka bir oynatıcı listeye daha sonra eklenebilir.
  FakeGraphPlayer latestPlayerForClip(String clipId) =>
      players.lastWhere((player) => player.id == clipId);

  FakeGraphPlayer create(File file) {
    final id = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    live++;
    maximumLive = math.max(maximumLive, live);
    final player = FakeGraphPlayer(
      id,
      events,
      () { live--; },
      (isPlaying) {
        playing += isPlaying ? 1 : -1;
        maximumPlaying = math.max(maximumPlaying, playing);
      },
    )
      ..openGate = openGates[id] ?? nextOpenGate
      ..failOpen = failedClip == id;
    nextOpenGate = null;
    players.add(player);
    onCreate?.call(player);
    if (!playerCreated.isCompleted) playerCreated.complete();
    return player;
  }

  // Eski sıra/hata testleri soğuk yükleme yolunu ayrıca korur.
  // Yeni hazırlama testleri bayrağı açık geçirerek üretim varsayılanını sınar.
  GraphPlaybackController controller({bool prepareNextClip = false}) => GraphPlaybackController(
    graph: graph, plan: plan, videoStore: store, createPlayer: create,
    prepareNextClip: prepareNextClip,
  );
}
