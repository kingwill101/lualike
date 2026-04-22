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
    'LoveFlameHarnessGame applies premultiplied multiply blend mode during live rendering',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 4, height: 4);
      graphics.backgroundColor = LoveColor.white;

      graphics.beginFrame();
      graphics.addCommand(
        _rectangleCommand(
          color: const LoveColor(0.5, 0, 0, 1),
          blendMode: LoveGraphicsBlendMode.multiply,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.premultiplied,
        ),
      );
      game.presentFrame(graphics.snapshotScreenSurface());

      game.onGameResize(Vector2(4, 4));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      game.render(canvas);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(4, 4);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      picture.dispose();
      rendered.dispose();
      expect(data, isNotNull);

      final pixel = _pixelAt(data!.buffer.asUint8List(), 4, 2, 2);
      expect(pixel.r, inInclusiveRange(120, 136));
      expect(pixel.g, lessThan(10));
      expect(pixel.b, lessThan(10));
      expect(pixel.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies screen blend mode during live rendering',
    () async {
      final pixel = await _renderCenterPixel(<LoveDrawCommand>[
        _rectangleCommand(
          color: const LoveColor(0.4, 0.3, 0.2, 1),
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
        _rectangleCommand(
          color: const LoveColor(0.8, 0.1, 0.05, 0.5),
          blendMode: LoveGraphicsBlendMode.screen,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
      ]);

      expect(pixel.r, inInclusiveRange(118, 126));
      expect(pixel.g, inInclusiveRange(78, 86));
      expect(pixel.b, inInclusiveRange(52, 60));
      expect(pixel.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies replace blend mode during live rendering',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 4, height: 4);
      graphics.backgroundColor = const LoveColor(0, 0, 0, 0);

      graphics.beginFrame();
      graphics.addCommand(
        _rectangleCommand(
          color: const LoveColor(1, 0, 0, 0.5),
          blendMode: LoveGraphicsBlendMode.replace,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
      );
      game.presentFrame(graphics.snapshotScreenSurface());

      game.onGameResize(Vector2(4, 4));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      game.render(canvas);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(4, 4);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      picture.dispose();
      rendered.dispose();
      expect(data, isNotNull);

      final pixel = _pixelAt(data!.buffer.asUint8List(), 4, 2, 2);
      expect(pixel.r, inInclusiveRange(120, 136));
      expect(pixel.g, lessThan(10));
      expect(pixel.b, lessThan(10));
      expect(pixel.a, inInclusiveRange(120, 136));
    },
  );

  test(
    'LoveFlameHarnessGame applies none blend mode during live rendering',
    () async {
      final pixel = await _renderCenterPixel(<LoveDrawCommand>[
        _rectangleCommand(
          color: const LoveColor(1, 0, 0, 0.5),
          blendMode: LoveGraphicsBlendMode.none,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
        _rectangleCommand(
          color: const LoveColor(0, 0, 1, 0.5),
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
      ]);

      expect(pixel.r, inInclusiveRange(92, 100));
      expect(pixel.g, lessThan(10));
      expect(pixel.b, inInclusiveRange(92, 100));
      expect(pixel.a, inInclusiveRange(188, 194));
    },
  );

  test(
    'LoveFlameHarnessGame applies add blend mode without changing surface alpha during live rendering',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 4, height: 4);
      graphics.backgroundColor = const LoveColor(0, 0, 0, 0);

      graphics.beginFrame();
      graphics.addCommand(
        _rectangleCommand(
          color: const LoveColor(1, 0, 0, 0.5),
          blendMode: LoveGraphicsBlendMode.add,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
      );
      game.presentFrame(graphics.snapshotScreenSurface());

      game.onGameResize(Vector2(4, 4));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      game.render(canvas);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(4, 4);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      picture.dispose();
      rendered.dispose();
      expect(data, isNotNull);

      final pixel = _pixelAt(data!.buffer.asUint8List(), 4, 2, 2);
      expect(pixel.r, lessThan(10));
      expect(pixel.g, lessThan(20));
      expect(pixel.b, lessThan(40));
      expect(pixel.a, 0);
    },
  );

  test(
    'LoveFlameHarnessGame applies subtract blend mode during live rendering',
    () async {
      final pixel = await _renderCenterPixel(<LoveDrawCommand>[
        _rectangleCommand(
          color: LoveColor.white,
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
        _rectangleCommand(
          color: const LoveColor(1, 0, 0, 0.25),
          blendMode: LoveGraphicsBlendMode.subtract,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
      ]);

      expect(pixel.r, inInclusiveRange(186, 196));
      expect(pixel.g, inInclusiveRange(250, 255));
      expect(pixel.b, inInclusiveRange(250, 255));
      expect(pixel.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies premultiplied lighten blend mode during live rendering',
    () async {
      final pixel = await _renderCenterPixel(<LoveDrawCommand>[
        _rectangleCommand(
          color: const LoveColor(0.3, 0.4, 0.2, 1),
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
        _rectangleCommand(
          color: const LoveColor(0.5, 0.1, 0.25, 1),
          blendMode: LoveGraphicsBlendMode.lighten,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.premultiplied,
        ),
      ]);

      expect(pixel.r, inInclusiveRange(124, 132));
      expect(pixel.g, inInclusiveRange(100, 108));
      expect(pixel.b, inInclusiveRange(60, 68));
      expect(pixel.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies premultiplied darken blend mode during live rendering',
    () async {
      final pixel = await _renderCenterPixel(<LoveDrawCommand>[
        _rectangleCommand(
          color: const LoveColor(0.3, 0.4, 0.2, 1),
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
        _rectangleCommand(
          color: const LoveColor(0.5, 0.1, 0.25, 1),
          blendMode: LoveGraphicsBlendMode.darken,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.premultiplied,
        ),
      ]);

      expect(pixel.r, inInclusiveRange(74, 82));
      expect(pixel.g, inInclusiveRange(23, 31));
      expect(pixel.b, inInclusiveRange(48, 56));
      expect(pixel.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame respects premultiplied alpha blend mode during live rendering',
    () async {
      final pixel = await _renderCenterPixel(<LoveDrawCommand>[
        _rectangleCommand(
          color: const LoveColor(0, 0, 0, 1),
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        ),
        _rectangleCommand(
          color: const LoveColor(0.5, 0, 0, 0.5),
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.premultiplied,
        ),
      ]);

      expect(pixel.r, inInclusiveRange(120, 136));
      expect(pixel.g, lessThan(10));
      expect(pixel.b, lessThan(10));
      expect(pixel.a, 255);
    },
  );
}

Future<({int r, int g, int b, int a})> _renderCenterPixel(
  List<LoveDrawCommand> commands,
) async {
  final game = LoveFlameHarnessGame();
  final graphics = game.host.graphics;
  game.host.windowMetrics = const LoveWindowMetrics(width: 4, height: 4);

  graphics.beginFrame();
  for (final command in commands) {
    graphics.addCommand(command);
  }
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

  final pixels = data!.buffer.asUint8List();
  return _pixelAt(pixels, 4, 2, 2);
}

LoveRectangleCommand _rectangleCommand({
  required LoveColor color,
  required LoveGraphicsBlendMode blendMode,
  required LoveGraphicsBlendAlphaMode blendAlphaMode,
}) {
  return LoveRectangleCommand(
    color: color,
    lineWidth: 1,
    lineStyle: LoveGraphicsLineStyle.smooth,
    lineJoin: LoveGraphicsLineJoin.miter,
    blendMode: blendMode,
    blendAlphaMode: blendAlphaMode,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: false,
    scissor: null,
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
