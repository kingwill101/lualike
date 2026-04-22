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
    'LoveFlameHarnessGame keeps front-facing strip triangles under back-face culling',
    () async {
      final pixels = await _renderStripPixels(
        frontFaceWinding: LoveGraphicsVertexWinding.ccw,
        cullMode: LoveGraphicsCullMode.back,
      );

      final upperLeft = _pixelAt(pixels, 10, 2, 2);
      final lowerRight = _pixelAt(pixels, 10, 7, 7);

      expect(upperLeft.r, greaterThan(200));
      expect(upperLeft.g, lessThan(20));
      expect(upperLeft.b, lessThan(20));
      expect(lowerRight.r, greaterThan(200));
      expect(lowerRight.g, lessThan(20));
      expect(lowerRight.b, lessThan(20));
    },
  );

  test(
    'LoveFlameHarnessGame culls strip triangles when front-face winding does not match',
    () async {
      final pixels = await _renderStripPixels(
        frontFaceWinding: LoveGraphicsVertexWinding.cw,
        cullMode: LoveGraphicsCullMode.back,
      );

      final upperLeft = _pixelAt(pixels, 10, 2, 2);
      final lowerRight = _pixelAt(pixels, 10, 7, 7);

      expect(upperLeft.r, lessThan(20));
      expect(upperLeft.g, lessThan(20));
      expect(upperLeft.b, lessThan(20));
      expect(lowerRight.r, lessThan(20));
      expect(lowerRight.g, lessThan(20));
      expect(lowerRight.b, lessThan(20));
    },
  );
}

Future<Uint8List> _renderStripPixels({
  required LoveGraphicsVertexWinding frontFaceWinding,
  required LoveGraphicsCullMode cullMode,
}) async {
  final game = LoveFlameHarnessGame();
  final graphics = game.host.graphics;
  game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

  final mesh = LoveMesh(
    vertices: const <LoveMeshVertex>[
      LoveMeshVertex(x: 0, y: 0),
      LoveMeshVertex(x: 0, y: 10),
      LoveMeshVertex(x: 10, y: 0),
      LoveMeshVertex(x: 10, y: 10),
    ],
    drawMode: LoveMeshDrawMode.strip,
    usage: LoveMeshUsage.staticUsage,
  );

  graphics.beginFrame();
  graphics.addCommand(
    LoveMeshCommand(
      color: const LoveColor(1, 0, 0, 1),
      lineWidth: 1,
      lineStyle: LoveGraphicsLineStyle.smooth,
      lineJoin: LoveGraphicsLineJoin.miter,
      blendMode: LoveGraphicsBlendMode.alpha,
      blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
      colorMask: LoveGraphicsColorMask.all,
      wireframe: false,
      scissor: null,
      shader: null,
      transform: vm.Matrix4.identity(),
      drawTransform: vm.Matrix4.identity(),
      mesh: mesh,
      frontFaceWinding: frontFaceWinding,
      cullMode: cullMode,
    ),
  );
  game.presentFrame(graphics.snapshotScreenSurface());

  game.onGameResize(Vector2(10, 10));
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  game.render(canvas);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(10, 10);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  rendered.dispose();
  expect(data, isNotNull);
  return data!.buffer.asUint8List();
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
