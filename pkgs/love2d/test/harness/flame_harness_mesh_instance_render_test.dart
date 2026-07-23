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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame applies mesh instanceCount for textured ui.Image meshes',
    () async {
      final shader = LoveShader.fromSource(_radialGradientShaderSource)
        ..send('innerRadius', 0.0)
        ..send('outerRadius', 1.0)
        ..send('center', <Object?>[0.5, 0.5])
        ..send('colorInner', <Object?>[1.0, 1.0, 1.0, 0.5])
        ..send('colorOuter', <Object?>[1.0, 1.0, 1.0, 0.5]);
      expect(shader.kind, LoveShaderKind.radialGradient);

      final single = await _renderMeshPixel(
        texture: LoveImage(
          source: 'mesh-fast-instance-texture',
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
        instanceCount: 1,
        shader: shader,
      );
      final repeated = await _renderMeshPixel(
        texture: LoveImage(
          source: 'mesh-fast-instance-texture',
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
        instanceCount: 3,
        shader: shader,
      );

      expect(single.r, greaterThan(0));
      expect(repeated.r, greaterThan(0));
      expect(repeated.r, greaterThan(single.r + 30));
    },
  );

  test(
    'LoveFlameHarnessGame applies mesh instanceCount for software textured meshes',
    () async {
      final single = await _renderMeshPixel(
        texture: LoveImage(
          source: 'mesh-software-instance-texture',
          width: 1,
          height: 1,
          imageData: LoveImageData(width: 1, height: 1)
            ..setPixel(0, 0, const LoveColor(1, 0, 0, 0.5)),
        ),
        instanceCount: 1,
      );
      final repeated = await _renderMeshPixel(
        texture: LoveImage(
          source: 'mesh-software-instance-texture',
          width: 1,
          height: 1,
          imageData: LoveImageData(width: 1, height: 1)
            ..setPixel(0, 0, const LoveColor(1, 0, 0, 0.5)),
        ),
        instanceCount: 3,
      );

      expect(single.r, greaterThan(0));
      expect(repeated.r, greaterThan(0));
      expect(repeated.r, greaterThan(single.r + 30));
    },
  );
}

Future<({int r, int g, int b, int a})> _renderMeshPixel({
  required LoveImage texture,
  required int instanceCount,
  LoveShader? shader,
}) async {
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
      instanceCount: instanceCount,
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
