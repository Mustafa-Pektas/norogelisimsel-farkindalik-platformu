import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/clip_video_store.dart';

/// Tek uygulama kopyasının önizlemesi; eşleme veya gözlem kaydını değiştirmez.
class ClipVideoPreviewScreen extends StatefulWidget {
  const ClipVideoPreviewScreen({
    super.key,
    required this.binding,
    required this.videoStore,
  });

  final ClipVideoBinding binding;
  final ClipVideoStore videoStore;

  @override
  State<ClipVideoPreviewScreen> createState() => _ClipVideoPreviewScreenState();
}

class _ClipVideoPreviewScreenState extends State<ClipVideoPreviewScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (!await widget.videoStore.fileExists(widget.binding)) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Video dosyası bulunamadı. Kayıtlı eşleme korunuyor.';
          });
        }
        return;
      }
      final file = await widget.videoStore.fileFor(widget.binding);
      if (!mounted) return;
      final controller = VideoPlayerController.file(file);
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      setState(() { _loading = false; });
      // initialize oynatmayı başlatmaz; yalnız kullanıcı Oynat'a basar.
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Video açılamadı. Dosya okunamıyor veya video biçimi '
              'desteklenmiyor olabilir. Kayıtlı eşleme korunuyor.';
        });
      }
    }
  }

  Future<void> _control({bool restart = false}) async {
    final controller = _controller;
    if (_busy || controller == null || !controller.value.isInitialized ||
        controller.value.hasError) {
      return;
    }
    setState(() { _busy = true; });
    try {
      if (restart) {
        await controller.pause();
        if (!mounted) return;
        await controller.seekTo(Duration.zero);
      } else if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Video oynatılamadı. Kayıtlı eşleme korunuyor.';
        });
      }
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  Future<void> _release(VideoPlayerController controller) async {
    try {
      // dispose zamanlayıcıyı ve native oynatıcıyı kapatarak oynatmayı da
      // sonlandırır. Video initialize olayını beklemeyi gerektirmez.
      await controller.dispose();
    } catch (_) {
      debugPrint('Klip önizlemesi oynatıcısı kapatılırken hata oluştu.');
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_release(controller));
    super.dispose();
  }

  Widget _errorMessage(String message) => Text(
    message,
    key: const ValueKey('clip-preview-error'),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: const Text('Klip önizlemesi'),
      backgroundColor: const Color(0xFF142540),
      foregroundColor: Colors.white,
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.binding.fileName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('İncelenmedi: videonun açılması davranış, süre veya '
                'süreklilik doğrulaması değildir.'),
            const SizedBox(height: 16),
            if (_error != null)
              _errorMessage(_error!)
            else if (_loading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Video yükleniyor…'),
                  ],
                ),
              )
            else if (_controller case final VideoPlayerController controller)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  if (value.hasError) {
                    return _errorMessage('Video oynatılamadı. '
                        'Kayıtlı eşleme korunuyor.');
                  }
                  return Column(
                    children: [
                      AspectRatio(
                        key: const ValueKey('clip-preview-aspect'),
                        aspectRatio: value.aspectRatio,
                        child: VideoPlayer(controller),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('clip-preview-play-pause'),
                            onPressed: _busy ? null : () => _control(),
                            icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                            label: Text(value.isPlaying ? 'Duraklat' : 'Oynat'),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('clip-preview-restart'),
                            onPressed: _busy ? null : () => _control(restart: true),
                            icon: const Icon(Icons.replay),
                            label: const Text('Başa dön'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}
