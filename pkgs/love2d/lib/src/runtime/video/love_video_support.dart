part of '../love_runtime.dart';

/// Synchronizes video playback position with an external timing source.
abstract interface class LoveVideoFrameSync {
  /// Starts playback on the underlying timing source.
  FutureOr<void> play();

  /// Pauses playback on the underlying timing source.
  FutureOr<void> pause();

  /// Seeks playback to [offset] seconds.
  FutureOr<void> seek(double offset);

  /// The current playback position in seconds.
  double tell();

  /// Whether playback is currently active.
  bool isPlaying();
}

/// Mirrors LOVE's constructor failure when a file is not an Ogg Theora video.
const String loveVideoInvalidFileMessage =
    'Invalid video file, video is not theora';

/// The decoded metadata needed to configure a LOVE video stream.
final class LoveVideoMetadata {
  /// Creates video metadata from decoded frame dimensions.
  const LoveVideoMetadata({
    required this.pixelWidth,
    required this.pixelHeight,
    this.frameRate,
    this.hasAudioTrack = false,
  });

  /// The encoded frame width in pixels.
  final int pixelWidth;

  /// The encoded frame height in pixels.
  final int pixelHeight;

  /// The encoded frame rate in frames per second, when present in metadata.
  final double? frameRate;

  /// Whether the container also includes an audio track.
  final bool hasAudioTrack;
}

/// A timer-based frame sync that tracks playback locally.
final class LoveVideoDeltaSync implements LoveVideoFrameSync {
  /// The stopwatch used to measure elapsed playback time while playing.
  final Stopwatch _clock = Stopwatch();

  /// The last committed playback position in seconds.
  double _position = 0.0;

  /// Whether playback is currently active.
  bool _playing = false;

  @override
  /// Starts advancing playback time.
  Future<void> play() async {
    if (_playing) {
      return;
    }

    _playing = true;
    _clock.start();
  }

  @override
  /// Pauses playback and commits the current position.
  Future<void> pause() async {
    if (!_playing) {
      return;
    }

    _position = tell();
    _playing = false;
    _clock
      ..stop()
      ..reset();
  }

  @override
  /// Seeks playback to [offset] seconds.
  Future<void> seek(double offset) async {
    _position = offset;
    if (_playing) {
      _clock
        ..reset()
        ..start();
    } else {
      _clock.reset();
    }
  }

  @override
  /// The current playback position in seconds.
  double tell() {
    if (!_playing) {
      return _position;
    }

    return _position +
        _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  /// Whether playback is currently active.
  bool isPlaying() => _playing;

  /// Copies seek and play state from [other].
  Future<void> copyStateFrom(LoveVideoFrameSync other) async {
    await seek(other.tell());
    if (other.isPlaying()) {
      await play();
    } else {
      await pause();
    }
  }
}

/// A frame sync driven by an attached audio source.
final class LoveVideoSourceSync implements LoveVideoFrameSync {
  /// Creates a frame sync that mirrors [source] playback.
  LoveVideoSourceSync(this.source);

  /// The audio source used as the timing authority.
  final LoveAudioSource source;

  @override
  /// Starts the source-backed playback clock.
  Future<void> play() => source.play().then((_) => null);

  @override
  /// Pauses the source-backed playback clock.
  Future<void> pause() => source.pause();

  @override
  /// Seeks the source-backed playback clock to [offset] seconds.
  Future<void> seek(double offset) async {
    await source.seek(offset, unit: 'seconds');
  }

  @override
  /// The current source-backed playback position in seconds.
  double tell() => source.tell('seconds');

  @override
  /// Whether the backing audio source is currently playing.
  bool isPlaying() => source.isPlayingNow;
}

/// The encoded video bytes and synchronization state for a LOVE video.
final class LoveVideoStream {
  /// Creates a video stream from verified encoded Theora [bytes].
  factory LoveVideoStream.encoded({
    required String filename,
    required List<int> bytes,
    LoveVideoFrameSync? sync,
  }) {
    final copiedBytes = Uint8List.fromList(bytes);
    final metadata = _tryParseTheoraMetadata(copiedBytes);
    if (metadata == null) {
      throw ArgumentError(loveVideoInvalidFileMessage);
    }

    return LoveVideoStream._(
      filename: filename,
      bytes: copiedBytes,
      metadata: metadata,
      sync: sync,
      copyBytes: false,
    );
  }

  /// Creates a video stream from optional encoded bytes and metadata.
  LoveVideoStream({
    required this.filename,
    Uint8List? bytes,
    LoveVideoMetadata? metadata,
    LoveVideoFrameSync? sync,
  }) : bytes = bytes == null ? null : Uint8List.fromList(bytes),
       metadata = metadata ?? _tryParseTheoraMetadata(bytes),
       _sync = sync ?? LoveVideoDeltaSync();

  /// Creates a video stream with optional byte-copy control.
  LoveVideoStream._({
    required this.filename,
    Uint8List? bytes,
    LoveVideoMetadata? metadata,
    LoveVideoFrameSync? sync,
    bool copyBytes = true,
  }) : bytes = bytes == null
           ? null
           : (copyBytes ? Uint8List.fromList(bytes) : bytes),
       metadata = metadata ?? _tryParseTheoraMetadata(bytes),
       _sync = sync ?? LoveVideoDeltaSync();

  /// The logical filename associated with this stream.
  final String filename;

  /// The encoded container bytes, if this stream owns them in memory.
  final Uint8List? bytes;

  /// The parsed video metadata, if it could be determined.
  final LoveVideoMetadata? metadata;

  /// The synchronization strategy currently driving playback timing.
  LoveVideoFrameSync _sync;

  /// The encoded frame width in pixels.
  int get pixelWidth => metadata?.pixelWidth ?? 0;

  /// The encoded frame height in pixels.
  int get pixelHeight => metadata?.pixelHeight ?? 0;

  /// Whether the stream metadata reports an audio track.
  bool get hasAudioTrack => metadata?.hasAudioTrack ?? false;

  /// Starts playback on the active sync source.
  Future<void> play() async {
    await _sync.play();
  }

  /// Pauses playback on the active sync source.
  Future<void> pause() async {
    await _sync.pause();
  }

  /// Seeks playback to [offset] seconds.
  Future<void> seek(double offset) async {
    await _sync.seek(offset);
  }

  /// Rewinds playback to the beginning of the stream.
  Future<void> rewind() => seek(0.0);

  /// The current playback position in seconds.
  double tell() => _sync.tell();

  /// Whether playback is currently active.
  bool isPlaying() => _sync.isPlaying();

  /// Uses [source] as the playback timing authority.
  void setSyncFromSource(LoveAudioSource source) {
    _sync = LoveVideoSourceSync(source);
  }

  /// Shares the sync source already used by [other].
  void setSyncFromStream(LoveVideoStream other) {
    _sync = other._sync;
  }

  /// Replaces shared or source-backed sync with an independent local timer.
  Future<void> setIndependentSync() async {
    final sync = LoveVideoDeltaSync();
    await sync.copyStateFrom(_sync);
    _sync = sync;
  }
}

/// A drawable LOVE video resource and its optional frame provider.
final class LoveVideo {
  /// Creates a LOVE video resource around [stream].
  LoveVideo({
    required this.stream,
    required this.dpiScale,
    LoveGraphicsDefaultFilter? filter,
    this.source,
    LoveVideoFrameProvider? frameProvider,
  }) : pixelWidth = stream.pixelWidth,
       pixelHeight = stream.pixelHeight,
       width = _logicalVideoDimension(stream.pixelWidth, dpiScale),
       height = _logicalVideoDimension(stream.pixelHeight, dpiScale),
       filter = filter ?? LoveGraphicsDefaultFilter.standard,
       _frameProvider = frameProvider;

  /// The underlying encoded video stream and playback sync.
  final LoveVideoStream stream;

  /// The logical video width after DPI scaling.
  final int width;

  /// The logical video height after DPI scaling.
  final int height;

  /// The encoded frame width in pixels.
  final int pixelWidth;

  /// The encoded frame height in pixels.
  final int pixelHeight;

  /// The DPI scale used to derive [width] and [height].
  final double dpiScale;

  /// The current graphics filter applied to the video image.
  LoveGraphicsDefaultFilter filter;

  /// The audio source currently associated with this video, if any.
  LoveAudioSource? source;

  /// The optional provider used to capture video frame snapshots.
  final LoveVideoFrameProvider? _frameProvider;

  /// Whether this video resource has been disposed.
  bool _disposed = false;

  /// Starts playback on the underlying stream.
  Future<void> play() async {
    await stream.play();
    if (_frameProvider
        case final LoveVideoPlaybackController playbackController) {
      await playbackController.playVideo();
    }
  }

  /// Pauses playback on the underlying stream.
  Future<void> pause() async {
    await stream.pause();
    if (_frameProvider
        case final LoveVideoPlaybackController playbackController) {
      await playbackController.pauseVideo();
    }
  }

  /// Seeks playback to [offset] seconds.
  Future<void> seek(double offset) async {
    await stream.seek(offset);
    if (_frameProvider
        case final LoveVideoPlaybackController playbackController) {
      await playbackController.seekVideo(offset);
    }
  }

  /// Rewinds playback to the start of the stream.
  Future<void> rewind() => seek(0.0);

  /// The current playback position in seconds.
  double tell() => stream.tell();

  /// Whether playback is currently active.
  bool isPlaying() => stream.isPlaying();

  /// Whether this video can provide decoded frame snapshots.
  bool get hasFrameProvider => _frameProvider != null;

  /// Whether this video can be presented through a live host surface.
  bool get hasLivePresentation => livePresentationHandle != null;

  /// The provider-specific live presentation handle when available.
  Object? get livePresentationHandle {
    final frameProvider = _frameProvider;
    return switch (frameProvider) {
      final LoveVideoLivePresentation presentation =>
        presentation.livePresentationHandle,
      _ => null,
    };
  }

  /// Sets the attached audio [value] without changing stream sync state.
  void setRawSource(LoveAudioSource? value) {
    source = value;
  }

  /// Sets the attached audio [value] and updates playback synchronization.
  Future<void> setSource(LoveAudioSource? value) async {
    source = value;
    if (value == null) {
      await stream.setIndependentSync();
      return;
    }

    stream.setSyncFromSource(value);
  }

  /// Captures a frame snapshot at the current playback position.
  Future<LoveVideoFrameSnapshot?> snapshotFrame() async {
    final frameProvider = _frameProvider;
    if (frameProvider == null) {
      return null;
    }

    return frameProvider.snapshotAt(tell());
  }

  /// Captures a frame snapshot at [positionSeconds].
  Future<LoveVideoFrameSnapshot?> snapshotFrameAt(
    double positionSeconds,
  ) async {
    final frameProvider = _frameProvider;
    if (frameProvider == null) {
      return null;
    }

    return frameProvider.snapshotAt(positionSeconds);
  }

  /// Releases the frame provider owned by this video, if one exists.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    final attachedSource = source;
    final frameProvider = _frameProvider;
    try {
      if (attachedSource != null) {
        await attachedSource.stop();
      }
    } finally {
      if (frameProvider != null) {
        await frameProvider.dispose();
      }
    }
  }
}

/// Converts encoded [pixels] into LOVE logical units using [dpiScale].
int _logicalVideoDimension(int pixels, double dpiScale) {
  if (pixels <= 0) {
    return 0;
  }
  if (dpiScale <= 0) {
    return pixels;
  }
  return (pixels / dpiScale).truncate();
}

/// Tries to extract Theora and Vorbis metadata from Ogg container [bytes].
LoveVideoMetadata? _tryParseTheoraMetadata(Uint8List? bytes) {
  if (bytes == null || bytes.length < 28) {
    return null;
  }

  final packetBuffers = <int, BytesBuilder>{};
  LoveVideoMetadata? videoMetadata;
  var hasVorbisAudio = false;
  var offset = 0;
  while (offset + 27 <= bytes.length) {
    if (!_matchesOggCapturePattern(bytes, offset)) {
      final nextOffset = _findNextOggCapturePattern(bytes, offset + 1);
      if (nextOffset < 0) {
        return null;
      }
      offset = nextOffset;
      continue;
    }

    final segmentCount = bytes[offset + 26];
    final headerLength = 27 + segmentCount;
    if (offset + headerLength > bytes.length) {
      return null;
    }

    final serial = ByteData.sublistView(
      bytes,
      offset + 14,
      offset + 18,
    ).getUint32(0, Endian.little);
    final packetBuffer = packetBuffers[serial] ??= BytesBuilder(copy: false);
    var dataOffset = offset + headerLength;

    for (var segmentIndex = 0; segmentIndex < segmentCount; segmentIndex++) {
      final segmentLength = bytes[offset + 27 + segmentIndex];
      if (dataOffset + segmentLength > bytes.length) {
        return null;
      }

      packetBuffer.add(bytes.sublist(dataOffset, dataOffset + segmentLength));
      dataOffset += segmentLength;

      if (segmentLength < 255) {
        final packet = packetBuffer.takeBytes();
        final metadata = _tryParseTheoraIdentificationPacket(packet);
        if (metadata != null) {
          videoMetadata = metadata;
        } else if (_isVorbisIdentificationPacket(packet)) {
          hasVorbisAudio = true;
        }

        if (videoMetadata != null && hasVorbisAudio) {
          return LoveVideoMetadata(
            pixelWidth: videoMetadata.pixelWidth,
            pixelHeight: videoMetadata.pixelHeight,
            frameRate: videoMetadata.frameRate,
            hasAudioTrack: true,
          );
        }
      }
    }

    offset = dataOffset;
  }

  if (videoMetadata == null) {
    return null;
  }

  return LoveVideoMetadata(
    pixelWidth: videoMetadata.pixelWidth,
    pixelHeight: videoMetadata.pixelHeight,
    frameRate: videoMetadata.frameRate,
    hasAudioTrack: hasVorbisAudio,
  );
}

/// Returns whether [bytes] contains the OggS capture pattern at [offset].
bool _matchesOggCapturePattern(Uint8List bytes, int offset) {
  return offset + 4 <= bytes.length &&
      bytes[offset] == 0x4f &&
      bytes[offset + 1] == 0x67 &&
      bytes[offset + 2] == 0x67 &&
      bytes[offset + 3] == 0x53;
}

/// Finds the next OggS capture-pattern offset at or after [start].
int _findNextOggCapturePattern(Uint8List bytes, int start) {
  for (var offset = math.max(0, start); offset + 4 <= bytes.length; offset++) {
    if (_matchesOggCapturePattern(bytes, offset)) {
      return offset;
    }
  }
  return -1;
}

/// Tries to parse Theora identification metadata from one Ogg [packet].
LoveVideoMetadata? _tryParseTheoraIdentificationPacket(Uint8List packet) {
  if (packet.length < 22) {
    return null;
  }

  if (!_matchesPacketSignature(packet, headerByte: 0x80, signature: 'theora')) {
    return null;
  }

  final macroBlockWidth = _readUint16BigEndian(packet, 10) * 16;
  final macroBlockHeight = _readUint16BigEndian(packet, 12) * 16;
  final pictureWidth = _readUint24BigEndian(packet, 14);
  final pictureHeight = _readUint24BigEndian(packet, 17);
  final pixelWidth = pictureWidth == 0 ? macroBlockWidth : pictureWidth;
  final pixelHeight = pictureHeight == 0 ? macroBlockHeight : pictureHeight;
  if (pixelWidth <= 0 || pixelHeight <= 0) {
    return null;
  }

  final frameRateNumerator = packet.length >= 30
      ? _readUint32BigEndian(packet, 22)
      : 0;
  final frameRateDenominator = packet.length >= 30
      ? _readUint32BigEndian(packet, 26)
      : 0;
  final frameRate = frameRateNumerator > 0 && frameRateDenominator > 0
      ? frameRateNumerator / frameRateDenominator
      : null;

  return LoveVideoMetadata(
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    frameRate: frameRate,
  );
}

/// Returns whether [packet] is a Vorbis identification packet.
bool _isVorbisIdentificationPacket(Uint8List packet) {
  return _matchesPacketSignature(packet, headerByte: 0x01, signature: 'vorbis');
}

/// Returns whether [packet] starts with [headerByte] and [signature].
bool _matchesPacketSignature(
  Uint8List packet, {
  required int headerByte,
  required String signature,
}) {
  if (packet.length < signature.length + 1 || packet[0] != headerByte) {
    return false;
  }

  for (var index = 0; index < signature.length; index++) {
    if (packet[index + 1] != signature.codeUnitAt(index)) {
      return false;
    }
  }

  return true;
}

/// Reads a big-endian 16-bit integer from [bytes] at [offset].
int _readUint16BigEndian(Uint8List bytes, int offset) {
  return ByteData.sublistView(
    bytes,
    offset,
    offset + 2,
  ).getUint16(0, Endian.big);
}

/// Reads a big-endian 24-bit integer from [bytes] at [offset].
int _readUint24BigEndian(Uint8List bytes, int offset) {
  return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
}

/// Reads a big-endian 32-bit integer from [bytes] at [offset].
int _readUint32BigEndian(Uint8List bytes, int offset) {
  return ByteData.sublistView(
    bytes,
    offset,
    offset + 4,
  ).getUint32(0, Endian.big);
}
