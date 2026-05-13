import 'package:flame/game.dart';
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

  test(
    'host viewport updates do not overwrite an explicit LOVE presentation mode',
    () {
      final game = LoveFlameHarnessGame();
      addTearDown(game.disposePresentationNotifier);

      game.host.windowMetrics = const LoveWindowMetrics(
        width: 960,
        height: 540,
        desktopWidth: 960,
        desktopHeight: 540,
      );
      game.host.updateHostViewportSize(const Size(640, 480));

      expect(game.host.windowMetrics.width, 960);
      expect(game.host.windowMetrics.height, 540);
      expect(game.host.windowMetrics.desktopWidth, 640);
      expect(game.host.windowMetrics.desktopHeight, 480);
    },
  );

  testWidgets(
    'camera-backed geometry matches the fixed-resolution Flame viewport',
    (tester) async {
      final game = LoveFlameHarnessGame();
      addTearDown(game.disposePresentationNotifier);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(const Size(640, 480));

      game.host.windowMetrics = const LoveWindowMetrics(
        width: 960,
        height: 540,
        desktopWidth: 960,
        desktopHeight: 540,
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GameWidget(game: game),
        ),
      );
      await tester.pump();

      final presentation = game.presentationGeometry;
      expect(
        presentation.destinationRect,
        const Rect.fromLTWH(0, 60, 640, 360),
      );
      expect(
        presentation.viewportToLogicalPoint(const Offset(320, 240)),
        const Offset(480, 270),
      );
      expect(
        presentation.logicalToViewportPoint(const Offset(480, 270)),
        const Offset(320, 240),
      );
    },
  );
}
