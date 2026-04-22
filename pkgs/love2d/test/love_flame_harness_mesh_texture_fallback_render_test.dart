import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';
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
    'LoveFlameHarnessGame renders textured meshes from imageData-only textures',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final image = LoveImage(
        source: 'mesh-texture-image-data-only',
        width: 2,
        height: 2,
        imageData: LoveImageData(width: 2, height: 2)
          ..setPixel(0, 0, const LoveColor(1, 0, 0, 1))
          ..setPixel(1, 0, const LoveColor(0, 1, 0, 1))
          ..setPixel(0, 1, const LoveColor(0, 0, 1, 1))
          ..setPixel(1, 1, const LoveColor(1, 1, 1, 1)),
      );

      _queueFullScreenMesh(
        graphics: graphics,
        mesh: _fullScreenMesh()..setImageTexture(image),
      );

      final pixels = await _renderPixels(game);
      final topLeft = _pixelAt(pixels, 10, 2, 2);
      final topRight = _pixelAt(pixels, 10, 7, 2);
      final bottomLeft = _pixelAt(pixels, 10, 2, 7);
      final bottomRight = _pixelAt(pixels, 10, 7, 7);
      expect(topLeft.r, inInclusiveRange(240, 255));
      expect(topLeft.g, inInclusiveRange(0, 15));
      expect(topLeft.b, inInclusiveRange(0, 15));
      expect(topRight.r, inInclusiveRange(0, 15));
      expect(topRight.g, inInclusiveRange(240, 255));
      expect(topRight.b, inInclusiveRange(0, 15));
      expect(bottomLeft.r, inInclusiveRange(0, 15));
      expect(bottomLeft.g, inInclusiveRange(0, 15));
      expect(bottomLeft.b, inInclusiveRange(240, 255));
      expect(bottomRight.r, inInclusiveRange(240, 255));
      expect(bottomRight.g, inInclusiveRange(240, 255));
      expect(bottomRight.b, inInclusiveRange(240, 255));
    },
  );

  test(
    'LoveFlameHarnessGame renders textured meshes from canvas snapshots',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final canvasTexture = LoveCanvas(
        source: 'mesh-texture-canvas',
        width: 1,
        height: 1,
        dpiScale: 1.0,
        readable: true,
        surface: LoveGraphicsSurface(
          clearColor: const LoveColor(1, 0, 0, 1),
          clearColorMask: LoveGraphicsColorMask.all,
        ),
      );

      _queueFullScreenMesh(
        graphics: graphics,
        mesh: _fullScreenMesh()..setCanvasTexture(canvasTexture),
      );

      final pixels = await _renderPixels(game);
      final center = _pixelAt(pixels, 10, 5, 5);
      expect(center.r, inInclusiveRange(240, 255));
      expect(center.g, inInclusiveRange(0, 15));
      expect(center.b, inInclusiveRange(0, 15));
      expect(center.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame renders canvas mesh textures from snapshot surfaces instead of stale nativeImage data',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final canvasTexture = LoveCanvas(
        source: 'mesh-texture-canvas-stale-native-image',
        width: 1,
        height: 1,
        dpiScale: 1.0,
        readable: true,
        nativeImage: await _imageFromPixels(
          Uint8List.fromList(<int>[255, 0, 0, 255]),
          1,
          1,
        ),
        surface: LoveGraphicsSurface(
          clearColor: const LoveColor(0, 1, 0, 1),
          clearColorMask: LoveGraphicsColorMask.all,
        ),
      );

      _queueFullScreenMesh(
        graphics: graphics,
        mesh: _fullScreenMesh()..setCanvasTexture(canvasTexture),
      );

      final pixels = await _renderPixels(game);
      final center = _pixelAt(pixels, 10, 5, 5);
      expect(center.r, inInclusiveRange(0, 15));
      expect(center.g, inInclusiveRange(240, 255));
      expect(center.b, inInclusiveRange(0, 15));
      expect(center.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies radial gradient shaders to imageData-backed textured meshes',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final image = LoveImage(
        source: 'mesh-red-image-data-only',
        width: 1,
        height: 1,
        imageData: LoveImageData(width: 1, height: 1)
          ..setPixel(0, 0, const LoveColor(1, 0, 0, 1)),
      );
      final shader = LoveShader.fromSource(_radialGradientShaderSource)
        ..send('innerRadius', 0.0)
        ..send('outerRadius', 4.5)
        ..send('center', <Object?>[5.5, 5.5])
        ..send('colorInner', <Object?>[1.0, 1.0, 1.0, 1.0])
        ..send('colorOuter', <Object?>[0.0, 0.0, 0.0, 1.0]);
      expect(shader.kind, LoveShaderKind.radialGradient);

      _queueFullScreenMesh(
        graphics: graphics,
        mesh: _fullScreenMesh()..setImageTexture(image),
        shader: shader,
      );

      final pixels = await _renderPixels(game);
      final center = _pixelAt(pixels, 10, 5, 5);
      final edge = _pixelAt(pixels, 10, 0, 5);
      expect(center.r, inInclusiveRange(240, 255));
      expect(center.g, inInclusiveRange(0, 15));
      expect(center.b, inInclusiveRange(0, 15));
      expect(center.a, 255);
      expect(edge.r, inInclusiveRange(0, 15));
      expect(edge.g, inInclusiveRange(0, 15));
      expect(edge.b, inInclusiveRange(0, 15));
      expect(edge.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies command color modulation to textured ui.Image meshes',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final image = LoveImage(
        source: 'mesh-ui-image-tint-fallback',
        width: 1,
        height: 1,
        imageData: LoveImageData(width: 1, height: 1)
          ..setPixel(0, 0, const LoveColor(1, 0, 0, 1)),
        nativeImage: await _imageFromPixels(
          Uint8List.fromList(<int>[255, 0, 0, 255]),
          1,
          1,
        ),
      );

      _queueFullScreenMesh(
        graphics: graphics,
        mesh: _fullScreenMesh()..setImageTexture(image),
        color: const LoveColor(1, 1, 1, 0.5),
        backgroundColor: const LoveColor(0, 0, 1, 1),
      );

      final pixels = await _renderPixels(game);
      final center = _pixelAt(pixels, 10, 5, 5);
      expect(center.r, inInclusiveRange(120, 140));
      expect(center.g, inInclusiveRange(0, 10));
      expect(center.b, inInclusiveRange(120, 140));
      expect(center.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies uniform vertex color modulation to textured ui.Image meshes',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final image = LoveImage(
        source: 'mesh-ui-image-uniform-vertex-color',
        width: 1,
        height: 1,
        imageData: LoveImageData(width: 1, height: 1)
          ..setPixel(0, 0, const LoveColor(1, 1, 1, 1)),
        nativeImage: await _imageFromPixels(
          Uint8List.fromList(<int>[255, 255, 255, 255]),
          1,
          1,
        ),
      );
      final mesh = LoveMesh(
        vertices: const <LoveMeshVertex>[
          LoveMeshVertex(
            x: 0,
            y: 0,
            u: 0,
            v: 0,
            color: LoveColor(0.5, 1, 1, 1),
          ),
          LoveMeshVertex(
            x: 10,
            y: 0,
            u: 1,
            v: 0,
            color: LoveColor(0.5, 1, 1, 1),
          ),
          LoveMeshVertex(
            x: 10,
            y: 10,
            u: 1,
            v: 1,
            color: LoveColor(0.5, 1, 1, 1),
          ),
          LoveMeshVertex(
            x: 0,
            y: 10,
            u: 0,
            v: 1,
            color: LoveColor(0.5, 1, 1, 1),
          ),
        ],
        drawMode: LoveMeshDrawMode.fan,
        usage: LoveMeshUsage.staticUsage,
      )..setImageTexture(image);

      _queueFullScreenMesh(graphics: graphics, mesh: mesh);

      final pixels = await _renderPixels(game);
      final center = _pixelAt(pixels, 10, 5, 5);
      expect(center.r, inInclusiveRange(120, 140));
      expect(center.g, inInclusiveRange(240, 255));
      expect(center.b, inInclusiveRange(240, 255));
      expect(center.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies non-uniform vertex color modulation to textured ui.Image meshes',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final image = LoveImage(
        source: 'mesh-ui-image-nonuniform-vertex-color',
        width: 1,
        height: 1,
        imageData: LoveImageData(width: 1, height: 1)
          ..setPixel(0, 0, const LoveColor(1, 1, 1, 1)),
        nativeImage: await _imageFromPixels(
          Uint8List.fromList(<int>[255, 255, 255, 255]),
          1,
          1,
        ),
      );
      final mesh = LoveMesh(
        vertices: const <LoveMeshVertex>[
          LoveMeshVertex(x: 0, y: 0, u: 0, v: 0, color: LoveColor(1, 0, 0, 1)),
          LoveMeshVertex(x: 10, y: 0, u: 1, v: 0, color: LoveColor(0, 1, 0, 1)),
          LoveMeshVertex(
            x: 10,
            y: 10,
            u: 1,
            v: 1,
            color: LoveColor(1, 1, 1, 1),
          ),
          LoveMeshVertex(x: 0, y: 10, u: 0, v: 1, color: LoveColor(0, 0, 1, 1)),
        ],
        drawMode: LoveMeshDrawMode.fan,
        usage: LoveMeshUsage.staticUsage,
      )..setImageTexture(image);

      _queueFullScreenMesh(graphics: graphics, mesh: mesh);

      final pixels = await _renderPixels(game);
      final topLeft = _pixelAt(pixels, 10, 2, 2);
      final topRight = _pixelAt(pixels, 10, 7, 2);
      final bottomLeft = _pixelAt(pixels, 10, 2, 7);
      final bottomRight = _pixelAt(pixels, 10, 7, 7);
      expect(topLeft.r, inInclusiveRange(220, 255));
      expect(topLeft.g, inInclusiveRange(40, 90));
      expect(topLeft.b, inInclusiveRange(40, 90));
      expect(topRight.r, inInclusiveRange(100, 160));
      expect(topRight.g, inInclusiveRange(170, 220));
      expect(topRight.b, inInclusiveRange(40, 90));
      expect(bottomLeft.r, inInclusiveRange(100, 160));
      expect(bottomLeft.g, inInclusiveRange(40, 90));
      expect(bottomLeft.b, inInclusiveRange(170, 220));
      expect(bottomRight.r, inInclusiveRange(220, 255));
      expect(bottomRight.g, inInclusiveRange(170, 220));
      expect(bottomRight.b, inInclusiveRange(170, 220));
      expect(bottomRight.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame applies non-uniform vertex alpha modulation to textured ui.Image meshes',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

      final image = LoveImage(
        source: 'mesh-ui-image-nonuniform-vertex-alpha',
        width: 1,
        height: 1,
        imageData: LoveImageData(width: 1, height: 1)
          ..setPixel(0, 0, const LoveColor(1, 1, 1, 1)),
        nativeImage: await _imageFromPixels(
          Uint8List.fromList(<int>[255, 255, 255, 255]),
          1,
          1,
        ),
      );
      final mesh = LoveMesh(
        vertices: const <LoveMeshVertex>[
          LoveMeshVertex(x: 0, y: 0, u: 0, v: 0, color: LoveColor.white),
          LoveMeshVertex(
            x: 10,
            y: 0,
            u: 1,
            v: 0,
            color: LoveColor(1, 1, 1, 0.5),
          ),
          LoveMeshVertex(
            x: 10,
            y: 10,
            u: 1,
            v: 1,
            color: LoveColor(1, 1, 1, 0),
          ),
          LoveMeshVertex(
            x: 0,
            y: 10,
            u: 0,
            v: 1,
            color: LoveColor(1, 1, 1, 0.25),
          ),
        ],
        drawMode: LoveMeshDrawMode.fan,
        usage: LoveMeshUsage.staticUsage,
      )..setImageTexture(image);

      _queueFullScreenMesh(
        graphics: graphics,
        mesh: mesh,
        backgroundColor: const LoveColor(0, 0, 1, 1),
      );

      final pixels = await _renderPixels(game);
      final topLeft = _pixelAt(pixels, 10, 1, 1);
      final topRight = _pixelAt(pixels, 10, 8, 1);
      final bottomLeft = _pixelAt(pixels, 10, 1, 8);
      final bottomRight = _pixelAt(pixels, 10, 8, 8);

      expect(topLeft.r, greaterThan(180));
      expect(topLeft.g, greaterThan(180));
      expect(topLeft.b, greaterThan(210));

      expect(topRight.b, greaterThan(210));
      expect(bottomLeft.b, greaterThan(210));
      expect(bottomRight.r, lessThan(100));
      expect(bottomRight.g, lessThan(100));
      expect(bottomRight.b, greaterThan(210));
      expect(bottomRight.a, 255);

      expect(topLeft.r, greaterThan(topRight.r));
      expect(topRight.r, greaterThan(bottomLeft.r));
      expect(bottomLeft.r, greaterThan(bottomRight.r));
    },
  );
}

LoveMesh _fullScreenMesh() {
  return LoveMesh(
    vertices: const <LoveMeshVertex>[
      LoveMeshVertex(x: 0, y: 0, u: 0, v: 0),
      LoveMeshVertex(x: 10, y: 0, u: 1, v: 0),
      LoveMeshVertex(x: 10, y: 10, u: 1, v: 1),
      LoveMeshVertex(x: 0, y: 10, u: 0, v: 1),
    ],
    drawMode: LoveMeshDrawMode.fan,
    usage: LoveMeshUsage.staticUsage,
  );
}

void _queueFullScreenMesh({
  required LoveGraphicsFrame graphics,
  required LoveMesh mesh,
  LoveShader? shader,
  LoveColor color = LoveColor.white,
  LoveColor? backgroundColor,
}) {
  graphics.beginFrame();
  if (backgroundColor != null) {
    graphics.addCommand(
      LoveRectangleCommand(
        color: backgroundColor,
        lineWidth: 1,
        lineStyle: LoveGraphicsLineStyle.smooth,
        lineJoin: LoveGraphicsLineJoin.miter,
        blendMode: LoveGraphicsBlendMode.alpha,
        blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
        colorMask: LoveGraphicsColorMask.all,
        wireframe: false,
        scissor: null,
        transform: vm.Matrix4.identity(),
        mode: LoveGraphicsDrawMode.fill,
        x: 0,
        y: 0,
        width: 10,
        height: 10,
      ),
    );
  }
  graphics.addCommand(
    LoveMeshCommand(
      color: color,
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
}

Future<Uint8List> _renderPixels(LoveFlameHarnessGame game) async {
  game.presentFrame(game.host.graphics.snapshotScreenSurface());
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
