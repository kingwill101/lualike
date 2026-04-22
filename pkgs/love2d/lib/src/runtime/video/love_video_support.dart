part of '../love_runtime.dart';

abstract interface class LoveVideoFrameSync {
  FutureOr<void> play();
  FutureOr<void> pause();
  FutureOr<void> seek(double offset);
  double tell();
  bool isPlaying();
}

final class LoveVideoMetadata {
  const LoveVideoMetadata({
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final int pixelWidth;
  final int pixelHeight;
}

final class LoveVideoDeltaSync implements LoveVideoFrameSync {
  final Stopwatch _clock = Stopwatch();
  double _position = 0.0;
  bool _playing = false;

  @override
  Future<void> play() async {
    if (_playing) {
      return;
    }

    _playing = true;
    _clock.start();
  }

  @override
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
  double tell() {
    if (!_playing) {
      return _position;
    }

    return _position +
        _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  bool isPlaying() => _playing;

  Future<void> copyStateFrom(LoveVideoFrameSync other) async {
    await seek(other.tell());
    if (other.isPlaying()) {
      await play();
    } else {
      await pause();
    }
  }
}

final class LoveVideoSourceSync implements LoveVideoFrameSync {
  LoveVideoSourceSync(this.source);

  final LoveAudioSource source;

  @override
  Future<void> play() => source.play().then((_) => null);

  @override
  Future<void> pause() => source.pause();

  @override
  Future<void> seek(double offset) async {
    source.seek(offset, unit: 'seconds');
  }

  @override
  double tell() => source.tell('seconds');

  @override
  bool isPlaying() => source.playing;
}

final class LoveVideoStream {
  LoveVideoStream({
    required this.filename,
    Uint8List? bytes,
    LoveVideoMetadata? metadata,
    LoveVideoFrameSync? sync,
  }) : bytes = bytes == null ? null : Uint8List.fromList(bytes),
       metadata = metadata ?? _tryParseTheoraMetadata(bytes),
       _sync = sync ?? LoveVideoDeltaSync();

  final String filename;
  final Uint8List? bytes;
  final LoveVideoMetadata? metadata;
  LoveVideoFrameSync _sync;

  int get pixelWidth => metadata?.pixelWidth ?? 0;

  int get pixelHeight => metadata?.pixelHeight ?? 0;

  Future<void> play() async {
    await _sync.play();
  }

  Future<void> pause() async {
    await _sync.pause();
  }

  Future<void> seek(double offset) async {
    await _sync.seek(offset);
  }

  Future<void> rewind() => seek(0.0);

  double tell() => _sync.tell();

  bool isPlaying() => _sync.isPlaying();

  void setSyncFromSource(LoveAudioSource source) {
    _sync = LoveVideoSourceSync(source);
  }

  void setSyncFromStream(LoveVideoStream other) {
    _sync = other._sync;
  }

  Future<void> setIndependentSync() async {
    final sync = LoveVideoDeltaSync();
    await sync.copyStateFrom(_sync);
    _sync = sync;
  }
}

final class LoveVideo {
  LoveVideo({
    required this.stream,
    required this.dpiScale,
    LoveGraphicsDefaultFilter? filter,
    this.source,
  }) : pixelWidth = stream.pixelWidth,
       pixelHeight = stream.pixelHeight,
       width = _logicalVideoDimension(stream.pixelWidth, dpiScale),
       height = _logicalVideoDimension(stream.pixelHeight, dpiScale),
       filter = filter ?? LoveGraphicsDefaultFilter.standard;

  final LoveVideoStream stream;
  final int width;
  final int height;
  final int pixelWidth;
  final int pixelHeight;
  final double dpiScale;
  LoveGraphicsDefaultFilter filter;
  LoveAudioSource? source;

  Future<void> play() => stream.play();

  Future<void> pause() => stream.pause();

  Future<void> seek(double offset) => stream.seek(offset);

  Future<void> rewind() => stream.rewind();

  double tell() => stream.tell();

  bool isPlaying() => stream.isPlaying();

  Future<void> setSource(LoveAudioSource? value) async {
    if (value == null) {
      await stream.setIndependentSync();
      source = null;
      return;
    }

    stream.setSyncFromSource(value);
    source = value;
  }
}

int _logicalVideoDimension(int pixels, double dpiScale) {
  if (pixels <= 0) {
    return 0;
  }
  if (dpiScale <= 0) {
    return pixels;
  }
  return math.max(1, (pixels / dpiScale).round());
}

LoveVideoMetadata? _tryParseTheoraMetadata(Uint8List? bytes) {
  if (bytes == null || bytes.length < 28) {
    return null;
  }

  final packetBuffers = <int, BytesBuilder>{};
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
        final metadata = _tryParseTheoraIdentificationPacket(
          packetBuffer.takeBytes(),
        );
        if (metadata != null) {
          return metadata;
        }
      }
    }

    offset = dataOffset;
  }

  return null;
}

bool _matchesOggCapturePattern(Uint8List bytes, int offset) {
  return offset + 4 <= bytes.length &&
      bytes[offset] == 0x4f &&
      bytes[offset + 1] == 0x67 &&
      bytes[offset + 2] == 0x67 &&
      bytes[offset + 3] == 0x53;
}

int _findNextOggCapturePattern(Uint8List bytes, int start) {
  for (var offset = math.max(0, start); offset + 4 <= bytes.length; offset++) {
    if (_matchesOggCapturePattern(bytes, offset)) {
      return offset;
    }
  }
  return -1;
}

LoveVideoMetadata? _tryParseTheoraIdentificationPacket(Uint8List packet) {
  if (packet.length < 22) {
    return null;
  }

  const signature = 'theora';
  if (packet[0] != 0x80) {
    return null;
  }
  for (var index = 0; index < signature.length; index++) {
    if (packet[index + 1] != signature.codeUnitAt(index)) {
      return null;
    }
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

  return LoveVideoMetadata(pixelWidth: pixelWidth, pixelHeight: pixelHeight);
}

int _readUint16BigEndian(Uint8List bytes, int offset) {
  return ByteData.sublistView(
    bytes,
    offset,
    offset + 2,
  ).getUint16(0, Endian.big);
}

int _readUint24BigEndian(Uint8List bytes, int offset) {
  return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
}
