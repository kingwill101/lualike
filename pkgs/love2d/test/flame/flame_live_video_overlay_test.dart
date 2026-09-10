import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_live_video_overlay.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('Love live video overlay sequencing', () {
    test('replays only the commands that need to appear above live videos', () {
      final firstVideo = _liveVideo();
      final secondVideo = _liveVideo();
      final beforeVideo = _rectangleCommand(1);
      final betweenVideos = _rectangleCommand(2);
      final afterVideos = _rectangleCommand(3);

      final entries = buildLoveFlameLiveVideoOverlayEntries(
        LoveGraphicsSurfaceSnapshot(
          clearColor: const LoveColor(0, 0, 0, 1),
          clearColorMask: LoveGraphicsColorMask.all,
          clearStencil: 0,
          clearScissor: null,
          commands: <LoveDrawCommand>[
            beforeVideo,
            _videoCommand(firstVideo),
            betweenVideos,
            _videoCommand(secondVideo),
            afterVideos,
          ],
        ),
      );

      expect(entries, hasLength(4));
      expect(entries[0], isA<LoveFlameLiveVideoOverlayVideoEntry>());
      expect(entries[1], isA<LoveFlameLiveVideoOverlaySurfaceEntry>());
      expect(entries[2], isA<LoveFlameLiveVideoOverlayVideoEntry>());
      expect(entries[3], isA<LoveFlameLiveVideoOverlaySurfaceEntry>());
      expect(
        (entries[1] as LoveFlameLiveVideoOverlaySurfaceEntry).snapshot.commands,
        <LoveDrawCommand>[betweenVideos],
      );
      expect(
        (entries[3] as LoveFlameLiveVideoOverlaySurfaceEntry).snapshot.commands,
        <LoveDrawCommand>[afterVideos],
      );
    });

    test(
      'returns no overlay entries when the frame has no live video commands',
      () {
        final entries = buildLoveFlameLiveVideoOverlayEntries(
          LoveGraphicsSurfaceSnapshot(
            clearColor: const LoveColor(0, 0, 0, 1),
            clearColorMask: LoveGraphicsColorMask.all,
            clearStencil: 0,
            clearScissor: null,
            commands: <LoveDrawCommand>[_rectangleCommand(1)],
          ),
        );

        expect(entries, isEmpty);
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
    width: 4,
    height: 4,
  );
}
