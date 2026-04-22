import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_viewport_geometry.dart';

void main() {
  test(
    'fits a LOVE window into the Flutter viewport while preserving aspect ratio',
    () {
      const windowMetrics = LoveWindowMetrics(width: 960, height: 540);
      const viewportSize = Size(640, 480);

      expect(
        loveViewportDestinationRect(
          windowMetrics: windowMetrics,
          viewportSize: viewportSize,
        ),
        const Rect.fromLTWH(0, 60, 640, 360),
      );
    },
  );

  test('maps between Flutter viewport and LOVE logical coordinates', () {
    const windowMetrics = LoveWindowMetrics(width: 960, height: 540);
    const viewportSize = Size(640, 480);

    expect(
      loveViewportToLogicalPoint(
        viewportPoint: const Offset(320, 240),
        windowMetrics: windowMetrics,
        viewportSize: viewportSize,
      ),
      const Offset(480, 270),
    );

    expect(
      loveLogicalToViewportPoint(
        logicalPoint: const Offset(480, 270),
        windowMetrics: windowMetrics,
        viewportSize: viewportSize,
      ),
      const Offset(320, 240),
    );
  });
}
