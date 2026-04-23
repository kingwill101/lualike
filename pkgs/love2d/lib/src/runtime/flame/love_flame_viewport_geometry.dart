import 'dart:math' as math;

import 'package:flame/camera.dart';
import 'package:flame/components.dart' show Vector2;
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show immutable;

import '../love_runtime.dart';

/// Presentation geometry for the logical LOVE surface inside the Flutter view.
@immutable
final class LoveFlamePresentationGeometry {
  /// Creates an immutable presentation geometry snapshot.
  const LoveFlamePresentationGeometry({
    required this.viewportSize,
    required this.logicalSize,
    required this.destinationRect,
    this.camera,
  });

  /// The current Flutter viewport size in physical widget coordinates.
  final Size viewportSize;

  /// The logical LOVE surface size before letterboxing/scaling.
  final Size logicalSize;

  /// The destination rect used to present the logical surface.
  final Rect destinationRect;

  /// The Flame camera currently presenting the logical surface, when mounted.
  final CameraComponent? camera;

  /// Converts a viewport-space point into LOVE logical coordinates.
  Offset viewportToLogicalPoint(Offset viewportPoint) {
    if (destinationRect.width <= 0 || destinationRect.height <= 0) {
      return viewportPoint;
    }
    if (camera case final presentationCamera?) {
      final logicalPoint = presentationCamera.viewport.globalToLocal(
        Vector2(viewportPoint.dx, viewportPoint.dy),
      );
      return Offset(logicalPoint.x, logicalPoint.y);
    }

    return Offset(
      (viewportPoint.dx - destinationRect.left) *
          (logicalSize.width / destinationRect.width),
      (viewportPoint.dy - destinationRect.top) *
          (logicalSize.height / destinationRect.height),
    );
  }

  /// Converts a viewport-space delta into LOVE logical coordinates.
  Offset viewportDeltaToLogicalDelta(Offset viewportDelta) {
    if (destinationRect.width <= 0 || destinationRect.height <= 0) {
      return viewportDelta;
    }
    if (camera case final presentationCamera?) {
      final logicalOrigin = presentationCamera.viewport.globalToLocal(
        Vector2.zero(),
      );
      final logicalDelta = presentationCamera.viewport.globalToLocal(
        Vector2(viewportDelta.dx, viewportDelta.dy),
      );
      return Offset(
        logicalDelta.x - logicalOrigin.x,
        logicalDelta.y - logicalOrigin.y,
      );
    }

    return Offset(
      viewportDelta.dx * (logicalSize.width / destinationRect.width),
      viewportDelta.dy * (logicalSize.height / destinationRect.height),
    );
  }

  /// Converts a LOVE logical point into viewport-space coordinates.
  Offset logicalToViewportPoint(Offset logicalPoint) {
    if (logicalSize.width <= 0 ||
        logicalSize.height <= 0 ||
        destinationRect.width <= 0 ||
        destinationRect.height <= 0) {
      return logicalPoint;
    }
    if (camera case final presentationCamera?) {
      final viewportPoint = presentationCamera.viewport.localToGlobal(
        Vector2(logicalPoint.dx, logicalPoint.dy),
      );
      return Offset(viewportPoint.x, viewportPoint.y);
    }

    return Offset(
      destinationRect.left +
          (logicalPoint.dx * destinationRect.width / logicalSize.width),
      destinationRect.top +
          (logicalPoint.dy * destinationRect.height / logicalSize.height),
    );
  }
}

Size _loveLogicalViewportSize({
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  final width = windowMetrics.width > 0
      ? windowMetrics.width.toDouble()
      : viewportSize.width;
  final height = windowMetrics.height > 0
      ? windowMetrics.height.toDouble()
      : viewportSize.height;
  return Size(
    width > 0 ? width : viewportSize.width,
    height > 0 ? height : viewportSize.height,
  );
}

/// Builds the presentation geometry for the current viewport.
LoveFlamePresentationGeometry loveFlamePresentationGeometry({
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
  CameraComponent? camera,
}) {
  final logicalSize = _loveLogicalViewportSize(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  );
  if (viewportSize.width <= 0 || viewportSize.height <= 0) {
    return LoveFlamePresentationGeometry(
      viewportSize: viewportSize,
      logicalSize: logicalSize,
      destinationRect: Rect.zero,
    );
  }
  if (logicalSize.width <= 0 || logicalSize.height <= 0) {
    return LoveFlamePresentationGeometry(
      viewportSize: viewportSize,
      logicalSize: logicalSize,
      destinationRect: Offset.zero & viewportSize,
    );
  }

  if (camera != null) {
    final topLeft = camera.viewport.localToGlobal(Vector2.zero());
    final bottomRight = camera.viewport.localToGlobal(
      Vector2(logicalSize.width, logicalSize.height),
    );
    return LoveFlamePresentationGeometry(
      viewportSize: viewportSize,
      logicalSize: logicalSize,
      destinationRect: Rect.fromLTRB(
        math.min(topLeft.x, bottomRight.x),
        math.min(topLeft.y, bottomRight.y),
        math.max(topLeft.x, bottomRight.x),
        math.max(topLeft.y, bottomRight.y),
      ),
      camera: camera,
    );
  }

  final fitted = applyBoxFit(BoxFit.contain, logicalSize, viewportSize);
  return LoveFlamePresentationGeometry(
    viewportSize: viewportSize,
    logicalSize: logicalSize,
    destinationRect: Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & viewportSize,
    ),
  );
}

/// Returns the logical LOVE viewport size for the current window state.
Size loveLogicalViewportSize({
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  return loveFlamePresentationGeometry(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  ).logicalSize;
}

/// Returns the centered destination rectangle used to present the viewport.
Rect loveViewportDestinationRect({
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  return loveFlamePresentationGeometry(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  ).destinationRect;
}

/// Converts a viewport-space point into LOVE logical coordinates.
Offset loveViewportToLogicalPoint({
  required Offset viewportPoint,
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  return loveFlamePresentationGeometry(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  ).viewportToLogicalPoint(viewportPoint);
}

/// Converts a viewport-space delta into LOVE logical coordinates.
Offset loveViewportDeltaToLogicalDelta({
  required Offset viewportDelta,
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  return loveFlamePresentationGeometry(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  ).viewportDeltaToLogicalDelta(viewportDelta);
}

/// Converts a LOVE logical point into viewport-space coordinates.
Offset loveLogicalToViewportPoint({
  required Offset logicalPoint,
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  return loveFlamePresentationGeometry(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  ).logicalToViewportPoint(logicalPoint);
}
