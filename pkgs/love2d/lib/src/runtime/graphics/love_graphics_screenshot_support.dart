part of '../love_runtime.dart';

typedef LoveGraphicsScreenshotDelivery =
    FutureOr<void> Function(LoveImageData imageData);

final class LoveGraphicsScreenshotQueue {
  final List<LoveGraphicsScreenshotDelivery> _deliveries =
      <LoveGraphicsScreenshotDelivery>[];

  bool get isEmpty => _deliveries.isEmpty;

  void enqueue(LoveGraphicsScreenshotDelivery delivery) {
    _deliveries.add(delivery);
  }

  List<LoveGraphicsScreenshotDelivery> takePending() {
    if (_deliveries.isEmpty) {
      return const <LoveGraphicsScreenshotDelivery>[];
    }

    final pending = List<LoveGraphicsScreenshotDelivery>.from(_deliveries);
    _deliveries.clear();
    return List<LoveGraphicsScreenshotDelivery>.unmodifiable(pending);
  }
}

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
