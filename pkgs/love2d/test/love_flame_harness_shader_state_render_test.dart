import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

const String _desaturationTintShaderSource = '''
extern vec4 tint;
extern number strength;

vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
  color = Texel(texture, tc);
  number luma = dot(vec3(0.299f, 0.587f, 0.114f), color.rgb);
  return mix(color, tint * luma, strength);
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame applies desaturation shaders with replace blend mode',
    () async {
      final imageData = LoveImageData(width: 4, height: 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          imageData.setPixel(x, y, const LoveColor(1, 0, 0, 0.5));
        }
      }
      final image = LoveImage(
        source: 'shader-state-replace',
        width: 4,
        height: 4,
        imageData: imageData,
        preferImageDataRendering: true,
      );
      final shader = LoveShader.fromSource(_desaturationTintShaderSource)
        ..send('tint', <Object?>[1.0, 1.0, 1.0, 0.5 / 0.299])
        ..send('strength', 1.0);

      final pixel = await _renderCenterPixel(
        commands: <LoveDrawCommand>[
          LoveImageCommand(
            color: LoveColor.white,
            lineWidth: 1,
            lineStyle: LoveGraphicsLineStyle.smooth,
            lineJoin: LoveGraphicsLineJoin.miter,
            blendMode: LoveGraphicsBlendMode.replace,
            blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
            colorMask: LoveGraphicsColorMask.all,
            wireframe: false,
            scissor: null,
            shader: shader,
            transform: vm.Matrix4.identity(),
            drawTransform: vm.Matrix4.identity(),
            image: image,
          ),
        ],
        backgroundColor: const LoveColor(0, 0, 0, 0),
      );

      expect(pixel.r, inInclusiveRange(34, 42));
      expect(pixel.g, inInclusiveRange(34, 42));
      expect(pixel.b, inInclusiveRange(34, 42));
      expect(pixel.a, inInclusiveRange(120, 136));
    },
  );

  test(
    'LoveFlameHarnessGame applies desaturation shaders with color masks',
    () async {
      final imageData = LoveImageData(width: 4, height: 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          imageData.setPixel(x, y, const LoveColor(1, 0, 0, 1));
        }
      }
      final image = LoveImage(
        source: 'shader-state-mask',
        width: 4,
        height: 4,
        imageData: imageData,
        preferImageDataRendering: true,
      );
      final shader = LoveShader.fromSource(_desaturationTintShaderSource)
        ..send('tint', <Object?>[1.0, 1.0, 1.0, 1 / 0.299])
        ..send('strength', 1.0);

      final pixel = await _renderCenterPixel(
        commands: <LoveDrawCommand>[
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
        ],
        backgroundColor: const LoveColor(0, 1, 0, 1),
        prepareGraphics: (graphics) {
          graphics.colorMask = const LoveGraphicsColorMask(
            red: true,
            green: false,
            blue: false,
            alpha: false,
          );
        },
      );

      expect(pixel.r, inInclusiveRange(72, 82));
      expect(pixel.g, inInclusiveRange(250, 255));
      expect(pixel.b, lessThan(10));
      expect(pixel.a, 255);
    },
  );
}

Future<({int r, int g, int b, int a})> _renderCenterPixel({
  required List<LoveDrawCommand> commands,
  required LoveColor backgroundColor,
  void Function(dynamic graphics)? prepareGraphics,
}) async {
  final game = LoveFlameHarnessGame();
  final graphics = game.host.graphics;
  game.host.windowMetrics = const LoveWindowMetrics(width: 4, height: 4);
  graphics.backgroundColor = backgroundColor;

  graphics.beginFrame();
  prepareGraphics?.call(graphics);
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

  return _pixelAt(data!.buffer.asUint8List(), 4, 2, 2);
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
