import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

const String _solidColorAssetKey =
    'test_assets/shaders/runtime_effect_solid_color.frag';
const String _textureAssetKey =
    'test_assets/shaders/runtime_effect_uniform_texture.frag';

const String _solidColorShaderSource =
    '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: $_solidColorAssetKey
extern vec4 uColor;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return uColor;
}
''';

const String _textureShaderSource =
    '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: $_textureAssetKey
extern Image uTexture;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return Texel(uTexture, vec2(0.5, 0.5));
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registered fragment shader test assets load', () async {
    final solid = await ui.FragmentProgram.fromAsset(_solidColorAssetKey);
    final texture = await ui.FragmentProgram.fromAsset(_textureAssetKey);
    expect(solid, isNotNull);
    expect(texture, isNotNull);
  });

  test(
    'LoveFlameHarnessGame renders registered fragment shaders for shape draws',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 1, height: 1);

      final shader = LoveShader.fromSource(_solidColorShaderSource)
        ..send('uColor', <Object?>[0.0, 1.0, 0.0, 1.0]);

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
          transform: vm.Matrix4.identity(),
          mode: LoveGraphicsDrawMode.fill,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
      );
      game.presentFrame(graphics.snapshotScreenSurface());

      game.onGameResize(Vector2(12, 12));
      final pixel = await _renderUntil(
        game,
        predicate: (pixel) => pixel.g > 220 && pixel.r < 40 && pixel.b < 40,
      );

      expect(pixel.r, lessThan(40));
      expect(pixel.g, greaterThan(220));
      expect(pixel.b, lessThan(40));
      expect(pixel.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame binds sampler uniforms for registered fragment shaders',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 1, height: 1);

      final nativeImage = await _singlePixelImage(const LoveColor(1, 0, 0, 1));
      addTearDown(nativeImage.dispose);

      final samplerImage = LoveImage(
        source: 'registered-texture',
        width: 1,
        height: 1,
        nativeImage: nativeImage,
      );
      final shader = LoveShader.fromSource(_textureShaderSource)
        ..send('uTexture', samplerImage);

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
          transform: vm.Matrix4.identity(),
          mode: LoveGraphicsDrawMode.fill,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
      );
      game.presentFrame(graphics.snapshotScreenSurface());

      game.onGameResize(Vector2(12, 12));
      final pixel = await _renderUntil(
        game,
        predicate: (pixel) => pixel.r > 220 && pixel.g < 40 && pixel.b < 40,
      );

      expect(pixel.r, greaterThan(220));
      expect(pixel.g, lessThan(40));
      expect(pixel.b, lessThan(40));
      expect(pixel.a, 255);
    },
  );
}

Future<({int r, int g, int b, int a})> _renderUntil(
  LoveFlameHarnessGame game, {
  required bool Function(({int r, int g, int b, int a}) pixel) predicate,
  int maxFrames = 20,
  int size = 12,
}) async {
  ({int r, int g, int b, int a})? lastPixel;
  for (var frame = 0; frame < maxFrames; frame++) {
    final rendered = await _renderFrame(game, size);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    rendered.dispose();
    expect(data, isNotNull);
    final pixel = _pixelAt(data!.buffer.asUint8List(), size);
    lastPixel = pixel;
    if (predicate(pixel)) {
      return pixel;
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  return lastPixel!;
}

Future<ui.Image> _renderFrame(LoveFlameHarnessGame game, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  game.render(canvas);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size, size);
  } finally {
    picture.dispose();
  }
}

Future<ui.Image> _singlePixelImage(LoveColor color) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(<int>[
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
      (color.a * 255).round(),
    ]),
    1,
    1,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
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
