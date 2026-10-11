import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class FloatingVideoControls extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback? onFullscreenToggle;
  final bool isFullscreen;

  const FloatingVideoControls({
    super.key,
    required this.controller,
    this.onFullscreenToggle,
    this.isFullscreen = false,
  });

  @override
  State<FloatingVideoControls> createState() => _FloatingVideoControlsState();
}

class _FloatingVideoControlsState extends State<FloatingVideoControls> {
  bool _isMuted = false;

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _replay5Seconds() {
    final current = widget.controller.value.position;
    final target = current - const Duration(seconds: 5);
    widget.controller.seekTo(target > Duration.zero ? target : Duration.zero);
  }

  void _forward5Seconds() {
    final current = widget.controller.value.position;
    final max = widget.controller.value.duration;
    final target = current + const Duration(seconds: 5);
    widget.controller.seekTo(target < max ? target : max);
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      widget.controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final position = value.position;
        final duration = value.duration;
        final isPlaying = value.isPlaying;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xDD0F172A), // 85% opacity slate
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Oynat / Duraklat
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 22,
                color: Colors.white,
                icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: () {
                  if (isPlaying) {
                    widget.controller.pause();
                  } else {
                    widget.controller.play();
                  }
                },
              ),

              // 5 Sn Geri
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: Colors.white70,
                tooltip: '5 sn Geri',
                icon: const Icon(Icons.replay_5_rounded),
                onPressed: _replay5Seconds,
              ),

              // 5 Sn İleri
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: Colors.white70,
                tooltip: '5 sn İleri',
                icon: const Icon(Icons.forward_5_rounded),
                onPressed: _forward5Seconds,
              ),

              const SizedBox(width: 4),

              // Zaman Sayacı
              Text(
                '${_formatDuration(position)} / ${_formatDuration(duration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),

              const SizedBox(width: 6),

              // Ses Aç / Kapa
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: _isMuted ? Colors.amberAccent : Colors.white70,
                icon: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                onPressed: _toggleMute,
              ),

              // Tam Ekran
              if (widget.onFullscreenToggle != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: Colors.white70,
                  icon: Icon(widget.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                  onPressed: widget.onFullscreenToggle,
                ),
            ],
          ),
        );
      },
    );
  }
}
