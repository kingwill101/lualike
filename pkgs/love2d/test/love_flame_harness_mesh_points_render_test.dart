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
    'LoveFlameHarnessGame renders mesh points using the queued point size',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final mesh = LoveMesh(
        vertices: const <LoveMeshVertex>[
          LoveMeshVertex(x: 5, y: 5, color: LoveColor(1, 0, 0, 1)),
        ],
        drawMode: LoveMeshDrawMode.points,
        usage: LoveMeshUsage.staticUsage,
      );

      graphics.beginFrame();
      graphics.addCommand(
        LoveMeshCommand(
          color: LoveColor.white,
          lineWidth: 1,
          lineStyle: LoveGraphicsLineStyle.rough,
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
          pointSize: 4,
          frontFaceWinding: LoveGraphicsVertexWinding.ccw,
          cullMode: LoveGraphicsCullMode.back,
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
      final center = _pixelAt(pixels, rendered.width, 5, 5);
      final expanded = _pixelAt(pixels, rendered.width, 3, 5);
      final outside = _pixelAt(pixels, rendered.width, 0, 0);

      expect(center.r, greaterThan(200));
      expect(center.g, lessThan(20));
      expect(center.b, lessThan(20));
      expect(center.a, 255);

      expect(expanded.r, greaterThan(200));
      expect(expanded.g, lessThan(20));
      expect(expanded.b, lessThan(20));
      expect(expanded.a, 255);

      expect(outside.r, lessThan(20));
      expect(outside.g, lessThan(20));
      expect(outside.b, lessThan(30));
      expect(outside.a, 255);
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
