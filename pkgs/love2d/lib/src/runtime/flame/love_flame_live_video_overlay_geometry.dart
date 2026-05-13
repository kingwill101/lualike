import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../love_runtime.dart';

@immutable
final class LoveFlameLiveVideoOverlayGeometry {
  const LoveFlameLiveVideoOverlayGeometry({
    required this.frameSize,
    required this.contentSize,
    required this.contentOffset,
    required this.transform,
    required this.scissorRect,
    required this.hasRgbTint,
    required this.rgbTintColor,
    required this.alpha,
  });

  final Size frameSize;
  final Size contentSize;
  final Offset contentOffset;
  final vm.Matrix4 transform;
  final Rect? scissorRect;
  final bool hasRgbTint;
  final Color rgbTintColor;
  final double alpha;
}

LoveFlameLiveVideoOverlayGeometry? computeLoveFlameLiveVideoOverlayGeometry(
  LoveVideoCommand command,
) {
  final video = command.video;
  if (video.pixelWidth <= 0 || video.pixelHeight <= 0) {
    return null;
  }

  final quad = command.quad;
  if (quad != null && (quad.width <= 0 || quad.height <= 0)) {
    return null;
  }

  final tint = command.color.clamped();
  return LoveFlameLiveVideoOverlayGeometry(
    frameSize: quad == null
        ? Size(video.pixelWidth.toDouble(), video.pixelHeight.toDouble())
        : Size(quad.width, quad.height),
    contentSize: Size(
      video.pixelWidth.toDouble(),
      video.pixelHeight.toDouble(),
    ),
    contentOffset: quad == null ? Offset.zero : Offset(-quad.x, -quad.y),
    transform: vm.Matrix4.copy(command.transform)
      ..multiply(command.drawTransform),
    scissorRect: command.scissor == null
        ? null
        : Rect.fromLTWH(
            command.scissor!.x,
            command.scissor!.y,
            command.scissor!.width,
            command.scissor!.height,
          ),
    hasRgbTint: tint.r != 1.0 || tint.g != 1.0 || tint.b != 1.0,
    rgbTintColor: Color.fromRGBO(
      (tint.r * 255).round().clamp(0, 255),
      (tint.g * 255).round().clamp(0, 255),
      (tint.b * 255).round().clamp(0, 255),
      1.0,
    ),
    alpha: tint.a.clamp(0.0, 1.0),
  );
}

Rect clampLoveFlameLiveVideoOverlayClipRect(Rect rect, Size size) {
  return Rect.fromLTRB(
    rect.left.clamp(0.0, size.width),
    rect.top.clamp(0.0, size.height),
    rect.right.clamp(0.0, size.width),
    rect.bottom.clamp(0.0, size.height),
  );
}
