import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'test_support/flame_harness_render_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame renders atlas-batched sprite batch draw commands',
    () async {
      final game = LoveFlameHarnessGame();
      final graphics = game.host.graphics;
      game.host.windowMetrics = const LoveWindowMetrics(width: 4, height: 2);

      final image = await loveImageFromRgbaPixels(
        source: 'sprite-batch-white',
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
          drawTransform: vm.Matrix4.identity()
            ..scaleByDouble(2.0, 2.0, 1.0, 1.0),
          spriteBatch: spriteBatch,
        ),
      );
      game.presentFrame(graphics.snapshotScreenSurface());

      game.onGameResize(Vector2(4, 2));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      game.render(canvas);
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      final rendered = await picture.toImage(4, 2);
      addTearDown(rendered.dispose);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(data, isNotNull);

      final pixels = data!.buffer.asUint8List();
      final left = rgbaPixelAt(pixels, rendered.width, 1, 1);
      final right = rgbaPixelAt(pixels, rendered.width, 3, 1);
      expect(left.r, inInclusiveRange(240, 255));
      expect(left.g, inInclusiveRange(0, 15));
      expect(left.b, inInclusiveRange(0, 15));
      expect(left.a, 255);
      expect(right.r, inInclusiveRange(0, 15));
      expect(right.g, inInclusiveRange(240, 255));
      expect(right.b, inInclusiveRange(0, 15));
      expect(right.a, 255);
      expect(game.lastRenderStats.atlasBatchCommands, 1);
      expect(game.lastRenderStats.atlasBatchItems, 2);
      expect(game.lastRenderStats.softwareSurfaceFallbacks, 0);
    },
  );
}
