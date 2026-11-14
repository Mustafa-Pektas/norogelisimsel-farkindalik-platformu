import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:video_player/video_player.dart';

import '../models/d01_marked_input.dart';

class D01RoiPreview extends StatefulWidget {
  const D01RoiPreview({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onSelected,
    this.pointMode = false,
    this.onPointSelected,
  });
  final bool pointMode;
  final ValueChanged<List<double>?>? onPointSelected;
  final VideoPlayerController controller;
  final bool enabled;
  final ValueChanged<D01Roi?> onSelected;
  @override
  State<D01RoiPreview> createState() => _D01RoiPreviewState();
}

class _D01RoiPreviewState extends State<D01RoiPreview> {
  Offset? _start;
  Rect? _selection;
  Offset? _point;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      final source = widget.controller.value.size;
      if (source.isEmpty) {
        return const SizedBox.shrink();
      }
      final video = D01Roi.videoRect(viewport, source);
      return GestureDetector(
        key: const ValueKey('pilot-roi-canvas'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTapDown: !widget.enabled || !widget.pointMode
            ? null
            : (d) async {
                if (!video.contains(d.localPosition)) {
                  return;
                }
                final point = Offset(
                  (d.localPosition.dx - video.left) / video.width,
                  (d.localPosition.dy - video.top) / video.height,
                );
                try {
                  await widget.controller.pause();
                  if (widget.controller.value.position > const Duration(milliseconds: 42)) {
                    await widget.controller.seekTo(Duration.zero);
                    if (mounted) {
                      setState(() => _point = null);
                      widget.onPointSelected?.call(null);
                    }
                    return; // Re-tap the now visible FIRST frame, never reuse another frame's point.
                  }
                  await widget.controller.seekTo(Duration.zero);
                  if (!mounted) {
                    return;
                  }
                  setState(() => _point = point);
                  widget.onPointSelected?.call([point.dx, point.dy]);
                } catch (_) {
                  if (mounted) {
                    widget.onPointSelected?.call(null);
                  }
                }
              },
        onPanStart: !widget.enabled || widget.pointMode
            ? null
            : (d) async {
                _start = d.localPosition;
                setState(() => _selection = null);
                widget.onSelected(null);
                try {
                  await widget.controller.pause();
                } catch (_) {
                  _start = null;
                  if (mounted) {
                    widget.onSelected(null);
                  }
                }
              },
        onPanUpdate: !widget.enabled || widget.pointMode
            ? null
            : (d) {
                final start = _start;
                if (start != null) {
                  setState(
                    () => _selection = Rect.fromPoints(start, d.localPosition),
                  );
                }
              },
        onPanEnd: !widget.enabled || widget.pointMode
            ? null
            : (_) {
                final selection = _selection;
                widget.onSelected(
                  selection == null
                      ? null
                      : D01Roi.fromPreview(selection, viewport, source),
                );
              },
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: video,
              child: VideoPlayer(widget.controller),
            ),
            if (widget.pointMode && _point != null)
              Positioned(
                left: video.left + _point!.dx * video.width - 8,
                top: video.top + _point!.dy * video.height - 8,
                child: const IgnorePointer(
                  child: Icon(Icons.add_circle, size: 16, color: Colors.amber),
                ),
              ),
            if (_selection != null && !_selection!.intersect(video).isEmpty)
              Positioned.fromRect(
                rect: _selection!.intersect(video),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.amber, width: 3),
                      color: const Color(0x2288CCFF),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
