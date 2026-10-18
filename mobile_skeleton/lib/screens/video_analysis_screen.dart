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
import 'institutions_screen.dart';

class VideoAnalysisScreen extends StatefulWidget {
  const VideoAnalysisScreen({super.key, this.pickVideo});

  /// Testlerde galeri yerine kontrollü seçim; normal kullanımda ImagePicker.
  final Future<XFile?> Function(ImageSource source)? pickVideo;

  @override
  State<VideoAnalysisScreen> createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends State<VideoAnalysisScreen> {
  final int _selectedCaseIndex = 0; // 0: Deniz Senaryosu
  VideoPlayerController? _controller;
  BehaviorFinding? _activeFinding;
  BehaviorFinding? _lastNonNullFinding;

  // Kontrol Çubuğu Otomatik Gizleme & Akıllı Konumlandırma
  bool _showControls = true;
  Timer? _controlsTimer;

  // Özel Video Yükleme Durumu
  bool _isCustomVideo = false;
  String? _customVideoName;

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
    _loadVideoForCurrentCase();
  }

  void _onVideoTick() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

    if (_isCustomVideo) {
      if (_activeFinding != null || _lastNonNullFinding != null) {
        setState(() {
          _activeFinding = null;
          _lastNonNullFinding = null;
        });
      }
      return;
    }

    final currentSec = _controller!.value.position.inSeconds;
    final findings = _clinicalCases[_selectedCaseIndex]['findings'] as List<BehaviorFinding>;

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

  Future<void> _loadVideoForCurrentCase() async {
    final oldController = _controller;
    if (oldController != null) {
      oldController.removeListener(_onVideoTick);
    }

    final currentCase = _clinicalCases[_selectedCaseIndex];
    final assetPath = currentCase['videoAsset'] as String;

    _controller = VideoPlayerController.asset(assetPath);
    try {
      await _controller!.initialize();
      _controller!.addListener(_onVideoTick);
      _showControls = true;
      _startHideControlsTimer();
      setState(() {});
    } catch (e) {
      debugPrint('Video oynatıcı yükleme hatası: $e');
    }

    if (oldController != null) {
      await oldController.dispose();
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picked = await (widget.pickVideo?.call(source) ??
          ImagePicker().pickVideo(source: source));
      if (picked != null) {
        final file = File(picked.path);
        final oldController = _controller;
        if (oldController != null) {
          oldController.removeListener(_onVideoTick);
        }

        _controller = VideoPlayerController.file(file);
        try {
          await _controller!.initialize();
          _controller!.addListener(_onVideoTick);
        } catch (e) {
          debugPrint('Video başlatma hatası: $e');
        }

        if (oldController != null) {
          await oldController.dispose();
        }

        setState(() {
          _isCustomVideo = true;
          _customVideoName = picked.name;
          _activeFinding = null;
          _lastNonNullFinding = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video yüklendi.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Video seçme hatası: $e');
    }
  }

  Future<void> _resetToDefaultVideo() async {
    setState(() {
      _isCustomVideo = false;
      _customVideoName = null;
      _activeFinding = null;
      _lastNonNullFinding = null;
    });
    await _loadVideoForCurrentCase();
  }

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
    if (_isCustomVideo) return;
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.seekTo(Duration(seconds: seconds));
      _controller!.play();

      final findings = _clinicalCases[_selectedCaseIndex]['findings'] as List<BehaviorFinding>;
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

  void _openFullscreen() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final currentCase = _clinicalCases[_selectedCaseIndex];
    final findings = _isCustomVideo
        ? <BehaviorFinding>[]
        : currentCase['findings'] as List<BehaviorFinding>;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenVideoScreen(
          controller: _controller!,
          title: _isCustomVideo
              ? '${_customVideoName ?? 'Yüklenen Video'} — analiz edilmedi'
              : 'Deniz — Örnek video',
          badgeColor: const Color(0xFF10B981),
          findings: findings,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentCase = _clinicalCases[_selectedCaseIndex];
    final findings = currentCase['findings'] as List<BehaviorFinding>;
    final bookmarks = currentCase['bookmarks'] as List<Map<String, dynamic>>;
    final level = currentCase['level'] as AwarenessLevel;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Video Analiz Modu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
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
                                child: const Center(
                                  child: CircularProgressIndicator(color: Colors.white),
                                ),
                              ),
                      ),

                      // DİNAMİK YÜZEN BİLDİRİM KAPSÜLÜ (KONTROLLER VARKEN YUKARIDA, YOKKEN EN ALTA İNER)
                      if (!_isCustomVideo) AnimatedPositioned(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        bottom: _showControls ? 58 : 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FindingNotificationPill(
                            finding: _lastNonNullFinding,
                            isVisible: _activeFinding != null,
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
                                onFullscreenToggle: _openFullscreen,
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

            // VİDEO YÜKLEME VE KAYNAK SEÇİMİ
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
                      _isCustomVideo ? 'Video Değiştir' : 'Video Yükle',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                if (_isCustomVideo) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Örnek Video',
                    icon: const Icon(Icons.restore_rounded, size: 20),
                    onPressed: _resetToDefaultVideo,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // ÖZEL VİDEO BİLGİSİ VEYA ZAMAN ÇİZELGESİ
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
                        _customVideoName ?? 'Video Yüklendi',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
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

            Text(
              _isCustomVideo
                  ? 'Seçtiğiniz video analiz edilmedi. Bu ekranda yalnızca '
                      'videoyu izleyebilirsiniz.'
                  : 'Örnek rapor — sabit örnek bulgulardır; '
                      'otomatik video analizi yapılmadı.',
              key: ValueKey(
                _isCustomVideo ? 'video-not-analyzed' : 'video-example-report',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (!_isCustomVideo) ...[
              // GENEL DEĞERLENDİRME KARTI (Traffic Light Pill)
              _buildResultCard(level, currentCase['summary'] as String),
              const SizedBox(height: 16),

              // AÇILIR-KAPANIR KANIT KARTLARI LİSTESİ (Expandable Accordion Cards)
              const Text(
                'Örnek rapordaki davranışlar',
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
                'Yetkili Çocuk Sağlığı ve Gelişim Merkezleri',
                style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
              ),
            ),
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
