import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';
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
    'LoveFlameHarnessGame applies desaturation tint shaders to textured ui.Image meshes',
    () async {
      final pixel = await _renderMeshPixel(
        LoveImage(
          source: 'mesh-desaturation-ui-image',
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

      expect(pixel.r, inInclusiveRange(72, 82));
      expect(pixel.g, inInclusiveRange(72, 82));
      expect(pixel.b, inInclusiveRange(72, 82));
      expect(pixel.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies desaturation tint shaders to imageData-backed textured meshes',
    () async {
      final pixel = await _renderMeshPixel(
        LoveImage(
          source: 'mesh-desaturation-image-data',
          width: 1,
          height: 1,
          imageData: LoveImageData(width: 1, height: 1)
            ..setPixel(0, 0, const LoveColor(1, 0, 0, 1)),
        ),
      );

      expect(pixel.r, inInclusiveRange(72, 82));
      expect(pixel.g, inInclusiveRange(72, 82));
      expect(pixel.b, inInclusiveRange(72, 82));
      expect(pixel.a, 255);
    },
  );
}

Future<({int r, int g, int b, int a})> _renderMeshPixel(
  LoveImage texture,
) async {
  final game = LoveFlameHarnessGame();
  final graphics = game.host.graphics;
  game.host.windowMetrics = const LoveWindowMetrics(width: 1, height: 1);

  final mesh = LoveMesh(
    vertices: const <LoveMeshVertex>[
      LoveMeshVertex(x: 0, y: 0, u: 0, v: 0),
      LoveMeshVertex(x: 1, y: 0, u: 1, v: 0),
      LoveMeshVertex(x: 1, y: 1, u: 1, v: 1),
      LoveMeshVertex(x: 0, y: 1, u: 0, v: 1),
    ],
    drawMode: LoveMeshDrawMode.fan,
    usage: LoveMeshUsage.staticUsage,
  )..setImageTexture(texture);
  final shader = LoveShader.fromSource(_desaturationTintShaderSource)
    ..send('tint', <Object?>[1.0, 1.0, 1.0, 1 / 0.299])
    ..send('strength', 1.0);
  expect(shader.kind, LoveShaderKind.desaturationTint);

  graphics.beginFrame();
  graphics.addCommand(
    LoveMeshCommand(
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
      mesh: mesh,
      frontFaceWinding: LoveGraphicsVertexWinding.ccw,
      cullMode: LoveGraphicsCullMode.none,
    ),
  );
  game.presentFrame(graphics.snapshotScreenSurface());

  game.onGameResize(Vector2(1, 1));
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  game.render(canvas);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(1, 1);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  rendered.dispose();
  expect(data, isNotNull);

  final pixels = data!.buffer.asUint8List();
  return (r: pixels[0], g: pixels[1], b: pixels[2], a: pixels[3]);
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
