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
  /// Yalnız açar/hazırlar; oynatmayı veya sesi başlatmaz.
  Future<void> open();
  Future<void> play();
  Future<void> pause();
  Future<void> close();
  Widget buildView();
}

typedef _UpcomingClip = ({String sceneId, int clipIndex, PlannedClip clip});

/// En fazla tek sessiz hazırlama yuvası; iptal, açılış Future'ını beklemez.
class _PreparedClip {
  _PreparedClip(this.target);
  final _UpcomingClip target;
  final settled = Completer<void>();
  GraphClipPlayer? player;
  bool invalidated = false;
  bool ready = false;
  String? error;
  Future<void>? _closing;

  void finish() { if (!settled.isCompleted) settled.complete(); }
  Future<void> release() {
    final resource = player;
    if (resource == null) return Future.value();
    return _closing ??= (() async {
      try { await resource.pause(); } finally { await resource.close(); }
    })();
  }
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
    this.prepareNextClip = true,
  }) : _sceneId = graph.startSceneId {
    plan.validateAgainst(graph);
  }

  final ScenarioGraph graph;
  final ScenarioClipPlan plan;
  final ClipVideoStore videoStore;
  final GraphClipPlayer Function(File) createPlayer;
  /// Kapalıysa soğuk yükleme yolu kullanılır; arayüzde ayrı bir ayar değildir.
  final bool prepareNextClip;
  _PreparedClip? _prepared;
  Future<void> _preparationCleanup = Future.value();
  /// Oynatma yapmadan hazırlığın başarı/hata/iptal sınırını bekler.
  Future<void> get pendingPreparation => _prepared?.settled.future ?? Future.value();
  String _sceneId;
  int _clipIndex = 0;
  int _epoch = 0;
  bool _closed = false;
  bool _suspended = false;
  int _pauseVersion = 0;
  bool _controlBusy = false;
  bool _endHandled = false;
  GraphPlaybackPhase _phase = GraphPlaybackPhase.ready;
  String? _error;
  GraphClipPlayer? _player;
  VoidCallback? _playerListener;
  Future<void> _releasing = Future.value();
  final _takenPath = <ScenarioTransition>[];
  List<ScenarioTransition>? _completedPath;
  List<ScenarioTransition>? _replayPath;
  int _replayIndex = 0;

  GraphPlaybackPhase get phase => _phase;
  String get sceneId => _sceneId;
  PlannedClip get clip => plan.clipsForScene(_sceneId)[_clipIndex];
  GraphClipPlayer? get player => _player;
  String? get error => _error;
  bool get controlsBusy => _controlBusy;
  bool get canReplayCompletedPath => !_closed &&
      _phase == GraphPlaybackPhase.completed && _completedPath != null;
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
    _takenPath.clear();
    _completedPath = null;
    _replayPath = null;
    _replayIndex = 0;
    _sceneId = graph.startSceneId;
    _clipIndex = 0;
    await _loadCurrent();
  }

  /// Yalnız bu oturumda eksiksiz tamamlanan yolu, aynı kliplerle tekrarlar.
  /// Bir video dosyası oluşturmaz; her klip yine ayrı açılıp kapatılır.
  Future<void> replayCompletedPath() async {
    if (!canReplayCompletedPath || _suspended || _controlBusy) return;
    _replayPath = _completedPath;
    _completedPath = null;
    _takenPath.clear();
    _replayIndex = 0;
    _sceneId = graph.startSceneId;
    _clipIndex = 0;
    await _loadCurrent(); // loading eşzamanlıdır; çift dokunma yeni iş açmaz.
  }

  Future<void> choose(int index) async {
    if (_closed || _suspended || _controlBusy || _phase != GraphPlaybackPhase.choosing) return;
    final available = choices;
    if (index < 0 || index >= available.length) return;
    await _follow(available[index]);
  }

  Future<void> _follow(ScenarioTransition edge) async {
    _takenPath.add(edge);
    _sceneId = edge.toSceneId;
    _clipIndex = 0;
    await _loadCurrent(usePrepared: true); // İkinci basış geçiş kilidine takılır.
  }

  Future<void> _releasePlayer() {
    final previous = _player;
    final listener = _playerListener;
    _player = null;
    _playerListener = null;
    if (previous != null) {
      if (listener != null) previous.removeListener(listener);
      // Hazır klip sessizce bekleyebilir; aktif klip değişiminde eskisi kapatılır.
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

  _UpcomingClip? _nextClip() {
    final clips = plan.clipsForScene(_sceneId);
    if (_clipIndex + 1 < clips.length) {
      return (sceneId: _sceneId, clipIndex: _clipIndex + 1, clip: clips[_clipIndex + 1]);
    }
    if (graph.endSceneIds.contains(_sceneId)) return null;
    final outgoing = graph.transitions.where((edge) => edge.fromSceneId == _sceneId).toList();
    final replay = _replayPath;
    final ScenarioTransition? edge;
    if (replay != null) {
      edge = _replayIndex < replay.length && outgoing.contains(replay[_replayIndex])
          ? replay[_replayIndex] : null;
    } else {
      edge = outgoing.length == 1 ? outgoing.single : null;
    }
    if (edge == null) return null; // İlk oynatmada dal kullanıcıdan önce seçilmez.
    return (sceneId: edge.toSceneId, clipIndex: 0, clip: plan.clipsForScene(edge.toSceneId).first);
  }

  void _prepareNext(int epoch) {
    if (!prepareNextClip || !_current(epoch) || _prepared != null) return;
    final target = _nextClip();
    if (target == null) return;
    final prepared = _PreparedClip(target);
    _prepared = prepared;
    unawaited(_prepare(prepared));
  }

  Future<void> _prepare(_PreparedClip prepared) async {
    bool valid() => !_closed && !prepared.invalidated;
    try {
      final bindings = await videoStore.loadPlan(plan.planId);
      if (!valid()) return;
      final binding = bindings[prepared.target.clip.id];
      if (binding == null) { prepared.error = 'Video eşlemesi yok.'; return; }
      final exists = await videoStore.fileExists(binding);
      if (!valid()) return;
      if (!exists) { prepared.error = 'Kayıtlı video dosyası bulunamadı.'; return; }
      final file = await videoStore.fileFor(binding);
      if (!valid()) return;
      final player = createPlayer(file);
      prepared.player = player;
      await player.open();
      if (!valid()) return;
      if (player.error != null) { prepared.error = 'Video açılamadı.'; return; }
      await player.pause(); // Hiç play çağrılmaz; hazırlanan klip ses çıkarmaz.
      if (!valid()) return;
      prepared.ready = true;
    } catch (_) {
      if (valid()) prepared.error = 'Sonraki video hazırlanamadı.';
    } finally {
      if (prepared.error != null || prepared.invalidated || _closed) {
        try { await prepared.release(); }
        catch (_) { prepared.error = 'Sonraki oynatıcı kapatılamadı.'; }
      }
      prepared.finish();
    }
  }

  Future<void> _discardPrepared() {
    final prepared = _prepared;
    _prepared = null;
    if (prepared != null) {
      prepared.invalidated = true;
      prepared.finish(); // Bekleyen açılış yanıtı kapanışı kilitlemez.
      _preparationCleanup = Future.wait<void>([
        _preparationCleanup, prepared.release(),
      ]).then<void>((_) {});
    }
    return _preparationCleanup;
  }

  Future<void> _releaseAll() async {
    await Future.wait<void>([_releasePlayer(), _discardPrepared()]);
  }

  Future<void> _loadCurrent({bool usePrepared = false}) async {
    final pauseVersion = _pauseVersion;
    final candidate = usePrepared && _prepared?.target.sceneId == _sceneId &&
        _prepared?.target.clipIndex == _clipIndex ? _prepared : null;
    final warm = candidate != null && candidate.ready && candidate.error == null;
    final epoch = ++_epoch;
    if (!warm) _phase = GraphPlaybackPhase.loading;
    _controlBusy = true;
    _endHandled = true;
    _error = null;
    if (!warm) _emit(); // Hazır geçişte aynı video alanı korunur; yeniden açılmaz.
    try {
      if (candidate == null) {
        await _releaseAll();
      } else {
        await _releasePlayer();
      }
      if (!_current(epoch)) return;
      GraphClipPlayer player;
      if (candidate != null) {
        await candidate.settled.future;
        if (!_current(epoch) || candidate.invalidated) return;
        if (candidate.error != null || candidate.player?.error != null || !candidate.ready) {
          await _fail(epoch, candidate.error ?? 'Hazırlanan video açılamadı.');
          return;
        }
        _prepared = null;
        player = candidate.player!;
        candidate.player = null; // Sahiplik aktif oynatıcıya geçer.
        _player = player;
      } else {
        final bindings = await videoStore.loadPlan(plan.planId);
        if (!_current(epoch)) return;
        final binding = bindings[clip.id];
        if (binding == null) { await _fail(epoch, 'Video eşlemesi yok.'); return; }
        final exists = await videoStore.fileExists(binding);
        if (!_current(epoch)) return;
        if (!exists) { await _fail(epoch, 'Kayıtlı video dosyası bulunamadı.'); return; }
        final file = await videoStore.fileFor(binding);
        if (!_current(epoch)) return;
        player = createPlayer(file);
        _player = player;
        await player.open();
        if (!_current(epoch)) return;
      }
      if (player.error != null) { await _fail(epoch, 'Video açılamadı.'); return; }
      void listener() => _playerChanged(player, epoch);
      _playerListener = listener;
      player.addListener(listener);
      _endHandled = false;
      _controlBusy = false;
      _phase = _suspended || pauseVersion != _pauseVersion
          ? GraphPlaybackPhase.paused : GraphPlaybackPhase.playing;
      _prepareNext(epoch);
      _emit();
      if (_current(epoch) && _phase == GraphPlaybackPhase.playing && !_suspended) {
        await player.play();
        if (_current(epoch) && (_suspended || pauseVersion != _pauseVersion)) await player.pause();
      }
    } catch (_) {
      if (_current(epoch)) await _fail(epoch, 'Video veya eşleme okunamadı; akış durduruldu.');
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
      await _loadCurrent(usePrepared: true);
      return;
    }
    if (graph.endSceneIds.contains(_sceneId)) {
      if (_replayPath != null && _replayIndex != _replayPath!.length) {
        await _fail(epoch, 'Tamamlanan yol kaydı bitiş sahnesiyle uyuşmuyor.');
        return;
      }
      await _stopAt(GraphPlaybackPhase.completed);
      return;
    }
    final outgoing = graph.transitions.where((edge) => edge.fromSceneId == _sceneId).toList();
    final replay = _replayPath;
    if (replay != null) {
      if (_replayIndex >= replay.length || !outgoing.contains(replay[_replayIndex])) {
        await _fail(epoch, 'Tamamlanan yolun geçişi bu sahnede bulunamadı.');
        return;
      }
      await _follow(replay[_replayIndex++]);
      return;
    }
    if (outgoing.length == 1) {
      await _follow(outgoing.single);
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
      await _releaseAll();
      if (!_current(epoch)) return;
      if (phase == GraphPlaybackPhase.completed) {
        _completedPath = List.unmodifiable(_takenPath);
        _replayPath = null;
      }
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
      await _releaseAll();
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
    final pauseVersion = _pauseVersion;
    final shouldPlay = _phase == GraphPlaybackPhase.paused;
    _phase = shouldPlay ? GraphPlaybackPhase.playing : GraphPlaybackPhase.paused;
    _emit();
    try {
      if (shouldPlay) {
        await player.play();
        if (_current(epoch) && (_suspended || pauseVersion != _pauseVersion)) await player.pause();
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
    ++_pauseVersion;
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
    _takenPath.clear();
    _completedPath = null;
    _replayPath = null;
    _phase = GraphPlaybackPhase.closed;
    await _releaseAll();
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {
      debugPrint('Graf denemesi oynatıcısı kapatılırken hata oluştu.');
    }));
    super.dispose();
  }
}
