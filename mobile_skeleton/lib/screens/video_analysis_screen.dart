import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../models/models.dart';
import '../widgets/floating_video_controls.dart';
import '../widgets/expandable_finding_card.dart';
import '../widgets/fullscreen_video_screen.dart';
import '../widgets/api_key_dialog.dart';
import '../widgets/finding_notification_pill.dart';
import '../services/server_api_service.dart';
import '../services/d01_pilot_service.dart';
import '../widgets/d01_pilot_panel.dart';
import 'institutions_screen.dart';

class VideoAnalysisScreen extends StatefulWidget {
  final Future<XFile?> Function(ImageSource)? pickVideo;
  final ValueNotifier<bool>? tabVisibility;
  final dynamic analysisService;
  final bool experimentalD01;
  final D01PilotApi? pilotApi;
  final String initialPilotAccessKey;

  const VideoAnalysisScreen({
    super.key,
    this.pickVideo,
    this.tabVisibility,
    this.analysisService,
    this.experimentalD01 = false,
    this.pilotApi,
    this.initialPilotAccessKey = '',
  });

  @override
  State<VideoAnalysisScreen> createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends State<VideoAnalysisScreen> with WidgetsBindingObserver {
  final int _selectedCaseIndex = 0; // 0: Deniz Senaryosu
  VideoPlayerController? _controller;
  bool _isAnalyzing = false;
  BehaviorFinding? _activeFinding;
  BehaviorFinding? _lastNonNullFinding;

  // Kontrol Çubuğu Otomatik Gizleme & Akıllı Konumlandırma
  bool _showControls = true;
  Timer? _controlsTimer;
  final _previewKey = GlobalKey();
  int _pilotSeekRequest = 0;

  // Özel Video Yükleme Durumu
  bool _isCustomVideo = false;
  String? _customVideoName;
  File? _customVideoFile;
  bool _customAnalysisDone = false;
  List<BehaviorFinding> _customFindings = [];
  String? _customSummary;
  AwarenessLevel _customLevel = AwarenessLevel.yellow;
  bool _openingVideo = false;
  String? _videoOpenError;
  int _selectionRequest = 0;
  int _analysisRequest = 0;
  final Set<VideoPlayerController> _pendingCandidates = {};
  final Map<VideoPlayerController, Future<void>> _candidateDisposals = {};
  final Map<VideoPlayerController, Completer<void>> _candidateInvalidations = {};

  void _startHideControlsTimer() {
    _controlsTimer?.cancel();
    if (_controller != null && _controller!.value.isPlaying) {
      _controlsTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted && _controller != null && _controller!.value.isPlaying) {
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

  List<Map<String, dynamic>> get _clinicalCases => [
    {
      'title': 'Deniz — Doğal Gözlem Kaydı',
      'videoAsset': 'assets/videos/Deniz_Senaryo_Kurtarilan.mp4',
      'level': AwarenessLevel.yellow,
      'summary':
          'Video kaydında çocuğun ilk bölümlerde isme yönelim ve sosyal gülümsemesi tipik normlarda izlenirken; 65. saniyede kısa süreli göz teması (takip) ve 88. saniyede tekrarlayıcı motor hareket (risk) bulguları saptanmıştır. Gelişimsel göstergeler zaman çizelgesine işlenmiştir.',
      'findings': [
        const BehaviorFinding(
          code: 'ONT-01',
          name: 'İsme Tepki',
          detected: true,
          latencySec: 1.8,
          evidenceTimeframe: '00:05 – 00:09',
          level: AwarenessLevel.green,
          explanation: 'Seslenme sonrasında baş ses yönüne dönmüş ve göz teması kurulmuştur.',
        ),
        const BehaviorFinding(
          code: 'ONT-06',
          name: 'Sosyal Gülümseme',
          detected: true,
          latencySec: 1.0,
          evidenceTimeframe: '00:18 – 00:22',
          level: AwarenessLevel.green,
          explanation: 'Göz teması ile eş zamanlı tebessüm ve olumlu duygulanım paylaşımı gerçekleşmiştir.',
        ),
        const BehaviorFinding(
          code: 'ONT-02',
          name: 'Ortak Dikkate Yanıt',
          detected: true,
          latencySec: 2.1,
          evidenceTimeframe: '00:42 – 00:46',
          level: AwarenessLevel.green,
          explanation: 'İşaret edilen nesneye bakış yönlendirilmiş ve odaklanma sağlanmıştır.',
        ),
        const BehaviorFinding(
          code: 'ONT-03',
          name: 'Kısa Süreli Göz Teması',
          detected: true,
          latencySec: 3.1,
          evidenceTimeframe: '01:05 – 01:10',
          level: AwarenessLevel.yellow,
          explanation: 'Klinisyenin yeni yönergesinde göz teması 0.9 sn ile sınırlı kalmış, bakış hızla çevredeki nesnelere kaymıştır (Takip önerilir).',
        ),
        const BehaviorFinding(
          code: 'ONT-12',
          name: 'Tekrarlayıcı Motor Hareket',
          detected: true,
          latencySec: null,
          evidenceTimeframe: '01:28 – 01:33',
          level: AwarenessLevel.red,
          explanation: 'Oyun esnasında parmak uçlarında ritmik hareket ve nesneyi kendi ekseninde stereotipik döndürme saptanmıştır.',
        ),
      ],
      'bookmarks': [
        {'timeSec': 5, 'label': '00:05 İsme Tepki', 'color': Color(0xFF10B981)},
        {'timeSec': 18, 'label': '00:18 Gülümseme', 'color': Color(0xFF10B981)},
        {'timeSec': 42, 'label': '00:42 Ortak Dikkat', 'color': Color(0xFF10B981)},
        {'timeSec': 65, 'label': '01:05 Göz Teması', 'color': Color(0xFFF59E0B)},
        {'timeSec': 88, 'label': '01:28 Motor Örüntü', 'color': Color(0xFFEF4444)},
      ]
    },
    {
      'title': 'Gecikmeli Tepki / Takip Gerektiren Vaka',
      'videoAsset': 'assets/videos/branch_yellow.mp4',
      'level': AwarenessLevel.yellow,
      'summary':
          'Yapılan analizde, çocuğun 1. seslenişte tepki vermediği, 2. sesleniş sonrasında gecikmeyle kısa süreli göz teması kurduğu gözlenmiştir. Nesne odaklanması yüksek seyretmektedir; gelişimsel periyodik takip önerilir.',
      'findings': [
        const BehaviorFinding(
          code: 'ONT-01',
          name: 'Gecikmeli İsme Tepki',
          detected: true,
          latencySec: 3.2,
          evidenceTimeframe: '00:03 – 00:07',
          level: AwarenessLevel.yellow,
          explanation: '1. seslenişe yanıtsızlık, 2. seslenişte 3.2 sn gecikmeli ve zayıf (28° açı) baş dönüşü.',
        ),
        const BehaviorFinding(
          code: 'ONT-03',
          name: 'Kısa Süreli Göz Teması',
          detected: true,
          latencySec: 2.8,
          evidenceTimeframe: '00:12 – 00:15',
          level: AwarenessLevel.yellow,
          explanation: 'Klinisyenle kurulan göz teması 0.8 sn sürmüş, bakış hızla yerdeki bloklara kaymıştır.',
        ),
        const BehaviorFinding(
          code: 'ONT-04',
          name: 'Nesneye Aşırı Odaklanma',
          detected: true,
          latencySec: null,
          evidenceTimeframe: '00:22 – 00:30',
          level: AwarenessLevel.yellow,
          explanation: 'Sosyal etkileşim yerine oyuncağın tekerlek mekanizmasına uzun süreli odaklanma.',
        ),
      ],
      'bookmarks': [
        {'timeSec': 3, 'label': '00:03 Gecikmeli İsim', 'color': Color(0xFFF59E0B)},
        {'timeSec': 12, 'label': '00:12 Kısa Bakış', 'color': Color(0xFFF59E0B)},
        {'timeSec': 22, 'label': '00:22 Nesne Odağı', 'color': Color(0xFFF59E0B)},
      ]
    },
    {
      'title': 'Atipik Tepki / İnceleme Gerektiren Vaka',
      'videoAsset': 'assets/videos/branch_red.mp4',
      'level': AwarenessLevel.red,
      'summary':
          'Yapılan analizde, 3 kez tekrarlanan işitsel uyarana karşın baş çevirme veya göz teması gerçekleşmemiştir (Δt > 5.0 sn). Aynı zamanda tekrarlayıcı nesne döndürme ve ortak dikkat başlatmama bulguları saptanmıştır. Çocuk Ruh Sağlığı uzmanı değerlendirmesi tavsiye edilir.',
      'findings': [
        const BehaviorFinding(
          code: 'ONT-01',
          name: 'İsme Tepkisizlik (Tepki Yok)',
          detected: false,
          latencySec: 5.5,
          evidenceTimeframe: '00:02 – 00:08',
          level: AwarenessLevel.red,
          explanation: '3 kez yüksek sesli uyaran verilmesine rağmen baş açısı değişmemiştir (ΔYaw < 8°).',
        ),
        const BehaviorFinding(
          code: 'ONT-04',
          name: 'Tekrarlayıcı Tekerlek Çevirme',
          detected: true,
          latencySec: null,
          evidenceTimeframe: '00:10 – 00:25',
          level: AwarenessLevel.red,
          explanation: 'Araba tekerleğini parmak ucuyla sürekli döndürme ve stereotipik hareket örüntüsü saptandı.',
        ),
        const BehaviorFinding(
          code: 'ONT-02',
          name: 'Ortak Dikkate Katılmama (IJA/RJA)',
          detected: false,
          latencySec: null,
          evidenceTimeframe: '00:26 – 00:35',
          level: AwarenessLevel.red,
          explanation: 'Klinisyenin işaret ettiği nesneye bakış yönlendirilmemiş, sosyal paylaşım oluşmamıştır.',
        ),
      ],
      'bookmarks': [
        {'timeSec': 2, 'label': '00:02 Tepkisizlik', 'color': Color(0xFFEF4444)},
        {'timeSec': 10, 'label': '00:10 Tekerlek Çevirme', 'color': Color(0xFFEF4444)},
        {'timeSec': 26, 'label': '00:26 Ortak Dikkat Yok', 'color': Color(0xFFEF4444)},
      ]
    },
  ];

  @override
  void initState() {
    super.initState();
    if (widget.experimentalD01) {
      WidgetsBinding.instance.addObserver(this);
    }
    widget.tabVisibility?.addListener(_tabVisibilityChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.experimentalD01) {
        _loadVideoForCurrentCase();
      }
    });
  }

  @override
  void didUpdateWidget(covariant VideoAnalysisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabVisibility != widget.tabVisibility) {
      oldWidget.tabVisibility?.removeListener(_tabVisibilityChanged);
      widget.tabVisibility?.addListener(_tabVisibilityChanged);
      _tabVisibilityChanged();
    }
  }

  void _tabVisibilityChanged() {
    if (!mounted || (widget.tabVisibility?.value ?? true)) {
      return;
    }
    _controlsTimer?.cancel();
    final controller = _controller;
    if (controller != null && controller.value.isInitialized && controller.value.isPlaying) {
      unawaited(controller.pause().catchError((Object _) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.experimentalD01 && state != AppLifecycleState.resumed) {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.pause().catchError((Object _) {}));
      }
    }
  }

  void _onVideoTick() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

    if (!_isCustomVideo || !_customAnalysisDone) {
      if (_activeFinding != null) {
        setState(() => _activeFinding = null);
      }
      return;
    }

    final currentSec = _controller!.value.position.inSeconds;
    final findings = _customFindings;

    BehaviorFinding? matched;
    for (final f in findings) {
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

  Future<bool> _openCandidate(VideoPlayerController candidate, int request, {
    required bool custom,
    String? name,
    File? file,
  }) async {
    for (final pending in _pendingCandidates.toList()) {
      final invalidation = _candidateInvalidations[pending];
      if (invalidation != null && !invalidation.isCompleted) {
        invalidation.complete();
      }
      unawaited(_disposePendingCandidate(pending));
    }
    _pendingCandidates.add(candidate);
    final invalidated = Completer<void>();
    _candidateInvalidations[candidate] = invalidated;
    if (mounted && request == _selectionRequest) {
      setState(() { _openingVideo = true; _videoOpenError = null; });
    }
    try {
      await Future.any<void>([candidate.initialize(), invalidated.future]);
      if (!mounted || request != _selectionRequest || invalidated.isCompleted) {
        await _disposePendingCandidate(candidate);
        return false;
      }
      final oldController = _controller;
      oldController?.removeListener(_onVideoTick);
      candidate.addListener(_onVideoTick);
      _pendingCandidates.remove(candidate);
      setState(() {
        _controller = candidate;
        _isCustomVideo = custom;
        _customVideoName = name;
        _customVideoFile = file;
        _customAnalysisDone = false;
        _customFindings = [];
        _customSummary = null;
        _activeFinding = null;
        _lastNonNullFinding = null;
        _isAnalyzing = false;
        _openingVideo = false;
        _videoOpenError = null;
        ++_analysisRequest;
      });
      if (oldController != null) {
        try { await oldController.dispose(); } catch (_) {
          debugPrint('Önceki video oynatıcı kapatılamadı.');
        }
      }
      if (!mounted || request != _selectionRequest || !identical(_controller, candidate)) {
        return false;
      }
      return true;
    } catch (_) {
      await _disposePendingCandidate(candidate);
      if (mounted && request == _selectionRequest) {
        final error = custom ? 'Video açılamadı' : 'Örnek video açılamadı';
        final previousKept = _controller?.value.isInitialized == true
            ? '. Önceki video korundu.'
            : '.';
        setState(() {
          _openingVideo = false;
          _videoOpenError = '$error$previousKept';
        });
      }
      return false;
    } finally {
      _candidateInvalidations.remove(candidate);
    }
  }

  Future<void> _disposePendingCandidate(VideoPlayerController candidate) async {
    final existingDisposal = _candidateDisposals[candidate];
    if (existingDisposal != null) {
      await existingDisposal;
      return;
    }
    if (!_pendingCandidates.remove(candidate)) return;
    final disposal = _disposeCandidate(candidate);
    _candidateDisposals[candidate] = disposal;
    await disposal;
  }

  Future<void> _disposeCandidate(VideoPlayerController candidate) async {
    try {
      await candidate.dispose();
    } catch (_) {
      // Aday zaten kapanmış olabilir; çalışan oynatıcı korunur.
    }
  }

  Future<void> _loadVideoForCurrentCase() async {
    final request = ++_selectionRequest;
    final currentCase = _clinicalCases[_selectedCaseIndex];
    final assetPath = currentCase['videoAsset'] as String;
    await _openCandidate(VideoPlayerController.asset(assetPath), request, custom: false);
  }

  Future<void> _pickVideo(ImageSource source) async {
    final request = ++_selectionRequest;
    try {
      final picked = await (widget.pickVideo?.call(source) ??
          ImagePicker().pickVideo(source: source));
      if (picked == null || !mounted || request != _selectionRequest) return;
      final file = File(picked.path);
      final opened = await _openCandidate(VideoPlayerController.file(file), request,
        custom: true, name: picked.name, file: file);
      if (!opened || !mounted || request != _selectionRequest) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video açıldı.'), behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2)),
      );
    } catch (_) {
      if (mounted && request == _selectionRequest) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video seçilemedi. Mevcut videonuz korundu; tekrar deneyin.')),
        );
      }
    }
  }

  Future<void> _resetToDefaultVideo() async {
    await _loadVideoForCurrentCase();
  }
  void _showVideoSourceSheet() {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Video Kaynağı',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('video-source-close'),
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF0F172A)),
                  title: const Text('Galeri', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickVideo(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined, color: Color(0xFF0F172A)),
                  title: const Text('Kamera', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickVideo(ImageSource.camera);
                  },
                ),
                if (_isCustomVideo && !widget.experimentalD01) ...[
                  const Divider(height: 16),
                  ListTile(
                    leading: const Icon(Icons.restore_outlined, color: Color(0xFF0F172A)),
                    title: const Text('Örnek Video', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _resetToDefaultVideo();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _seekToSecond(int seconds) {
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.seekTo(Duration(seconds: seconds));
      _controller!.play();

      final findings = _isCustomVideo && _customAnalysisDone
          ? _customFindings
          : const <BehaviorFinding>[];
      BehaviorFinding? matched;
      for (final f in findings) {
        if (seconds >= f.startSec && seconds <= f.endSec) {
          matched = f;
          break;
        }
      }
      if (matched != null) {
        setState(() {
          _activeFinding = matched;
          _lastNonNullFinding = matched;
          _showControls = true;
        });
      } else {
        setState(() {
          _showControls = true;
        });
      }
      _startHideControlsTimer();
    }
  }

  Future<void> _runPipelineAnalysis() async {
    if (widget.experimentalD01) {
      return;
    }
    final file = _customVideoFile;
    final controller = _controller;
    if (!_isCustomVideo || file == null || controller?.value.isInitialized != true ||
        _isAnalyzing || _openingVideo) {
      return;
    }
    final request = ++_analysisRequest;
    setState(() { _isAnalyzing = true; });
    try {
      final aiResult = await ServerApiService.analyzeVideo(file);
      if (!mounted || request != _analysisRequest || !identical(controller, _controller) ||
          _customVideoFile?.path != file.path) {
        return;
      }
      final rawFindings = aiResult['findings'];
      if (rawFindings is! List) {
        throw const FormatException('Servis yanıtında bulgu listesi yok.');
      }
      if (aiResult['summary'] is! String || (aiResult['summary'] as String).trim().isEmpty) {
        throw const FormatException('Servis yanıtında açıklama yok.');
      }
      final parsedFindings = <BehaviorFinding>[];
      for (final item in rawFindings) {
        if (item is! Map || item['code'] is! String || item['name'] is! String ||
            item['detected'] is! bool || item['evidenceTimeframe'] is! String ||
            item['explanation'] is! String) {
          throw const FormatException('Servis yanıtındaki bulgu alanları eksik veya geçersiz.');
        }
        final levelValue = (item['level'] ?? '').toString().toLowerCase();
        final level = switch (levelValue) {
          'green' => AwarenessLevel.green,
          'yellow' => AwarenessLevel.yellow,
          'red' => AwarenessLevel.red,
          _ => AwarenessLevel.inconclusive,
        };
        parsedFindings.add(BehaviorFinding(
          code: item['code'] as String,
          name: item['name'] as String,
          detected: item['detected'] as bool,
          latencySec: item['latencySec'] is num ? (item['latencySec'] as num).toDouble() : null,
          evidenceTimeframe: item['evidenceTimeframe'] as String,
          level: level,
          explanation: item['explanation'] as String,
        ));
      }
      final overallValue = (aiResult['overallLevel'] ?? '').toString().toLowerCase();
      final overall = switch (overallValue) {
        'green' => AwarenessLevel.green,
        'yellow' => AwarenessLevel.yellow,
        'red' => AwarenessLevel.red,
        _ => AwarenessLevel.inconclusive,
      };
      setState(() {
        _customFindings = parsedFindings;
        _customSummary = aiResult['summary'] is String ? aiResult['summary'] as String : null;
        _customLevel = overall;
        _customAnalysisDone = true;
        _isAnalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucu yanıtı alındı; içerik ve davranış doğruluğu incelenmedi.'),
          behavior: SnackBarBehavior.floating),
      );
    } catch (_) {
      if (!mounted || request != _analysisRequest || !identical(controller, _controller)) return;
      setState(() { _isAnalyzing = false; _customAnalysisDone = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analiz yanıtı alınamadı veya beklenen biçimde değil. Örnek sonuç kullanılmadı.'),
          behavior: SnackBarBehavior.floating),
      );
    }
  }
  void _openFullscreen() {
    if (_openingVideo || _controller == null || !_controller!.value.isInitialized) return;
    final findings = _isCustomVideo && _customAnalysisDone
        ? _customFindings : const <BehaviorFinding>[];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenVideoScreen(
          controller: _controller!,
          title: _isCustomVideo ? (_customVideoName ?? 'Seçilen video') : 'Örnek video — analiz edilmedi',
          badgeColor: const Color(0xFF10B981),
          findings: findings,
        ),
      ),
    );
  }

  Future<void> _seekPilot(VideoPlayerController? expected, Duration target) async {
    final request = ++_pilotSeekRequest;
    final selection = _selectionRequest;
    final controller = _controller;
    if (_openingVideo || controller == null || !identical(controller, expected) || !controller.value.isInitialized ||
        target < Duration.zero || target >= controller.value.duration) {
      return;
    }
    bool current() => mounted && request == _pilotSeekRequest && selection == _selectionRequest &&
        identical(controller, _controller) && !_openingVideo && ModalRoute.of(context)?.isCurrent != false;
    try {
      await controller.pause();
      if (!current()) return;
      await controller.seekTo(target);
      if (!current()) return;
      _controlsTimer?.cancel();
      setState(() => _showControls = true);
      final previewContext = _previewKey.currentContext;
      if (previewContext != null && previewContext.mounted) {
        await Scrollable.ensureVisible(previewContext,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic,
          alignment: 0,
        );
      }
    } catch (_) {
      if (!mounted || !current()) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text('Aday zamanına gidilemedi. Yeniden deneyin.'),
      ));
    }
  }

  @override
  void dispose() {
    ++_pilotSeekRequest;
    WidgetsBinding.instance.removeObserver(this);
    ++_selectionRequest;
    ++_analysisRequest;
    widget.tabVisibility?.removeListener(_tabVisibilityChanged);
    _controlsTimer?.cancel();
    for (final candidate in _pendingCandidates.toList()) {
      final invalidation = _candidateInvalidations[candidate];
      if (invalidation != null && !invalidation.isCompleted) {
        invalidation.complete();
      }
      unawaited(_disposePendingCandidate(candidate));
    }
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pilotController = _controller;
    final hasServerResult = _isCustomVideo && _customAnalysisDone;
    final findings = hasServerResult ? _customFindings : const <BehaviorFinding>[];
    final bookmarks = hasServerResult
        ? _customFindings.map((finding) => <String, dynamic>{
            'timeSec': finding.startSec,
            'label': '${finding.evidenceTimeframe} ${finding.name}',
            'color': const Color(0xFF64748B),
          }).toList()
        : <Map<String, dynamic>>[];
    final level = hasServerResult ? _customLevel : AwarenessLevel.inconclusive;
    final summary = hasServerResult
        ? _customSummary!
        : _isCustomVideo
            ? 'Bu video için sunucu yanıtı bekleniyor.'
            : 'Örnek video analiz edilmedi.';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(widget.experimentalD01 ? 'D01 pilot' : 'Video Analizi', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [

          if (!widget.experimentalD01) IconButton(
            tooltip: 'Gemini API Anahtarı',
            icon: const Icon(Icons.key_outlined, size: 20),
            onPressed: () => ApiKeyDialog.show(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            if (!widget.experimentalD01)
              Card(
                child: ListTile(
                  key: const ValueKey('open-d01-pilot-analysis'),
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Deneysel D01 baş hareketi analizi'),
                  subtitle: const Text('Ekip aracı · Yalnız iki denetlenmiş video desteklenir.'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => VideoAnalysisScreen(
                      experimentalD01: true,
                      pilotApi: widget.pilotApi,
                      pickVideo: widget.pickVideo,
                      initialPilotAccessKey: widget.initialPilotAccessKey,
                    ),
                  )),
                ),
              ),

            if (!_isCustomVideo && !widget.experimentalD01)
              Container(
                key: const ValueKey('video-analysis-example-notice'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Örnek video — analiz edilmedi.'),
              ),


            // VİDEO EKRANI & YÜZEN KONTROLLER
            Container(
              key: _previewKey,
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _controller != null && _controller!.value.isInitialized
                            ? VideoPlayer(_controller!)
                            : Container(
                                color: const Color(0xFF0F172A),
                                child: Center(
                                  child: widget.experimentalD01 && !_openingVideo && _videoOpenError == null
                                      ? const Text('Önizleme için video seçin.', style: TextStyle(color: Colors.white))
                                      : _videoOpenError == null
                                      ? CircularProgressIndicator(
                                          key: ValueKey('video-opening-spinner'),
                                          color: Colors.white,
                                        )
                                      : Icon(
                                          Icons.error_outline_rounded,
                                          key: ValueKey('video-open-failed'),
                                          color: Colors.white,
                                          size: 36,
                                        ),
                                ),
                              ),
                      ),

                      // DİNAMİK YÜZEN BİLDİRİM KAPSÜLÜ (KONTROLLER VARKEN YUKARIDA, YOKKEN EN ALTA İNER)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        bottom: _showControls ? 58 : 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _customAnalysisDone && _lastNonNullFinding != null
                              ? FindingNotificationPill(
                                  finding: _lastNonNullFinding,
                                  isVisible: _activeFinding != null,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),

                      // YÜZEN ŞEFFAF KONTROL KAPSÜLÜ (OTOMATİK GİZLENİR / DOKUNUNCA AÇILIR)
                      if (_controller != null && _controller!.value.isInitialized)
                        Positioned(
                          bottom: 4,
                          left: widget.experimentalD01 ? 0 : null,
                          right: widget.experimentalD01 ? 0 : null,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeInOut,
                            opacity: _showControls ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !_showControls,
                              child: FloatingVideoControls(
                                controller: _controller!,
                                wrapControls: widget.experimentalD01,
                                onFullscreenToggle: _openingVideo ? null : _openFullscreen,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_openingVideo)
              const LinearProgressIndicator(key: ValueKey('video-opening')),
            const SizedBox(height: 12),

            // VİDEO YÜKLEME VE KAYNAK SEÇİMİ
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('video-source-button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    onPressed: _showVideoSourceSheet,
                    icon: Icon(
                      _isCustomVideo ? Icons.sync_rounded : Icons.upload_file_outlined,
                      size: 18,
                      color: const Color(0xFF0F172A),
                    ),
                    label: Text(
                      _isCustomVideo ? 'Video Değiştir' : 'Video seç',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                if (_isCustomVideo && !widget.experimentalD01) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const ValueKey('video-reset-example'),
                    tooltip: 'Örnek Video',
                    icon: const Icon(Icons.restore_rounded, size: 20),
                    onPressed: _resetToDefaultVideo,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // ÖZEL VİDEO BİLGİSİ VEYA ZAMAN ÇİZELGESİ
            if (_isCustomVideo && !_customAnalysisDone) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.video_file_outlined, color: Color(0xFF0F172A), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _customVideoName ?? 'Video Yüklendi',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else if (bookmarks.isNotEmpty) ...[
              // BÖLÜMLENDİRİLMİŞ ZAMAN ÇİZELGESİ (Bölüm İmleri / Bookmarks)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bookmarks_outlined, size: 16, color: Color(0xFF64748B)),
                            SizedBox(width: 6),
                            Text(
                              'Önemli Anlar',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${bookmarks.length} Kanıt Noktası',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // TIKLANABİLİR ZAMAN DAMGALARI
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: bookmarks.map((b) {
                        final timeSec = b['timeSec'] as int;
                        final label = b['label'] as String;
                        final color = b['color'] as Color;

                        return Material(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _seekToSecond(timeSec),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: color.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.play_circle_fill_rounded, size: 14, color: color),
                                  const SizedBox(width: 5),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ANALİZ YÜRÜT BUTONU
            if (widget.experimentalD01) ...[
              if (_videoOpenError != null) Text(_videoOpenError!, key: const ValueKey('video-open-error')),
              D01PilotPanel(
                video: _customVideoFile, videoIdentity: _controller,
                duration: _controller?.value.duration ?? Duration.zero,
                openingVideo: _openingVideo, onSeek: (target) => _seekPilot(pilotController, target),
                api: widget.pilotApi ?? const HttpD01PilotApi(),
                initialAccessKey: widget.initialPilotAccessKey,
              ),
            ] else ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _isAnalyzing || _openingVideo || !_isCustomVideo || _customVideoFile == null
                  ? null : _runPipelineAnalysis,
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_graph_rounded),
              label: Text(
                _isAnalyzing
                    ? 'Sunucu yanıtı bekleniyor...'
                    : (_customAnalysisDone ? 'Yeniden analiz iste' : 'Seçilen videodan analiz iste'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),

            // ANALİZ SÜRECİ ADIMLARI
            if (_videoOpenError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_videoOpenError!, key: const ValueKey('video-open-error')),
                    if (_controller == null)
                      TextButton(
                        key: const ValueKey('video-retry-example'),
                        onPressed: _openingVideo ? null : _loadVideoForCurrentCase,
                        child: const Text('Örnek videoyu yeniden dene'),
                      ),
                  ],
                ),
              ),
            if (_isAnalyzing)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('İstek gönderildi. Sunucu bu ekranda aşama ilerlemesi bildirmiyor.'),
              ),

            if (hasServerResult) ...[
              // GENEL DEĞERLENDİRME KARTI (Traffic Light Pill)
              _buildResultCard(level, summary),
              const SizedBox(height: 16),

              // AÇILIR-KAPANIR KANIT KARTLARI LİSTESİ (Expandable Accordion Cards)
              Text(
                'Sunucu yanıtındaki davranışlar — doğrulanmadı',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),

              ...findings.map((f) {
                return ExpandableFindingCard(
                  finding: f,
                  onPlayEvidence: () => _seekToSecond(f.startSec),
                );
              }),
              const SizedBox(height: 16),
            ],

            // YETKİLİ MERKEZLER BUTONU
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const InstitutionsScreen()),
                );
              },
              icon: const Icon(Icons.local_hospital_outlined, color: Color(0xFF0F172A)),
              label: const Text(
                'Kurum bilgileri',
                style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
              ),
            ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(AwarenessLevel level, String summary) {
    Color cardColor = const Color(0xFF10B981); // Emerald
    Color cardBg = const Color(0xFFECFDF5);
    Color borderColor = const Color(0xFFA7F3D0);
    IconData iconData = Icons.verified_rounded;

    if (level == AwarenessLevel.yellow) {
      cardColor = const Color(0xFFD97706);
      cardBg = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFDE68A);
      iconData = Icons.warning_amber_rounded;
    } else if (level == AwarenessLevel.red) {
      cardColor = const Color(0xFFDC2626);
      cardBg = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFFECACA);
      iconData = Icons.priority_high_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, color: cardColor, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _friendlyResultTitle(level),
                  style: TextStyle(color: cardColor, fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            summary,
            style: const TextStyle(color: Color(0xFF334155), fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }

  String _friendlyResultTitle(AwarenessLevel level) {
    switch (level) {
      case AwarenessLevel.green:
        return 'Gelişimsel Normlara Uygun (Risk Saptanmadı)';
      case AwarenessLevel.yellow:
        return 'Gelişimsel Takip Önerilir (Sınırda Tepki)';
      case AwarenessLevel.red:
        return 'Uzman Değerlendirmesi Önerilir (Klinik İnceleme)';
      case AwarenessLevel.inconclusive:
        return 'Yetersiz Görüntü (Yeniden Çekim Gerekli)';
    }
  }
}
