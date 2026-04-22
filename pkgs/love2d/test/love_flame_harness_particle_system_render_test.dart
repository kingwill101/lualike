import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LoveFlameHarnessGame renders particle system draw commands', () async {
    final game = LoveFlameHarnessGame();
    final graphics = game.host.graphics;
    game.host.windowMetrics = const LoveWindowMetrics(width: 4, height: 4);

    final imageData = LoveImageData(width: 1, height: 1)
      ..setPixel(0, 0, const LoveColor(1, 0, 0, 1));
    final image = LoveImage(
      source: 'particle-red',
      width: 1,
      height: 1,
      imageData: imageData,
      preferImageDataRendering: true,
    );
    final particleSnapshot = LoveParticleSystemSnapshot(
      texture: image,
      particles: <LoveParticleDrawEntry>[
        LoveParticleDrawEntry(
          transform: vm.Matrix4.identity(),
          color: LoveColor.white,
        ),
      ],
    );

    graphics.beginFrame();
    graphics.addCommand(
      LoveParticleSystemCommand(
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
        particleSystem: particleSnapshot,
      ),
    );
    game.presentFrame(graphics.snapshotScreenSurface());

    game.onGameResize(Vector2(4, 4));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    game.render(canvas);
    final picture = recorder.endRecording();
    addTearDown(picture.dispose);
    final rendered = await picture.toImage(4, 4);
    addTearDown(rendered.dispose);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);

    final pixel = _pixelAt(data!.buffer.asUint8List(), rendered.width, 0, 0);
    expect(pixel.r, 255);
    expect(pixel.g, 0);
    expect(pixel.b, 0);
    expect(pixel.a, 255);
  });
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
