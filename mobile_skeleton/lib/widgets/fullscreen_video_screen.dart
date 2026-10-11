import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models/models.dart';
import '../models/scenarios_data.dart';
import '../screens/interactive_player_screen.dart' show SimulationState;
import 'floating_video_controls.dart';
import 'finding_notification_pill.dart';

class FullscreenVideoScreen extends StatefulWidget {
  final VideoPlayerController controller;
  final SimulationState? simulationState;
  final List<ScenarioBranchModel>? branches;
  final ValueChanged<ScenarioBranchModel>? onSelectBranch;
  final Future<VideoPlayerController?> Function(ScenarioBranchModel)? onSelectBranchAsync;
  final VoidCallback? onStartSimulation;
  final VoidCallback? onResetSimulation;
  final ValueChanged<SimulationState>? onStateChanged;
  final String? scenarioCode;
  final String? title;
  final Color? badgeColor;
  final List<BehaviorFinding>? findings;

  const FullscreenVideoScreen({
    super.key,
    required this.controller,
    this.simulationState,
    this.branches,
    this.onSelectBranch,
    this.onSelectBranchAsync,
    this.onStartSimulation,
    this.onResetSimulation,
    this.onStateChanged,
    this.scenarioCode,
    this.title,
    this.badgeColor,
    this.findings,
  });

  @override
  State<FullscreenVideoScreen> createState() => _FullscreenVideoScreenState();
}

class _FullscreenVideoScreenState extends State<FullscreenVideoScreen> {
  late VideoPlayerController _activeController;
  SimulationState? _currentState;
  ScenarioBranchModel? _selectedBranch;
  BehaviorFinding? _activeFinding;
  BehaviorFinding? _lastNonNullFinding;

  bool _showControls = true;
  Timer? _controlsTimer;

  bool get _isSimulation => widget.branches != null && widget.branches!.isNotEmpty;

  void _startHideControlsTimer() {
    _controlsTimer?.cancel();
    if (_activeController.value.isPlaying) {
      _controlsTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted && _activeController.value.isPlaying) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _onVideoTick() {
    if (!mounted) return;

    if (_activeController.value.isPlaying && _showControls && (_controlsTimer == null || !_controlsTimer!.isActive)) {
      _startHideControlsTimer();
    }

    // Simülasyon yaşam döngüsü kontrolü
    final pos = _activeController.value.position;
    final dur = _activeController.value.duration;

    if (_currentState == SimulationState.playingRoot) {
      if (dur > Duration.zero && pos >= dur) {
        _activeController.pause();
        setState(() {
          _currentState = SimulationState.waitingDecision;
          _showControls = false;
        });
        widget.onStateChanged?.call(SimulationState.waitingDecision);
      }
    } else if (_currentState == SimulationState.playingBranch) {
      if (dur > Duration.zero && pos >= dur) {
        _activeController.pause();
        setState(() {
          _currentState = SimulationState.finished;
          _showControls = false;
        });
        widget.onStateChanged?.call(SimulationState.finished);
      }
    }

    // Video analizi bulgu takibi
    if (widget.findings != null && widget.findings!.isNotEmpty) {
      final currentSec = _activeController.value.position.inSeconds;
      BehaviorFinding? matched;
      for (final f in widget.findings!) {
        if (currentSec >= f.startSec && currentSec <= f.endSec) {
          matched = f;
          break;
        }
      }
      if (matched != _activeFinding) {
        setState(() {
          _activeFinding = matched;
          if (matched != null) {
            _lastNonNullFinding = matched;
          }
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _activeController = widget.controller;
    _currentState = widget.simulationState ?? SimulationState.idle;

    _activeController.addListener(_onVideoTick);
    _showControls = true;
    _startHideControlsTimer();

    // Yatay ekrana geç ve sistem çubuklarını gizle (Immersive Mode)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didUpdateWidget(covariant FullscreenVideoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.simulationState != oldWidget.simulationState && widget.simulationState != null) {
      setState(() {
        _currentState = widget.simulationState;
      });
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _activeController.removeListener(_onVideoTick);
    // Dikey ekrana ve normal sistem çubuklarına dön
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startFullscreenSimulation() {
    setState(() {
      _currentState = SimulationState.playingRoot;
      _showControls = true;
    });
    widget.onStartSimulation?.call();
    widget.onStateChanged?.call(SimulationState.playingRoot);
    _activeController.seekTo(Duration.zero);
    _activeController.play();
    _startHideControlsTimer();
  }

  Future<void> _handleBranchTap(ScenarioBranchModel branch) async {
    setState(() {
      _selectedBranch = branch;
      _currentState = SimulationState.playingBranch;
    });
    widget.onStateChanged?.call(SimulationState.playingBranch);

    if (widget.onSelectBranchAsync != null) {
      final newCtrl = await widget.onSelectBranchAsync!(branch);
      if (newCtrl != null && mounted) {
        _activeController.removeListener(_onVideoTick);
        _activeController = newCtrl;
        _activeController.addListener(_onVideoTick);
        await _activeController.seekTo(Duration.zero);
        await _activeController.play();
        setState(() {
          _showControls = true;
        });
        _startHideControlsTimer();
      }
    } else if (widget.onSelectBranch != null) {
      widget.onSelectBranch!(branch);
    }
  }

  Widget _buildGlowingDot(Color color, {double size = 16}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white,
            color,
            color.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.75),
            blurRadius: 10,
            spreadRadius: 1.5,
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceCard(ScenarioBranchModel branch) {
    Color borderColor = const Color(0xFF10B981);
    Color glowColor = const Color(0xFF10B981);
    Color hoverTint = const Color(0x1F10B981);

    if (branch.level == 'SARI') {
      borderColor = const Color(0xFFF59E0B);
      glowColor = const Color(0xFFF59E0B);
      hoverTint = const Color(0x1FF59E0B);
    } else if (branch.level == 'KIRMIZI') {
      borderColor = const Color(0xFFEF4444);
      glowColor = const Color(0xFFEF4444);
      hoverTint = const Color(0x1FEF4444);
    }

    final cleanTitle = branch.title.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

    return Material(
      color: const Color(0xFF1E293B), // Slate 800
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _handleBranchTap(branch),
        splashColor: borderColor.withValues(alpha: 0.3),
        highlightColor: hoverTint,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor.withValues(alpha: 0.7),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildGlowingDot(glowColor, size: 18),
              const SizedBox(height: 10),
              Text(
                cleanTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinishedOverlay() {
    final branch = _selectedBranch;
    Color color = branch?.color ?? const Color(0xFF10B981);
    final title = branch?.title.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim() ?? 'Tamamlandı';

    return Positioned.fill(
      child: Container(
        color: const Color(0xF20F172A),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withValues(alpha: 0.65), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildGlowingDot(color, size: 24),
                  const SizedBox(height: 10),
                  const Text(
                    'Simülasyon Tamamlandı',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (branch?.details != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      branch!.details,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onPressed: () {
                          widget.onResetSimulation?.call();
                          setState(() {
                            _currentState = SimulationState.idle;
                            _selectedBranch = null;
                            _showControls = true;
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Yeniden Başlat', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        ),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: const Text('Kapat', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showDecisionOverlay = _currentState == SimulationState.waitingDecision &&
        widget.branches != null &&
        widget.branches!.isNotEmpty;

    final showFinishedOverlay = _currentState == SimulationState.finished && _isSimulation;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // VİDEO YÜZEYİ
            Center(
              child: AspectRatio(
                aspectRatio: _activeController.value.aspectRatio,
                child: VideoPlayer(_activeController),
              ),
            ),

            // TAM EKRANDA BULGU BİLDİRİM KAPSÜLÜ (Video Analizi için)
            if (widget.findings != null && widget.findings!.isNotEmpty)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                bottom: _showControls ? 64 : 16,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Center(
                    child: FindingNotificationPill(
                      finding: _lastNonNullFinding,
                      isVisible: _activeFinding != null,
                    ),
                  ),
                ),
              ),

            // TAM EKRANDA YÜZEN KONTROL KAPSÜLÜ (Karar ve Bitiş anında gizlenir)
            if (!showDecisionOverlay && !showFinishedOverlay)
              Positioned(
                bottom: 12,
                child: SafeArea(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOut,
                    opacity: _showControls ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: FloatingVideoControls(
                        controller: _activeController,
                        isFullscreen: true,
                        onFullscreenToggle: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
              ),

            // TAM EKRANDA BAŞLATMA BUTONU (IDLE İKEN)
            if (_currentState == SimulationState.idle && _isSimulation)
              Center(
                child: ElevatedButton.icon(
                  onPressed: _startFullscreenSimulation,
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: const Text('Simülasyonu Başlat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xF20F172A),
                    foregroundColor: Colors.white,
                    elevation: 8,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
              ),

            // TAM EKRAN İÇİN ORTALANMIŞ KARAR KATMANI OVERLAY (INDEX.HTML İLE BİREBİR)
            if (showDecisionOverlay)
              Positioned.fill(
                child: Container(
                  color: const Color(0xF00F172A), // Slate 900 ~%94
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Tepkiyi Seçin (${widget.scenarioCode ?? ""})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Gözlenen davranışı seçin:',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: widget.branches!.map((branch) {
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: _buildChoiceCard(branch),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // SİMÜLASYON BİTİŞ KARTI
            if (showFinishedOverlay)
              _buildFinishedOverlay(),
          ],
        ),
      ),
    );
  }
}
