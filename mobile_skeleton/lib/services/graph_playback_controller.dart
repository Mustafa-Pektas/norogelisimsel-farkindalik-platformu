import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/scenario_clip_plan.dart';
import '../models/scenario_graph.dart';
import 'clip_video_store.dart';

/// Akış native video motoruna değil bu küçük sınıra bağlıdır.
abstract class GraphClipPlayer extends ChangeNotifier {
  bool get completed;
  String? get error;
  Future<void> open();
  Future<void> play();
  Future<void> pause();
  Future<void> close();
  Widget buildView();
}

enum GraphPlaybackPhase { ready, loading, playing, paused, choosing, completed, error, closed }

/// Hedef süreleri kullanmaz; yalnız oynatıcının gerçek bitiş bildirimi ilerletir.
/// Depoya yalnız okuma çağrıları yapar. Her yüklemenin ayrı olay kimliği vardır.
class GraphPlaybackController extends ChangeNotifier {
  GraphPlaybackController({
    required this.graph,
    required this.plan,
    required this.videoStore,
    required this.createPlayer,
  }) : _sceneId = graph.startSceneId {
    plan.validateAgainst(graph);
  }

  final ScenarioGraph graph;
  final ScenarioClipPlan plan;
  final ClipVideoStore videoStore;
  final GraphClipPlayer Function(File) createPlayer;
  String _sceneId;
  int _clipIndex = 0;
  int _epoch = 0;
  bool _closed = false;
  bool _suspended = false;
  bool _controlBusy = false;
  bool _endHandled = false;
  GraphPlaybackPhase _phase = GraphPlaybackPhase.ready;
  String? _error;
  GraphClipPlayer? _player;
  VoidCallback? _playerListener;
  Future<void> _releasing = Future.value();

  GraphPlaybackPhase get phase => _phase;
  String get sceneId => _sceneId;
  PlannedClip get clip => plan.clipsForScene(_sceneId)[_clipIndex];
  GraphClipPlayer? get player => _player;
  String? get error => _error;
  bool get controlsBusy => _controlBusy;
  List<ScenarioTransition> get choices => _phase == GraphPlaybackPhase.choosing
      ? graph.transitions.where((edge) => edge.fromSceneId == _sceneId).toList()
      : const [];

  bool _current(int epoch) => !_closed && epoch == _epoch;
  void _emit() { if (!_closed) notifyListeners(); }

  Future<void> start() async {
    if (_closed || _suspended || _phase != GraphPlaybackPhase.ready) return;
    await _loadCurrent();
  }

  Future<void> restart() async {
    if (_closed || _suspended || _controlBusy || _phase == GraphPlaybackPhase.loading ||
        _phase == GraphPlaybackPhase.ready) {
      return;
    }
    _sceneId = graph.startSceneId;
    _clipIndex = 0;
    await _loadCurrent();
  }

  Future<void> choose(int index) async {
    if (_closed || _suspended || _phase != GraphPlaybackPhase.choosing) return;
    final available = choices;
    if (index < 0 || index >= available.length) return;
    _sceneId = available[index].toSceneId;
    _clipIndex = 0;
    await _loadCurrent(); // loading eşzamanlı ayarlanır; ikinci basış kabul edilmez.
  }

  Future<void> _releasePlayer() {
    final previous = _player;
    final listener = _playerListener;
    _player = null;
    _playerListener = null;
    if (previous != null) {
      if (listener != null) previous.removeListener(listener);
      // Yeni oynatıcı, eski oynatıcının kapanması tamamlanmadan oluşturulmaz.
      _releasing = _releasing.then((_) async {
        try {
          await previous.pause();
        } finally {
          await previous.close();
        }
      });
    }
    return _releasing;
  }

  Future<void> _loadCurrent() async {
    final epoch = ++_epoch;
    _phase = GraphPlaybackPhase.loading;
    _controlBusy = false;
    _endHandled = false;
    _error = null;
    _emit();
    try {
      await _releasePlayer();
      if (!_current(epoch)) return;
      final bindings = await videoStore.loadPlan(plan.planId);
      if (!_current(epoch)) return;
      final binding = bindings[clip.id];
      if (binding == null) {
        await _fail(epoch, 'Video eşlemesi yok.');
        return;
      }
      final exists = await videoStore.fileExists(binding);
      if (!_current(epoch)) return;
      if (!exists) {
        await _fail(epoch, 'Kayıtlı video dosyası bulunamadı.');
        return;
      }
      final file = await videoStore.fileFor(binding);
      if (!_current(epoch)) return;
      final player = createPlayer(file);
      _player = player;
      void listener() => _playerChanged(player, epoch);
      _playerListener = listener;
      player.addListener(listener);
      await player.open();
      if (!_current(epoch)) return;
      if (player.error != null) {
        await _fail(epoch, 'Video açılamadı.');
        return;
      }
      _phase = _suspended ? GraphPlaybackPhase.paused : GraphPlaybackPhase.playing;
      _emit();
      if (!_suspended) {
        await player.play();
        if (_current(epoch) && _suspended) await player.pause();
      }
    } catch (_) {
      if (_current(epoch)) {
        await _fail(epoch, 'Video veya eşleme okunamadı; akış durduruldu.');
      }
    }
  }

  void _playerChanged(GraphClipPlayer player, int epoch) {
    if (!_current(epoch) || !identical(player, _player)) return;
    if (player.error != null) {
      unawaited(_fail(epoch, 'Video açılamadı veya oynatma hatası oluştu.'));
      return;
    }
    if (!_suspended && !_endHandled && player.completed &&
        (_phase == GraphPlaybackPhase.playing || _phase == GraphPlaybackPhase.paused)) {
      _endHandled = true;
      unawaited(_advance(epoch));
    }
  }

  Future<void> _advance(int epoch) async {
    if (!_current(epoch)) return;
    if (_clipIndex + 1 < plan.clipsForScene(_sceneId).length) {
      _clipIndex++;
      await _loadCurrent();
      return;
    }
    if (graph.endSceneIds.contains(_sceneId)) {
      await _stopAt(GraphPlaybackPhase.completed);
      return;
    }
    final outgoing = graph.transitions.where((edge) => edge.fromSceneId == _sceneId).toList();
    if (outgoing.length == 1) {
      _sceneId = outgoing.single.toSceneId;
      _clipIndex = 0;
      await _loadCurrent();
    } else {
      await _stopAt(GraphPlaybackPhase.choosing);
    }
  }

  Future<void> _stopAt(GraphPlaybackPhase phase) async {
    final epoch = ++_epoch;
    _phase = GraphPlaybackPhase.loading;
    _controlBusy = false;
    _emit();
    try {
      await _releasePlayer();
      if (!_current(epoch)) return;
      _phase = phase;
      _emit();
    } catch (_) {
      if (_current(epoch)) await _fail(epoch, 'Önceki oynatıcı kapatılamadı.');
    }
  }

  Future<void> _fail(int epoch, String reason) async {
    if (!_current(epoch)) return;
    final failedEpoch = ++_epoch;
    _phase = GraphPlaybackPhase.error;
    _controlBusy = false;
    _error = 'Sahne: $_sceneId · Klip: ${clip.id}\n$reason Eşlemeler korunuyor.';
    _emit();
    try {
      await _releasePlayer();
    } catch (_) {
      if (_current(failedEpoch)) {
        _error = '$_error Oynatıcı kapatma işlemi de başarısız oldu.';
        _emit();
      }
    }
  }

  Future<void> togglePlayback() async {
    if (_closed || _suspended || _controlBusy || _player == null ||
        (_phase != GraphPlaybackPhase.playing && _phase != GraphPlaybackPhase.paused)) {
      return;
    }
    final player = _player!;
    final epoch = _epoch;
    if (player.completed) {
      _playerChanged(player, epoch);
      return;
    }
    _controlBusy = true;
    final shouldPlay = _phase == GraphPlaybackPhase.paused;
    _phase = shouldPlay ? GraphPlaybackPhase.playing : GraphPlaybackPhase.paused;
    _emit();
    try {
      if (shouldPlay) {
        await player.play();
        if (_current(epoch) && _suspended) await player.pause();
      } else {
        await player.pause();
      }
    } catch (_) {
      if (_current(epoch)) await _fail(epoch, 'Oynatma kontrolü başarısız oldu.');
    } finally {
      if (_current(epoch)) {
        _controlBusy = false;
        _emit();
      }
    }
  }

  Future<void> suspend() async {
    if (_closed) return;
    _suspended = true;
    final epoch = _epoch;
    final player = _player;
    if (_phase == GraphPlaybackPhase.playing || _phase == GraphPlaybackPhase.paused) {
      _phase = GraphPlaybackPhase.paused;
      _emit();
      try {
        await player?.pause();
      } catch (_) {
        if (_current(epoch)) await _fail(epoch, 'Video duraklatılamadı.');
      }
    }
  }

  void resume() {
    _suspended = false;
    // Bilerek play çağrılmaz; kullanıcı Devam et düğmesine basar.
  }

  Future<void> close() async {
    _closed = true;
    ++_epoch;
    _phase = GraphPlaybackPhase.closed;
    await _releasePlayer();
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {
      debugPrint('Graf denemesi oynatıcısı kapatılırken hata oluştu.');
    }));
    super.dispose();
  }
}
