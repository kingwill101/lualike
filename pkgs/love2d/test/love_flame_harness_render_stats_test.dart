import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'test_support/flame_harness_render_test_support.dart';

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

  test('LoveFlameHarnessGame counts command blend layers', () async {
    final stats = await _renderStats((graphics) {
      graphics.beginFrame();
      graphics.addCommand(
        LoveRectangleCommand(
          color: const LoveColor(1, 0, 0, 0.5),
          lineWidth: 1,
          lineStyle: LoveGraphicsLineStyle.smooth,
          lineJoin: LoveGraphicsLineJoin.miter,
          blendMode: LoveGraphicsBlendMode.replace,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
          colorMask: LoveGraphicsColorMask.all,
          wireframe: false,
          scissor: null,
          transform: vm.Matrix4.identity(),
          mode: LoveGraphicsDrawMode.fill,
          x: 0,
          y: 0,
          width: 4,
          height: 4,
        ),
      );
    });

    expect(stats.renderedCommands, 1);
    expect(stats.commandBlendLayers, 1);
    expect(stats.commandShaderLayers, 0);
    expect(stats.commandRadialMaskLayers, 0);
    expect(stats.totalSaveLayers, 1);
  });

  test(
    'LoveFlameHarnessGame avoids full-surface fallback for additive blend commands',
    () async {
      final stats = await _renderStats((graphics) {
        graphics.beginFrame();
        graphics.addCommand(
          LoveRectangleCommand(
            color: const LoveColor(1, 0, 0, 0.5),
            lineWidth: 1,
            lineStyle: LoveGraphicsLineStyle.smooth,
            lineJoin: LoveGraphicsLineJoin.miter,
            blendMode: LoveGraphicsBlendMode.add,
            blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
            colorMask: LoveGraphicsColorMask.all,
            wireframe: false,
            scissor: null,
            transform: vm.Matrix4.identity(),
            mode: LoveGraphicsDrawMode.fill,
            x: 0,
            y: 0,
            width: 4,
            height: 4,
          ),
        );
      });

      expect(stats.renderedCommands, 0);
      expect(stats.softwareSurfaceFallbacks, 0);
      expect(stats.totalSaveLayers, 0);
    },
  );

  test('LoveFlameHarnessGame counts command shader layers', () async {
    final imageData = LoveImageData(width: 1, height: 1)
      ..setPixel(0, 0, const LoveColor(1, 0, 0, 1));
    final image = LoveImage(
      source: 'stats-shader-image',
      width: 1,
      height: 1,
      imageData: imageData,
      preferImageDataRendering: true,
    );
    final shader = LoveShader.fromSource(_desaturationTintShaderSource)
      ..send('tint', <Object?>[1.0, 1.0, 1.0, 1 / 0.299])
      ..send('strength', 1.0);
    expect(shader.kind, LoveShaderKind.desaturationTint);

    final stats = await _renderStats((graphics) {
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
    });

    expect(stats.renderedCommands, 1);
    expect(stats.commandBlendLayers, 0);
    expect(stats.commandShaderLayers, 1);
    expect(stats.totalSaveLayers, 1);
  });

  test('LoveFlameHarnessGame counts radial mask layers', () async {
    final shader = LoveShader.fromSource(_radialGradientShaderSource)
      ..send('innerRadius', 0.0)
      ..send('outerRadius', 4.0)
      ..send('center', <Object?>[5.5, 5.5])
      ..send('colorInner', <Object?>[1.0, 0.0, 0.0, 1.0])
      ..send('colorOuter', <Object?>[0.0, 0.0, 1.0, 1.0]);
    expect(shader.kind, LoveShaderKind.radialGradient);

    final stats = await _renderStats((graphics) {
      graphics.beginFrame();
      graphics.addCommand(
        LovePointsCommand(
          color: const LoveColor(0, 1, 0, 1),
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
          pointSize: 8,
          points: const <({double x, double y, LoveColor? color})>[
            (x: 5, y: 5, color: null),
          ],
        ),
      );
    }, windowMetrics: const LoveWindowMetrics(width: 10, height: 10));

    expect(stats.renderedCommands, 1);
    expect(stats.commandRadialMaskLayers, 1);
    expect(stats.commandBlendLayers, 0);
    expect(stats.commandShaderLayers, 0);
    expect(stats.totalSaveLayers, 1);
  });

  test('LoveFlameHarnessGame counts software surface fallbacks', () async {
    final imageData = LoveImageData(width: 1, height: 1)
      ..setPixel(0, 0, const LoveColor(1, 0, 0, 1));
    final image = LoveImage(
      source: 'stats-fallback-image',
      width: 1,
      height: 1,
      imageData: imageData,
      preferImageDataRendering: true,
    );
    final stats = await _renderStats((graphics) {
      graphics.beginFrame();
      graphics.addCommand(
        LoveImageCommand(
          color: LoveColor.white,
          lineWidth: 1,
          lineStyle: LoveGraphicsLineStyle.smooth,
          lineJoin: LoveGraphicsLineJoin.miter,
          blendMode: LoveGraphicsBlendMode.screen,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
          colorMask: LoveGraphicsColorMask.all,
          wireframe: false,
          scissor: null,
          shader: null,
          transform: vm.Matrix4.identity(),
          drawTransform: vm.Matrix4.identity(),
          image: image,
        ),
      );
    });

    expect(stats.renderedCommands, 0);
    expect(stats.softwareSurfaceFallbacks, 1);
    expect(stats.totalSaveLayers, 0);
  });

  test(
    'LoveFlameHarnessGame counts atlas batch usage for sprite batches',
    () async {
      final image = await loveImageFromRgbaPixels(
        source: 'stats-sprite-batch-image',
        width: 1,
        height: 1,
        pixels: Uint8List.fromList(const <int>[255, 255, 255, 255]),
        preferImageDataRendering: true,
      );
      addTearDown((image.nativeImage! as ui.Image).dispose);

      final spriteBatch = LoveSpriteBatch(texture: image, bufferSize: 2)
        ..setColor(const LoveColor(1, 0, 0, 1))
        ..add(vm.Matrix4.identity())
        ..setColor(const LoveColor(0, 1, 0, 1))
        ..add(vm.Matrix4.translationValues(1, 0, 0));

      final stats = await _renderStats((graphics) {
        graphics.beginFrame();
        graphics.addCommand(
          LoveSpriteBatchCommand(
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
            spriteBatch: spriteBatch,
          ),
        );
      }, windowMetrics: const LoveWindowMetrics(width: 2, height: 1));

      expect(stats.renderedCommands, 1);
      expect(stats.atlasBatchCommands, 1);
      expect(stats.atlasBatchItems, 2);
      expect(stats.softwareSurfaceFallbacks, 0);
      expect(stats.totalSaveLayers, 0);
    },
  );

  test(
    'LoveFlameHarnessGame counts atlas batch usage for particle systems',
    () async {
      final image = await loveImageFromRgbaPixels(
        source: 'stats-particle-batch-image',
        width: 1,
        height: 1,
        pixels: Uint8List.fromList(const <int>[255, 255, 255, 255]),
        preferImageDataRendering: true,
      );
      addTearDown((image.nativeImage! as ui.Image).dispose);

      final particleSnapshot = LoveParticleSystemSnapshot(
        texture: image,
        particles: <LoveParticleDrawEntry>[
          LoveParticleDrawEntry(
            transform: vm.Matrix4.identity(),
            color: const LoveColor(1, 0, 0, 1),
          ),
          LoveParticleDrawEntry(
            transform: vm.Matrix4.translationValues(1, 0, 0),
            color: const LoveColor(0, 1, 0, 1),
          ),
        ],
      );

      final stats = await _renderStats((graphics) {
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
      }, windowMetrics: const LoveWindowMetrics(width: 2, height: 1));

      expect(stats.renderedCommands, 1);
      expect(stats.atlasBatchCommands, 1);
      expect(stats.atlasBatchItems, 2);
      expect(stats.softwareSurfaceFallbacks, 0);
      expect(stats.totalSaveLayers, 0);
    },
  );

  test(
    'LoveFlameHarnessGame tracks text painter cache misses and hits',
    () async {
      const probeText = 'stats-text-layout-cache-probe-2026-04-22';

      final firstStats = await _renderStats((graphics) {
        graphics.beginFrame();
        graphics.addCommand(_textCommand(probeText));
      });
      expect(firstStats.textPainterCacheMisses, 1);
      expect(firstStats.textPainterCacheHits, 0);

      final secondStats = await _renderStats((graphics) {
        graphics.beginFrame();
        graphics.addCommand(_textCommand(probeText));
      });
      expect(secondStats.textPainterCacheMisses, 0);
      expect(secondStats.textPainterCacheHits, 1);
    },
  );

  test(
    'LoveFlameHarnessGame tracks print text painter cache misses and hits',
    () async {
      const probeText = 'stats-print-layout-cache-probe-2026-04-22';

      final firstStats = await _renderStats((graphics) {
        graphics.beginFrame();
        graphics.addCommand(_printTextCommand(probeText));
      });
      expect(firstStats.textPainterCacheMisses, 1);
      expect(firstStats.textPainterCacheHits, 0);

      final secondStats = await _renderStats((graphics) {
        graphics.beginFrame();
        graphics.addCommand(_printTextCommand(probeText));
      });
      expect(secondStats.textPainterCacheMisses, 0);
      expect(secondStats.textPainterCacheHits, 1);
    },
  );
}

Future<LoveFlameRenderStats> _renderStats(
  void Function(LoveGraphicsFrame graphics) record, {
  LoveWindowMetrics windowMetrics = const LoveWindowMetrics(
    width: 4,
    height: 4,
  ),
}) async {
  final game = LoveFlameHarnessGame();
  final graphics = game.host.graphics;
  game.host.windowMetrics = windowMetrics;

  record(graphics);
  game.presentFrame(graphics.snapshotScreenSurface());

  game.onGameResize(
    Vector2(windowMetrics.width.toDouble(), windowMetrics.height.toDouble()),
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  game.render(canvas);
  final picture = recorder.endRecording();
  picture.dispose();
  return game.lastRenderStats;
}

LoveTextObjectCommand _textCommand(String text) {
  final drawable = LoveTextDrawable(
    font: LoveFont(size: 16, family: 'monospace'),
  )..set(<LoveTextSpan>[LoveTextSpan(text: text)]);
  return LoveTextObjectCommand(
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
    textObject: drawable,
  );
}

LoveTextCommand _printTextCommand(String text) {
  return LoveTextCommand(
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
    textTransform: vm.Matrix4.identity(),
    font: LoveFont(size: 16, family: 'monospace'),
    spans: <LoveTextSpan>[LoveTextSpan(text: text)],
    x: 0,
    y: 0,
  );
}
