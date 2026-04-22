import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_live_video_overlay_geometry.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  group('Love live video overlay geometry', () {
    test('combines command and draw transforms for full-frame video', () {
      final geometry = computeLoveFlameLiveVideoOverlayGeometry(
        _videoCommand(
          video: _liveVideo(pixelWidth: 8, pixelHeight: 4),
          transform: vm.Matrix4.translationValues(3, 4, 0),
          drawTransform: vm.Matrix4.diagonal3Values(2, 2, 1),
        ),
      );

      expect(geometry, isNotNull);
      expect(geometry!.frameSize, const Size(8, 4));
      expect(geometry.contentSize, const Size(8, 4));
      expect(geometry.contentOffset, Offset.zero);
      expect(geometry.scissorRect, isNull);
      expect(geometry.hasRgbTint, isFalse);
      expect(geometry.alpha, 1.0);

      final point = geometry.transform.transformed3(vm.Vector3(1, 1, 0));
      expect(point.x, closeTo(5.0, 1e-9));
      expect(point.y, closeTo(6.0, 1e-9));
    });

    test('preserves quad crop geometry with dpi-scaled draw transforms', () {
      final video = _liveVideo(pixelWidth: 8, pixelHeight: 4, dpiScale: 2.0);
      final geometry = computeLoveFlameLiveVideoOverlayGeometry(
        _videoCommand(
          video: video,
          quad: LoveQuad(
            x: 4,
            y: 0,
            width: 4,
            height: 2,
            textureWidth: 8,
            textureHeight: 4,
          ),
          drawTransform: vm.Matrix4.translationValues(2, 3, 0)
            ..scaleByDouble(
              video.width / video.pixelWidth,
              video.height / video.pixelHeight,
              1.0,
              1.0,
            ),
        ),
      );

      expect(geometry, isNotNull);
      expect(geometry!.frameSize, const Size(4, 2));
      expect(geometry.contentSize, const Size(8, 4));
      expect(geometry.contentOffset, const Offset(-4, 0));

      final topLeft = geometry.transform.transformed3(vm.Vector3.zero());
      final bottomRight = geometry.transform.transformed3(
        vm.Vector3(geometry.frameSize.width, geometry.frameSize.height, 0),
      );
      expect(topLeft.x, closeTo(2.0, 1e-9));
      expect(topLeft.y, closeTo(3.0, 1e-9));
      expect(bottomRight.x - topLeft.x, closeTo(2.0, 1e-9));
      expect(bottomRight.y - topLeft.y, closeTo(1.0, 1e-9));
    });

    test('captures tint alpha and scissor state', () {
      final geometry = computeLoveFlameLiveVideoOverlayGeometry(
        _videoCommand(
          video: _liveVideo(pixelWidth: 8, pixelHeight: 4),
          color: const LoveColor(0.25, 0.5, 0.75, 0.5),
          scissor: LoveScissorRect(x: -2, y: 4, width: 10, height: 8),
        ),
      );

      expect(geometry, isNotNull);
      expect(geometry!.hasRgbTint, isTrue);
      expect(geometry.rgbTintColor, const Color(0xFF4080BF));
      expect(geometry.alpha, closeTo(0.5, 1e-9));
      expect(geometry.scissorRect, const Rect.fromLTWH(-2, 4, 10, 8));
    });

    test('rejects invalid video and quad dimensions', () {
      expect(
        computeLoveFlameLiveVideoOverlayGeometry(
          _videoCommand(video: _liveVideo(pixelWidth: 0, pixelHeight: 4)),
        ),
        isNull,
      );
      expect(
        computeLoveFlameLiveVideoOverlayGeometry(
          _videoCommand(
            video: _liveVideo(pixelWidth: 8, pixelHeight: 4),
            quad: LoveQuad(
              x: 0,
              y: 0,
              width: 0,
              height: 4,
              textureWidth: 8,
              textureHeight: 4,
            ),
          ),
        ),
        isNull,
      );
    });

    test('clamps scissor rects to overlay bounds', () {
      expect(
        clampLoveFlameLiveVideoOverlayClipRect(
          const Rect.fromLTWH(-3, 4, 20, 10),
          const Size(12, 10),
        ),
        const Rect.fromLTRB(0, 4, 12, 10),
      );
    });
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

LoveVideo _liveVideo({
  required int pixelWidth,
  required int pixelHeight,
  double dpiScale = 1.0,
}) {
  return LoveVideo(
    stream: LoveVideoStream(
      filename: 'videos/demo.ogv',
      metadata: LoveVideoMetadata(
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      ),
    ),
    dpiScale: dpiScale,
    frameProvider: _FakeLivePresentationProvider(),
  );
}

LoveVideoCommand _videoCommand({
  required LoveVideo video,
  LoveQuad? quad,
  LoveColor color = LoveColor.white,
  LoveScissorRect? scissor,
  vm.Matrix4? transform,
  vm.Matrix4? drawTransform,
}) {
  return LoveVideoCommand(
    color: color,
    lineWidth: 1.0,
    lineStyle: LoveGraphicsLineStyle.smooth,
    lineJoin: LoveGraphicsLineJoin.none,
    blendMode: LoveGraphicsBlendMode.alpha,
    blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: false,
    scissor: scissor,
    transform: transform ?? vm.Matrix4.identity(),
    drawTransform: drawTransform ?? vm.Matrix4.identity(),
    video: video,
    quad: quad,
  );
}
