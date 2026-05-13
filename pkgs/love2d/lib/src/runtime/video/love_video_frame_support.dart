part of '../love_runtime.dart';

/// Creates a video frame provider for [source] and optional in-memory [bytes].
typedef LoveVideoFrameProviderFactory =
    Future<LoveVideoFrameProvider?> Function(
      String source, {
      Uint8List? bytes,
      LoveVideoMetadata? metadata,
    });

/// The pixel format used by a captured video frame snapshot.
enum LoveVideoFramePixelFormat { bgra8888, rgba8888 }

/// A captured video frame and its decoded pixel payload.
final class LoveVideoFrameSnapshot {
  /// Creates a frame snapshot from raw [bytes] and frame dimensions.
  LoveVideoFrameSnapshot({
    required this.width,
    required this.height,
    required Uint8List bytes,
    int? rowBytes,
    this.pixelFormat = LoveVideoFramePixelFormat.bgra8888,
    bool copyBytes = true,
  }) : rowBytes = rowBytes ?? (width * 4),
       bytes = copyBytes ? Uint8List.fromList(bytes) : bytes;

  /// The frame width in pixels.
  final int width;

  /// The frame height in pixels.
  final int height;

  /// The copied pixel bytes for this snapshot.
  final Uint8List bytes;

  /// The number of bytes between adjacent pixel rows in [bytes].
  final int rowBytes;

  /// The pixel format used by [bytes].
  final LoveVideoFramePixelFormat pixelFormat;
}

/// Captures video frames at requested playback positions.
abstract interface class LoveVideoFrameProvider {
  /// Returns a snapshot near [positionSeconds], or `null` when unavailable.
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds);

  /// Releases any resources held by this frame provider.
  Future<void> dispose();
}

/// Exposes a live-presented video output handled outside the software canvas.
abstract interface class LoveVideoLivePresentation {
  /// The provider-specific presentation handle used by the active host.
  Object? get livePresentationHandle;
}

/// Allows a frame provider to mirror playback state for live presentation.
abstract interface class LoveVideoPlaybackController {
  /// Starts or resumes the underlying video output.
  Future<void> playVideo();

  /// Pauses the underlying video output.
  Future<void> pauseVideo();

  /// Seeks the underlying video output to [positionSeconds].
  Future<void> seekVideo(double positionSeconds);
}
