import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame renders untextured mesh wireframes as edges only',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final mesh = LoveMesh(
        vertices: const <LoveMeshVertex>[
          LoveMeshVertex(x: 0, y: 0),
          LoveMeshVertex(x: 10, y: 0),
          LoveMeshVertex(x: 10, y: 10),
          LoveMeshVertex(x: 0, y: 10),
        ],
        drawMode: LoveMeshDrawMode.fan,
        usage: LoveMeshUsage.staticUsage,
      );

      graphics.beginFrame();
      graphics.addCommand(
        LoveMeshCommand(
          color: const LoveColor(1, 1, 1, 1),
          lineWidth: 1,
          lineStyle: LoveGraphicsLineStyle.rough,
          lineJoin: LoveGraphicsLineJoin.miter,
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
          colorMask: LoveGraphicsColorMask.all,
          wireframe: true,
          scissor: null,
          shader: null,
          transform: vm.Matrix4.identity(),
          drawTransform: vm.Matrix4.identity(),
          mesh: mesh,
          frontFaceWinding: LoveGraphicsVertexWinding.ccw,
          cullMode: LoveGraphicsCullMode.none,
        ),
      );
      game.presentFrame(graphics.snapshotScreenSurface());

      game.onGameResize(Vector2(10, 10));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      game.render(canvas);
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      final rendered = await picture.toImage(10, 10);
      addTearDown(rendered.dispose);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(data, isNotNull);

      final pixels = data!.buffer.asUint8List();
      final interior = _pixelAt(pixels, rendered.width, 2, 5);
      final edge = _pixelAt(pixels, rendered.width, 5, 0);

      expect(interior.r, lessThan(20));
      expect(interior.g, lessThan(20));
      expect(interior.b, lessThan(20));
      expect(interior.a, 255);

      expect(edge.r, greaterThan(200));
      expect(edge.g, greaterThan(200));
      expect(edge.b, greaterThan(200));
      expect(edge.a, 255);
    },
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
