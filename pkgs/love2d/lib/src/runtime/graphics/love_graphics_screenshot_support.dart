part of '../love_runtime.dart';

/// Delivers a captured screenshot image to a pending consumer.
typedef LoveGraphicsScreenshotDelivery =
    FutureOr<void> Function(LoveImageData imageData);

/// Queues screenshot delivery callbacks until a frame snapshot is available.
final class LoveGraphicsScreenshotQueue {
  /// The pending screenshot deliveries waiting for rasterized image data.
  final List<LoveGraphicsScreenshotDelivery> _deliveries =
      <LoveGraphicsScreenshotDelivery>[];

  /// Whether no screenshot deliveries are currently queued.
  bool get isEmpty => _deliveries.isEmpty;

  /// Adds [delivery] to the pending screenshot queue.
  void enqueue(LoveGraphicsScreenshotDelivery delivery) {
    _deliveries.add(delivery);
  }

  /// Removes and returns every pending screenshot delivery.
  List<LoveGraphicsScreenshotDelivery> takePending() {
    if (_deliveries.isEmpty) {
      return const <LoveGraphicsScreenshotDelivery>[];
    }

    final pending = List<LoveGraphicsScreenshotDelivery>.from(_deliveries);
    _deliveries.clear();
    return List<LoveGraphicsScreenshotDelivery>.unmodifiable(pending);
  }
}

/// Rasterizes [snapshot] and delivers clones to every pending queue callback.
///
/// Throws an [UnsupportedError] when software readback cannot reproduce the
/// captured surface with the current command set.
Future<void> dispatchLoveGraphicsScreenshotQueue(
  LoveGraphicsScreenshotQueue queue, {
  required LoveGraphicsSurfaceSnapshot snapshot,
  required int pixelWidth,
  required int pixelHeight,
}) async {
  if (queue.isEmpty) {
    return;
  }

  final pending = queue.takePending();
  if (pending.isEmpty) {
    return;
  }

  final unsupportedReason = loveSoftwareReadbackUnsupportedReasonForSnapshot(
    snapshot,
  );
  if (unsupportedReason != null) {
    throw UnsupportedError(
      'love.graphics.captureScreenshot $unsupportedReason',
    );
  }

  final imageData = LoveCanvasRasterizer.rasterizeSurface(
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    format: 'rgba8',
    snapshot: snapshot,
  );

  for (final delivery in pending) {
    await delivery(imageData.clone());
  }
}
