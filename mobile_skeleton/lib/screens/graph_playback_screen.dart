import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/scenario_clip_plan.dart';
import '../models/scenario_graph.dart';
import '../services/clip_video_store.dart';
import '../services/graph_playback_controller.dart';

class _NativeClipPlayer extends GraphClipPlayer {
  _NativeClipPlayer(File file) : _controller = VideoPlayerController.file(
    file,
    // Paket kendi lifecycle gözlemcisiyle geri dönüşte otomatik play yapmasın.
    // Arka plana geçişi ekran gözlemler ve controller.suspend ile duraklatır.
    videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
  ) {
    _controller.addListener(_changed);
  }

  final VideoPlayerController _controller;
  Future<void>? _closing;
  void _changed() => notifyListeners();
  @override
  bool get completed => _controller.value.isCompleted;
  @override
  String? get error => _controller.value.errorDescription;
  @override
  Future<void> open() => _controller.initialize();
  @override
  Future<void> play() => _controller.play();
  @override
  Future<void> pause() => _controller.pause();
  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _controller.removeListener(_changed);
    super.dispose();
    // Native dispose oynatmayı durdurup zamanlayıcı ve aboneliği de kapatır.
    await _controller.dispose();
  }

  @override
  Widget buildView() => AspectRatio(
    aspectRatio: _controller.value.aspectRatio,
    child: VideoPlayer(_controller),
  );
}

class GraphPlaybackScreen extends StatefulWidget {
  const GraphPlaybackScreen({
    super.key,
    required this.graph,
    required this.plan,
    required this.videoStore,
    this.createPlayer,
    this.prepareNextClip = true,
    this.title = 'Grafı dene',
    this.notice = 'Geliştirici denemesi; video içeriği ve sürekliliği doğrulanmadı',
  });

  final ScenarioGraph graph;
  final ScenarioClipPlan plan;
  final ClipVideoStore videoStore;
  final GraphClipPlayer Function(File)? createPlayer;
  final bool prepareNextClip;
  final String title;
  final String notice;

  @override
  State<GraphPlaybackScreen> createState() => _GraphPlaybackScreenState();
}

class _GraphPlaybackScreenState extends State<GraphPlaybackScreen>
    with WidgetsBindingObserver {
  late final GraphPlaybackController _flow;

  @override
  void initState() {
    super.initState();
    _flow = GraphPlaybackController(
      graph: widget.graph,
      plan: widget.plan,
      videoStore: widget.videoStore,
      createPlayer: widget.createPlayer ?? _NativeClipPlayer.new,
      prepareNextClip: widget.prepareNextClip,
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      unawaited(_flow.suspend());
    }
  }

  void _changed() { if (mounted) setState(() {}); }

  String _choiceLabel(ScenarioTransition transition) {
    final label = transition.label;
    if (label != null && label.trim().isNotEmpty) {
      return label;
    }
    final target = widget.graph.scenes.firstWhere(
      (scene) => scene.id == transition.toSceneId,
    );
    final title = target.title;
    if (title != null && title.trim().isNotEmpty) {
      return title;
    }
    return transition.description;
  }

  Widget _choice(int index, ScenarioTransition transition) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton(
        key: ValueKey('graph-playback-choice:$index'),
        onPressed: () => _flow.choose(index),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          minimumSize: const Size(0, 48),
        ),
        child: Text(_choiceLabel(transition),
            softWrap: true, textAlign: TextAlign.center),
      ),
      ExpansionTile(
        key: ValueKey('graph-playback-choice-details:${transition.fromSceneId}:$index'),
        title: const Text('Geçiş ayrıntıları'),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SelectableText(transition.description,
                key: ValueKey('graph-playback-choice-description:$index')),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _flow.resume();
    } else {
      unawaited(_flow.suspend());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flow.removeListener(_changed);
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _flow.phase;
    final playing = phase == GraphPlaybackPhase.playing;
    final canControl = !_flow.controlsBusy &&
        (playing || phase == GraphPlaybackPhase.paused);
    final scene = widget.graph.scenes.firstWhere((scene) => scene.id == _flow.sceneId);
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Çıkış animasyonu sürerken yükleme bitse bile artık oynatma yapma.
          unawaited(_flow.close().catchError((Object _) {
            debugPrint('Graf denemesi kapatılırken hata oluştu.');
          }));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: const Color(0xFF142540),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.notice),
                const SizedBox(height: 12),
                Text(scene.title ?? scene.id,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Sahne: ${_flow.sceneId} · Klip: ${_flow.clip.id}',
                    key: const ValueKey('graph-playback-current')),
                const SizedBox(height: 12),
                if (phase == GraphPlaybackPhase.loading) ...[
                  const Center(child: CircularProgressIndicator()),
                  const Text('Video yükleniyor…'),
                ],
                if ((playing || phase == GraphPlaybackPhase.paused) && _flow.player != null)
                  _flow.player!.buildView(),
                if (phase == GraphPlaybackPhase.error)
                  Text(_flow.error!, key: const ValueKey('graph-playback-error')),
                if (phase == GraphPlaybackPhase.completed)
                  const Text('Senaryo tamamlandı', key: ValueKey('graph-playback-completed')),
                if (phase == GraphPlaybackPhase.choosing) ...[
                  const Text('Bir devam seçin:'),
                  for (var i = 0; i < _flow.choices.length; i++)
                    _choice(i, _flow.choices[i]),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (phase == GraphPlaybackPhase.ready)
                      FilledButton(
                        key: const ValueKey('graph-playback-start'),
                        onPressed: () => _flow.start(),
                        child: const Text('Başlat'),
                      ),
                    if (playing || phase == GraphPlaybackPhase.paused)
                      FilledButton.icon(
                        key: const ValueKey('graph-playback-toggle'),
                        onPressed: canControl ? () => _flow.togglePlayback() : null,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        label: Text(playing ? 'Duraklat' : 'Devam et'),
                      ),
                    if (_flow.canReplayCompletedPath)
                      FilledButton.icon(
                        key: const ValueKey('graph-playback-replay-path'),
                        onPressed: () => _flow.replayCompletedPath(),
                        icon: const Icon(Icons.replay),
                        label: const Text('Seçtiğim yolu tekrar oynat'),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('graph-playback-restart'),
                      onPressed: phase == GraphPlaybackPhase.ready ||
                          phase == GraphPlaybackPhase.loading || _flow.controlsBusy
                          ? null : () => _flow.restart(),
                      icon: const Icon(Icons.replay),
                      label: const Text('Yeniden seçimle baştan başlat'),
                    ),
                  ],
                ),
                if (phase == GraphPlaybackPhase.completed)
                  const Text('Aynı klipler sırayla yeniden oynatılır; yol yalnız bu ekran oturumunda tutulur.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
