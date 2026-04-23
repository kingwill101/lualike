import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame applies stencil-masked draws during live rendering',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 4, height: 4);

      graphics.beginFrame();
      graphics.beginStencilWrite(LoveGraphicsStencilAction.replace, 1);
      graphics.addCommand(
        _rectangleCommand(
          color: LoveColor.white,
          x: 0,
          y: 0,
          width: 2,
          height: 4,
        ),
      );
      graphics.endStencilWrite();
      graphics.stencilCompare = LoveGraphicsCompareMode.greater;
      graphics.stencilValue = 0;
      graphics.addCommand(
        _rectangleCommand(
          color: const LoveColor(0, 1, 0, 1),
          x: 0,
          y: 0,
          width: 4,
          height: 4,
        ),
      );
      game.presentFrame(graphics.snapshotScreenSurface());

      game.onGameResize(Vector2(40, 40));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      game.render(canvas);
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      final image = await picture.toImage(40, 40);
      addTearDown(image.dispose);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data, isNotNull);

      final pixels = data!.buffer.asUint8List();
      final left = _pixelAt(pixels, image.width, x: 5, y: 20);
      final right = _pixelAt(pixels, image.width, x: 35, y: 20);

      expect(left.r, lessThan(30));
      expect(left.g, greaterThan(200));
      expect(left.b, lessThan(30));
      expect(left.a, 255);

      expect(right.r, lessThan(20));
      expect(right.g, lessThan(20));
      expect(right.b, lessThan(20));
      expect(right.a, 255);
    },
  );
}

LoveRectangleCommand _rectangleCommand({
  required LoveColor color,
  required double x,
  required double y,
  required double width,
  required double height,
}) {
  return LoveRectangleCommand(
    color: color,
    lineWidth: 1,
    lineStyle: LoveGraphicsLineStyle.smooth,
    lineJoin: LoveGraphicsLineJoin.miter,
    blendMode: LoveGraphicsBlendMode.alpha,
    blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: false,
    scissor: null,
    transform: vm.Matrix4.identity(),
    mode: LoveGraphicsDrawMode.fill,
    x: x,
    y: y,
    width: width,
    height: height,
  );
}

({int r, int g, int b, int a}) _pixelAt(
  Uint8List pixels,
  int width, {
  required int x,
  required int y,
}) {
  final offset = ((y * width) + x) * 4;
  return (
    r: pixels[offset],
    g: pixels[offset + 1],
    b: pixels[offset + 2],
    a: pixels[offset + 3],
  );
}
