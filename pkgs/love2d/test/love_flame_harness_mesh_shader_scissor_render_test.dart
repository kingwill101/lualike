import 'dart:async';
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
    'LoveFlameHarnessGame applies radial gradient mesh shaders under scissor clipping',
    () async {
      final mesh =
          LoveMesh(
            vertices: const <LoveMeshVertex>[
              LoveMeshVertex(x: 0, y: 0, u: 0, v: 0),
              LoveMeshVertex(x: 10, y: 0, u: 1, v: 0),
              LoveMeshVertex(x: 10, y: 10, u: 1, v: 1),
              LoveMeshVertex(x: 0, y: 10, u: 0, v: 1),
            ],
            drawMode: LoveMeshDrawMode.fan,
            usage: LoveMeshUsage.staticUsage,
          )..setImageTexture(
            LoveImage(
              source: 'mesh-shader-scissor-radial',
              width: 1,
              height: 1,
              imageData: LoveImageData(width: 1, height: 1)
                ..setPixel(0, 0, const LoveColor(1, 0, 0, 1)),
              nativeImage: await _imageFromPixels(
                Uint8List.fromList(<int>[255, 0, 0, 255]),
                1,
                1,
              ),
            ),
          );
      final shader = LoveShader.fromSource(_radialGradientShaderSource)
        ..send('innerRadius', 0.0)
        ..send('outerRadius', 4.5)
        ..send('center', <Object?>[5.5, 5.5])
        ..send('colorInner', <Object?>[1.0, 1.0, 1.0, 1.0])
        ..send('colorOuter', <Object?>[0.0, 0.0, 0.0, 1.0]);

      final pixels = await _renderPixels(
        <LoveDrawCommand>[
          LoveMeshCommand(
            color: LoveColor.white,
            lineWidth: 1,
            lineStyle: LoveGraphicsLineStyle.smooth,
            lineJoin: LoveGraphicsLineJoin.miter,
            blendMode: LoveGraphicsBlendMode.alpha,
            blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
            colorMask: LoveGraphicsColorMask.all,
            wireframe: false,
            scissor: const LoveScissorRect(x: 3, y: 3, width: 4, height: 4),
            shader: shader,
            transform: vm.Matrix4.identity(),
            drawTransform: vm.Matrix4.identity(),
            mesh: mesh,
            frontFaceWinding: LoveGraphicsVertexWinding.ccw,
            cullMode: LoveGraphicsCullMode.none,
          ),
        ],
        outsideSample: const (x: 0, y: 5),
      );

      expect(pixels.outside.r, lessThan(10));
      expect(pixels.outside.g, inInclusiveRange(250, 255));
      expect(pixels.outside.b, lessThan(10));
      expect(pixels.outside.a, 255);

      expect(pixels.inside.r, inInclusiveRange(240, 255));
      expect(pixels.inside.g, lessThan(15));
      expect(pixels.inside.b, lessThan(15));
      expect(pixels.inside.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies desaturation mesh shaders under scissor clipping',
    () async {
      final mesh =
          LoveMesh(
            vertices: const <LoveMeshVertex>[
              LoveMeshVertex(x: 0, y: 0, u: 0, v: 0),
              LoveMeshVertex(x: 10, y: 0, u: 1, v: 0),
              LoveMeshVertex(x: 10, y: 10, u: 1, v: 1),
              LoveMeshVertex(x: 0, y: 10, u: 0, v: 1),
            ],
            drawMode: LoveMeshDrawMode.fan,
            usage: LoveMeshUsage.staticUsage,
          )..setImageTexture(
            LoveImage(
              source: 'mesh-shader-scissor-desaturation',
              width: 1,
              height: 1,
              imageData: LoveImageData(width: 1, height: 1)
                ..setPixel(0, 0, const LoveColor(1, 0, 0, 1)),
            ),
          );
      final shader = LoveShader.fromSource(_desaturationTintShaderSource)
        ..send('tint', <Object?>[1.0, 1.0, 1.0, 1 / 0.299])
        ..send('strength', 1.0);

      final pixels = await _renderPixels(<LoveDrawCommand>[
        LoveMeshCommand(
          color: LoveColor.white,
          lineWidth: 1,
          lineStyle: LoveGraphicsLineStyle.smooth,
          lineJoin: LoveGraphicsLineJoin.miter,
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
          colorMask: LoveGraphicsColorMask.all,
          wireframe: false,
          scissor: const LoveScissorRect(x: 3, y: 3, width: 4, height: 4),
          shader: shader,
          transform: vm.Matrix4.identity(),
          drawTransform: vm.Matrix4.identity(),
          mesh: mesh,
          frontFaceWinding: LoveGraphicsVertexWinding.ccw,
          cullMode: LoveGraphicsCullMode.none,
        ),
      ]);

      expect(pixels.outside.r, lessThan(10));
      expect(pixels.outside.g, inInclusiveRange(250, 255));
      expect(pixels.outside.b, lessThan(10));
      expect(pixels.outside.a, 255);

      expect(pixels.inside.r, inInclusiveRange(72, 82));
      expect(pixels.inside.g, inInclusiveRange(72, 82));
      expect(pixels.inside.b, inInclusiveRange(72, 82));
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
_renderPixels(
  List<LoveDrawCommand> commands, {
  ({int x, int y}) insideSample = const (x: 5, y: 5),
  ({int x, int y}) outsideSample = const (x: 0, y: 0),
}) async {
  final game = LoveFlameHarnessGame();
  final graphics = game.host.graphics;
  game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);
  graphics.backgroundColor = const LoveColor(0, 1, 0, 1);

  graphics.beginFrame();
  for (final command in commands) {
    graphics.addCommand(command);
  }
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

  final raw = data!.buffer.asUint8List();
  return (
    outside: _pixelAt(raw, 10, outsideSample.x, outsideSample.y),
    inside: _pixelAt(raw, 10, insideSample.x, insideSample.y),
  );
}

Future<ui.Image> _imageFromPixels(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
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
