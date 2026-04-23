import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

const String _radialGradientShaderSource = '''
extern number innerRadius;
extern number outerRadius;
extern vec2 center;
extern vec4 colorInner;
extern vec4 colorOuter;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  number dist = distance(screen_coords, center);
  number t = smoothstep(innerRadius, outerRadius, dist);
  return mix(colorInner, colorOuter, t) * Texel(texture, texture_coords);
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame applies radial gradient shaders to image draws',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final imageData = LoveImageData(width: 10, height: 10);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          imageData.setPixel(x, y, const LoveColor(1, 0, 0, 1));
        }
      }
      final image = LoveImage(
        source: 'test-red-gradient',
        width: 10,
        height: 10,
        imageData: imageData,
        preferImageDataRendering: true,
      );
      final shader = LoveShader.fromSource(_radialGradientShaderSource)
        ..send('innerRadius', 0.0)
        ..send('outerRadius', 4.5)
        ..send('center', <Object?>[5.5, 5.5])
        ..send('colorInner', <Object?>[1.0, 1.0, 1.0, 1.0])
        ..send('colorOuter', <Object?>[0.0, 0.0, 0.0, 1.0]);
      expect(shader.kind, LoveShaderKind.radialGradient);

      graphics.beginFrame();
      graphics.addCommand(
        LoveImageCommand(
          color: LoveColor.white,
          lineWidth: 1,
          lineStyle: LoveGraphicsLineStyle.smooth,
          lineJoin: LoveGraphicsLineJoin.miter,
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
          colorMask: LoveGraphicsColorMask.all,
          wireframe: false,
          scissor: null,
          shader: shader,
          transform: vm.Matrix4.identity(),
          drawTransform: vm.Matrix4.identity(),
          image: image,
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

      final center = _pixelAt(data!.buffer.asUint8List(), rendered.width, 5, 5);
      final edge = _pixelAt(data.buffer.asUint8List(), rendered.width, 0, 5);
      expect(center.r, inInclusiveRange(250, 255));
      expect(center.g, inInclusiveRange(0, 5));
      expect(center.b, inInclusiveRange(0, 5));
      expect(center.a, 255);
      expect(edge.r, inInclusiveRange(0, 5));
      expect(edge.g, inInclusiveRange(0, 5));
      expect(edge.b, inInclusiveRange(0, 5));
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
