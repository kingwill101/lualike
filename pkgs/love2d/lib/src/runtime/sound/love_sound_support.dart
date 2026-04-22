part of '../love_runtime.dart';

/// The default decode chunk size, in bytes, for [LoveSoundDecoder].
const int loveSoundDefaultBufferSize = 16384;

/// The default sample rate used for synthesized sound data.
const int loveSoundDefaultSampleRate = 44100;

/// The default channel count used for synthesized sound data.
const int loveSoundDefaultChannels = 2;

/// The default bit depth used for synthesized sound data.
const int loveSoundDefaultBitDepth = 16;

/// Stores PCM sound data and its playback metadata.
final class LoveSoundData extends LoveDataObject {
  /// Creates sound data from normalized PCM bytes and metadata.
  LoveSoundData._(
    super.bytes, {
    required this.sampleRate,
    required this.bitDepth,
    required this.channels,
  }) : super._();

  /// Creates silent PCM sound data with the requested frame count.
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

  /// Creates sound data from raw PCM bytes.
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

  /// The sample rate in frames per second.
  final int sampleRate;

  /// The PCM bit depth per channel sample.
  final int bitDepth;

  /// The number of channels in each sample frame.
  final int channels;

  /// The number of sample frames stored in [bytes].
  int get sampleCount => bytes.length ~/ frameByteSize;

  /// The number of individual channel samples stored in [bytes].
  int get rawSampleCount => sampleCount * channels;

  /// The number of bytes in one interleaved sample frame.
  int get frameByteSize =>
      _soundFrameByteSize(bitDepth: bitDepth, channels: channels);

  /// The playback duration in seconds.
  double get duration => bytes.isEmpty ? 0.0 : bytes.length / frameRateBytes;

  /// The number of PCM bytes played per second.
  double get frameRateBytes => channels * sampleRate * (bitDepth / 8);

  /// Returns a copy of this sound data.
  @override
  LoveSoundData clone() => LoveSoundData.fromPcmBytes(
    bytes: bytes,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
    channels: channels,
  );

  /// Returns a normalized sample value from `-1.0` to `1.0`.
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

  /// Writes a normalized sample value at [index].
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

  /// Returns a copy of the frame range starting at [frameOffset].
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

  /// Resolves a frame and optional [channel] to a raw sample index.
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

  /// Validates that [rawIndex] refers to an existing channel sample.
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

/// Decodes sound data into sequential PCM chunks.
final class LoveSoundDecoder {
  /// Creates a decoder that reads from a cloned copy of [data].
  LoveSoundDecoder(
    LoveSoundData data, {
    int bufferSize = loveSoundDefaultBufferSize,
  }) : _data = data.clone(),
       bufferSize = _validateDecoderBufferSize(bufferSize);

  /// The source sound data being decoded.
  final LoveSoundData _data;

  /// The target chunk size in bytes.
  final int bufferSize;
  int _frameCursor = 0;

  /// The bit depth of the decoded PCM output.
  int get bitDepth => _data.bitDepth;

  /// The channel count of the decoded PCM output.
  int get channels => _data.channels;

  /// The sample rate of the decoded PCM output.
  int get sampleRate => _data.sampleRate;

  /// The full source duration in seconds.
  double get duration => _data.duration;

  /// The total number of frames in the source data.
  int get sampleCount => _data.sampleCount;

  /// Whether all sample frames have been decoded.
  bool get isFinished => _frameCursor >= sampleCount;

  /// Returns a decoder starting from the beginning of the same sound data.
  LoveSoundDecoder clone() => LoveSoundDecoder(_data, bufferSize: bufferSize);

  /// Decodes the next PCM chunk, or `null` when exhausted.
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

  /// Decodes and returns all remaining sample frames.
  LoveSoundData decodeAllRemaining() {
    final remaining = sampleCount - _frameCursor;
    final chunk = _data.copyFrames(_frameCursor, remaining);
    _frameCursor = sampleCount;
    return chunk;
  }

  /// Seeks back to the beginning of the source data.
  void rewind() {
    _frameCursor = 0;
  }

  /// Seeks to approximately [seconds] within the source data.
  void seek(double seconds) {
    if (seconds <= 0) {
      rewind();
      return;
    }

    _frameCursor = (seconds * sampleRate).floor().clamp(0, sampleCount);
  }

  /// Returns the number of frames emitted per decode chunk.
  int _chunkFrameCount() {
    final frameByteSize = _data.frameByteSize;
    final alignedBytes = bufferSize < frameByteSize
        ? frameByteSize
        : bufferSize - (bufferSize % frameByteSize);
    return math.max(1, alignedBytes ~/ frameByteSize);
  }
}

/// Creates a sound decoder by decoding the audio bytes in [bytes].
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

/// Encodes [data] as a PCM WAV byte stream.
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

/// Decodes a supported sound file into [LoveSoundData].
LoveSoundData loveDecodeSoundFile({
  required List<int> bytes,
  required String source,
}) {
  final extension = _soundExtension(source);
  final looksLikeWave = _looksLikeWave(bytes);
  if (looksLikeWave || extension == 'wav' || extension == 'wave') {
    return _decodeWaveSoundData(bytes, source: source);
  }

  final hostWaveBytes = love_sound_host_decode
      .decodeCompressedSoundFileToWaveBytesViaHost(bytes, source: source);
  if (hostWaveBytes != null) {
    return _decodeWaveSoundData(hostWaveBytes, source: source);
  }

  throw UnsupportedError('Extension "$extension" not supported.');
}

/// Decodes WAV data from [bytes].
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

/// The WAV format tag for PCM integer samples.
const int _waveFormatPcm = 0x0001;

/// The WAV format tag for IEEE floating-point samples.
const int _waveFormatIeeeFloat = 0x0003;

/// The WAV format tag for extensible format chunks.
const int _waveFormatExtensible = 0xFFFE;

/// Decodes integer PCM WAV payloads into [LoveSoundData].
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

/// Decodes floating-point WAV payloads into 16-bit [LoveSoundData].
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

/// Converts arbitrary WAV samples to 16-bit PCM sound data.
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

/// Validates constructor arguments for synthesized sound data.
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

/// Validates shared PCM metadata values.
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

/// Validates the configured decode buffer size.
int _validateDecoderBufferSize(int bufferSize) {
  if (bufferSize <= 0) {
    throw ArgumentError('Invalid decoder buffer size: $bufferSize');
  }
  return bufferSize;
}

/// Returns the byte size of one PCM frame.
int _soundFrameByteSize({required int bitDepth, required int channels}) {
  _validateSoundMetadata(
    sampleRate: loveSoundDefaultSampleRate,
    bitDepth: bitDepth,
    channels: channels,
  );
  return (bitDepth ~/ 8) * channels;
}

/// Returns the lowercase extension from [source].
String _soundExtension(String source) {
  final dot = source.lastIndexOf('.');
  if (dot < 0 || dot == source.length - 1) {
    return '';
  }
  return source.substring(dot + 1).toLowerCase();
}

/// Returns whether [bytes] begins with a WAV RIFF header.
bool _looksLikeWave(List<int> bytes) {
  return bytes.length >= 12 &&
      _matchesAscii(bytes, 0, 'RIFF') &&
      _matchesAscii(bytes, 8, 'WAVE');
}

/// Returns whether [bytes] matches [value] at [offset].
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

/// Reads an unsigned 16-bit little-endian integer from [bytes].
int _readUint16Le(List<int> bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

/// Reads an unsigned 32-bit little-endian integer from [bytes].
int _readUint32Le(List<int> bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

/// Reads a signed 24-bit little-endian integer from [bytes].
int _readInt24Le(List<int> bytes, int offset) {
  var value =
      bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  if ((value & 0x00800000) != 0) {
    value |= ~0x00FFFFFF;
  }
  return value;
}

/// Converts a normalized floating-point sample to signed 16-bit PCM.
int _normalizedSampleToInt16(double sample) {
  final normalized = sample.clamp(-1.0, 1.0);
  return (normalized * 32767.0).round().clamp(-32768, 32767);
}
