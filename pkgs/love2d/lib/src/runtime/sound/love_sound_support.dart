part of '../love_runtime.dart';

const int loveSoundDefaultBufferSize = 16384;
const int loveSoundDefaultSampleRate = 44100;
const int loveSoundDefaultChannels = 2;
const int loveSoundDefaultBitDepth = 16;

final class LoveSoundData extends LoveDataObject {
  LoveSoundData._(
    super.bytes, {
    required this.sampleRate,
    required this.bitDepth,
    required this.channels,
  }) : super._();

  factory LoveSoundData.silence({
    required int samples,
    int sampleRate = loveSoundDefaultSampleRate,
    int bitDepth = loveSoundDefaultBitDepth,
    int channels = loveSoundDefaultChannels,
  }) {
    _validateSoundConstruction(
      samples: samples,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
    );

    final frameByteSize = _soundFrameByteSize(
      bitDepth: bitDepth,
      channels: channels,
    );
    final bytes = Uint8List(samples * frameByteSize);
    if (bitDepth == 8) {
      bytes.fillRange(0, bytes.length, 128);
    }

    return LoveSoundData._(
      bytes,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
    );
  }

  factory LoveSoundData.fromPcmBytes({
    required List<int> bytes,
    required int sampleRate,
    required int bitDepth,
    required int channels,
  }) {
    _validateSoundMetadata(
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
    );

    final copied = Uint8List.fromList(bytes);
    final frameByteSize = _soundFrameByteSize(
      bitDepth: bitDepth,
      channels: channels,
    );
    if (copied.length % frameByteSize != 0) {
      throw ArgumentError('PCM byte length must align to sample frames.');
    }

    return LoveSoundData._(
      copied,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
    );
  }

  final int sampleRate;
  final int bitDepth;
  final int channels;

  int get sampleCount => bytes.length ~/ frameByteSize;

  int get rawSampleCount => sampleCount * channels;

  int get frameByteSize =>
      _soundFrameByteSize(bitDepth: bitDepth, channels: channels);

  double get duration => bytes.isEmpty ? 0.0 : bytes.length / frameRateBytes;

  double get frameRateBytes => channels * sampleRate * (bitDepth / 8);

  @override
  LoveSoundData clone() => LoveSoundData.fromPcmBytes(
    bytes: bytes,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
    channels: channels,
  );

  double getSample(int index, {int? channel}) {
    final rawIndex = _resolveRawSampleIndex(
      index,
      channel: channel,
      forSet: false,
    );
    if (bitDepth == 16) {
      final sample = ByteData.sublistView(
        bytes,
      ).getInt16(rawIndex * 2, Endian.little);
      return sample / 32767.0;
    }

    return (bytes[rawIndex] - 128.0) / 127.0;
  }

  void setSample(int index, double sample, {int? channel}) {
    final rawIndex = _resolveRawSampleIndex(
      index,
      channel: channel,
      forSet: true,
    );
    final normalized = sample.clamp(-1.0, 1.0);
    if (bitDepth == 16) {
      final raw = (normalized * 32767.0).toInt().clamp(-32768, 32767);
      ByteData.sublistView(bytes).setInt16(rawIndex * 2, raw, Endian.little);
      return;
    }

    final raw = (normalized * 127.0 + 128.0).toInt().clamp(0, 255);
    bytes[rawIndex] = raw;
  }

  LoveSoundData copyFrames(int frameOffset, int frameCount) {
    final clampedStart = frameOffset.clamp(0, sampleCount);
    final available = sampleCount - clampedStart;
    final resolvedCount = frameCount.clamp(0, available);
    final byteOffset = clampedStart * frameByteSize;
    final byteCount = resolvedCount * frameByteSize;
    return LoveSoundData.fromPcmBytes(
      bytes: bytes.sublist(byteOffset, byteOffset + byteCount),
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
    );
  }

  int _resolveRawSampleIndex(
    int index, {
    required int? channel,
    required bool forSet,
  }) {
    if (channel != null) {
      if (channel < 1 || channel > channels) {
        throw ArgumentError(
          forSet
              ? 'Attempt to set sample from out-of-range channel!'
              : 'Attempt to get sample from out-of-range channel!',
        );
      }
      return _validateRawSampleIndex(
        index * channels + (channel - 1),
        forSet: forSet,
      );
    }

    return _validateRawSampleIndex(index, forSet: forSet);
  }

  int _validateRawSampleIndex(int rawIndex, {required bool forSet}) {
    if (rawIndex < 0 || rawIndex >= rawSampleCount) {
      throw ArgumentError(
        forSet
            ? 'Attempt to set out-of-range sample!'
            : 'Attempt to get out-of-range sample!',
      );
    }
    return rawIndex;
  }
}

final class LoveSoundDecoder {
  LoveSoundDecoder(
    LoveSoundData data, {
    int bufferSize = loveSoundDefaultBufferSize,
  }) : _data = data.clone(),
       bufferSize = _validateDecoderBufferSize(bufferSize);

  final LoveSoundData _data;
  final int bufferSize;
  int _frameCursor = 0;

  int get bitDepth => _data.bitDepth;

  int get channels => _data.channels;

  int get sampleRate => _data.sampleRate;

  double get duration => _data.duration;

  int get sampleCount => _data.sampleCount;

  bool get isFinished => _frameCursor >= sampleCount;

  LoveSoundDecoder clone() => LoveSoundDecoder(_data, bufferSize: bufferSize);

  LoveSoundData? decode() {
    if (isFinished) {
      return null;
    }

    final remaining = sampleCount - _frameCursor;
    final chunkFrames = _chunkFrameCount();
    final frameCount = math.min(remaining, chunkFrames);
    final chunk = _data.copyFrames(_frameCursor, frameCount);
    _frameCursor += frameCount;
    return chunk;
  }

  LoveSoundData decodeAllRemaining() {
    final remaining = sampleCount - _frameCursor;
    final chunk = _data.copyFrames(_frameCursor, remaining);
    _frameCursor = sampleCount;
    return chunk;
  }

  void rewind() {
    _frameCursor = 0;
  }

  void seek(double seconds) {
    if (seconds <= 0) {
      rewind();
      return;
    }

    _frameCursor = (seconds * sampleRate).floor().clamp(0, sampleCount);
  }

  int _chunkFrameCount() {
    final frameByteSize = _data.frameByteSize;
    final alignedBytes = bufferSize < frameByteSize
        ? frameByteSize
        : bufferSize - (bufferSize % frameByteSize);
    return math.max(1, alignedBytes ~/ frameByteSize);
  }
}

LoveSoundDecoder loveNewSoundDecoderFromBytes(
  List<int> bytes, {
  required String source,
  int bufferSize = loveSoundDefaultBufferSize,
}) {
  return LoveSoundDecoder(
    loveDecodeSoundFile(bytes: bytes, source: source),
    bufferSize: bufferSize,
  );
}

Uint8List loveEncodeSoundDataAsWaveBytes(LoveSoundData data) {
  final dataSize = data.bytes.length;
  final result = Uint8List(44 + dataSize);
  final header = ByteData.sublistView(result, 0, 44);
  final byteRate = data.sampleRate * data.frameByteSize;

  result.setRange(0, 4, 'RIFF'.codeUnits);
  result.setRange(8, 12, 'WAVE'.codeUnits);
  result.setRange(12, 16, 'fmt '.codeUnits);
  result.setRange(36, 40, 'data'.codeUnits);

  header.setUint32(4, 36 + dataSize, Endian.little);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, data.channels, Endian.little);
  header.setUint32(24, data.sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, data.frameByteSize, Endian.little);
  header.setUint16(34, data.bitDepth, Endian.little);
  header.setUint32(40, dataSize, Endian.little);

  result.setRange(44, result.length, data.bytes);
  return result;
}

LoveSoundData loveDecodeSoundFile({
  required List<int> bytes,
  required String source,
}) {
  final extension = _soundExtension(source);
  final looksLikeWave = _looksLikeWave(bytes);
  if (!looksLikeWave && extension != 'wav' && extension != 'wave') {
    throw UnsupportedError('Extension "$extension" not supported.');
  }

  return _decodeWaveSoundData(bytes, source: source);
}

LoveSoundData _decodeWaveSoundData(List<int> bytes, {required String source}) {
  final data = Uint8List.fromList(bytes);
  if (!_looksLikeWave(data)) {
    throw ArgumentError('Invalid WAV file.');
  }

  int? formatTag;
  int? channels;
  int? sampleRate;
  int? bitDepth;
  int? extensibleSubformatTag;
  Uint8List? pcmData;

  var offset = 12;
  while (offset + 8 <= data.length) {
    final chunkId = String.fromCharCodes(data.sublist(offset, offset + 4));
    final chunkSize = _readUint32Le(data, offset + 4);
    final dataOffset = offset + 8;
    final dataEnd = dataOffset + chunkSize;
    if (dataEnd > data.length) {
      throw ArgumentError('Invalid WAV chunk size in "$source".');
    }

    switch (chunkId) {
      case 'fmt ':
        if (chunkSize < 16) {
          throw ArgumentError('Invalid WAV format chunk in "$source".');
        }
        formatTag = _readUint16Le(data, dataOffset);
        channels = _readUint16Le(data, dataOffset + 2);
        sampleRate = _readUint32Le(data, dataOffset + 4);
        bitDepth = _readUint16Le(data, dataOffset + 14);
        if (formatTag == _waveFormatExtensible) {
          if (chunkSize < 40) {
            throw ArgumentError(
              'Invalid WAV extensible format chunk in "$source".',
            );
          }
          extensibleSubformatTag = _readUint16Le(data, dataOffset + 24);
        }
      case 'data':
        pcmData = Uint8List.fromList(data.sublist(dataOffset, dataEnd));
    }

    offset = dataEnd + (chunkSize.isOdd ? 1 : 0);
  }

  if (formatTag == null ||
      channels == null ||
      sampleRate == null ||
      bitDepth == null) {
    throw ArgumentError('Missing WAV format metadata in "$source".');
  }
  if (pcmData == null) {
    throw ArgumentError('Missing WAV audio data in "$source".');
  }
  final resolvedFormatTag = formatTag == _waveFormatExtensible
      ? extensibleSubformatTag
      : formatTag;
  if (resolvedFormatTag == null) {
    throw UnsupportedError('Unsupported WAV audio format.');
  }

  return switch (resolvedFormatTag) {
    _waveFormatPcm => _decodeWavePcmSoundData(
      pcmData,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
      source: source,
    ),
    _waveFormatIeeeFloat => _decodeWaveFloatSoundData(
      pcmData,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
      source: source,
    ),
    _ => throw UnsupportedError('Unsupported WAV audio format.'),
  };
}

const int _waveFormatPcm = 0x0001;
const int _waveFormatIeeeFloat = 0x0003;
const int _waveFormatExtensible = 0xFFFE;

LoveSoundData _decodeWavePcmSoundData(
  Uint8List pcmData, {
  required int sampleRate,
  required int bitDepth,
  required int channels,
  required String source,
}) {
  switch (bitDepth) {
    case 8:
    case 16:
      final frameByteSize = _soundFrameByteSize(
        bitDepth: bitDepth,
        channels: channels,
      );
      if (pcmData.length % frameByteSize != 0) {
        throw ArgumentError('WAV audio data is not aligned to sample frames.');
      }

      return LoveSoundData.fromPcmBytes(
        bytes: pcmData,
        sampleRate: sampleRate,
        bitDepth: bitDepth,
        channels: channels,
      );
    case 24:
    case 32:
      return _convertWaveSamplesTo16Bit(
        pcmData,
        sampleRate: sampleRate,
        channels: channels,
        source: source,
        bytesPerSample: bitDepth ~/ 8,
        sampleReader: (byteData, offset) {
          return switch (bitDepth) {
            24 =>
              _readInt24Le(byteData.buffer.asUint8List(), offset) / 8388607.0,
            32 => byteData.getInt32(offset, Endian.little) / 2147483647.0,
            _ => 0.0,
          };
        },
      );
    default:
      throw UnsupportedError(
        'Only 8-bit, 16-bit, 24-bit, and 32-bit PCM WAV audio is currently supported.',
      );
  }
}

LoveSoundData _decodeWaveFloatSoundData(
  Uint8List pcmData, {
  required int sampleRate,
  required int bitDepth,
  required int channels,
  required String source,
}) {
  return switch (bitDepth) {
    32 => _convertWaveSamplesTo16Bit(
      pcmData,
      sampleRate: sampleRate,
      channels: channels,
      source: source,
      bytesPerSample: 4,
      sampleReader: (byteData, offset) =>
          byteData.getFloat32(offset, Endian.little),
    ),
    64 => _convertWaveSamplesTo16Bit(
      pcmData,
      sampleRate: sampleRate,
      channels: channels,
      source: source,
      bytesPerSample: 8,
      sampleReader: (byteData, offset) =>
          byteData.getFloat64(offset, Endian.little),
    ),
    _ => throw UnsupportedError(
      'Only 32-bit and 64-bit IEEE float WAV audio is currently supported.',
    ),
  };
}

LoveSoundData _convertWaveSamplesTo16Bit(
  Uint8List pcmData, {
  required int sampleRate,
  required int channels,
  required int bytesPerSample,
  required String source,
  required double Function(ByteData byteData, int offset) sampleReader,
}) {
  final frameByteSize = channels * bytesPerSample;
  if (pcmData.length % frameByteSize != 0) {
    throw ArgumentError('WAV audio data is not aligned to sample frames.');
  }

  final byteData = ByteData.sublistView(pcmData);
  final sampleCount = pcmData.length ~/ bytesPerSample;
  final converted = Uint8List(sampleCount * 2);
  final convertedData = ByteData.sublistView(converted);
  for (var index = 0; index < sampleCount; index++) {
    final sample = sampleReader(byteData, index * bytesPerSample);
    convertedData.setInt16(
      index * 2,
      _normalizedSampleToInt16(sample),
      Endian.little,
    );
  }

  return LoveSoundData.fromPcmBytes(
    bytes: converted,
    sampleRate: sampleRate,
    bitDepth: 16,
    channels: channels,
  );
}

void _validateSoundConstruction({
  required int samples,
  required int sampleRate,
  required int bitDepth,
  required int channels,
}) {
  if (samples <= 0) {
    throw ArgumentError('Invalid sample count: $samples');
  }

  _validateSoundMetadata(
    sampleRate: sampleRate,
    bitDepth: bitDepth,
    channels: channels,
  );
}

void _validateSoundMetadata({
  required int sampleRate,
  required int bitDepth,
  required int channels,
}) {
  if (sampleRate <= 0) {
    throw ArgumentError('Invalid sample rate: $sampleRate');
  }
  if (bitDepth != 8 && bitDepth != 16) {
    throw ArgumentError('Invalid bit depth: $bitDepth');
  }
  if (channels <= 0) {
    throw ArgumentError('Invalid channel count: $channels');
  }
}

int _validateDecoderBufferSize(int bufferSize) {
  if (bufferSize <= 0) {
    throw ArgumentError('Invalid decoder buffer size: $bufferSize');
  }
  return bufferSize;
}

int _soundFrameByteSize({required int bitDepth, required int channels}) {
  _validateSoundMetadata(
    sampleRate: loveSoundDefaultSampleRate,
    bitDepth: bitDepth,
    channels: channels,
  );
  return (bitDepth ~/ 8) * channels;
}

String _soundExtension(String source) {
  final dot = source.lastIndexOf('.');
  if (dot < 0 || dot == source.length - 1) {
    return '';
  }
  return source.substring(dot + 1).toLowerCase();
}

bool _looksLikeWave(List<int> bytes) {
  return bytes.length >= 12 &&
      _matchesAscii(bytes, 0, 'RIFF') &&
      _matchesAscii(bytes, 8, 'WAVE');
}

bool _matchesAscii(List<int> bytes, int offset, String value) {
  if (offset + value.length > bytes.length) {
    return false;
  }

  for (var index = 0; index < value.length; index++) {
    if (bytes[offset + index] != value.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}

int _readUint16Le(List<int> bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _readUint32Le(List<int> bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

int _readInt24Le(List<int> bytes, int offset) {
  var value =
      bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  if ((value & 0x00800000) != 0) {
    value |= ~0x00FFFFFF;
  }
  return value;
}

int _normalizedSampleToInt16(double sample) {
  final normalized = sample.clamp(-1.0, 1.0);
  return (normalized * 32767.0).round().clamp(-32768, 32767);
}
