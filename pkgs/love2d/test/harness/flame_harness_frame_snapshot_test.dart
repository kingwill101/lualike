import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame keeps the last committed frame while the live surface resets',
    () {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;

      graphics.beginFrame();
      graphics.addCommand(
        LoveRectangleCommand(
          color: LoveColor.white,
          lineWidth: 1,
          lineStyle: LoveGraphicsLineStyle.smooth,
          lineJoin: LoveGraphicsLineJoin.miter,
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
          colorMask: LoveGraphicsColorMask.all,
          wireframe: false,
          scissor: null,
          transform: Matrix4.identity(),
          mode: LoveGraphicsDrawMode.fill,
          x: 10,
          y: 12,
          width: 24,
          height: 36,
        ),
      );

      game.presentFrame(graphics.snapshotScreenSurface());
      expect(game.presentedFrame.commands, hasLength(1));

      graphics.beginFrame();
      expect(graphics.commands, isEmpty);
      expect(game.presentedFrame.commands, hasLength(1));

      final rectangle =
          game.presentedFrame.commands.single as LoveRectangleCommand;
      expect(rectangle.x, 10);
      expect(rectangle.y, 12);
      expect(rectangle.width, 24);
      expect(rectangle.height, 36);
    },
  );
}
