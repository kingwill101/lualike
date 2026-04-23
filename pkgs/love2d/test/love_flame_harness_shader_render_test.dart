import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

const String _desaturationTintShaderSource = '''
extern vec4 tint;
extern number strength;

vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _)
{
  color = Texel(texture, tc);
  number luma = dot(vec3(0.299f, 0.587f, 0.114f), color.rgb);
  return mix(color, tint * luma, strength);
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame applies desaturation tint shaders to image draws',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 1, height: 1);

      final imageData = LoveImageData(width: 1, height: 1)
        ..setPixel(0, 0, const LoveColor(1, 0, 0, 1));
      final image = LoveImage(
        source: 'test-red',
        width: 1,
        height: 1,
        imageData: imageData,
        preferImageDataRendering: true,
      );
      final shader = LoveShader.fromSource(_desaturationTintShaderSource)
        ..send('tint', <Object?>[1.0, 1.0, 1.0, 1 / 0.299])
        ..send('strength', 1.0);
      expect(shader.kind, LoveShaderKind.desaturationTint);

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

      final pixel = _pixelAt(data!.buffer.asUint8List(), rendered.width);
      expect(pixel.r, inInclusiveRange(72, 82));
      expect(pixel.g, inInclusiveRange(72, 82));
      expect(pixel.b, inInclusiveRange(72, 82));
      expect(pixel.a, 255);
    },
  );
}

({int r, int g, int b, int a}) _pixelAt(Uint8List pixels, int width) {
  final sampleX = width ~/ 2;
  final sampleY = width ~/ 2;
  final offset = ((sampleY * width) + sampleX) * 4;
  return (
    r: pixels[offset],
    g: pixels[offset + 1],
    b: pixels[offset + 2],
    a: pixels[offset + 3],
  );
}
