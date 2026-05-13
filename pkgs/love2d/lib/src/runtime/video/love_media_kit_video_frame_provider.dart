import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as package_image;
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;

import '../love_runtime.dart';

/// Initializes the `media_kit` runtime for LOVE video support.
typedef LoveMediaKitInitializer = Future<void> Function();

/// Ensures the shared `media_kit` runtime has been initialized.
Future<void> ensureLoveMediaKitInitialized() async {
  final existing = _loveMediaKitInitialization;
  if (existing != null) {
    return existing.future;
  }

  final completer = Completer<void>();
  _loveMediaKitInitialization = completer;
  try {
    media_kit.MediaKit.ensureInitialized();
    completer.complete();
  } catch (error, stackTrace) {
    _loveMediaKitInitialization = null;
    completer.completeError(error, stackTrace);
  }
  return completer.future;
}

/// Creates a LOVE video frame provider factory backed by `media_kit`.
LoveVideoFrameProviderFactory loveMediaKitVideoFrameProviderFactory({
  LoveMediaKitInitializer? initializer,
}) {
  final resolvedInitializer = initializer ?? ensureLoveMediaKitInitialized;
  return (source, {bytes, metadata}) async {
    await resolvedInitializer();
    return LoveMediaKitVideoFrameProvider.open(
      source: source,
      bytes: bytes,
      metadata: metadata,
    );
  };
}

/// A LOVE video frame provider backed by `media_kit` screenshots.
final class LoveMediaKitVideoFrameProvider
    implements
        LoveVideoFrameProvider,
        LoveVideoLivePresentation,
        LoveVideoPlaybackController {
  /// Creates a provider from injected player callbacks and screenshot hooks.
  LoveMediaKitVideoFrameProvider._({
    required this.metadata,
    required Future<void> Function(Duration position) seekPosition,
    required Future<void> Function() playPlayer,
    required Future<void> Function() pausePlayer,
    required Future<Uint8List?> Function() takeScreenshot,
    required Future<void> Function() disposePlayer,
    Future<void> Function()? waitForVideoOutputReady,
    Object? attachedVideoOutput,
    required int? fallbackWidth,
    required int? fallbackHeight,
    double? initialFrameRate,
    double? Function()? readFrameRate,
    required Duration settleDelay,
  }) : _seekPosition = seekPosition,
       _playPlayer = playPlayer,
       _pausePlayer = pausePlayer,
       _takeScreenshot = takeScreenshot,
       _disposePlayer = disposePlayer,
       _waitForVideoOutputReady = waitForVideoOutputReady,
       _attachedVideoOutput = attachedVideoOutput,
       _fallbackWidth = fallbackWidth,
       _fallbackHeight = fallbackHeight,
       _frameRate = _normalizeFrameRate(
         initialFrameRate ?? metadata?.frameRate,
       ),
       _readFrameRate = readFrameRate,
       _settleDelay = settleDelay;

  /// Creates a test provider with optional callback overrides.
  factory LoveMediaKitVideoFrameProvider.test({
    LoveVideoMetadata? metadata,
    Future<void> Function(Duration position)? seekPosition,
    Future<void> Function()? playPlayer,
    Future<void> Function()? pausePlayer,
    Future<Uint8List?> Function()? takeScreenshot,
    Future<void> Function()? disposePlayer,
    Future<void> Function()? waitForVideoOutputReady,
    int? fallbackWidth,
    int? fallbackHeight,
    double? frameRate,
    Duration settleDelay = const Duration(milliseconds: 20),
  }) {
    return LoveMediaKitVideoFrameProvider._(
      metadata: metadata,
      seekPosition: seekPosition ?? (_) async {},
      playPlayer: playPlayer ?? () async {},
      pausePlayer: pausePlayer ?? () async {},
      takeScreenshot: takeScreenshot ?? () async => null,
      disposePlayer: disposePlayer ?? () async {},
      waitForVideoOutputReady: waitForVideoOutputReady,
      fallbackWidth: fallbackWidth,
      fallbackHeight: fallbackHeight,
      initialFrameRate: frameRate,
      settleDelay: settleDelay,
    );
  }

  /// Opens a `media_kit`-backed frame provider for [source] or in-memory [bytes].
  static Future<LoveMediaKitVideoFrameProvider> open({
    required String source,
    Uint8List? bytes,
    LoveVideoMetadata? metadata,
  }) async {
    final player = media_kit.Player(
      configuration: const media_kit.PlayerConfiguration(
        muted: true,
        title: 'LuaLike LOVE video frame provider',
      ),
    );
    try {
      final videoController = media_kit_video.VideoController(
        player,
        configuration: media_kit_video.VideoControllerConfiguration(
          width: metadata?.pixelWidth,
          height: metadata?.pixelHeight,
        ),
      );
      final playable = bytes == null
          ? media_kit.Media(source)
          : await media_kit.Media.memory(bytes);
      await player.open(playable, play: false);
      return LoveMediaKitVideoFrameProvider._(
        metadata: metadata,
        seekPosition: player.seek,
        playPlayer: player.play,
        pausePlayer: player.pause,
        takeScreenshot: () => player.screenshot(format: null),
        disposePlayer: player.dispose,
        waitForVideoOutputReady: () => videoController
            .waitUntilFirstFrameRendered
            .timeout(const Duration(seconds: 2), onTimeout: () {}),
        attachedVideoOutput: videoController,
        fallbackWidth: player.state.width,
        fallbackHeight: player.state.height,
        initialFrameRate: _playerFrameRate(player),
        readFrameRate: () => _playerFrameRate(player),
        settleDelay: const Duration(milliseconds: 35),
      );
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  /// The optional video metadata associated with this provider.
  final LoveVideoMetadata? metadata;

  /// Seeks playback to a requested position.
  final Future<void> Function(Duration position) _seekPosition;

  /// Starts or resumes player playback.
  final Future<void> Function() _playPlayer;

  /// Pauses player playback.
  final Future<void> Function() _pausePlayer;

  /// Captures a screenshot from the current video frame.
  final Future<Uint8List?> Function() _takeScreenshot;

  /// Disposes the underlying player resources.
  final Future<void> Function() _disposePlayer;

  /// Waits for the first rendered video frame, when supported.
  final Future<void> Function()? _waitForVideoOutputReady;

  /// The attached video output kept alive until the first frame is ready.
  final Object? _attachedVideoOutput;

  /// The fallback width reported by the underlying player.
  final int? _fallbackWidth;

  /// The fallback height reported by the underlying player.
  final int? _fallbackHeight;

  /// Reads the latest frame rate from the underlying player when available.
  final double? Function()? _readFrameRate;

  /// The delay used to let decoded frames settle before capture.
  final Duration _settleDelay;

  /// The serial queue that keeps snapshot requests ordered.
  Future<void> _serial = Future<void>.value();

  /// The in-flight dispose action when teardown has started.
  Future<void>? _disposeAction;

  /// The shared future for the first rendered video frame, if requested.
  Future<void>? _videoOutputReady;

  /// Whether this provider has been disposed.
  bool _disposed = false;

  /// Whether the underlying player is currently playing.
  bool _playing = false;

  /// The last requested snapshot position in seconds.
  double? _lastRequestedPositionSeconds;

  /// The decoded frame slot associated with [_lastSnapshot], when known.
  int? _lastSnapshotFrameSlot;

  /// The last successfully captured snapshot.
  LoveVideoFrameSnapshot? _lastSnapshot;

  /// The detected frame rate for the active video track.
  double? _frameRate;

  @override
  Object? get livePresentationHandle => _attachedVideoOutput;

  @override
  /// Releases the underlying player and invalidates future snapshots.
  Future<void> dispose() {
    final existingDispose = _disposeAction;
    if (existingDispose != null) {
      return existingDispose;
    }

    if (_disposed) {
      return Future<void>.value();
    }

    _disposed = true;
    final action = _serial.then((_) async {
      _videoOutputReady = null;
      _lastRequestedPositionSeconds = null;
      _lastSnapshotFrameSlot = null;
      _lastSnapshot = null;
      await _disposePlayer();
    });
    _disposeAction = action;
    _serial = action.then<void>((_) {}, onError: (_, _) {});
    return action;
  }

  @override
  /// Returns a snapshot of the video near [positionSeconds].
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds) {
    final action = _serial.then((_) => _snapshotAtInternal(positionSeconds));
    _serial = action.then<void>((_) {}, onError: (_, _) {});
    return action;
  }

  @override
  Future<void> pauseVideo() {
    final action = _serial.then((_) => _pauseVideoInternal());
    _serial = action.then<void>((_) {}, onError: (_, _) {});
    return action;
  }

  @override
  Future<void> playVideo() {
    final action = _serial.then((_) => _playVideoInternal());
    _serial = action.then<void>((_) {}, onError: (_, _) {});
    return action;
  }

  @override
  Future<void> seekVideo(double positionSeconds) {
    final action = _serial.then((_) => _seekVideoInternal(positionSeconds));
    _serial = action.then<void>((_) {}, onError: (_, _) {});
    return action;
  }

  /// Captures a snapshot after seeking or advancing playback as needed.
  Future<LoveVideoFrameSnapshot?> _snapshotAtInternal(
    double positionSeconds,
  ) async {
    if (_disposed) {
      return null;
    }

    final safePosition = !positionSeconds.isFinite || positionSeconds <= 0.0
        ? Duration.zero
        : Duration(
            microseconds: (positionSeconds * Duration.microsecondsPerSecond)
                .round(),
          );
    final requestedPositionSeconds =
        safePosition.inMicroseconds / Duration.microsecondsPerSecond;
    final lastRequestedPositionSeconds = _lastRequestedPositionSeconds;
    final requestedDelta = lastRequestedPositionSeconds == null
        ? null
        : requestedPositionSeconds - lastRequestedPositionSeconds;
    final requestedFrameSlot = _frameSlotFor(requestedPositionSeconds);
    final lastSnapshot = _lastSnapshot;

    if (lastSnapshot != null &&
        requestedFrameSlot != null &&
        requestedFrameSlot == _lastSnapshotFrameSlot) {
      _lastRequestedPositionSeconds = requestedPositionSeconds;
      return lastSnapshot;
    }

    if (requestedDelta == null) {
      await _seekPosition(safePosition);
      await _playPlayer();
      _playing = true;
      if (_settleDelay > Duration.zero) {
        await Future<void>.delayed(_settleDelay);
      }
      await _ensureVideoOutputReady();
    } else if (requestedDelta.abs() <= 0.002) {
      if (_playing) {
        await _pausePlayer();
        _playing = false;
      }
      if (lastSnapshot != null) {
        return lastSnapshot;
      }
      await _seekPosition(safePosition);
      if (_settleDelay > Duration.zero) {
        await Future<void>.delayed(_settleDelay);
      }
    } else if (requestedDelta < -0.05 || requestedDelta > 0.25) {
      await _seekPosition(safePosition);
      if (!_playing) {
        await _playPlayer();
        _playing = true;
      }
      if (_settleDelay > Duration.zero) {
        await Future<void>.delayed(_settleDelay);
      }
      await _ensureVideoOutputReady();
    } else if (!_playing) {
      await _seekPosition(safePosition);
      await _playPlayer();
      _playing = true;
      if (_settleDelay > Duration.zero) {
        await Future<void>.delayed(_settleDelay);
      }
      await _ensureVideoOutputReady();
    }

    final bytes = await _takeScreenshot();
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final rawSnapshot = _decodeRawSnapshot(bytes);
    if (rawSnapshot != null) {
      _lastRequestedPositionSeconds = requestedPositionSeconds;
      _lastSnapshotFrameSlot = requestedFrameSlot;
      _lastSnapshot = rawSnapshot;
      return rawSnapshot;
    }

    final decodedSnapshot = _decodeEncodedSnapshot(bytes);
    if (decodedSnapshot != null) {
      _lastRequestedPositionSeconds = requestedPositionSeconds;
      _lastSnapshotFrameSlot = requestedFrameSlot;
      _lastSnapshot = decodedSnapshot;
      return decodedSnapshot;
    }
    return null;
  }

  Future<void> _pauseVideoInternal() async {
    if (_disposed || !_playing) {
      return;
    }

    await _pausePlayer();
    _playing = false;
  }

  Future<void> _playVideoInternal() async {
    if (_disposed || _playing) {
      return;
    }

    await _ensureVideoOutputReady();
    await _playPlayer();
    _playing = true;
  }

  Future<void> _seekVideoInternal(double positionSeconds) async {
    if (_disposed) {
      return;
    }

    final safePosition = !positionSeconds.isFinite || positionSeconds <= 0.0
        ? Duration.zero
        : Duration(
            microseconds: (positionSeconds * Duration.microsecondsPerSecond)
                .round(),
          );
    _lastRequestedPositionSeconds =
        safePosition.inMicroseconds / Duration.microsecondsPerSecond;
    _lastSnapshot = null;
    _lastSnapshotFrameSlot = null;
    await _seekPosition(safePosition);
    if (_settleDelay > Duration.zero) {
      await Future<void>.delayed(_settleDelay);
    }
  }

  /// Waits until the first rendered video frame is available, if supported.
  Future<void> _ensureVideoOutputReady() {
    final attachedVideoOutput = _attachedVideoOutput;
    final waitForVideoOutputReady = _waitForVideoOutputReady;
    if (waitForVideoOutputReady == null) {
      return Future<void>.value();
    }
    return _videoOutputReady ??= () async {
      // Keep the video output attachment strongly reachable until the first
      // rendered frame has been observed.
      final keepAlive = attachedVideoOutput;
      await waitForVideoOutputReady();
      if (keepAlive == null) {
        return;
      }
    }();
  }

  /// Decodes an encoded screenshot into an RGBA video frame snapshot.
  LoveVideoFrameSnapshot? _decodeEncodedSnapshot(Uint8List bytes) {
    final decoded = package_image.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }

    final rgbaBytes = Uint8List(decoded.width * decoded.height * 4);
    var offset = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        rgbaBytes[offset++] = pixel.r.toInt();
        rgbaBytes[offset++] = pixel.g.toInt();
        rgbaBytes[offset++] = pixel.b.toInt();
        rgbaBytes[offset++] = pixel.a.toInt();
      }
    }

    return LoveVideoFrameSnapshot(
      width: decoded.width,
      height: decoded.height,
      bytes: rgbaBytes,
      rowBytes: decoded.width * 4,
      pixelFormat: LoveVideoFramePixelFormat.rgba8888,
      copyBytes: false,
    );
  }

  /// Decodes a raw BGRA screenshot when the frame layout can be inferred.
  LoveVideoFrameSnapshot? _decodeRawSnapshot(Uint8List bytes) {
    final layout = _resolveRawFrameLayout(bytes.lengthInBytes);
    if (layout == null) {
      return null;
    }

    return LoveVideoFrameSnapshot(
      width: layout.$1,
      height: layout.$2,
      bytes: bytes,
      rowBytes: layout.$3,
      pixelFormat: LoveVideoFramePixelFormat.bgra8888,
      copyBytes: false,
    );
  }

  /// Resolves frame dimensions and row stride for raw screenshot bytes.
  (int, int, int)? _resolveRawFrameLayout(int byteLength) {
    final metadataWidth = metadata?.pixelWidth;
    final metadataHeight = metadata?.pixelHeight;
    final metadataLayout = _layoutForKnownDimensions(
      metadataWidth,
      metadataHeight,
      byteLength,
    );
    if (metadataLayout != null) {
      return metadataLayout;
    }

    final fallbackWidth = _fallbackWidth;
    final fallbackHeight = _fallbackHeight;
    final fallbackLayout = _layoutForKnownDimensions(
      fallbackWidth,
      fallbackHeight,
      byteLength,
    );
    if (fallbackLayout != null) {
      return fallbackLayout;
    }

    final width = metadataWidth ?? fallbackWidth;
    if (width != null && width > 0 && byteLength % (width * 4) == 0) {
      final height = byteLength ~/ (width * 4);
      if (height > 0) {
        return (width, height, width * 4);
      }
    }

    final height = metadataHeight ?? fallbackHeight;
    if (height != null && height > 0 && byteLength % (height * 4) == 0) {
      final width = byteLength ~/ (height * 4);
      if (width > 0) {
        return (width, height, width * 4);
      }
    }

    return null;
  }

  /// Resolves a raw frame layout when both dimensions are already known.
  (int, int, int)? _layoutForKnownDimensions(
    int? width,
    int? height,
    int byteLength,
  ) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }

    final tightRowBytes = width * 4;
    final tightLength = tightRowBytes * height;
    if (tightLength == byteLength) {
      return (width, height, tightRowBytes);
    }

    if (byteLength % height != 0) {
      return null;
    }

    final rowBytes = byteLength ~/ height;
    if (rowBytes < tightRowBytes || rowBytes % 4 != 0) {
      return null;
    }

    return (width, height, rowBytes);
  }

  /// Returns the decoded frame slot for [positionSeconds], if the frame rate
  /// is currently known.
  int? _frameSlotFor(double positionSeconds) {
    final frameRate = _resolvedFrameRate;
    if (frameRate == null) {
      return null;
    }

    return (positionSeconds * frameRate).floor();
  }

  /// The most recently resolved frame rate, updating lazily when needed.
  double? get _resolvedFrameRate {
    final existing = _frameRate;
    if (existing != null) {
      return existing;
    }

    final resolved = _normalizeFrameRate(_readFrameRate?.call());
    _frameRate = resolved;
    return resolved;
  }

  /// Normalizes [value] into a usable frame rate.
  static double? _normalizeFrameRate(double? value) {
    if (value == null || !value.isFinite || value <= 0.0) {
      return null;
    }
    return value;
  }

  /// Resolves the current video track frame rate from [player].
  static double? _playerFrameRate(media_kit.Player player) {
    final selected = _normalizeFrameRate(player.state.track.video.fps);
    if (selected != null) {
      return selected;
    }

    for (final track in player.state.tracks.video) {
      final frameRate = _normalizeFrameRate(track.fps);
      if (frameRate != null) {
        return frameRate;
      }
    }

    return null;
  }
}

/// The shared completer for one-time `media_kit` initialization.
Completer<void>? _loveMediaKitInitialization;
