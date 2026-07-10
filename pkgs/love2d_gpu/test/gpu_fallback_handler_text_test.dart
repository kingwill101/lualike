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
    handler.renderFallback(canvas, snapshot, const ui.Size(64, 64), [0]);

    final picture = recorder.endRecording();
    addTearDown(picture.dispose);
    final image = await picture.toImage(64, 64);
    addTearDown(image.dispose);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(data, isNotNull);
    final pixels = data!.buffer.asUint8List();
    expect(
      pixels.any((value) => value != 0),
      isTrue,
      reason: 'expected the fallback overlay to draw non-transparent text',
    );
  });
}
