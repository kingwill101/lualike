import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LoveFlameHarnessGame renders textured meshes', () async {
    final game = LoveFlameHarnessGame();
    final graphics = game.host.graphics;
    game.host.windowMetrics = const LoveWindowMetrics(width: 10, height: 10);

    final imageData = LoveImageData(width: 2, height: 2)
      ..setPixel(0, 0, const LoveColor(1, 0, 0, 1))
      ..setPixel(1, 0, const LoveColor(0, 1, 0, 1))
      ..setPixel(0, 1, const LoveColor(0, 0, 1, 1))
      ..setPixel(1, 1, const LoveColor(1, 1, 1, 1));
    final image = LoveImage(
      source: 'mesh-texture',
      width: 2,
      height: 2,
      imageData: imageData,
      nativeImage: await _imageFromPixels(
        Uint8List.fromList(<int>[
          255,
          0,
          0,
          255,
          0,
          255,
          0,
          255,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
          255,
        ]),
        2,
        2,
      ),
    );

    final mesh = LoveMesh(
      vertices: const <LoveMeshVertex>[
        LoveMeshVertex(x: 0, y: 0, u: 0, v: 0),
        LoveMeshVertex(x: 10, y: 0, u: 1, v: 0),
        LoveMeshVertex(x: 10, y: 10, u: 1, v: 1),
        LoveMeshVertex(x: 0, y: 10, u: 0, v: 1),
      ],
      drawMode: LoveMeshDrawMode.fan,
      usage: LoveMeshUsage.staticUsage,
    )..setImageTexture(image);

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
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);

    final pixels = data!.buffer.asUint8List();
    final topLeft = _pixelAt(pixels, rendered.width, 2, 2);
    final topRight = _pixelAt(pixels, rendered.width, 7, 2);
    final bottomLeft = _pixelAt(pixels, rendered.width, 2, 7);
    final bottomRight = _pixelAt(pixels, rendered.width, 7, 7);
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
  });
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
