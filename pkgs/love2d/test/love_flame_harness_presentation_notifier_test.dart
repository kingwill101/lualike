import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoveFlameHarnessGame presentation notifier', () {
    test(
      'presentFrame stops notifying once the notifier has been disposed',
      () {
        final game = LoveFlameHarnessGame();
        addTearDown(game.disposePresentationNotifier);

        var notifications = 0;
        game.presentedFrameListenable.addListener(() {
          notifications++;
        });

        final firstFrame = _snapshotWithRectangle(8);
        game.presentFrame(firstFrame);
        expect(game.presentedFrame, same(firstFrame));
        expect(game.presentedFrameListenable.value, same(firstFrame));
        expect(notifications, 1);

        game.disposePresentationNotifier();

        final secondFrame = _snapshotWithRectangle(16);
        expect(() => game.presentFrame(secondFrame), returnsNormally);
        expect(() => game.disposePresentationNotifier(), returnsNormally);
        expect(game.presentedFrame, same(secondFrame));
        expect(notifications, 1);
      },
    );

    test('onDispose tears down the presentation notifier idempotently', () {
      final game = LoveFlameHarnessGame();

      var notifications = 0;
      game.presentedFrameListenable.addListener(() {
        notifications++;
      });

      final firstFrame = _snapshotWithRectangle(4);
      game.presentFrame(firstFrame);
      expect(notifications, 1);

      expect(() => game.onDispose(), returnsNormally);
      expect(() => game.onDispose(), returnsNormally);

      final secondFrame = _snapshotWithRectangle(12);
      expect(() => game.presentFrame(secondFrame), returnsNormally);
      expect(game.presentedFrame, same(secondFrame));
      expect(notifications, 1);
    });
  });
}

LoveGraphicsSurfaceSnapshot _snapshotWithRectangle(double x) {
  return LoveGraphicsSurfaceSnapshot(
    clearColor: const LoveColor(0, 0, 0, 1),
    clearColorMask: LoveGraphicsColorMask.all,
    clearStencil: 0,
    clearScissor: null,
    commands: <LoveDrawCommand>[
      LoveRectangleCommand(
        color: LoveColor.white,
        lineWidth: 1.0,
        lineStyle: LoveGraphicsLineStyle.smooth,
        lineJoin: LoveGraphicsLineJoin.none,
        blendMode: LoveGraphicsBlendMode.alpha,
        blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        colorMask: LoveGraphicsColorMask.all,
        wireframe: false,
        scissor: null,
        transform: Matrix4.identity(),
        mode: LoveGraphicsDrawMode.fill,
        x: x,
        y: 0,
        width: 8,
        height: 4,
      ),
    ],
  );
}
