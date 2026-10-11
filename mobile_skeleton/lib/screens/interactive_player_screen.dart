import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/scenarios_data.dart';
import '../widgets/floating_video_controls.dart';
import '../widgets/age_slider_card.dart';
import '../widgets/fullscreen_video_screen.dart';
import '../widgets/scenario_picker_sheet.dart';
import '../widgets/api_key_dialog.dart';

enum SimulationState {
  idle,
  playingRoot,
  waitingDecision,
  playingBranch,
  finished,
}

class InteractivePlayerScreen extends StatefulWidget {
  final ScenarioModel? initialScenario;
  final String? initialAgeGroup;

  const InteractivePlayerScreen({
    super.key,
    this.initialScenario,
    this.initialAgeGroup,
  });

  @override
  State<InteractivePlayerScreen> createState() => _InteractivePlayerScreenState();
}

class _InteractivePlayerScreenState extends State<InteractivePlayerScreen> {
  late ScenarioModel _currentScenario;
  int _selectedScenarioIndex = 0;
  double _currentMonth = 18.0;

  VideoPlayerController? _controller;
  SimulationState _state = SimulationState.idle;
  ScenarioBranchModel? _selectedBranch;

  // Klinik Metrikler
  String _latencyText = '-';
  String _angleText = '-';
  String _classificationText = '-';
  Color _classificationColor = const Color(0xFF0284C7);
  String _clinicalReport = '';

  String get _currentAgeGroupLabel {
    if (_currentMonth < 18) return '12–18 Ay';
    if (_currentMonth < 24) return '18–24 Ay';
    return '24–36 Ay';
  }

  @override
  void initState() {
    super.initState();
    final all = ScenariosRepository.allScenarios;
    if (widget.initialScenario != null) {
      _currentScenario = widget.initialScenario!;
      _selectedScenarioIndex = all.indexWhere((s) => s.code == _currentScenario.code);
      if (_selectedScenarioIndex == -1) _selectedScenarioIndex = 0;
    } else {
      _currentScenario = all.first;
      _selectedScenarioIndex = 0;
    }

    if (widget.initialAgeGroup != null) {
      if (widget.initialAgeGroup == '12–18 Ay') _currentMonth = 15;
      if (widget.initialAgeGroup == '18–24 Ay') _currentMonth = 20;
      if (widget.initialAgeGroup == '24–36 Ay') _currentMonth = 30;
    }

    _clinicalReport = _currentScenario.instruction;
    _setupVideoForScenario();
  }

  void _setupVideoForScenario() {
    final videoMap = _currentScenario.videoAssets;
    if (videoMap != null && videoMap.containsKey('node0')) {
      _initController(videoMap['node0']!);
    } else {
      _controller?.dispose();
      _controller = null;
      setState(() {});
    }
  }

  Future<void> _initController(String assetPath) async {
    final oldController = _controller;
    _controller = VideoPlayerController.asset(assetPath);

    try {
      await _controller!.initialize();
      _controller!.addListener(_videoListener);
      setState(() {});
    } catch (e) {
      debugPrint('Video yüklenirken hata: $e');
      _controller = null;
      setState(() {});
    }

    if (oldController != null) {
      await oldController.dispose();
    }
  }

  void _videoListener() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;

    // Node 0 tamamen bittiğinde karar ekranını aç
    if (_state == SimulationState.playingRoot) {
      if (pos >= dur) {
        _controller!.pause();
        setState(() {
          _state = SimulationState.waitingDecision;
        });
      }
    } else if (_state == SimulationState.playingBranch) {
      if (pos >= dur) {
        _controller!.pause();
        _finishSimulation();
      }
    }
  }

  void _startSimulation() {
    setState(() {
      _state = SimulationState.playingRoot;
      _selectedBranch = null;
      _latencyText = '-';
      _angleText = '-';
      _classificationText = '-';
      _classificationColor = const Color(0xFF0284C7);
      _clinicalReport = 'Öncül Uyaran Başlatıldı: ${_currentScenario.antecedent}';
    });

    if (_controller != null && _controller!.value.isInitialized) {
      _controller?.seekTo(Duration.zero);
      _controller?.play();
    } else {
      // Sentetik zaman akışı (video olmayan senaryolar için)
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _state == SimulationState.playingRoot) {
          setState(() {
            _state = SimulationState.waitingDecision;
          });
        }
      });
    }
  }

  Future<void> _selectBranch(ScenarioBranchModel branch) async {
    setState(() {
      _selectedBranch = branch;
      _state = SimulationState.playingBranch;
      _clinicalReport = 'Tepki Simüle Ediliyor: ${branch.details}';
    });

    final videoMap = _currentScenario.videoAssets;
    String? targetAsset;
    if (branch.level == 'YEŞİL') {
      targetAsset = videoMap?['green'];
    } else if (branch.level == 'SARI') {
      targetAsset = videoMap?['yellow'];
    } else if (branch.level == 'KIRMIZI') {
      targetAsset = videoMap?['red'];
    }

    if (targetAsset != null && targetAsset.isNotEmpty) {
      await _initController(targetAsset);
      await _controller?.seekTo(Duration.zero);
      _controller?.play();
    } else {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _state == SimulationState.playingBranch) {
          _finishSimulation();
        }
      });
    }
  }

  void _finishSimulation() {
    if (_selectedBranch == null) return;
    setState(() {
      _state = SimulationState.finished;
      _latencyText = _selectedBranch!.latency;
      _angleText = _selectedBranch!.level == 'YEŞİL'
          ? '≥ 45°'
          : _selectedBranch!.level == 'SARI'
              ? '25°–35°'
              : '< 10°';

      if (_selectedBranch!.level == 'YEŞİL') {
        _classificationText = 'Tipik';
        _classificationColor = const Color(0xFF10B981);
      } else if (_selectedBranch!.level == 'SARI') {
        _classificationText = 'Takip';
        _classificationColor = const Color(0xFFF59E0B);
      } else if (_selectedBranch!.level == 'KIRMIZI') {
        _classificationText = 'Risk';
        _classificationColor = const Color(0xFFEF4444);
      } else {
        _classificationText = 'Tipik';
        _classificationColor = const Color(0xFF10B981);
      }

      _clinicalReport = _selectedBranch!.clinicalOutcome;
    });
  }

  void _resetSimulation() {
    _controller?.pause();
    _controller?.seekTo(Duration.zero);
    setState(() {
      _state = SimulationState.idle;
      _selectedBranch = null;
      _latencyText = '-';
      _angleText = '-';
      _classificationText = '-';
      _classificationColor = const Color(0xFF0284C7);
      _clinicalReport = _currentScenario.instruction;
    });
  }

  void _switchScenario(int index) {
    final all = ScenariosRepository.allScenarios;
    if (index >= 0 && index < all.length) {
      setState(() {
        _selectedScenarioIndex = index;
        _currentScenario = all[index];
        _state = SimulationState.idle;
        _selectedBranch = null;
        _latencyText = '-';
        _angleText = '-';
        _classificationText = '-';
        _classificationColor = const Color(0xFF0284C7);
        _clinicalReport = _currentScenario.instruction;
      });
      _setupVideoForScenario();
    }
  }

  void _openFullscreen(List<ScenarioBranchModel> branches) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenVideoScreen(
          controller: _controller!,
          simulationState: _state,
          branches: branches,
          scenarioCode: _currentScenario.code,
          title: _currentScenario.title.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim(),
          onStartSimulation: _startSimulation,
          onSelectBranchAsync: (branch) async {
            await _selectBranch(branch);
            return _controller;
          },
          onResetSimulation: _resetSimulation,
          onStateChanged: (newState) {
            setState(() {
              _state = newState;
            });
          },
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final selectedAge = _currentAgeGroupLabel;
    final branches = _currentScenario.getBranchesForAge(selectedAge);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'İnteraktif Davranış Simülatörü',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Gemini API Anahtarı',
            icon: const Icon(Icons.key_outlined, size: 20),
            onPressed: () => ApiKeyDialog.show(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // YAŞ SEÇİM KARTI (Sürüklemeli Slider)
            AgeSliderCard(
              currentMonth: _currentMonth,
              onChanged: (newMonth) {
                setState(() {
                  _currentMonth = newMonth;
                  _resetSimulation();
                });
              },
            ),
            const SizedBox(height: 12),

            // SENARYO SEÇİCİ KARTI (Design System Bottom Sheet)
            InkWell(
              onTap: () {
                ScenarioPickerSheet.show(
                  context,
                  selectedIndex: _selectedScenarioIndex,
                  onSelected: (newIdx) {
                    _switchScenario(newIdx);
                  },
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _currentScenario.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _currentScenario.title,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF64748B),
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // KLİNİK YÖNERGE KARTI
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF), // Blue-50
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFF1D4ED8), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Hedef Norm: $selectedAge',
                              style: const TextStyle(
                                color: Color(0xFF1D4ED8),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _currentScenario.category,
                                style: const TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _currentScenario.instruction,
                          style: const TextStyle(
                            color: Color(0xFF1E3A8A),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // VİDEO EKRANI & YÜZEN KONTROLLER
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _controller != null && _controller!.value.isInitialized
                          ? VideoPlayer(_controller!)
                          : Container(
                              color: const Color(0xFF0F172A),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _state == SimulationState.playingRoot || _state == SimulationState.playingBranch
                                        ? Icons.motion_photos_on_rounded
                                        : Icons.video_collection_outlined,
                                    color: Colors.blueAccent,
                                    size: 42,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _currentScenario.videoAssets != null
                                        ? 'Video Yükleniyor...'
                                        : 'Simülasyon Hazır (${_currentScenario.code})',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _state == SimulationState.playingRoot
                                        ? 'Sesleniliyor...'
                                        : _state == SimulationState.playingBranch
                                            ? 'Tepki Oynatılıyor...'
                                            : 'Başlatmak için dokunun',
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                    ),

                    // TAM EKRAN BUTONU (SAĞ ÜST) - Her aşamada doğrudan tam ekrana geçmeyi sağlar
                    if (_controller != null && _controller!.value.isInitialized)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: const Color(0xB30F172A),
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _openFullscreen(branches),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // YÜZEN ŞEFFAF KONTROL KAPSÜLÜ (ALT ORTA) - Karar anında gizlenir
                    if (_controller != null && _controller!.value.isInitialized && _state != SimulationState.waitingDecision)
                      Positioned(
                        bottom: 4,
                        child: FloatingVideoControls(
                          controller: _controller!,
                          onFullscreenToggle: () => _openFullscreen(branches),
                        ),
                      ),

                    // KARAR KATMANI OVERLAY (EKRANA ÇIKAN BUTONLAR - INDEX.HTML MANTIĞI)
                    if (_state == SimulationState.waitingDecision)
                      Positioned.fill(
                        child: _buildDecisionOverlay(branches),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // SİMÜLASYON BAŞLAT / SIFIRLA BUTONLARI
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _state == SimulationState.playingRoot || _state == SimulationState.playingBranch
                        ? null
                        : _startSimulation,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Simülasyonu Başlat'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _resetSimulation,
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF475569)),
                  label: const Text('Sıfırla', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // KLİNİK ANALİZ & SONUÇ PANELİ (Design System Kartı)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assessment_outlined, color: Color(0xFF0F172A), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Değerlendirme Sonucu',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _classificationColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _classificationColor.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_classificationText != '-') ...[
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: _classificationColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              _classificationText,
                              style: TextStyle(
                                color: _classificationColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFFF1F5F9), height: 20),

                  // 3'LÜ METRİK KARTLARI
                  Row(
                    children: [
                      _buildMetricTile('Tepki Süresi', _latencyText, Icons.timer_outlined),
                      const SizedBox(width: 8),
                      _buildMetricTile('Dönüş Açısı', _angleText, Icons.screen_rotation_outlined),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Çıkarım Açıklaması
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gözlem Özeti:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _clinicalReport,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF334155),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: const Color(0xFF64748B)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowingDot(Color color, {double size = 15}) {
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
            blurRadius: 9,
            spreadRadius: 1.5,
          ),
        ],
      ),
    );
  }

  // KARAR KATMANI OVERLAY & SEÇİM BUTONLARI (INDEX.HTML İLE BİREBİR ŞIK VE DENGELİ)
  Widget _buildDecisionOverlay(List<ScenarioBranchModel> branches) {
    return Container(
      color: const Color(0xF20F172A), // Slate 900
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tepkiyi Seçin (${_currentScenario.code})',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            const Text(
              'Gözlenen davranışı seçin:',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              children: branches.map((branch) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _buildChoiceCard(branch),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceCard(ScenarioBranchModel branch) {
    Color borderColor = const Color(0xFF10B981); // Emerald
    Color glowColor = const Color(0xFF10B981);
    Color hoverTint = const Color(0x1F10B981);

    if (branch.level == 'SARI') {
      borderColor = const Color(0xFFF59E0B); // Amber
      glowColor = const Color(0xFFF59E0B);
      hoverTint = const Color(0x1FF59E0B);
    } else if (branch.level == 'KIRMIZI') {
      borderColor = const Color(0xFFEF4444); // Red
      glowColor = const Color(0xFFEF4444);
      hoverTint = const Color(0x1FEF4444);
    }

    final cleanTitle = branch.title.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

    return Material(
      color: const Color(0xFF1E293B), // Slate 800
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _selectBranch(branch),
        splashColor: borderColor.withValues(alpha: 0.3),
        highlightColor: hoverTint,
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor.withValues(alpha: 0.65),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildGlowingDot(glowColor, size: 14),
              const SizedBox(height: 5),
              Text(
                cleanTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10.5,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
