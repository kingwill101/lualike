part of '../love_api_bindings.dart';

LoveCompressedImageData _decodeCompressedImageData({
  required List<int> bytes,
  required String source,
}) {
  final normalizedBytes = bytes is Uint8List
      ? bytes
      : Uint8List.fromList(bytes);

  if (_isCompressedDds(normalizedBytes)) {
    return _decodeCompressedDds(normalizedBytes, source: source);
  }
  if (_isCompressedKtx(normalizedBytes)) {
    return _decodeCompressedKtx(normalizedBytes, source: source);
  }
  if (_isCompressedPkm(normalizedBytes)) {
    return _decodeCompressedPkm(normalizedBytes, source: source);
  }
  if (_isCompressedAstc(normalizedBytes)) {
    return _decodeCompressedAstc(normalizedBytes, source: source);
  }
  if (_isCompressedPvr(normalizedBytes)) {
    return _decodeCompressedPvr(normalizedBytes, source: source);
  }

  throw ArgumentError('Could not parse compressed data: Unknown format.');
}

LoveCompressedImageData _decodeCompressedDds(
  Uint8List bytes, {
  required String source,
}) {
  if (bytes.length < 128) {
    throw ArgumentError('Could not parse compressed data: unexpected EOF.');
  }

  final height = _readUint32Le(bytes, 12);
  final width = _readUint32Le(bytes, 16);
  final mipmapCount = math.max(_readUint32Le(bytes, 28), 1);
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Could not parse compressed data: invalid dimensions.');
  }

  final pixelFormatFlags = _readUint32Le(bytes, 80);
  const ddpfFourCc = 0x000004;
  if ((pixelFormatFlags & ddpfFourCc) == 0) {
    throw ArgumentError(
      'Could not parse compressed data: unsupported DDS format.',
    );
  }

  final fourCc = _readUint32Le(bytes, 84);
  final mapping = fourCc == _fourCc('DX10')
      ? _ddsDx10Format(_readUint32Le(bytes, 128))
      : _ddsLegacyFormat(fourCc);
  if (mapping == null) {
    throw ArgumentError(
      'Could not parse compressed data: unsupported DDS format.',
    );
  }

  final dataOffset = fourCc == _fourCc('DX10') ? 148 : 128;
  var runningOffset = dataOffset;
  final mipmaps = <LoveCompressedImageMipmap>[];
  for (var level = 0; level < mipmapCount; level++) {
    final levelWidth = math.max(width >> level, 1);
    final levelHeight = math.max(height >> level, 1);
    final levelSize = _ddsMipSize(
      mapping.format,
      width: levelWidth,
      height: levelHeight,
    );
    if (runningOffset + levelSize > bytes.length) {
      throw ArgumentError('Could not parse compressed data: unexpected EOF.');
    }

    mipmaps.add(
      LoveCompressedImageMipmap(
        width: levelWidth,
        height: levelHeight,
        offset: runningOffset,
        size: levelSize,
      ),
    );
    runningOffset += levelSize;
  }

  return LoveCompressedImageData(
    source: source,
    bytes: bytes,
    format: mapping.format,
    srgb: mapping.srgb,
    mipmaps: mipmaps,
  );
}

LoveCompressedImageData _decodeCompressedKtx(
  Uint8List bytes, {
  required String source,
}) {
  if (bytes.length < 64) {
    throw ArgumentError('Could not parse compressed data: unexpected EOF.');
  }

  final reverseEndian = _readUint32Le(bytes, 12) == 0x01020304;
  final width = _readUint32Ktx(bytes, 36, reverseEndian: reverseEndian);
  final height = _readUint32Ktx(bytes, 40, reverseEndian: reverseEndian);
  final pixelDepth = _readUint32Ktx(bytes, 44, reverseEndian: reverseEndian);
  final arrayElements = _readUint32Ktx(bytes, 48, reverseEndian: reverseEndian);
  final faces = _readUint32Ktx(bytes, 52, reverseEndian: reverseEndian);
  final mipmapCount = math.max(
    _readUint32Ktx(bytes, 56, reverseEndian: reverseEndian),
    1,
  );
  final bytesOfKeyValueData = _readUint32Ktx(
    bytes,
    60,
    reverseEndian: reverseEndian,
  );
  if (arrayElements > 0 || pixelDepth > 1 || faces > 1) {
    throw ArgumentError(
      'Could not parse compressed data: unsupported KTX texture layout.',
    );
  }

  final mapping = _ktxFormat(
    _readUint32Ktx(bytes, 28, reverseEndian: reverseEndian),
  );
  if (mapping == null) {
    throw ArgumentError('Unsupported image format in KTX file.');
  }

  var runningOffset = 64 + bytesOfKeyValueData;
  final mipmaps = <LoveCompressedImageMipmap>[];
  for (var level = 0; level < mipmapCount; level++) {
    if (runningOffset + 4 > bytes.length) {
      throw ArgumentError('Could not parse KTX file: unexpected EOF.');
    }

    final mipSize = _readUint32Ktx(
      bytes,
      runningOffset,
      reverseEndian: reverseEndian,
    );
    final dataOffset = runningOffset + 4;
    final paddedMipSize = (mipSize + 3) & ~3;
    if (dataOffset + paddedMipSize > bytes.length) {
      throw ArgumentError('Could not parse KTX file: unexpected EOF.');
    }

    mipmaps.add(
      LoveCompressedImageMipmap(
        width: math.max(width >> level, 1),
        height: math.max(height >> level, 1),
        offset: dataOffset,
        size: mipSize,
      ),
    );
    runningOffset = dataOffset + paddedMipSize;
  }

  return LoveCompressedImageData(
    source: source,
    bytes: bytes,
    format: mapping.format,
    srgb: mapping.srgb,
    mipmaps: mipmaps,
  );
}

LoveCompressedImageData _decodeCompressedPkm(
  Uint8List bytes, {
  required String source,
}) {
  if (bytes.length <= 16) {
    throw ArgumentError('Could not parse compressed data: unexpected EOF.');
  }

  final format = _pkmFormat(_readUint16Be(bytes, 6));
  if (format == null) {
    throw ArgumentError(
      'Could not parse PKM file: unsupported texture format.',
    );
  }

  final width = _readUint16Be(bytes, 12);
  final height = _readUint16Be(bytes, 14);
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Could not parse compressed data: invalid dimensions.');
  }

  return LoveCompressedImageData(
    source: source,
    bytes: bytes,
    format: format,
    srgb: false,
    mipmaps: <LoveCompressedImageMipmap>[
      LoveCompressedImageMipmap(
        width: width,
        height: height,
        offset: 16,
        size: bytes.length - 16,
      ),
    ],
  );
}

LoveCompressedImageData _decodeCompressedAstc(
  Uint8List bytes, {
  required String source,
}) {
  if (bytes.length <= 16) {
    throw ArgumentError('Could not parse compressed data: unexpected EOF.');
  }

  final format = _astcFormat(bytes[4], bytes[5], bytes[6]);
  if (format == null) {
    throw ArgumentError('Could not parse ASTC file: unsupported block size.');
  }

  final width = _readUint24Le(bytes, 7);
  final height = _readUint24Le(bytes, 10);
  final depth = _readUint24Le(bytes, 13);
  if (width <= 0 || height <= 0 || depth != 1) {
    throw ArgumentError('Could not parse compressed data: invalid ASTC size.');
  }

  return LoveCompressedImageData(
    source: source,
    bytes: bytes,
    format: format,
    srgb: false,
    mipmaps: <LoveCompressedImageMipmap>[
      LoveCompressedImageMipmap(
        width: width,
        height: height,
        offset: 16,
        size: bytes.length - 16,
      ),
    ],
  );
}

LoveCompressedImageData _decodeCompressedPvr(
  Uint8List bytes, {
  required String source,
}) {
  if (bytes.length < 52) {
    throw ArgumentError('Could not parse compressed data: unexpected EOF.');
  }

  final version = _readUint32Le(bytes, 0);
  final header = switch (version) {
    0x03525650 || 0x50565203 => _parsePvrV3Header(bytes),
    0x21525650 || 0x50565221 => _convertPvrV2Header(bytes),
    _ => throw ArgumentError(
      'Could not decode compressed data (not a PVR file?)',
    ),
  };

  if (header.depth > 1) {
    throw ArgumentError('Could not parse PVR file: unsupported image depth.');
  }

  final mapping = _pvrFormat(
    header.pixelFormat,
    channelType: header.channelType,
  );
  if (mapping == null) {
    throw ArgumentError('Could not parse PVR file: unsupported image format.');
  }

  final fileOffset = 52 + header.metaDataSize;
  final mipmapCount = math.max(header.mipmaps, 1);
  var runningOffset = fileOffset;
  final mipmaps = <LoveCompressedImageMipmap>[];
  for (var level = 0; level < mipmapCount; level++) {
    final levelWidth = math.max(header.width >> level, 1);
    final levelHeight = math.max(header.height >> level, 1);
    final size = _pvrMipSize(
      header.pixelFormat,
      width: levelWidth,
      height: levelHeight,
    );
    if (runningOffset + size > bytes.length) {
      throw ArgumentError(
        'Could not parse PVR file: invalid size calculation.',
      );
    }

    mipmaps.add(
      LoveCompressedImageMipmap(
        width: levelWidth,
        height: levelHeight,
        offset: runningOffset,
        size: size,
      ),
    );
    runningOffset += size;
  }

  return LoveCompressedImageData(
    source: source,
    bytes: bytes,
    format: mapping.format,
    srgb: header.colorSpace == 1 || mapping.srgb,
    mipmaps: mipmaps,
  );
}

({String format, bool srgb})? _ddsLegacyFormat(int fourCc) {
  return switch (fourCc) {
    final value when value == _fourCc('DXT1') => (format: 'DXT1', srgb: false),
    final value when value == _fourCc('DXT2') => (format: 'DXT3', srgb: false),
    final value when value == _fourCc('DXT3') => (format: 'DXT3', srgb: false),
    final value when value == _fourCc('DXT4') => (format: 'DXT5', srgb: false),
    final value when value == _fourCc('DXT5') => (format: 'DXT5', srgb: false),
    final value when value == _fourCc('ATI1') => (format: 'BC4', srgb: false),
    final value when value == _fourCc('BC4U') => (format: 'BC4', srgb: false),
    final value when value == _fourCc('BC4S') => (format: 'BC4s', srgb: false),
    final value when value == _fourCc('ATI2') => (format: 'BC5', srgb: false),
    final value when value == _fourCc('BC5U') => (format: 'BC5', srgb: false),
    final value when value == _fourCc('BC5S') => (format: 'BC5s', srgb: false),
    _ => null,
  };
}

({String format, bool srgb})? _ddsDx10Format(int dxgiFormat) {
  return switch (dxgiFormat) {
    70 => (format: 'DXT1', srgb: false),
    71 => (format: 'DXT1', srgb: false),
    72 => (format: 'DXT1', srgb: true),
    73 => (format: 'DXT3', srgb: false),
    74 => (format: 'DXT3', srgb: false),
    75 => (format: 'DXT3', srgb: true),
    76 => (format: 'DXT5', srgb: false),
    77 => (format: 'DXT5', srgb: false),
    78 => (format: 'DXT5', srgb: true),
    79 => (format: 'BC4', srgb: false),
    80 => (format: 'BC4', srgb: false),
    81 => (format: 'BC4s', srgb: false),
    82 => (format: 'BC5', srgb: false),
    83 => (format: 'BC5', srgb: false),
    84 => (format: 'BC5s', srgb: false),
    94 => (format: 'BC6h', srgb: false),
    95 => (format: 'BC6hs', srgb: false),
    96 => (format: 'BC7', srgb: false),
    97 => (format: 'BC7', srgb: false),
    98 => (format: 'BC7', srgb: true),
    99 => (format: 'BC7', srgb: true),
    _ => null,
  };
}

int _ddsMipSize(String format, {required int width, required int height}) {
  final blockBytes = switch (format) {
    'DXT1' || 'BC4' || 'BC4s' => 8,
    _ => 16,
  };
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  return blocksWide * blocksHigh * blockBytes;
}

({String format, bool srgb})? _ktxFormat(int internalFormat) {
  return switch (internalFormat) {
    0x8D64 => (format: 'ETC1', srgb: false),
    0x9270 => (format: 'EACr', srgb: false),
    0x9271 => (format: 'EACrs', srgb: false),
    0x9272 => (format: 'EACrg', srgb: false),
    0x9273 => (format: 'EACrgs', srgb: false),
    0x9274 => (format: 'ETC2rgb', srgb: false),
    0x9275 => (format: 'ETC2rgb', srgb: true),
    0x9276 => (format: 'ETC2rgba1', srgb: false),
    0x9277 => (format: 'ETC2rgba1', srgb: true),
    0x9278 => (format: 'ETC2rgba', srgb: false),
    0x9279 => (format: 'ETC2rgba', srgb: true),
    0x8C00 => (format: 'PVR1rgb4', srgb: false),
    0x8C01 => (format: 'PVR1rgb2', srgb: false),
    0x8C02 => (format: 'PVR1rgba4', srgb: false),
    0x8C03 => (format: 'PVR1rgba2', srgb: false),
    0x83F0 => (format: 'DXT1', srgb: false),
    0x8C4C => (format: 'DXT1', srgb: true),
    0x83F2 => (format: 'DXT3', srgb: false),
    0x8C4E => (format: 'DXT3', srgb: true),
    0x83F3 => (format: 'DXT5', srgb: false),
    0x8C4F => (format: 'DXT5', srgb: true),
    0x8DBB => (format: 'BC4', srgb: false),
    0x8DBC => (format: 'BC4s', srgb: false),
    0x8DBD => (format: 'BC5', srgb: false),
    0x8DBE => (format: 'BC5s', srgb: false),
    0x8E8C => (format: 'BC7', srgb: false),
    0x8E8D => (format: 'BC7', srgb: true),
    0x8E8E => (format: 'BC6hs', srgb: false),
    0x8E8F => (format: 'BC6h', srgb: false),
    0x93B0 => (format: 'ASTC4x4', srgb: false),
    0x93D0 => (format: 'ASTC4x4', srgb: true),
    0x93B1 => (format: 'ASTC5x4', srgb: false),
    0x93D1 => (format: 'ASTC5x4', srgb: true),
    0x93B2 => (format: 'ASTC5x5', srgb: false),
    0x93D2 => (format: 'ASTC5x5', srgb: true),
    0x93B3 => (format: 'ASTC6x5', srgb: false),
    0x93D3 => (format: 'ASTC6x5', srgb: true),
    0x93B4 => (format: 'ASTC6x6', srgb: false),
    0x93D4 => (format: 'ASTC6x6', srgb: true),
    0x93B5 => (format: 'ASTC8x5', srgb: false),
    0x93D5 => (format: 'ASTC8x5', srgb: true),
    0x93B6 => (format: 'ASTC8x6', srgb: false),
    0x93D6 => (format: 'ASTC8x6', srgb: true),
    0x93B7 => (format: 'ASTC8x8', srgb: false),
    0x93D7 => (format: 'ASTC8x8', srgb: true),
    0x93B8 => (format: 'ASTC10x5', srgb: false),
    0x93D8 => (format: 'ASTC10x5', srgb: true),
    0x93B9 => (format: 'ASTC10x6', srgb: false),
    0x93D9 => (format: 'ASTC10x6', srgb: true),
    0x93BA => (format: 'ASTC10x8', srgb: false),
    0x93DA => (format: 'ASTC10x8', srgb: true),
    0x93BB => (format: 'ASTC10x10', srgb: false),
    0x93DB => (format: 'ASTC10x10', srgb: true),
    0x93BC => (format: 'ASTC12x10', srgb: false),
    0x93DC => (format: 'ASTC12x10', srgb: true),
    0x93BD => (format: 'ASTC12x12', srgb: false),
    0x93DD => (format: 'ASTC12x12', srgb: true),
    _ => null,
  };
}

int _readUint32Ktx(List<int> bytes, int offset, {required bool reverseEndian}) {
  if (!reverseEndian) {
    return _readUint32Le(bytes, offset);
  }

  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

String? _pkmFormat(int format) {
  return switch (format) {
    0 => 'ETC1',
    1 => 'ETC2rgb',
    2 || 3 => 'ETC2rgba',
    4 => 'ETC2rgba1',
    5 => 'EACr',
    6 => 'EACrg',
    7 => 'EACrs',
    8 => 'EACrgs',
    _ => null,
  };
}

String? _astcFormat(int blockX, int blockY, int blockZ) {
  if (blockZ != 1) {
    return null;
  }

  return switch ((blockX, blockY)) {
    (4, 4) => 'ASTC4x4',
    (5, 4) => 'ASTC5x4',
    (5, 5) => 'ASTC5x5',
    (6, 5) => 'ASTC6x5',
    (6, 6) => 'ASTC6x6',
    (8, 5) => 'ASTC8x5',
    (8, 6) => 'ASTC8x6',
    (8, 8) => 'ASTC8x8',
    (10, 5) => 'ASTC10x5',
    (10, 6) => 'ASTC10x6',
    (10, 8) => 'ASTC10x8',
    (10, 10) => 'ASTC10x10',
    (12, 10) => 'ASTC12x10',
    (12, 12) => 'ASTC12x12',
    _ => null,
  };
}

class _PvrHeader {
  const _PvrHeader({
    required this.pixelFormat,
    required this.colorSpace,
    required this.channelType,
    required this.width,
    required this.height,
    required this.depth,
    required this.mipmaps,
    required this.metaDataSize,
  });

  final int pixelFormat;
  final int colorSpace;
  final int channelType;
  final int width;
  final int height;
  final int depth;
  final int mipmaps;
  final int metaDataSize;
}

_PvrHeader _parsePvrV3Header(Uint8List bytes) {
  final reversed = _readUint32Le(bytes, 0) == 0x50565203;
  return _PvrHeader(
    pixelFormat: _readUint64Le(bytes, 8, reverseEndian: reversed),
    colorSpace: _readUint32Endian(bytes, 16, reversed),
    channelType: _readUint32Endian(bytes, 20, reversed),
    height: _readUint32Endian(bytes, 24, reversed),
    width: _readUint32Endian(bytes, 28, reversed),
    depth: _readUint32Endian(bytes, 32, reversed),
    mipmaps: _readUint32Endian(bytes, 44, reversed),
    metaDataSize: _readUint32Endian(bytes, 48, reversed),
  );
}

_PvrHeader _convertPvrV2Header(Uint8List bytes) {
  final reversed = _readUint32Le(bytes, 44) == 0x50565221;
  final height = _readUint32Endian(bytes, 4, reversed);
  final width = _readUint32Endian(bytes, 8, reversed);
  final mipmaps = _readUint32Endian(bytes, 12, reversed);
  final flags = _readUint32Endian(bytes, 16, reversed);
  final pixelFormat = switch (flags & 0xFF) {
    0x18 => 1,
    0x19 => 3,
    0x1C => 4,
    0x1D => 5,
    0x20 => 7,
    0x22 => 9,
    0x24 => 11,
    0x36 => 6,
    _ => 0x7F,
  };
  return _PvrHeader(
    pixelFormat: pixelFormat,
    colorSpace: 0,
    channelType: 0,
    width: width,
    height: height,
    depth: 1,
    mipmaps: mipmaps,
    metaDataSize: 0,
  );
}

({String format, bool srgb})? _pvrFormat(
  int pixelFormat, {
  required int channelType,
}) {
  final signed = switch (channelType) {
    1 || 5 || 9 => true,
    _ => false,
  };

  return switch (pixelFormat) {
    0 => (format: 'PVR1rgb2', srgb: false),
    1 => (format: 'PVR1rgba2', srgb: false),
    2 => (format: 'PVR1rgb4', srgb: false),
    3 => (format: 'PVR1rgba4', srgb: false),
    6 => (format: 'ETC1', srgb: false),
    7 => (format: 'DXT1', srgb: false),
    8 || 9 => (format: 'DXT3', srgb: false),
    10 || 11 => (format: 'DXT5', srgb: false),
    12 => (format: signed ? 'BC4s' : 'BC4', srgb: false),
    13 => (format: signed ? 'BC5s' : 'BC5', srgb: false),
    14 => (format: signed ? 'BC6hs' : 'BC6h', srgb: false),
    15 => (format: 'BC7', srgb: false),
    22 => (format: 'ETC2rgb', srgb: false),
    23 => (format: 'ETC2rgba', srgb: false),
    24 => (format: 'ETC2rgba1', srgb: false),
    25 => (format: signed ? 'EACrs' : 'EACr', srgb: false),
    26 => (format: signed ? 'EACrgs' : 'EACrg', srgb: false),
    27 => (format: 'ASTC4x4', srgb: false),
    28 => (format: 'ASTC5x4', srgb: false),
    29 => (format: 'ASTC5x5', srgb: false),
    30 => (format: 'ASTC6x5', srgb: false),
    31 => (format: 'ASTC6x6', srgb: false),
    32 => (format: 'ASTC8x5', srgb: false),
    33 => (format: 'ASTC8x6', srgb: false),
    34 => (format: 'ASTC8x8', srgb: false),
    35 => (format: 'ASTC10x5', srgb: false),
    36 => (format: 'ASTC10x6', srgb: false),
    37 => (format: 'ASTC10x8', srgb: false),
    38 => (format: 'ASTC10x10', srgb: false),
    39 => (format: 'ASTC12x10', srgb: false),
    40 => (format: 'ASTC12x12', srgb: false),
    _ => null,
  };
}

int _pvrMipSize(int pixelFormat, {required int width, required int height}) {
  final minDimensions = _pvrMinDimensions(pixelFormat);
  final paddedWidth =
      ((width + minDimensions.$1 - 1) ~/ minDimensions.$1) * minDimensions.$1;
  final paddedHeight =
      ((height + minDimensions.$2 - 1) ~/ minDimensions.$2) * minDimensions.$2;
  if (pixelFormat >= 27 && pixelFormat <= 40) {
    return (paddedWidth ~/ minDimensions.$1) *
        (paddedHeight ~/ minDimensions.$2) *
        16;
  }

  final bitsPerPixel = _pvrBitsPerPixel(pixelFormat);
  return bitsPerPixel * paddedWidth * paddedHeight ~/ 8;
}

(int, int) _pvrMinDimensions(int pixelFormat) {
  return switch (pixelFormat) {
    0 || 1 => (16, 8),
    2 || 3 => (8, 8),
    4 => (8, 4),
    5 => (4, 4),
    27 => (4, 4),
    28 => (5, 4),
    29 => (5, 5),
    30 => (6, 5),
    31 => (6, 6),
    32 => (8, 5),
    33 => (8, 6),
    34 => (8, 8),
    35 => (10, 5),
    36 => (10, 6),
    37 => (10, 8),
    38 => (10, 10),
    39 => (12, 10),
    40 => (12, 12),
    _ => (4, 4),
  };
}

int _pvrBitsPerPixel(int pixelFormat) {
  return switch (pixelFormat) {
    0 || 1 || 4 => 2,
    2 || 3 || 5 || 6 || 7 || 12 || 22 || 24 || 25 => 4,
    8 || 9 || 10 || 11 || 13 || 14 || 15 || 23 || 26 => 8,
    _ => 0,
  };
}

int _readUint16Be(List<int> bytes, int offset) {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

int _readUint24Le(List<int> bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

int _readUint32Endian(List<int> bytes, int offset, bool reverseEndian) {
  if (!reverseEndian) {
    return _readUint32Le(bytes, offset);
  }

  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int _readUint64Le(List<int> bytes, int offset, {required bool reverseEndian}) {
  if (!reverseEndian) {
    final low = _readUint32Le(bytes, offset);
    final high = _readUint32Le(bytes, offset + 4);
    return low | (high << 32);
  }

  final high = _readUint32Endian(bytes, offset, true);
  final low = _readUint32Endian(bytes, offset + 4, true);
  return low | (high << 32);
}
