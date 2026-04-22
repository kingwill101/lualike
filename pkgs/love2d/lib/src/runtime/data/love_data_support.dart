part of '../love_runtime.dart';

enum LoveCompressedDataFormat { lz4, zlib, gzip, deflate }

enum LoveDataEncodeFormat { base64, hex }

enum LoveDataHashFunction { md5, sha1, sha224, sha256, sha384, sha512 }

abstract base class LoveDataObject {
  LoveDataObject._(this.bytes);

  final Uint8List bytes;

  int get size => bytes.length;

  LoveDataObject clone();
}

final class LoveByteData extends LoveDataObject {
  LoveByteData._(super.bytes) : super._();

  factory LoveByteData.fromBytes(List<int> bytes) {
    return LoveByteData._(_loveDataBytes(bytes));
  }

  factory LoveByteData.withSize(int size) {
    return LoveByteData._(Uint8List(size));
  }

  @override
  LoveByteData clone() => LoveByteData.fromBytes(bytes);
}

final class LoveDataView extends LoveDataObject {
  LoveDataView._(super.bytes) : super._();

  factory LoveDataView.fromBytes(List<int> bytes) {
    return LoveDataView._(_loveDataBytes(bytes));
  }

  @override
  LoveDataView clone() => LoveDataView.fromBytes(bytes);
}

final class LoveCompressedData extends LoveDataObject {
  LoveCompressedData._(
    super.bytes, {
    required this.format,
    required this.decompressedSize,
  }) : super._();

  factory LoveCompressedData.fromBytes({
    required List<int> bytes,
    required LoveCompressedDataFormat format,
    required int decompressedSize,
  }) {
    return LoveCompressedData._(
      _loveDataBytes(bytes),
      format: format,
      decompressedSize: decompressedSize,
    );
  }

  final LoveCompressedDataFormat format;
  final int decompressedSize;

  @override
  LoveCompressedData clone() => LoveCompressedData.fromBytes(
    bytes: bytes,
    format: format,
    decompressedSize: decompressedSize,
  );
}

Uint8List loveDataSlice(List<int> bytes, int offset, int size) {
  final source = _loveDataBytes(bytes);
  return Uint8List.sublistView(source, offset, offset + size);
}

LoveCompressedData loveCompressData(
  LoveCompressedDataFormat format,
  List<int> bytes, {
  int level = -1,
}) {
  final normalizedLevel = switch (level) {
    -1 => null,
    >= 0 && <= 9 => level,
    _ => throw ArgumentError(
      'Compression level must be between 0 and 9, or -1 for the default.',
    ),
  };

  final rawBytes = _loveDataBytes(bytes);
  final compressed = switch (format) {
    LoveCompressedDataFormat.lz4 => _loveCompressLz4Data(
      rawBytes,
    ),
    LoveCompressedDataFormat.zlib => ZLibEncoder().encodeBytes(
      rawBytes,
      level: normalizedLevel,
    ),
    LoveCompressedDataFormat.gzip => GZipEncoder().encodeBytes(
      rawBytes,
      level: normalizedLevel,
    ),
    LoveCompressedDataFormat.deflate => Deflate(
      rawBytes,
      level: normalizedLevel ?? DeflateLevel.defaultCompression,
    ).getBytes(),
  };

  return LoveCompressedData.fromBytes(
    bytes: compressed,
    format: format,
    decompressedSize: rawBytes.length,
  );
}

Uint8List loveDecompressData(LoveCompressedDataFormat format, List<int> bytes) {
  final compressedBytes = _loveDataBytes(bytes);
  return switch (format) {
    LoveCompressedDataFormat.lz4 => _loveDecompressLz4Data(compressedBytes),
    LoveCompressedDataFormat.zlib => ZLibDecoder().decodeBytes(compressedBytes),
    LoveCompressedDataFormat.gzip => GZipDecoder().decodeBytes(compressedBytes),
    LoveCompressedDataFormat.deflate => Inflate(compressedBytes).getBytes(),
  };
}

const int _loveLz4HeaderSize = 4;
const int _loveLz4MaxInputSize = 0x7E000000;

Uint8List _loveCompressLz4Data(Uint8List bytes) {
  if (bytes.length > _loveLz4MaxInputSize) {
    throw ArgumentError('Data is too large for LZ4 compressor.');
  }

  final builder = BytesBuilder(copy: false);
  final header = ByteData(_loveLz4HeaderSize)
    ..setUint32(0, bytes.length, Endian.little);
  builder.add(
    header.buffer.asUint8List(header.offsetInBytes, header.lengthInBytes),
  );
  builder.add(_loveEncodeLz4LiteralOnlyBlock(bytes));
  return builder.toBytes();
}

Uint8List _loveEncodeLz4LiteralOnlyBlock(Uint8List bytes) {
  if (bytes.isEmpty) {
    return Uint8List(0);
  }

  final builder = BytesBuilder(copy: false);
  _loveWriteLz4SequenceHeader(
    builder,
    literalLength: bytes.length,
    matchLength: null,
  );
  builder.add(bytes);
  return builder.toBytes();
}

void _loveWriteLz4SequenceHeader(
  BytesBuilder builder, {
  required int literalLength,
  required int? matchLength,
}) {
  final literalNibble = math.min(literalLength, 0x0F);
  final rawMatchLength = matchLength == null ? 0 : matchLength - 4;
  final matchNibble = math.min(rawMatchLength, 0x0F);
  builder.addByte((literalNibble << 4) | matchNibble);
  _loveWriteLz4LengthExtension(builder, literalLength - literalNibble);
  if (matchLength != null) {
    _loveWriteLz4LengthExtension(builder, rawMatchLength - matchNibble);
  }
}

void _loveWriteLz4LengthExtension(BytesBuilder builder, int remainingLength) {
  var next = remainingLength;
  while (next > 0) {
    final chunk = math.min(next, 0xFF);
    builder.addByte(chunk);
    next -= chunk;
  }
}

Uint8List _loveDecompressLz4Data(Uint8List bytes) {
  if (bytes.length < _loveLz4HeaderSize) {
    throw const FormatException('Invalid LZ4-compressed data size.');
  }

  final header = ByteData.sublistView(bytes, 0, _loveLz4HeaderSize);
  final expectedSize = header.getUint32(0, Endian.little);
  final payload = Uint8List.sublistView(bytes, _loveLz4HeaderSize);
  final output = Uint8List(expectedSize);
  final actualSize = _loveDecodeLz4Block(payload, output);
  return actualSize == output.length
      ? output
      : Uint8List.sublistView(output, 0, actualSize);
}

int _loveDecodeLz4Block(Uint8List input, Uint8List output) {
  var inputOffset = 0;
  var outputOffset = 0;

  int readLength(int length) {
    if (length != 0x0F) {
      return length;
    }

    var resolvedLength = length;
    while (true) {
      if (inputOffset >= input.length) {
        throw const FormatException('Could not decompress LZ4-compressed data.');
      }

      final chunk = input[inputOffset++];
      resolvedLength += chunk;
      if (chunk != 0xFF) {
        return resolvedLength;
      }
    }
  }

  while (inputOffset < input.length) {
    final token = input[inputOffset++];
    final literalLength = readLength(token >>> 4);
    if (inputOffset + literalLength > input.length ||
        outputOffset + literalLength > output.length) {
      throw const FormatException('Could not decompress LZ4-compressed data.');
    }

    output.setRange(
      outputOffset,
      outputOffset + literalLength,
      input,
      inputOffset,
    );
    inputOffset += literalLength;
    outputOffset += literalLength;

    if (inputOffset >= input.length) {
      return outputOffset;
    }

    if (inputOffset + 2 > input.length) {
      throw const FormatException('Could not decompress LZ4-compressed data.');
    }

    final offset = input[inputOffset] | (input[inputOffset + 1] << 8);
    inputOffset += 2;
    if (offset <= 0 || offset > outputOffset) {
      throw const FormatException('Could not decompress LZ4-compressed data.');
    }

    final matchLength = readLength(token & 0x0F) + 4;
    if (outputOffset + matchLength > output.length) {
      throw const FormatException('Could not decompress LZ4-compressed data.');
    }

    var matchOffset = outputOffset - offset;
    for (var i = 0; i < matchLength; i++) {
      output[outputOffset++] = output[matchOffset++];
    }
  }

  return outputOffset;
}

Uint8List loveEncodeData(
  LoveDataEncodeFormat format,
  List<int> bytes, {
  int lineLength = 0,
}) {
  final rawBytes = _loveDataBytes(bytes);
  return switch (format) {
    LoveDataEncodeFormat.base64 => Uint8List.fromList(
      _insertBase64LineBreaks(
        convert.base64Encode(rawBytes),
        lineLength: lineLength,
      ).codeUnits,
    ),
    LoveDataEncodeFormat.hex => Uint8List.fromList(
      _encodeHex(rawBytes).codeUnits,
    ),
  };
}

Uint8List loveDecodeData(LoveDataEncodeFormat format, List<int> bytes) {
  final encodedBytes = _loveDataBytes(bytes);
  return switch (format) {
    LoveDataEncodeFormat.base64 => Uint8List.fromList(
      convert.base64Decode(
        String.fromCharCodes(
          encodedBytes.where((byte) => !_isAsciiWhitespace(byte)),
        ),
      ),
    ),
    LoveDataEncodeFormat.hex => Uint8List.fromList(
      _decodeHex(String.fromCharCodes(encodedBytes)),
    ),
  };
}

Uint8List loveHashData(LoveDataHashFunction function, List<int> bytes) {
  final input = _loveDataBytes(bytes);
  final digest = switch (function) {
    LoveDataHashFunction.md5 => crypto.md5.convert(input),
    LoveDataHashFunction.sha1 => crypto.sha1.convert(input),
    LoveDataHashFunction.sha224 => crypto.sha224.convert(input),
    LoveDataHashFunction.sha256 => crypto.sha256.convert(input),
    LoveDataHashFunction.sha384 => crypto.sha384.convert(input),
    LoveDataHashFunction.sha512 => crypto.sha512.convert(input),
  };
  return Uint8List.fromList(digest.bytes);
}

Uint8List _loveDataBytes(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

String _insertBase64LineBreaks(String input, {required int lineLength}) {
  if (lineLength <= 0 || input.length <= lineLength) {
    return input;
  }

  final buffer = StringBuffer();
  for (var index = 0; index < input.length; index += lineLength) {
    if (index > 0) {
      buffer.write('\n');
    }

    final end = math.min(index + lineLength, input.length);
    buffer.write(input.substring(index, end));
  }
  return buffer.toString();
}

String _encodeHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

List<int> _decodeHex(String input) {
  final normalized = input.trim();
  if (normalized.length.isOdd) {
    throw FormatException('Hex string must contain an even number of digits.');
  }

  final bytes = Uint8List(normalized.length ~/ 2);
  for (var i = 0; i < normalized.length; i += 2) {
    final value = int.tryParse(normalized.substring(i, i + 2), radix: 16);
    if (value == null) {
      throw FormatException('Hex string contains invalid digits.');
    }
    bytes[i ~/ 2] = value;
  }

  return bytes;
}

bool _isAsciiWhitespace(int byte) {
  return byte == 0x09 ||
      byte == 0x0A ||
      byte == 0x0D ||
      byte == 0x20 ||
      byte == 0x0C ||
      byte == 0x0B;
}
