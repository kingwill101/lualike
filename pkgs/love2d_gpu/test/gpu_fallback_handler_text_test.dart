import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/src/renderer/gpu_fallback_handler.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GpuFallbackHandler renders text through the canvas backend', () async {
    final handler = GpuFallbackHandler(
      canvasBackend: LoveCanvasRenderBackend(),
    );

    final snapshot = LoveGraphicsSurfaceSnapshot(
      clearColor: const LoveColor(0, 0, 0, 0),
      clearColorMask: LoveGraphicsColorMask.all,
      clearStencil: 0,
      clearScissor: null,
      commands: <LoveDrawCommand>[
        LoveTextCommand(
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
          textTransform: vm.Matrix4.translationValues(0, 8, 0),
          font: LoveFont(size: 24, family: 'monospace'),
          spans: const <LoveTextSpan>[LoveTextSpan(text: 'A')],
          x: 0,
          y: 8,
        ),
      ],
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFF102030), ui.BlendMode.src);
    final stats = LoveRenderStatsAccumulator();
    handler.renderFallback(canvas, snapshot, const ui.Size(64, 64), [
      0,
    ], stats: stats);

    final picture = recorder.endRecording();
    addTearDown(picture.dispose);
    final image = await picture.toImage(64, 64);
    addTearDown(image.dispose);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(data, isNotNull);
    final pixels = data!.buffer.asUint8List();
    expect(stats.hybridFallbackCommands, 1);
    expect(stats.textPainterCacheMisses + stats.textPainterCacheHits, 1);
    expect(pixels.take(4), orderedEquals(const <int>[16, 32, 48, 255]));
    expect(
      pixels.any((value) => value != 0),
      isTrue,
      reason: 'expected the fallback overlay to draw non-transparent text',
    );
  });

  test('software fallback overlay preserves the primary frame', () async {
    final handler = GpuFallbackHandler(
      canvasBackend: LoveCanvasRenderBackend(),
    );
    final snapshot = LoveGraphicsSurfaceSnapshot(
      clearColor: const LoveColor(0, 0, 0, 0),
      clearColorMask: LoveGraphicsColorMask.all,
      clearStencil: 0,
      clearScissor: null,
      commands: <LoveDrawCommand>[
        LoveRectangleCommand(
          color: const LoveColor(0.25, 0, 0, 1),
          lineWidth: 1,
          lineStyle: LoveGraphicsLineStyle.smooth,
          lineJoin: LoveGraphicsLineJoin.miter,
          blendMode: LoveGraphicsBlendMode.alpha,
          blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
          colorMask: const LoveGraphicsColorMask(
            red: true,
            green: false,
            blue: false,
            alpha: true,
          ),
          wireframe: false,
          scissor: null,
          transform: vm.Matrix4.identity(),
          mode: LoveGraphicsDrawMode.fill,
          x: 8,
          y: 8,
          width: 16,
          height: 16,
        ),
      ],
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFF102030), ui.BlendMode.src);
    final stats = LoveRenderStatsAccumulator();
    handler.renderFallback(canvas, snapshot, const ui.Size(32, 32), [
      0,
    ], stats: stats);

    final picture = recorder.endRecording();
    addTearDown(picture.dispose);
    final image = await picture.toImage(32, 32);
    addTearDown(image.dispose);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    final pixels = data!.buffer.asUint8List();

    expect(stats.hybridFallbackCommands, 1);
    expect(stats.softwareSurfaceFallbacks, 0);
    expect(_pixelAt(pixels, 32, 0, 0), const <int>[16, 32, 48, 255]);
    expect(_pixelAt(pixels, 32, 12, 12)[0], greaterThan(16));
  });
}

List<int> _pixelAt(List<int> pixels, int width, int x, int y) {
  final offset = ((y * width) + x) * 4;
  return pixels.sublist(offset, offset + 4);
}
