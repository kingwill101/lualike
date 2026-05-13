import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame renders centered printf text within the full wrap box',
    () async {
      final game = LoveFlameHarnessGame();
      game.host.windowMetrics = const LoveWindowMetrics(
        width: 960,
        height: 540,
      );
      game.presentFrame(
        LoveGraphicsSurfaceSnapshot(
          clearColor: LoveColor.black,
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
              transform: vm.Matrix4.identity(),
              textTransform: vm.Matrix4.translationValues(0, 120, 0),
              font: LoveFont(size: 40, family: 'monospace'),
              spans: const <LoveTextSpan>[LoveTextSpan(text: 'PLAY')],
              x: 0,
              y: 120,
              limit: 960,
              align: 'center',
            ),
          ],
        ),
      );

      game.onGameResize(Vector2(640, 480));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      game.render(canvas);
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      final image = await picture.toImage(640, 480);
      addTearDown(image.dispose);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data, isNotNull);

      final pixels = data!.buffer.asUint8List();
      var minX = image.width;
      var maxX = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final offset = ((y * image.width) + x) * 4;
          final red = pixels[offset];
          final green = pixels[offset + 1];
          final blue = pixels[offset + 2];
          if (red > 200 && green > 200 && blue > 200) {
            if (x < minX) {
              minX = x;
            }
            if (x > maxX) {
              maxX = x;
            }
          }
        }
      }

      expect(maxX, greaterThan(minX));
      final centerX = (minX + maxX) / 2;
      expect(centerX, closeTo(320, 40));
      expect(minX, greaterThan(200));
    },
  );
}
