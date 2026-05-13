import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_live_video_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoveFlameLiveVideoOverlay', () {
    testWidgets(
      'falls back to the layout size when window metrics are not ready yet',
      (tester) async {
        final presentedFrame = ValueNotifier<LoveGraphicsSurfaceSnapshot>(
          LoveGraphicsSurfaceSnapshot(
            clearColor: const LoveColor(0, 0, 0, 1),
            clearColorMask: LoveGraphicsColorMask.all,
            clearStencil: 0,
            clearScissor: null,
            commands: <LoveDrawCommand>[
              _videoCommand(_liveVideo()),
              _rectangleCommand(24),
            ],
          ),
        );
        addTearDown(presentedFrame.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 320,
              height: 180,
              child: LoveFlameLiveVideoOverlay(
                presentedFrameListenable: presentedFrame,
                windowMetricsProvider: () {
                  throw AssertionError('size is not ready');
                },
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CustomPaint), findsOneWidget);
        expect(find.byType(Texture), findsNothing);
      },
    );

    testWidgets(
      'removes overlay repaint segments when the frame no longer has live video',
      (tester) async {
        final presentedFrame = ValueNotifier<LoveGraphicsSurfaceSnapshot>(
          LoveGraphicsSurfaceSnapshot(
            clearColor: const LoveColor(0, 0, 0, 1),
            clearColorMask: LoveGraphicsColorMask.all,
            clearStencil: 0,
            clearScissor: null,
            commands: <LoveDrawCommand>[
              _videoCommand(_liveVideo()),
              _rectangleCommand(24),
            ],
          ),
        );
        addTearDown(presentedFrame.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 320,
              height: 180,
              child: LoveFlameLiveVideoOverlay(
                presentedFrameListenable: presentedFrame,
                windowMetricsProvider: () => const LoveWindowMetrics(
                  width: 320,
                  height: 180,
                  desktopWidth: 320,
                  desktopHeight: 180,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(CustomPaint), findsOneWidget);

        presentedFrame.value = LoveGraphicsSurfaceSnapshot(
          clearColor: const LoveColor(0, 0, 0, 1),
          clearColorMask: LoveGraphicsColorMask.all,
          clearStencil: 0,
          clearScissor: null,
          commands: <LoveDrawCommand>[_rectangleCommand(48)],
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(CustomPaint), findsNothing);
        expect(find.byType(Texture), findsNothing);
      },
    );
  });
}

final class _FakeLivePresentationProvider
    implements LoveVideoFrameProvider, LoveVideoLivePresentation {
  @override
  final Object livePresentationHandle = Object();

  @override
  Future<void> dispose() async {}

  @override
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds) async {
    return null;
  }
}

LoveVideo _liveVideo() {
  return LoveVideo(
    stream: LoveVideoStream(
      filename: 'videos/demo.ogv',
      metadata: const LoveVideoMetadata(pixelWidth: 8, pixelHeight: 4),
    ),
    dpiScale: 1.0,
    frameProvider: _FakeLivePresentationProvider(),
  );
}

LoveVideoCommand _videoCommand(LoveVideo video) {
  return LoveVideoCommand(
    color: LoveColor.white,
    lineWidth: 1.0,
    lineStyle: LoveGraphicsLineStyle.smooth,
    lineJoin: LoveGraphicsLineJoin.none,
    blendMode: LoveGraphicsBlendMode.alpha,
    blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: false,
    scissor: null,
    transform: Matrix4.identity(),
    drawTransform: Matrix4.translationValues(10, 20, 0),
    video: video,
  );
}

LoveRectangleCommand _rectangleCommand(double x) {
  return LoveRectangleCommand(
    color: LoveColor.white,
    lineWidth: 1.0,
    lineStyle: LoveGraphicsLineStyle.smooth,
    lineJoin: LoveGraphicsLineJoin.none,
    blendMode: LoveGraphicsBlendMode.alpha,
    blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: false,
    scissor: null,
    transform: Matrix4.identity(),
    mode: LoveGraphicsDrawMode.fill,
    x: x,
    y: 0,
    width: 16,
    height: 12,
  );
}
