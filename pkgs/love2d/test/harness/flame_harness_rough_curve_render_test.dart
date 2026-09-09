import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rough circles use LOVE automatic point counts', () async {
    final automatic = await _renderCommand(_circleCommand());
    final explicit = await _renderCommand(_circleCommand(pointCount: 20));

    expect(automatic, orderedEquals(explicit));
    expect(_hasColoredPixel(automatic), isTrue);
  });

  test('rough open arcs use LOVE automatic point counts', () async {
    final automatic = await _renderCommand(_arcCommand());
    final explicit = await _renderCommand(_arcCommand(pointCount: 15));

    expect(automatic, orderedEquals(explicit));
    expect(_hasColoredPixel(automatic), isTrue);
  });
}

LoveCircleCommand _circleCommand({int? pointCount}) {
  return LoveCircleCommand(
    color: const LoveColor(0.2, 0.9, 1, 0.7),
    lineWidth: 2,
    lineStyle: LoveGraphicsLineStyle.rough,
    lineJoin: LoveGraphicsLineJoin.miter,
    blendMode: LoveGraphicsBlendMode.alpha,
    blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: false,
    scissor: null,
    shader: null,
    transform: vm.Matrix4.identity(),
    mode: LoveGraphicsDrawMode.line,
    x: 32,
    y: 32,
    radius: 20,
    pointCount: pointCount,
  );
}

LoveArcCommand _arcCommand({int? pointCount}) {
  return LoveArcCommand(
    color: const LoveColor(1, 0.2, 0.7, 0.7),
    lineWidth: 3,
    lineStyle: LoveGraphicsLineStyle.rough,
    lineJoin: LoveGraphicsLineJoin.miter,
    blendMode: LoveGraphicsBlendMode.alpha,
    blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: false,
    scissor: null,
    shader: null,
    transform: vm.Matrix4.identity(),
    drawMode: LoveGraphicsDrawMode.line,
    arcMode: LoveGraphicsArcMode.open,
    x: 32,
    y: 32,
    radius: 20,
    angle1: 0.25,
    angle2: 0.25 + math.pi * 1.5,
    pointCount: pointCount,
  );
}

Future<Uint8List> _renderCommand(LoveDrawCommand command) async {
  final game = LoveFlameHarnessGame();
  final graphics = game.host.graphics;
  game.host.windowMetrics = const LoveWindowMetrics(width: 64, height: 64);
  graphics.beginFrame();
  graphics.addCommand(command);
  game.presentFrame(graphics.snapshotScreenSurface());
  game.onGameResize(Vector2(64, 64));

  final recorder = ui.PictureRecorder();
  game.render(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

bool _hasColoredPixel(Uint8List pixels) {
  for (var offset = 0; offset < pixels.length; offset += 4) {
    if (pixels[offset] > 20 ||
        pixels[offset + 1] > 20 ||
        pixels[offset + 2] > 20) {
      return true;
    }
  }
  return false;
}
