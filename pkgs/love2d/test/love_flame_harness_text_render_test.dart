import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LoveFlameHarnessGame renders centered printf text within the full wrap box',
    (tester) async {
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

      const boundaryKey = Key('frame-boundary');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 640,
              height: 480,
              child: RepaintBoundary(
                key: boundaryKey,
                child: CustomPaint(
                  painter: _LoveFlameHarnessPainter(game: game),
                  size: const Size(640, 480),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage(pixelRatio: 1);
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

class _LoveFlameHarnessPainter extends CustomPainter {
  _LoveFlameHarnessPainter({required this.game});

  final LoveFlameHarnessGame game;

  @override
  void paint(Canvas canvas, Size size) {
    game.onGameResize(Vector2(size.width, size.height));
    game.render(canvas);
  }

  @override
  bool shouldRepaint(covariant _LoveFlameHarnessPainter oldDelegate) =>
      !identical(oldDelegate.game, game);
}
