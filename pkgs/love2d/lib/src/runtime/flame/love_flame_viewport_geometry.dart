import 'package:flutter/painting.dart';

import '../love_runtime.dart';

/// Returns the logical LOVE viewport size for the current window state.
Size loveLogicalViewportSize({
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

/// Returns the centered destination rectangle used to present the viewport.
Rect loveViewportDestinationRect({
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  if (viewportSize.width <= 0 || viewportSize.height <= 0) {
    return Rect.zero;
  }

  final logicalSize = loveLogicalViewportSize(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  );
  if (logicalSize.width <= 0 || logicalSize.height <= 0) {
    return Offset.zero & viewportSize;
  }

  final fitted = applyBoxFit(BoxFit.contain, logicalSize, viewportSize);
  return Alignment.center.inscribe(
    fitted.destination,
    Offset.zero & viewportSize,
  );
}

/// Converts a viewport-space point into LOVE logical coordinates.
Offset loveViewportToLogicalPoint({
  required Offset viewportPoint,
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  final logicalSize = loveLogicalViewportSize(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  );
  final destinationRect = loveViewportDestinationRect(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  );
  if (destinationRect.width <= 0 || destinationRect.height <= 0) {
    return viewportPoint;
  }

  return Offset(
    (viewportPoint.dx - destinationRect.left) *
        (logicalSize.width / destinationRect.width),
    (viewportPoint.dy - destinationRect.top) *
        (logicalSize.height / destinationRect.height),
  );
}

/// Converts a viewport-space delta into LOVE logical coordinates.
Offset loveViewportDeltaToLogicalDelta({
  required Offset viewportDelta,
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  final logicalSize = loveLogicalViewportSize(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  );
  final destinationRect = loveViewportDestinationRect(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  );
  if (destinationRect.width <= 0 || destinationRect.height <= 0) {
    return viewportDelta;
  }

  return Offset(
    viewportDelta.dx * (logicalSize.width / destinationRect.width),
    viewportDelta.dy * (logicalSize.height / destinationRect.height),
  );
}

/// Converts a LOVE logical point into viewport-space coordinates.
Offset loveLogicalToViewportPoint({
  required Offset logicalPoint,
  required LoveWindowMetrics windowMetrics,
  required Size viewportSize,
}) {
  final logicalSize = loveLogicalViewportSize(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  );
  final destinationRect = loveViewportDestinationRect(
    windowMetrics: windowMetrics,
    viewportSize: viewportSize,
  );
  if (logicalSize.width <= 0 ||
      logicalSize.height <= 0 ||
      destinationRect.width <= 0 ||
      destinationRect.height <= 0) {
    return logicalPoint;
  }

  return Offset(
    destinationRect.left +
        (logicalPoint.dx * destinationRect.width / logicalSize.width),
    destinationRect.top +
        (logicalPoint.dy * destinationRect.height / logicalSize.height),
  );
}
