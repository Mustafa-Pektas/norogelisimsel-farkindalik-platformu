import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../widgets/floating_video_controls.dart';
import '../widgets/fullscreen_video_screen.dart';
import '../models/video_analysis.dart';
import '../models/behavior_cards.dart';
import '../services/video_analysis_service.dart';
import 'institutions_screen.dart';

class VideoAnalysisScreen extends StatefulWidget {
  const VideoAnalysisScreen({super.key, this.pickVideo, this.tabVisibility,
    this.analysisService = const UnavailableVideoAnalysisService()});

  final VideoAnalysisService analysisService;

  /// Yalnız Home sekmesinin görünürlüğü; tek başına açıldığında görünürdür.
  final ValueListenable<bool>? tabVisibility;

  /// Testlerde galeri yerine kontrollü seçim; normal kullanımda ImagePicker.
  final Future<XFile?> Function(ImageSource source)? pickVideo;

  @override
  State<VideoAnalysisScreen> createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends State<VideoAnalysisScreen> {
  static const _exampleVideoAsset = 'assets/videos/Deniz_Senaryo_Kurtarilan.mp4';
  VideoPlayerController? _controller;

  // Kontrol Çubuğu Otomatik Gizleme & Akıllı Konumlandırma
  bool _showControls = true;
  Timer? _controlsTimer;

  // Seçilen video durumu
  bool _isCustomVideo = false;
  String? _customVideoName;
  bool _openingVideo = false;
  String? _videoError;
  int _selectionRequest = 0;
  int _openRequest = 0;
  Completer<void>? _cancelOpen;
  final _candidates = <VideoPlayerController>{};
  final _releases = <VideoPlayerController, Future<void>>{};
  final _ageText = TextEditingController();
  int? _ageMonths;
  String? _ageError;
  static int _videoSequence = 0;
  static int _analysisSequence = 0;
  String? _videoId;
  String? _videoSource;
  VideoSourceKind? _videoSourceKind;
  VideoAnalysisRequest? _analysisRequest;
  VideoAnalysisResult? _analysisResult;
  VideoAnalysisPhase? _analysisPhase;
  String? _analysisError;
  bool _analysisBusy = false;
  bool _cancellingAnalysis = false;
  int _analysisGeneration = 0;
  VideoAnalysisJob? _analysisJob;
  StreamSubscription<VideoAnalysisEvent>? _analysisSubscription;
  final _closingAnalysisJobs = Expando<bool>();

  Future<void> _closeAnalysisJob(VideoAnalysisJob job, {required bool cancel}) async {
    if (_closingAnalysisJobs[job] == true) return;
    _closingAnalysisJobs[job] = true;
    try {
      if (cancel) {
        // Yerel kaynak kapatma uzak bir iptal cevabını beklemez.
        unawaited(job.cancel().catchError((Object error) {
          debugPrint('Analiz işi iptal edilirken hata oluştu.');
        }));
      }
    } catch (_) {
      debugPrint('Analiz işi iptal edilirken hata oluştu.');
    } finally {
      try {
        await job.dispose();
      } catch (_) {
        debugPrint('Analiz kaynakları kapatılamadı.');
      }
    }
  }

  void _detachAnalysis({bool cancel = true}) {
    ++_analysisGeneration;
    final subscription = _analysisSubscription;
    _analysisSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object error) {
        debugPrint('Analiz dinleyicisi kapatılamadı.');
      }));
    }
    final job = _analysisJob;
    _analysisJob = null;
    if (job != null) {
      unawaited(_closeAnalysisJob(job, cancel: cancel && !_cancellingAnalysis));
    }
  }

  void _clearAnalysis() {
    _detachAnalysis();
    _analysisRequest = null;
    _analysisResult = null;
    _analysisPhase = null;
    _analysisError = null;
    _analysisBusy = false;
    _cancellingAnalysis = false;
  }

  void _finishAnalysisError(String message) {
    _detachAnalysis();
    setState(() {
      _analysisBusy = false;
      _analysisPhase = VideoAnalysisPhase.error;
      _analysisResult = null;
      _analysisError = message;
    });
  }

  void _startAnalysis() {
    final controller = _controller;
    if (_analysisBusy || _openingVideo || _ageError != null ||
        !widget.analysisService.isAvailable || controller == null ||
        !controller.value.isInitialized || _videoId == null) {
      return;
    }
    _clearAnalysis();
    final request = VideoAnalysisRequest(
      requestId: 'analysis-${++_analysisSequence}', videoId: _videoId!,
      sourceKind: _videoSourceKind!, source: _videoSource!,
      duration: controller.value.duration, ageMonths: _ageMonths,
    );
    final generation = _analysisGeneration;
    setState(() {
      _analysisRequest = request;
      _analysisBusy = true;
    });
    bool current() => mounted && generation == _analysisGeneration &&
        _videoId == request.videoId;
    try {
      final job = widget.analysisService.start(request);
      _analysisJob = job;
      _analysisSubscription = job.events.listen((event) {
        if (!current()) return;
        if (event.requestId != request.requestId) {
          _finishAnalysisError('Analiz bildirimi bu isteğe ait değil.');
          return;
        }
        if (event.phase == VideoAnalysisPhase.completed) {
          final result = event.result;
          if (result == null || result.requestId != request.requestId ||
              result.videoId != request.videoId) {
            _finishAnalysisError('Analiz sonucu bu videoya ait değil.');
            return;
          }
        }
        final terminal = event.phase != VideoAnalysisPhase.sending &&
            event.phase != VideoAnalysisPhase.processing;
        setState(() {
          _analysisPhase = event.phase;
          _analysisBusy = !terminal;
          _analysisError = event.phase == VideoAnalysisPhase.error
              ? (event.message ?? 'Analiz tamamlanamadı. Tekrar deneyebilirsiniz.') : null;
          _analysisResult = event.phase == VideoAnalysisPhase.completed ? event.result : null;
        });
        if (terminal) _detachAnalysis(cancel: false);
      }, onError: (Object error, StackTrace stack) {
        if (current()) _finishAnalysisError('Analiz sırasında hata oluştu. Tekrar deneyebilirsiniz.');
      }, onDone: () {
        if (current() && _analysisBusy) {
          _finishAnalysisError('Analiz bağlantısı sonuç gelmeden kapandı.');
        }
      });
    } catch (_) {
      if (current()) _finishAnalysisError('Analiz başlatılamadı. Tekrar deneyebilirsiniz.');
    }
  }

  Future<void> _cancelAnalysis() async {
    if (!_analysisBusy || _cancellingAnalysis) return;
    final job = _analysisJob;
    final subscription = _analysisSubscription;
    final generation = ++_analysisGeneration;
    _analysisSubscription = null;
    setState(() { _cancellingAnalysis = true; });
    try {
      // Nesil kontrolü geç bildirimleri zaten reddeder. Dinleyicinin
      // temizlenmesi hizmet iptalini veya yerel kaynak kapatmayı bekletmesin.
      if (subscription != null) {
        unawaited(subscription.cancel().catchError((Object error) {
          debugPrint('Analiz dinleyicisi kapatılamadı.');
        }));
      }
      if (job != null) await job.cancel();
      if (!mounted || generation != _analysisGeneration) return;
      setState(() {
        _analysisPhase = VideoAnalysisPhase.cancelled;
        _analysisBusy = false;
        _cancellingAnalysis = false;
        _analysisResult = null;
      });
    } catch (_) {
      if (!mounted || generation != _analysisGeneration) return;
      setState(() {
        _analysisPhase = VideoAnalysisPhase.error;
        _analysisBusy = false;
        _cancellingAnalysis = false;
        _analysisError = 'Sonuç takibi durduruldu; hizmetin iptali doğrulanamadı.';
      });
    } finally {
      if (identical(_analysisJob, job)) _analysisJob = null;
      if (job != null) unawaited(_closeAnalysisJob(job, cancel: false));
    }
  }

  Future<void> _showEvidence(AnalysisEvidence evidence) async {
    final controller = _controller;
    final videoId = _videoId;
    if (controller == null || _openingVideo ||
        _analysisRequest?.videoId != videoId ||
        !evidence.isValidFor(controller.value.duration)) {
      return;
    }
    try {
      await controller.pause();
      if (!mounted || videoId != _videoId || !identical(controller, _controller)) return;
      await controller.seekTo(Duration(
        microseconds: (evidence.startSeconds * Duration.microsecondsPerSecond).round()));
    } catch (_) {
      if (!mounted || videoId != _videoId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İlgili bölüm açılamadı. Tekrar deneyin.')));
    }
  }

  void _ageChanged(String value) {
    if (_controller?.value.isInitialized != true || _openingVideo) return;
    final text = value.trim();
    final parsed = RegExp(r'^[0-9]+$').hasMatch(text) ? int.tryParse(text) : null;
    setState(() {
      _clearAnalysis();
      _ageMonths = parsed != null && parsed >= 12 && parsed <= 36 ? parsed : null;
      _ageError = text.isEmpty || _ageMonths != null
          ? null
          : '12–36 arasında tam ay girin veya boş bırakın.';
    });
  }

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

  @override
  void initState() {
    super.initState();
    widget.tabVisibility?.addListener(_tabVisibilityChanged);
    unawaited(_loadExampleVideo());
  }

  bool get _tabVisible => widget.tabVisibility?.value ?? true;

  @override
  void didUpdateWidget(covariant VideoAnalysisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabVisibility != widget.tabVisibility) {
      oldWidget.tabVisibility?.removeListener(_tabVisibilityChanged);
      widget.tabVisibility?.addListener(_tabVisibilityChanged);
      _tabVisibilityChanged();
    }
    if (!identical(oldWidget.analysisService, widget.analysisService)) {
      _clearAnalysis();
    }
  }

  void _tabVisibilityChanged() {
    if (!mounted || _tabVisible) return; // Görünür olmak otomatik play yapmaz.
    _controlsTimer?.cancel();
    setState(() { _showControls = true; });
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      unawaited(_pauseHiddenVideo(controller));
    }
  }

  Future<void> _pauseHiddenVideo(VideoPlayerController controller) async {
    try {
      await controller.pause();
    } catch (_) {
      if (!mounted || !identical(_controller, controller)) return;
      setState(() {
        _videoError = 'Video duraklatılamadı. Tekrar deneyin.';
      });
    }
  }

  Future<void> _loadExampleVideo() async {
    if (!mounted) return;
    ++_selectionRequest;
    await _openCandidate(VideoPlayerController.asset(_exampleVideoAsset), isCustom: false);
  }

  Future<void> _release(VideoPlayerController controller) =>
      _releases.putIfAbsent(controller, () async {
        try {
          await controller.dispose();
        } catch (_) {
          debugPrint('Video oynatıcısı kapatılırken hata oluştu.');
        }
      });

  Future<void> _openCandidate(
    VideoPlayerController candidate, {
    required bool isCustom,
    String? fileName,
  }) async {
    final request = ++_openRequest;
    final previousCancel = _cancelOpen;
    if (previousCancel != null && !previousCancel.isCompleted) {
      previousCancel.complete();
    }
    for (final stale in _candidates.toList()) {
      unawaited(_release(stale));
    }
    final cancelled = Completer<void>();
    _cancelOpen = cancelled;
    _candidates.add(candidate);
    setState(() {
      _openingVideo = true;
      _videoError = null;
    });
    try {
      // dispose() bekleyen initialize Future'ını tamamlamak zorunda değildir.
      // Yeni seçim/ekran kapanışı bu beklemeyi de sonlandırır.
      await Future.any<void>([candidate.initialize(), cancelled.future]);
      if (!mounted || request != _openRequest || cancelled.isCompleted) return;
      if (!candidate.value.isInitialized || candidate.value.hasError) {
        throw StateError('Video başlatılamadı.');
      }
      if (!_tabVisible) {
        // Bekleyen açılış sekme dışında tamamlansa da oynatmayı başlatma.
        await candidate.pause();
        if (!mounted || request != _openRequest || cancelled.isCompleted) return;
      }
      final previous = _controller;
      _controlsTimer?.cancel();
      _candidates.remove(candidate);
      setState(() {
        _clearAnalysis();
        _controller = candidate;
        _videoId = 'video-${++_videoSequence}';
        _videoSource = candidate.dataSource;
        _videoSourceKind = isCustom ? VideoSourceKind.file : VideoSourceKind.asset;
        _isCustomVideo = isCustom;
        _customVideoName = fileName;
        // Yaş yalnız başarıyla açılan mevcut videoya aittir.
        _ageText.clear();
        _ageMonths = null;
        _ageError = null;
        _showControls = true;
        _openingVideo = false;
      });
      if (previous != null) {
        await _release(previous);
      }
      if (!mounted || request != _openRequest) return;
      if (isCustom) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video açıldı.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (!mounted || request != _openRequest) return;
      setState(() {
        _openingVideo = false;
        _videoError = isCustom
            ? 'Video açılamadı. Başka bir video seçip tekrar deneyin.'
            : 'Örnek video açılamadı. Bir video seçebilir veya yeniden deneyebilirsiniz.';
      });
    } finally {
      if (identical(_cancelOpen, cancelled)) {
        _cancelOpen = null;
      }
      if (_candidates.remove(candidate)) {
        await _release(candidate);
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    final request = ++_selectionRequest;
    try {
      final picked = await (widget.pickVideo?.call(source) ??
          ImagePicker().pickVideo(source: source));
      if (!mounted || request != _selectionRequest || picked == null) return;
      await _openCandidate(
        VideoPlayerController.file(File(picked.path)),
        isCustom: true,
        fileName: picked.name,
      );
    } catch (_) {
      if (!mounted || request != _selectionRequest) return;
      setState(() {
        _videoError = _controller == null
            ? 'Video seçilemedi. Tekrar deneyin.'
            : 'Video seçilemedi. Mevcut videonuz korundu; tekrar deneyin.';
      });
    }
  }

  Future<void> _resetToDefaultVideo() => _loadExampleVideo();

  void _showVideoSourceSheet() {
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
                    const Text(
                      'Video Kaynağı',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
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
                if (_isCustomVideo) ...[
                  const Divider(height: 16),
                  ListTile(
                    leading: const Icon(Icons.restore_outlined, color: Color(0xFF0F172A)),
                    title: const Text('Örnek video', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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

  void _openFullscreen() {
    final controller = _controller;
    if (_openingVideo || controller == null || !controller.value.isInitialized) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenVideoScreen(
          controller: controller,
          title: _isCustomVideo
              ? '${_customVideoName ?? 'Seçilen video'}${_analysisResult == null ? ' — analiz edilmedi' : ''}'
              : 'Örnek video${_analysisResult == null ? ' — analiz edilmedi' : ''}',
          badgeColor: const Color(0xFF0F172A),
          findings: const [],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _detachAnalysis();
    widget.tabVisibility?.removeListener(_tabVisibilityChanged);
    ++_selectionRequest;
    ++_openRequest;
    final cancel = _cancelOpen;
    if (cancel != null && !cancel.isCompleted) {
      cancel.complete();
    }
    _controlsTimer?.cancel();
    _ageText.dispose();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(_release(controller));
    }
    for (final candidate in _candidates.toList()) {
      unawaited(_release(candidate));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Video Analizi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                                  child: _openingVideo
                                      ? const CircularProgressIndicator(color: Colors.white)
                                      : const Text('Video açılamadı.',
                                          style: TextStyle(color: Colors.white)),
                                ),
                              ),
                      ),

                      // YÜZEN ŞEFFAF KONTROL KAPSÜLÜ (OTOMATİK GİZLENİR / DOKUNUNCA AÇILIR)
                      if (_controller != null && _controller!.value.isInitialized)
                        Positioned(
                          bottom: 4,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeInOut,
                            opacity: _showControls ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !_showControls,
                              child: FloatingVideoControls(
                                controller: _controller!,
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
            const SizedBox(height: 12),

            const Text(
              'Videodaki sentetik karakterin yaşı (ay, isteğe bağlı)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('video-age-months'),
              controller: _ageText,
              enabled: _controller?.value.isInitialized == true && !_openingVideo && !_analysisBusy,
              keyboardType: const TextInputType.numberWithOptions(),
              textInputAction: TextInputAction.done,
              onChanged: _ageChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                labelText: 'Yaş (ay)',
                hintText: 'Bilinmiyor',
                border: const OutlineInputBorder(),
                errorText: _ageError,
                errorMaxLines: 6,
              ),
            ),
            if (_controller?.value.isInitialized != true)
              const Text('Yaş girmek için önce bir video açın.')
            else if (_ageError == null)
              Text(
                _ageMonths == null ? 'Yaş: Bilinmiyor' : 'Yaş: $_ageMonths ay',
                key: const ValueKey('video-age-summary'),
              ),
            Text(
              widget.analysisService.isAvailable
                  ? 'Girilen yaş kullanıcı beyanı olarak analiz isteğine eklenir. '
                      'Proje hedefi 12–36 aydır; tüm aralıkta analiz desteği doğrulanmadı.'
                  : 'Girilen yaş kullanıcı beyanıdır; henüz otomatik analizde kullanılmaz. '
                      'Proje hedefi 12–36 aydır; tüm aralıkta analiz desteği doğrulanmadı.',
              key: const ValueKey('video-age-note'),
            ),
            const SizedBox(height: 12),

            if (_videoError != null) ...[
              Text(_videoError!, key: const ValueKey('video-open-error')),
              if (_controller == null)
                OutlinedButton.icon(
                  key: const ValueKey('video-retry-example'),
                  onPressed: _openingVideo ? null : _loadExampleVideo,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Örnek videoyu yeniden dene'),
                ),
              const SizedBox(height: 12),
            ],
            if (_openingVideo && _controller != null) ...[
              const Text('Yeni video açılıyor…', key: ValueKey('video-opening')),
              const SizedBox(height: 12),
            ],

            // VİDEO VE KAYNAK SEÇİMİ
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
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
                      _isCustomVideo ? 'Video değiştir' : 'Video seç',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                if (_isCustomVideo) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Örnek video',
                    icon: const Icon(Icons.restore_rounded, size: 20),
                    onPressed: _resetToDefaultVideo,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // SEÇİLEN DOSYA BİLGİSİ
            if (_isCustomVideo) ...[
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
                        _customVideoName ?? 'Seçilen video',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            _buildAnalysis(),
            const SizedBox(height: 16),

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
                'Yetkili Çocuk Sağlığı ve Gelişim Merkezleri',
                style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysis() {
    final ready = _controller?.value.isInitialized == true;
    final service = widget.analysisService;
    final phaseLabel = switch (_analysisPhase) {
      VideoAnalysisPhase.sending => 'Gönderiliyor',
      VideoAnalysisPhase.processing => 'İşleniyor',
      VideoAnalysisPhase.completed => 'Tamamlandı',
      VideoAnalysisPhase.error => 'Hata',
      VideoAnalysisPhase.cancelled => 'İptal edildi',
      null => _analysisBusy ? 'Hizmet bildirimi bekleniyor' :
          !ready ? 'Video seçilmedi. Önce bir video açın.' :
          service.isAvailable ? 'Analize hazır' : 'Analiz hizmeti bağlı değil',
    };
    final result = _analysisResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!service.isAvailable && result == null && !_analysisBusy)
          const Text(
            'Bu video analiz edilmedi. Video seçip izleyebilirsiniz; '
            'otomatik analiz bağlantısı henüz tamamlanmadı.',
            key: ValueKey('video-not-analyzed'),
          ),
        Text(_cancellingAnalysis ? 'İptal bekleniyor' : phaseLabel,
          key: const ValueKey('video-analysis-status')),
        Text(service.scopeDescription),
        if (_analysisError != null)
          Text(_analysisError!, key: const ValueKey('video-analysis-error')),
        if (service.isAvailable) ...[
          FilledButton(
            key: const ValueKey('video-analysis-start'),
            onPressed: ready && !_openingVideo && !_analysisBusy && _ageError == null
                ? _startAnalysis : null,
            child: const Text('Analiz et'),
          ),
          if (_analysisBusy)
            OutlinedButton(
              key: const ValueKey('video-analysis-cancel'),
              onPressed: _cancellingAnalysis ? null : _cancelAnalysis,
              child: const Text('İptal et'),
            ),
        ],
        if (result != null) ...[
          const Text('Analiz sonuçları', style: TextStyle(fontWeight: FontWeight.bold)),
          if (result.findings.isEmpty)
            const Text('Hizmet bulgu döndürmedi; bu, davranışın gözlenmediği anlamına gelmez.'),
          for (final (index, finding) in result.findings.indexed)
            Card(
              key: ValueKey('video-analysis-finding-$index'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${_behaviorTitle(finding.behaviorId)} · Kart ${finding.cardVersion}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(finding.status.label),
                    Text(finding.explanation),
                    if (finding.confidence case final confidence? when confidence.isDescribed)
                      Text('Güven: ${confidence.value} (${confidence.scale})\n'
                        '${confidence.meaning} · Kaynak: ${confidence.source}'),
                    if (finding.evidence case final evidence?
                        when evidence.isValidFor(_controller!.value.duration)) ...[
                      Text('${evidence.startSeconds}–${evidence.endSeconds} saniye · '
                        '${evidence.timeSource}'),
                      OutlinedButton(
                        key: ValueKey('video-analysis-evidence-$index'),
                        onPressed: _openingVideo ? null : () => _showEvidence(evidence),
                        child: const Text('İlgili bölümü izle'),
                      ),
                    ] else
                      const Text('Geçerli zaman kanıtı yok.'),
                  ],
                ),
              ),
            ),
        ],
        // Yapısal sonuç taşınır; istemci baş hareketinden D01/klinik karar türetmez.
      ],
    );
  }

  String _behaviorTitle(String id) {
    for (final card in BehaviorCards.all) {
      if (card.id == id) return '${card.title} ($id)';
    }
    return id;
  }
}
