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
  return mix(colorInner, colorOuter, t);
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame preserves transformed radial shader output for filled shapes',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 8, height: 4);
      graphics.backgroundColor = const LoveColor(0, 1, 0, 1);

      final shader = LoveShader.fromSource(_radialGradientShaderSource)
        ..send('innerRadius', 0.0)
        ..send('outerRadius', 1.5)
        ..send('center', <Object?>[5.5, 1.5])
        ..send('colorInner', <Object?>[1.0, 0.0, 0.0, 1.0])
        ..send('colorOuter', <Object?>[0.0, 0.0, 1.0, 1.0]);

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
          shader: shader,
          transform: vm.Matrix4.translationValues(4, 0, 0),
          mode: LoveGraphicsDrawMode.fill,
          x: 0,
          y: 0,
          width: 4,
          height: 4,
          cornerRadiusX: 0,
          cornerRadiusY: 0,
        ),
      );
      game.presentFrame(graphics.snapshotScreenSurface());

      game.onGameResize(Vector2(8, 4));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      game.render(canvas);
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      final rendered = await picture.toImage(8, 4);
      addTearDown(rendered.dispose);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(data, isNotNull);

      final raw = data!.buffer.asUint8List();
      final outside = _pixelAt(raw, 8, 1, 1);
      final inside = _pixelAt(raw, 8, 5, 1);

      expect(outside.r, 0);
      expect(outside.g, 0);
      expect(outside.b, 0);
      expect(outside.a, 0);

      expect(inside.r, inInclusiveRange(250, 255));
      expect(inside.g, lessThan(10));
      expect(inside.b, lessThan(10));
      expect(inside.a, 255);
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
