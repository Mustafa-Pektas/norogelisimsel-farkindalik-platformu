import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Source pixels, not preview pixels. No inferred or persisted annotations.
class D01Roi {
  const D01Roi(this.x, this.y, this.width, this.height);
  final int x, y, width, height;
  Map<String, int> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
  static Rect videoRect(Size viewport, Size source) {
    final scale = math.min(
      viewport.width / source.width,
      viewport.height / source.height,
    );
    final size = Size(source.width * scale, source.height * scale);
    return Rect.fromLTWH(
      (viewport.width - size.width) / 2,
      (viewport.height - size.height) / 2,
      size.width,
      size.height,
    );
  }

  static D01Roi? fromPreview(Rect selection, Size viewport, Size source) {
    if (source.isEmpty ||
        viewport.isEmpty ||
        !source.width.isFinite ||
        !source.height.isFinite ||
        !viewport.width.isFinite ||
        !viewport.height.isFinite) {
      return null;
    }
    final video = videoRect(viewport, source);
    final clipped = selection.intersect(video);
    if (clipped.isEmpty) {
      return null;
    }
    final left =
        (((clipped.left - video.left) / video.width * source.width) + 1e-7)
            .floor()
            .clamp(0, source.width.toInt())
            .toInt();
    final top =
        (((clipped.top - video.top) / video.height * source.height) + 1e-7)
            .floor()
            .clamp(0, source.height.toInt())
            .toInt();
    final right =
        (((clipped.right - video.left) / video.width * source.width) - 1e-7)
            .ceil()
            .clamp(0, source.width.toInt())
            .toInt();
    final bottom =
        (((clipped.bottom - video.top) / video.height * source.height) - 1e-7)
            .ceil()
            .clamp(0, source.height.toInt())
            .toInt();
    return right > left && bottom > top
        ? D01Roi(left, top, right - left, bottom - top)
        : null;
  }
}

class D01MarkedInput {
  const D01MarkedInput(this.roi, this.callStart, this.callEnd);
  final D01Roi roi;
  final Duration callStart, callEnd;
  bool validFor(Duration duration) =>
      roi.x >= 0 &&
      roi.y >= 0 &&
      roi.width > 0 &&
      roi.height > 0 &&
      callStart >= Duration.zero &&
      callEnd >= callStart &&
      callEnd <= duration;
}

/// Optional initial face point and manual call marks. Never a child classifier.
class D01FastInput {
  const D01FastInput({this.targetPoint, this.callStart, this.callEnd});
  final List<double>? targetPoint;
  final Duration? callStart, callEnd;
  bool validFor(Duration duration) {
    final point = targetPoint;
    return (point == null ||
            point.length == 2 &&
                point.every((v) => v.isFinite && v >= 0 && v <= 1)) &&
        ((callStart == null && callEnd == null) ||
            (callStart != null &&
                callEnd != null &&
                callStart! >= Duration.zero &&
                callEnd! >= callStart! &&
                callEnd! <= duration));
  }
}
