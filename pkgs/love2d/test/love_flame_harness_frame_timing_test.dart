import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'test_support/flame_harness_render_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LoveFlameHarnessGame summarizes recent frame timings', () async {
    final game = LoveFlameHarnessGame();
    const windowMetrics = LoveWindowMetrics(width: 4, height: 4);
    game.host.windowMetrics = windowMetrics;
    game.onGameResize(
      Vector2(windowMetrics.width.toDouble(), windowMetrics.height.toDouble()),
    );
    final graphics = game.host.graphics;
    final fallbackImage = LoveImage(
      source: 'frame-timing-fallback-image',
      width: 1,
      height: 1,
      imageData: LoveImageData(width: 1, height: 1)
        ..setPixel(0, 0, const LoveColor(1, 0, 0, 1)),
      preferImageDataRendering: true,
    );
    final atlasImage = await loveImageFromRgbaPixels(
      source: 'frame-timing-atlas-image',
      width: 1,
      height: 1,
      pixels: Uint8List.fromList(const <int>[255, 255, 255, 255]),
      preferImageDataRendering: true,
    );
    addTearDown((atlasImage.nativeImage! as ui.Image).dispose);

    await _recordFrame(
      game,
      graphics,
      1 / 60,
      _spriteBatchCommand(image: atlasImage),
    );
    await _recordFrame(
      game,
      graphics,
      1 / 30,
      _rectangleCommand(blendMode: LoveGraphicsBlendMode.replace),
    );
    await _recordFrame(
      game,
      graphics,
      1 / 15,
      _imageCommand(
        image: fallbackImage,
        blendMode: LoveGraphicsBlendMode.screen,
      ),
    );

    final stats = game.frameTimingStats;

    expect(stats.sampleCount, 3);
    expect(
      stats.averageDeltaSeconds,
      closeTo(((1 / 60) + (1 / 30) + (1 / 15)) / 3, 1e-9),
    );
    expect(stats.p95DeltaSeconds, closeTo(1 / 15, 1e-9));
    expect(stats.maxDeltaSeconds, closeTo(1 / 15, 1e-9));
    expect(stats.averageRenderedCommands, closeTo(2 / 3, 1e-9));
    expect(stats.maxRenderedCommands, 1);
    expect(stats.averageAtlasBatchCommands, closeTo(1 / 3, 1e-9));
    expect(stats.maxAtlasBatchCommands, 1);
    expect(stats.averageAtlasBatchItems, closeTo(2 / 3, 1e-9));
    expect(stats.maxAtlasBatchItems, 2);
    expect(stats.averageTextPainterCacheHits, 0);
    expect(stats.maxTextPainterCacheHits, 0);
    expect(stats.averageTextPainterCacheMisses, 0);
    expect(stats.maxTextPainterCacheMisses, 0);
    expect(stats.averageTextLayoutDuration, Duration.zero);
    expect(stats.maxTextLayoutDuration, Duration.zero);
    expect(stats.averageSaveLayers, closeTo(1 / 3, 1e-9));
    expect(stats.maxSaveLayers, 1);
    expect(stats.averageSoftwareSurfaceFallbacks, closeTo(1 / 3, 1e-9));
    expect(stats.maxSoftwareSurfaceFallbacks, 1);
    expect(stats.lastFrame.deltaSeconds, closeTo(1 / 15, 1e-9));
    expect(stats.lastFrame.renderStats.softwareSurfaceFallbacks, 1);
    expect(stats.lastFrame.renderStats.renderedCommands, 0);
    expect(game.recentFrameTimingSamples, hasLength(3));
    expect(
      stats.maxUpdateDuration.inMicroseconds,
      greaterThanOrEqualTo(stats.p95UpdateDuration.inMicroseconds),
    );
    expect(
      stats.maxRenderDuration.inMicroseconds,
      greaterThanOrEqualTo(stats.p95RenderDuration.inMicroseconds),
    );
    expect(
      stats.maxCpuFrameDuration.inMicroseconds,
      greaterThanOrEqualTo(stats.p95CpuFrameDuration.inMicroseconds),
    );
  });

  test('LoveFlameHarnessGame can reset recent frame timings', () async {
    final game = LoveFlameHarnessGame();
    const windowMetrics = LoveWindowMetrics(width: 4, height: 4);
    game.host.windowMetrics = windowMetrics;
    game.onGameResize(
      Vector2(windowMetrics.width.toDouble(), windowMetrics.height.toDouble()),
    );

    await _recordFrame(game, game.host.graphics, 1 / 60, _rectangleCommand());

    expect(game.frameTimingStats.sampleCount, 1);
    expect(game.recentFrameTimingSamples, hasLength(1));

    game.resetFrameTimingStats();

    expect(game.frameTimingStats.sampleCount, 0);
    expect(game.recentFrameTimingSamples, isEmpty);
  });
}

Future<void> _recordFrame(
  LoveFlameHarnessGame game,
  LoveGraphicsFrame graphics,
  double dt,
  LoveDrawCommand command,
) async {
  graphics.beginFrame();
  graphics.addCommand(command);
  game.presentFrame(graphics.snapshotScreenSurface());
  game.update(dt);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  game.render(canvas);
  final picture = recorder.endRecording();
  picture.dispose();
}

LoveRectangleCommand _rectangleCommand({
  LoveGraphicsBlendMode blendMode = LoveGraphicsBlendMode.alpha,
}) {
  return LoveRectangleCommand(
    color: const LoveColor(1, 0, 0, 0.5),
    lineWidth: 1,
    lineStyle: LoveGraphicsLineStyle.smooth,
    lineJoin: LoveGraphicsLineJoin.miter,
    blendMode: blendMode,
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
  );
}

LoveImageCommand _imageCommand({
  required LoveImage image,
  LoveGraphicsBlendMode blendMode = LoveGraphicsBlendMode.alpha,
}) {
  return LoveImageCommand(
    color: LoveColor.white,
    lineWidth: 1,
    lineStyle: LoveGraphicsLineStyle.smooth,
    lineJoin: LoveGraphicsLineJoin.miter,
    blendMode: blendMode,
    blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: false,
    scissor: null,
    shader: null,
    transform: vm.Matrix4.identity(),
    drawTransform: vm.Matrix4.identity(),
    image: image,
  );
}

LoveSpriteBatchCommand _spriteBatchCommand({required LoveImage image}) {
  final spriteBatch = LoveSpriteBatch(texture: image, bufferSize: 2)
    ..setColor(const LoveColor(1, 0, 0, 1))
    ..add(vm.Matrix4.identity())
    ..setColor(const LoveColor(0, 1, 0, 1))
    ..add(vm.Matrix4.translationValues(1, 0, 0));
  return LoveSpriteBatchCommand(
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
  );
}
