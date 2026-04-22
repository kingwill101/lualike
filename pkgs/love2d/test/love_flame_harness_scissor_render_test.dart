import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame applies command scissor clipping during live rendering',
    () async {
      final pixels = await _renderPixels((graphics) {
        graphics.backgroundColor = const LoveColor(0, 1, 0, 1);
        graphics.beginFrame();
        graphics.addCommand(
          _rectangleCommand(
            color: const LoveColor(1, 0, 0, 1),
            scissor: const LoveScissorRect(x: 1, y: 1, width: 2, height: 2),
          ),
        );
      });

      expect(pixels.outside.r, lessThan(10));
      expect(pixels.outside.g, inInclusiveRange(250, 255));
      expect(pixels.outside.b, lessThan(10));
      expect(pixels.outside.a, 255);

      expect(pixels.inside.r, inInclusiveRange(250, 255));
      expect(pixels.inside.g, lessThan(10));
      expect(pixels.inside.b, lessThan(10));
      expect(pixels.inside.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies scissored clears during live rendering',
    () async {
      final pixels = await _renderPixels((graphics) {
        graphics.backgroundColor = const LoveColor(0, 1, 0, 1);
        graphics.beginFrame();
        graphics.scissor = const LoveScissorRect(
          x: 1,
          y: 1,
          width: 2,
          height: 2,
        );
        graphics.clear(const LoveColor(1, 0, 0, 1));
        graphics.scissor = null;
      });

      expect(pixels.outside.r, lessThan(10));
      expect(pixels.outside.g, inInclusiveRange(250, 255));
      expect(pixels.outside.b, lessThan(10));
      expect(pixels.outside.a, 255);

      expect(pixels.inside.r, inInclusiveRange(250, 255));
      expect(pixels.inside.g, lessThan(10));
      expect(pixels.inside.b, lessThan(10));
      expect(pixels.inside.a, 255);
    },
  );
}

Future<
  ({
    ({int r, int g, int b, int a}) inside,
    ({int r, int g, int b, int a}) outside,
  })
>
_renderPixels(void Function(dynamic graphics) record) async {
  final game = LoveFlameHarnessGame();
  final graphics = game.host.graphics;
  game.host.windowMetrics = const LoveWindowMetrics(width: 4, height: 4);

  record(graphics);
  game.presentFrame(graphics.snapshotScreenSurface());

  game.onGameResize(Vector2(4, 4));
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  game.render(canvas);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(4, 4);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  rendered.dispose();
  expect(data, isNotNull);

  final raw = data!.buffer.asUint8List();
  return (outside: _pixelAt(raw, 4, 0, 0), inside: _pixelAt(raw, 4, 2, 2));
}

LoveRectangleCommand _rectangleCommand({
  required LoveColor color,
  required LoveScissorRect? scissor,
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
    scissor: scissor,
    transform: vm.Matrix4.identity(),
    mode: LoveGraphicsDrawMode.fill,
    x: 0,
    y: 0,
    width: 4,
    height: 4,
  );
}

({int r, int g, int b, int a}) _pixelAt(
  Uint8List pixels,
  int width,
  int x,
  int y,
) {
  final offset = ((y * width) + x) * 4;
  return (
    r: pixels[offset],
    g: pixels[offset + 1],
    b: pixels[offset + 2],
    a: pixels[offset + 3],
  );
}
