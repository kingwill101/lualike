part of '../love_runtime.dart';

LoveImageData? rasterizeCompressedImageData(
  LoveCompressedImageData imageData, {
  int mipmap = 1,
}) {
  if (mipmap < 1 || mipmap > imageData.mipmapCount) {
    return null;
  }

  return switch (imageData.format) {
    'DXT1' => _decodeDxt1Mipmap(imageData, mipmap: mipmap),
    'DXT3' => _decodeDxt3Mipmap(imageData, mipmap: mipmap),
    'DXT5' => _decodeDxt5Mipmap(imageData, mipmap: mipmap),
    'ETC1' => _decodeEtc1Mipmap(imageData, mipmap: mipmap),
    'ETC2rgb' => _decodeEtc2RgbMipmap(
      imageData,
      mipmap: mipmap,
      punchThroughAlpha: false,
    ),
    'ETC2rgba1' => _decodeEtc2RgbMipmap(
      imageData,
      mipmap: mipmap,
      punchThroughAlpha: true,
    ),
    'ETC2rgba' => _decodeEtc2RgbaMipmap(imageData, mipmap: mipmap),
    'EACr' => _decodeEacR11Mipmap(imageData, mipmap: mipmap, signed: false),
    'EACrs' => _decodeEacR11Mipmap(imageData, mipmap: mipmap, signed: true),
    'EACrg' => _decodeEacRg11Mipmap(imageData, mipmap: mipmap, signed: false),
    'EACrgs' => _decodeEacRg11Mipmap(imageData, mipmap: mipmap, signed: true),
    'BC4' => _decodeBc4Mipmap(imageData, mipmap: mipmap, signed: false),
    'BC4s' => _decodeBc4Mipmap(imageData, mipmap: mipmap, signed: true),
    'BC5' => _decodeBc5Mipmap(imageData, mipmap: mipmap, signed: false),
    'BC5s' => _decodeBc5Mipmap(imageData, mipmap: mipmap, signed: true),
    _ => null,
  };
}

LoveImageData _decodeDxt1Mipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      _decodeColorBlockInto(
        result,
        imageData.bytes,
        blockOffset: blockOffset,
        blockX: blockX,
        blockY: blockY,
        allowTransparentColor: true,
      );

      blockOffset += 8;
    }
  }

  return result;
}

LoveImageData _decodeDxt3Mipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      final alphaBits = _readCompressedUint64Le(imageData.bytes, blockOffset);
      final colors = _decodeColorBlock(
        imageData.bytes,
        blockOffset: blockOffset + 8,
        allowTransparentColor: false,
      );
      _writeDecodedBlock(
        result,
        colors,
        blockX: blockX,
        blockY: blockY,
        alphaForPixel: (pixelIndex) {
          final alpha = (alphaBits >> (pixelIndex * 4)) & 0xf;
          return alpha / 15.0;
        },
      );
      blockOffset += 16;
    }
  }

  return result;
}

LoveImageData _decodeDxt5Mipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      final alphaPalette = _dxt5AlphaPalette(
        imageData.bytes[blockOffset],
        imageData.bytes[blockOffset + 1],
      );
      final alphaBits = _readCompressed48Le(imageData.bytes, blockOffset + 2);
      final colors = _decodeColorBlock(
        imageData.bytes,
        blockOffset: blockOffset + 8,
        allowTransparentColor: false,
      );
      _writeDecodedBlock(
        result,
        colors,
        blockX: blockX,
        blockY: blockY,
        alphaForPixel: (pixelIndex) {
          final alphaIndex = (alphaBits >> (pixelIndex * 3)) & 0x7;
          return alphaPalette[alphaIndex];
        },
      );
      blockOffset += 16;
    }
  }

  return result;
}

LoveImageData _decodeEtc1Mipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      _decodeEtc1BlockInto(
        result,
        imageData.bytes,
        blockOffset: blockOffset,
        blockX: blockX,
        blockY: blockY,
      );
      blockOffset += 8;
    }
  }

  return result;
}

LoveImageData _decodeEtc2RgbMipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
  required bool punchThroughAlpha,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      _decodeEtc2ColorBlockInto(
        result,
        imageData.bytes,
        blockOffset: blockOffset,
        blockX: blockX,
        blockY: blockY,
        punchThroughAlpha: punchThroughAlpha,
      );
      blockOffset += 8;
    }
  }

  return result;
}

LoveImageData _decodeEtc2RgbaMipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      final alphaValues = _decodeEtc2AlphaBlock(
        imageData.bytes,
        blockOffset: blockOffset,
      );
      _decodeEtc2ColorBlockInto(
        result,
        imageData.bytes,
        blockOffset: blockOffset + 8,
        blockX: blockX,
        blockY: blockY,
        alphaValues: alphaValues,
        punchThroughAlpha: false,
      );
      blockOffset += 16;
    }
  }

  return result;
}

LoveImageData _decodeBc4Mipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
  required bool signed,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      final red = _decodeBcChannelBlock(
        imageData.bytes,
        blockOffset: blockOffset,
        signed: signed,
      );
      _writeDecodedBlock(
        result,
        List<LoveColor>.generate(16, (pixelIndex) {
          return LoveColor(red[pixelIndex], 0.0, 0.0, 1.0);
        }, growable: false),
        blockX: blockX,
        blockY: blockY,
        alphaForPixel: (_) => 1.0,
      );
      blockOffset += 8;
    }
  }

  return result;
}

LoveImageData _decodeEacR11Mipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
  required bool signed,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      final red = _decodeEacChannelBlock(
        imageData.bytes,
        blockOffset: blockOffset,
        signed: signed,
      );
      _writeDecodedBlock(
        result,
        List<LoveColor>.generate(16, (pixelIndex) {
          return LoveColor(red[pixelIndex], 0.0, 0.0, 1.0);
        }, growable: false),
        blockX: blockX,
        blockY: blockY,
        alphaForPixel: (_) => 1.0,
      );
      blockOffset += 8;
    }
  }

  return result;
}

LoveImageData _decodeEacRg11Mipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
  required bool signed,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      final red = _decodeEacChannelBlock(
        imageData.bytes,
        blockOffset: blockOffset,
        signed: signed,
      );
      final green = _decodeEacChannelBlock(
        imageData.bytes,
        blockOffset: blockOffset + 8,
        signed: signed,
      );
      _writeDecodedBlock(
        result,
        List<LoveColor>.generate(16, (pixelIndex) {
          return LoveColor(red[pixelIndex], green[pixelIndex], 0.0, 1.0);
        }, growable: false),
        blockX: blockX,
        blockY: blockY,
        alphaForPixel: (_) => 1.0,
      );
      blockOffset += 16;
    }
  }

  return result;
}

LoveImageData _decodeBc5Mipmap(
  LoveCompressedImageData imageData, {
  required int mipmap,
  required bool signed,
}) {
  final level = imageData.mipmap(mipmap);
  final width = level.width;
  final height = level.height;
  final result = LoveImageData(width: width, height: height);
  final blocksWide = math.max((width + 3) ~/ 4, 1);
  final blocksHigh = math.max((height + 3) ~/ 4, 1);
  var blockOffset = level.offset;

  for (var blockY = 0; blockY < blocksHigh; blockY++) {
    for (var blockX = 0; blockX < blocksWide; blockX++) {
      final red = _decodeBcChannelBlock(
        imageData.bytes,
        blockOffset: blockOffset,
        signed: signed,
      );
      final green = _decodeBcChannelBlock(
        imageData.bytes,
        blockOffset: blockOffset + 8,
        signed: signed,
      );
      _writeDecodedBlock(
        result,
        List<LoveColor>.generate(16, (pixelIndex) {
          return LoveColor(red[pixelIndex], green[pixelIndex], 0.0, 1.0);
        }, growable: false),
        blockX: blockX,
        blockY: blockY,
        alphaForPixel: (_) => 1.0,
      );
      blockOffset += 16;
    }
  }

  return result;
}

void _decodeColorBlockInto(
  LoveImageData target,
  Uint8List bytes, {
  required int blockOffset,
  required int blockX,
  required int blockY,
  required bool allowTransparentColor,
}) {
  _writeDecodedBlock(
    target,
    _decodeColorBlock(
      bytes,
      blockOffset: blockOffset,
      allowTransparentColor: allowTransparentColor,
    ),
    blockX: blockX,
    blockY: blockY,
    alphaForPixel: (_) => 1.0,
  );
}

List<LoveColor> _decodeColorBlock(
  Uint8List bytes, {
  required int blockOffset,
  required bool allowTransparentColor,
}) {
  final color0 = _readCompressedUint16Le(bytes, blockOffset);
  final color1 = _readCompressedUint16Le(bytes, blockOffset + 2);
  final palette = _dxtColorPalette(
    color0,
    color1,
    allowTransparentColor: allowTransparentColor,
  );
  final lookup = _readCompressedUint32Le(bytes, blockOffset + 4);
  return List<LoveColor>.generate(16, (pixelIndex) {
    final paletteIndex = (lookup >> (pixelIndex * 2)) & 0x3;
    return palette[paletteIndex];
  }, growable: false);
}

List<double> _decodeBcChannelBlock(
  Uint8List bytes, {
  required int blockOffset,
  required bool signed,
}) {
  final palette = signed
      ? _bc4SignedPalette(
          _readCompressedInt8(bytes, blockOffset),
          _readCompressedInt8(bytes, blockOffset + 1),
        )
      : _dxt5AlphaPalette(bytes[blockOffset], bytes[blockOffset + 1]);
  final lookup = _readCompressed48Le(bytes, blockOffset + 2);
  return List<double>.generate(16, (pixelIndex) {
    final paletteIndex = (lookup >> (pixelIndex * 3)) & 0x7;
    return palette[paletteIndex];
  }, growable: false);
}

List<double> _decodeEacChannelBlock(
  Uint8List bytes, {
  required int blockOffset,
  required bool signed,
}) {
  var baseCodeword = signed
      ? _readCompressedInt8(bytes, blockOffset)
      : bytes[blockOffset];
  if (signed && baseCodeword <= -128) {
    baseCodeword = -127;
  }

  final secondByte = bytes[blockOffset + 1];
  final multiplier = secondByte >> 4;
  final tableIndex = secondByte & 0xf;
  final table = _eacModifierTable[tableIndex];
  final selectors = _readCompressed48Be(bytes, blockOffset + 2);

  return List<double>.generate(16, (pixelIndex) {
    final selector = (selectors >> ((15 - pixelIndex) * 3)) & 0x7;
    final modifier = table[selector];
    final decoded = signed
        ? _decodeSignedEac11(
            baseCodeword,
            modifier: modifier,
            multiplier: multiplier,
          )
        : _decodeUnsignedEac11(
            baseCodeword,
            modifier: modifier,
            multiplier: multiplier,
          );
    return signed ? decoded / 1023.0 : decoded / 2047.0;
  }, growable: false);
}

List<double> _decodeEtc2AlphaBlock(
  Uint8List bytes, {
  required int blockOffset,
}) {
  final baseCodeword = bytes[blockOffset];
  final secondByte = bytes[blockOffset + 1];
  final multiplier = secondByte >> 4;
  final table = _eacModifierTable[secondByte & 0xf];
  final selectors = _readCompressed48Be(bytes, blockOffset + 2);

  return List<double>.generate(16, (pixelIndex) {
    final selector = (selectors >> ((15 - pixelIndex) * 3)) & 0x7;
    final value = _clampCompressedByte(
      baseCodeword + (table[selector] * multiplier),
    );
    return value / 255.0;
  }, growable: false);
}

void _decodeEtc2ColorBlockInto(
  LoveImageData target,
  Uint8List bytes, {
  required int blockOffset,
  required int blockX,
  required int blockY,
  required bool punchThroughAlpha,
  List<double>? alphaValues,
}) {
  final colors = _decodeEtc2ColorBlock(
    bytes,
    blockOffset: blockOffset,
    alphaValues: alphaValues,
    punchThroughAlpha: punchThroughAlpha,
  );
  _writeDecodedBlock(
    target,
    colors,
    blockX: blockX,
    blockY: blockY,
    alphaForPixel: (pixelIndex) => colors[pixelIndex].a,
  );
}

List<LoveColor> _decodeEtc2ColorBlock(
  Uint8List bytes, {
  required int blockOffset,
  required bool punchThroughAlpha,
  List<double>? alphaValues,
}) {
  final high = _readCompressedUint32Be(bytes, blockOffset);
  final low = _readCompressedUint32Be(bytes, blockOffset + 4);
  final differentialOrOpaque = (high & 0x2) != 0;
  final flipped = (high & 0x1) != 0;
  final nonOpaquePunchThroughAlpha = punchThroughAlpha && !differentialOrOpaque;

  if (!punchThroughAlpha && !differentialOrOpaque) {
    return _decodeEtcSubblockColors(
      low: low,
      flipped: flipped,
      tableCodewordA: (high >> 5) & 0x7,
      tableCodewordB: (high >> 2) & 0x7,
      redA: _convertEtc4To8(high >> 28),
      greenA: _convertEtc4To8(high >> 20),
      blueA: _convertEtc4To8(high >> 12),
      redB: _convertEtc4To8(high >> 24),
      greenB: _convertEtc4To8(high >> 16),
      blueB: _convertEtc4To8(high >> 8),
      alphaValues: alphaValues,
      transparentIndex: null,
      modifierTables: _etcOpaqueModifierTables,
    );
  }

  final redBase = (high >> 27) & 0x1f;
  final greenBase = (high >> 19) & 0x1f;
  final blueBase = (high >> 11) & 0x1f;
  final redDiff = _etc1DiffLookup[(high >> 24) & 0x7];
  final greenDiff = _etc1DiffLookup[(high >> 16) & 0x7];
  final blueDiff = _etc1DiffLookup[(high >> 8) & 0x7];
  final redSecond = redBase + redDiff;
  final greenSecond = greenBase + greenDiff;
  final blueSecond = blueBase + blueDiff;

  if (redSecond < 0 || redSecond > 31) {
    return _decodeEtc2TModeColors(
      bytes,
      blockOffset: blockOffset,
      low: low,
      alphaValues: alphaValues,
      transparentIndex: nonOpaquePunchThroughAlpha ? 2 : null,
    );
  }
  if (greenSecond < 0 || greenSecond > 31) {
    return _decodeEtc2HModeColors(
      bytes,
      blockOffset: blockOffset,
      low: low,
      alphaValues: alphaValues,
      transparentIndex: nonOpaquePunchThroughAlpha ? 2 : null,
    );
  }
  if (blueSecond < 0 || blueSecond > 31) {
    return _decodeEtc2PlanarModeColors(
      bytes,
      blockOffset: blockOffset,
      alphaValues: alphaValues,
    );
  }

  return _decodeEtcSubblockColors(
    low: low,
    flipped: flipped,
    tableCodewordA: (high >> 5) & 0x7,
    tableCodewordB: (high >> 2) & 0x7,
    redA: _convertEtc5To8(redBase),
    greenA: _convertEtc5To8(greenBase),
    blueA: _convertEtc5To8(blueBase),
    redB: _convertEtc5To8(redSecond),
    greenB: _convertEtc5To8(greenSecond),
    blueB: _convertEtc5To8(blueSecond),
    alphaValues: alphaValues,
    transparentIndex: nonOpaquePunchThroughAlpha ? 2 : null,
    modifierTables: nonOpaquePunchThroughAlpha
        ? _etcNonOpaquePunchThroughModifierTables
        : _etcOpaqueModifierTables,
  );
}

List<LoveColor> _decodeEtcSubblockColors({
  required int low,
  required bool flipped,
  required int tableCodewordA,
  required int tableCodewordB,
  required int redA,
  required int greenA,
  required int blueA,
  required int redB,
  required int greenB,
  required int blueB,
  required List<List<int>> modifierTables,
  List<double>? alphaValues,
  int? transparentIndex,
}) {
  return List<LoveColor>.generate(16, (pixelIndex) {
    final localX = pixelIndex % 4;
    final localY = pixelIndex ~/ 4;
    final selector = _decodeEtcSelector(low, localX, localY);
    if (transparentIndex != null && selector == transparentIndex) {
      return const LoveColor(0, 0, 0, 0);
    }

    final secondSubblock = flipped ? localY >= 2 : localX >= 2;
    final red = secondSubblock ? redB : redA;
    final green = secondSubblock ? greenB : greenA;
    final blue = secondSubblock ? blueB : blueA;
    final table =
        modifierTables[secondSubblock ? tableCodewordB : tableCodewordA];
    final modifier = table[selector];
    return LoveColor(
      _clampCompressedByte(red + modifier) / 255.0,
      _clampCompressedByte(green + modifier) / 255.0,
      _clampCompressedByte(blue + modifier) / 255.0,
      alphaValues?[pixelIndex] ?? 1.0,
    );
  }, growable: false);
}

List<LoveColor> _decodeEtc2TModeColors(
  Uint8List bytes, {
  required int blockOffset,
  required int low,
  List<double>? alphaValues,
  int? transparentIndex,
}) {
  final byte0 = bytes[blockOffset];
  final byte1 = bytes[blockOffset + 1];
  final byte2 = bytes[blockOffset + 2];
  final byte3 = bytes[blockOffset + 3];
  final red1 = _convertEtc4To8(((byte0 >> 3) & 0x3) << 2 | (byte0 & 0x3));
  final green1 = _convertEtc4To8((byte1 >> 4) & 0xf);
  final blue1 = _convertEtc4To8(byte1 & 0xf);
  final red2 = _convertEtc4To8((byte2 >> 4) & 0xf);
  final green2 = _convertEtc4To8(byte2 & 0xf);
  final blue2 = _convertEtc4To8((byte3 >> 4) & 0xf);
  final distance =
      _etc2DistanceTable[(((byte3 >> 2) & 0x3) << 1) | (byte3 & 0x1)];
  final paintColors = <LoveColor>[
    LoveColor(red1 / 255.0, green1 / 255.0, blue1 / 255.0, 1.0),
    LoveColor(
      _clampCompressedByte(red2 + distance) / 255.0,
      _clampCompressedByte(green2 + distance) / 255.0,
      _clampCompressedByte(blue2 + distance) / 255.0,
      1.0,
    ),
    LoveColor(red2 / 255.0, green2 / 255.0, blue2 / 255.0, 1.0),
    LoveColor(
      _clampCompressedByte(red2 - distance) / 255.0,
      _clampCompressedByte(green2 - distance) / 255.0,
      _clampCompressedByte(blue2 - distance) / 255.0,
      1.0,
    ),
  ];

  return _decodeEtcPaintColors(
    paintColors,
    low: low,
    alphaValues: alphaValues,
    transparentIndex: transparentIndex,
  );
}

List<LoveColor> _decodeEtc2HModeColors(
  Uint8List bytes, {
  required int blockOffset,
  required int low,
  List<double>? alphaValues,
  int? transparentIndex,
}) {
  final byte0 = bytes[blockOffset];
  final byte1 = bytes[blockOffset + 1];
  final byte2 = bytes[blockOffset + 2];
  final byte3 = bytes[blockOffset + 3];
  final red1 = _convertEtc4To8((byte0 >> 3) & 0xf);
  final green1 = _convertEtc4To8(((byte0 & 0x7) << 1) | ((byte1 >> 4) & 0x1));
  final blue1 = _convertEtc4To8(
    (((byte1 >> 3) & 0x1) << 3) | ((byte1 & 0x3) << 1) | ((byte2 >> 7) & 0x1),
  );
  final red2 = _convertEtc4To8((byte2 >> 3) & 0xf);
  final green2 = _convertEtc4To8(((byte2 & 0x7) << 1) | ((byte3 >> 7) & 0x1));
  final blue2 = _convertEtc4To8((byte3 >> 3) & 0xf);
  final firstValue =
      (((byte0 >> 3) & 0xf) << 8) |
      ((((byte0 & 0x7) << 1) | ((byte1 >> 4) & 0x1)) << 4) |
      ((((byte1 >> 3) & 0x1) << 3) |
          ((byte1 & 0x3) << 1) |
          ((byte2 >> 7) & 0x1));
  final secondValue =
      (((byte2 >> 3) & 0xf) << 8) |
      ((((byte2 & 0x7) << 1) | ((byte3 >> 7) & 0x1)) << 4) |
      ((byte3 >> 3) & 0xf);
  final distance =
      _etc2DistanceTable[(((byte3 >> 2) & 0x1) << 2) |
          ((byte3 & 0x1) << 1) |
          (firstValue >= secondValue ? 1 : 0)];
  final paintColors = <LoveColor>[
    LoveColor(
      _clampCompressedByte(red1 + distance) / 255.0,
      _clampCompressedByte(green1 + distance) / 255.0,
      _clampCompressedByte(blue1 + distance) / 255.0,
      1.0,
    ),
    LoveColor(
      _clampCompressedByte(red1 - distance) / 255.0,
      _clampCompressedByte(green1 - distance) / 255.0,
      _clampCompressedByte(blue1 - distance) / 255.0,
      1.0,
    ),
    LoveColor(
      _clampCompressedByte(red2 + distance) / 255.0,
      _clampCompressedByte(green2 + distance) / 255.0,
      _clampCompressedByte(blue2 + distance) / 255.0,
      1.0,
    ),
    LoveColor(
      _clampCompressedByte(red2 - distance) / 255.0,
      _clampCompressedByte(green2 - distance) / 255.0,
      _clampCompressedByte(blue2 - distance) / 255.0,
      1.0,
    ),
  ];

  return _decodeEtcPaintColors(
    paintColors,
    low: low,
    alphaValues: alphaValues,
    transparentIndex: transparentIndex,
  );
}

List<LoveColor> _decodeEtc2PlanarModeColors(
  Uint8List bytes, {
  required int blockOffset,
  List<double>? alphaValues,
}) {
  final byte0 = bytes[blockOffset];
  final byte1 = bytes[blockOffset + 1];
  final byte2 = bytes[blockOffset + 2];
  final byte3 = bytes[blockOffset + 3];
  final byte4 = bytes[blockOffset + 4];
  final byte5 = bytes[blockOffset + 5];
  final byte6 = bytes[blockOffset + 6];
  final byte7 = bytes[blockOffset + 7];
  final redOrigin = _convertEtc6To8((byte0 >> 1) & 0x3f);
  final greenOrigin = _convertEtc7To8(
    ((byte0 & 0x1) << 6) | ((byte1 >> 1) & 0x3f),
  );
  final blueOrigin = _convertEtc6To8(
    ((byte1 & 0x1) << 5) |
        (((byte2 >> 3) & 0x3) << 3) |
        ((byte2 & 0x3) << 1) |
        ((byte3 >> 7) & 0x1),
  );
  final redHorizontal = _convertEtc6To8(
    ((byte3 >> 2) & 0x1f) << 1 | (byte3 & 0x1),
  );
  final greenHorizontal = _convertEtc7To8((byte4 >> 1) & 0x7f);
  final blueHorizontal = _convertEtc6To8(
    ((byte4 & 0x1) << 5) | ((byte5 >> 3) & 0x1f),
  );
  final redVertical = _convertEtc6To8(
    ((byte5 & 0x7) << 3) | ((byte6 >> 5) & 0x7),
  );
  final greenVertical = _convertEtc7To8(
    ((byte6 & 0x1f) << 2) | ((byte7 >> 6) & 0x3),
  );
  final blueVertical = _convertEtc6To8(byte7 & 0x3f);

  return List<LoveColor>.generate(16, (pixelIndex) {
    final localX = pixelIndex % 4;
    final localY = pixelIndex ~/ 4;
    final red = _clampCompressedByte(
      (((localX * (redHorizontal - redOrigin)) +
                  (localY * (redVertical - redOrigin)) +
                  2) >>
              2) +
          redOrigin,
    );
    final green = _clampCompressedByte(
      (((localX * (greenHorizontal - greenOrigin)) +
                  (localY * (greenVertical - greenOrigin)) +
                  2) >>
              2) +
          greenOrigin,
    );
    final blue = _clampCompressedByte(
      (((localX * (blueHorizontal - blueOrigin)) +
                  (localY * (blueVertical - blueOrigin)) +
                  2) >>
              2) +
          blueOrigin,
    );
    return LoveColor(
      red / 255.0,
      green / 255.0,
      blue / 255.0,
      alphaValues?[pixelIndex] ?? 1.0,
    );
  }, growable: false);
}

List<LoveColor> _decodeEtcPaintColors(
  List<LoveColor> paintColors, {
  required int low,
  List<double>? alphaValues,
  int? transparentIndex,
}) {
  return List<LoveColor>.generate(16, (pixelIndex) {
    final localX = pixelIndex % 4;
    final localY = pixelIndex ~/ 4;
    final selector = _decodeEtcSelector(low, localX, localY);
    if (transparentIndex != null && selector == transparentIndex) {
      return const LoveColor(0, 0, 0, 0);
    }
    final color = paintColors[selector];
    return LoveColor(
      color.r,
      color.g,
      color.b,
      alphaValues?[pixelIndex] ?? 1.0,
    );
  }, growable: false);
}

int _decodeEtcSelector(int low, int localX, int localY) {
  final selectorBit = localY + (localX * 4);
  return ((low >> selectorBit) & 0x1) | ((low >> (selectorBit + 15)) & 0x2);
}

void _decodeEtc1BlockInto(
  LoveImageData target,
  Uint8List bytes, {
  required int blockOffset,
  required int blockX,
  required int blockY,
}) {
  final high = _readCompressedUint32Be(bytes, blockOffset);
  final low = _readCompressedUint32Be(bytes, blockOffset + 4);

  int r1;
  int r2;
  int g1;
  int g2;
  int b1;
  int b2;

  if ((high & 0x2) != 0) {
    final rBase = high >> 27;
    final gBase = high >> 19;
    final bBase = high >> 11;
    r1 = _convertEtc5To8(rBase);
    r2 = _convertEtcDiff(rBase, high >> 24);
    g1 = _convertEtc5To8(gBase);
    g2 = _convertEtcDiff(gBase, high >> 16);
    b1 = _convertEtc5To8(bBase);
    b2 = _convertEtcDiff(bBase, high >> 8);
  } else {
    r1 = _convertEtc4To8(high >> 28);
    r2 = _convertEtc4To8(high >> 24);
    g1 = _convertEtc4To8(high >> 20);
    g2 = _convertEtc4To8(high >> 16);
    b1 = _convertEtc4To8(high >> 12);
    b2 = _convertEtc4To8(high >> 8);
  }

  final tableOffsetA = ((high >> 5) & 0x7) * 4;
  final tableOffsetB = ((high >> 2) & 0x7) * 4;
  final flipped = (high & 0x1) != 0;

  _decodeEtc1SubblockInto(
    target,
    blockX: blockX,
    blockY: blockY,
    low: low,
    red: r1,
    green: g1,
    blue: b1,
    tableOffset: tableOffsetA,
    second: false,
    flipped: flipped,
  );
  _decodeEtc1SubblockInto(
    target,
    blockX: blockX,
    blockY: blockY,
    low: low,
    red: r2,
    green: g2,
    blue: b2,
    tableOffset: tableOffsetB,
    second: true,
    flipped: flipped,
  );
}

void _decodeEtc1SubblockInto(
  LoveImageData target, {
  required int blockX,
  required int blockY,
  required int low,
  required int red,
  required int green,
  required int blue,
  required int tableOffset,
  required bool second,
  required bool flipped,
}) {
  final baseX = second && !flipped ? 2 : 0;
  final baseY = second && flipped ? 2 : 0;

  for (var index = 0; index < 8; index++) {
    final localX = flipped ? baseX + (index >> 1) : baseX + (index >> 2);
    final localY = flipped ? baseY + (index & 0x1) : baseY + (index & 0x3);
    final selectorBit = localY + (localX * 4);
    final selector =
        ((low >> selectorBit) & 0x1) | ((low >> (selectorBit + 15)) & 0x2);
    final modifier = _etc1ModifierTable[tableOffset + selector];
    final destX = (blockX * 4) + localX;
    final destY = (blockY * 4) + localY;
    if (destX >= target.width || destY >= target.height) {
      continue;
    }

    target.setPixel(
      destX,
      destY,
      LoveColor(
        _clampCompressedByte(red + modifier) / 255.0,
        _clampCompressedByte(green + modifier) / 255.0,
        _clampCompressedByte(blue + modifier) / 255.0,
        1.0,
      ),
    );
  }
}

void _writeDecodedBlock(
  LoveImageData target,
  List<LoveColor> colors, {
  required int blockX,
  required int blockY,
  required double Function(int pixelIndex) alphaForPixel,
}) {
  for (var pixelY = 0; pixelY < 4; pixelY++) {
    final destY = (blockY * 4) + pixelY;
    if (destY >= target.height) {
      break;
    }

    for (var pixelX = 0; pixelX < 4; pixelX++) {
      final destX = (blockX * 4) + pixelX;
      if (destX >= target.width) {
        break;
      }

      final pixelIndex = (pixelY * 4) + pixelX;
      final color = colors[pixelIndex];
      target.setPixel(
        destX,
        destY,
        LoveColor(color.r, color.g, color.b, alphaForPixel(pixelIndex)),
      );
    }
  }
}

List<LoveColor> _dxtColorPalette(
  int color0,
  int color1, {
  required bool allowTransparentColor,
}) {
  final first = _decodeRgb565(color0);
  final second = _decodeRgb565(color1);
  if (!allowTransparentColor || color0 > color1) {
    return <LoveColor>[
      first,
      second,
      _blendColors(first, second, 2, 1, 3),
      _blendColors(first, second, 1, 2, 3),
    ];
  }

  return <LoveColor>[
    first,
    second,
    _blendColors(first, second, 1, 1, 2),
    const LoveColor(0, 0, 0, 0),
  ];
}

LoveColor _decodeRgb565(int value) {
  return LoveColor(
    ((value >> 11) & 0x1f) / 31.0,
    ((value >> 5) & 0x3f) / 63.0,
    (value & 0x1f) / 31.0,
    1.0,
  );
}

LoveColor _blendColors(
  LoveColor first,
  LoveColor second,
  int firstWeight,
  int secondWeight,
  int divisor,
) {
  return LoveColor(
    ((first.r * firstWeight) + (second.r * secondWeight)) / divisor,
    ((first.g * firstWeight) + (second.g * secondWeight)) / divisor,
    ((first.b * firstWeight) + (second.b * secondWeight)) / divisor,
    ((first.a * firstWeight) + (second.a * secondWeight)) / divisor,
  );
}

List<double> _dxt5AlphaPalette(int alpha0, int alpha1) {
  final first = alpha0 / 255.0;
  final second = alpha1 / 255.0;
  if (alpha0 > alpha1) {
    return <double>[
      first,
      second,
      ((6 * first) + second) / 7,
      ((5 * first) + (2 * second)) / 7,
      ((4 * first) + (3 * second)) / 7,
      ((3 * first) + (4 * second)) / 7,
      ((2 * first) + (5 * second)) / 7,
      (first + (6 * second)) / 7,
    ];
  }

  return <double>[
    first,
    second,
    ((4 * first) + second) / 5,
    ((3 * first) + (2 * second)) / 5,
    ((2 * first) + (3 * second)) / 5,
    (first + (4 * second)) / 5,
    0.0,
    1.0,
  ];
}

List<double> _bc4SignedPalette(int endpoint0, int endpoint1) {
  final first = _signedNormalizedByte(endpoint0);
  final second = _signedNormalizedByte(endpoint1);
  if (endpoint0 > endpoint1) {
    return <double>[
      first,
      second,
      ((6 * first) + second) / 7,
      ((5 * first) + (2 * second)) / 7,
      ((4 * first) + (3 * second)) / 7,
      ((3 * first) + (4 * second)) / 7,
      ((2 * first) + (5 * second)) / 7,
      (first + (6 * second)) / 7,
    ];
  }

  return <double>[
    first,
    second,
    ((4 * first) + second) / 5,
    ((3 * first) + (2 * second)) / 5,
    ((2 * first) + (3 * second)) / 5,
    (first + (4 * second)) / 5,
    -1.0,
    1.0,
  ];
}

double _signedNormalizedByte(int value) {
  if (value <= -127) {
    return -1.0;
  }
  return value / 127.0;
}

int _decodeUnsignedEac11(
  int baseCodeword, {
  required int modifier,
  required int multiplier,
}) {
  final value =
      (baseCodeword * 8) +
      4 +
      (multiplier == 0 ? modifier : modifier * multiplier * 8);
  return _clampUnsignedEac11(value);
}

int _decodeSignedEac11(
  int baseCodeword, {
  required int modifier,
  required int multiplier,
}) {
  final value =
      (baseCodeword * 8) +
      (multiplier == 0 ? modifier : modifier * multiplier * 8);
  return _clampSignedEac11(value);
}

int _clampUnsignedEac11(int value) {
  if (value <= 0) {
    return 0;
  }
  if (value >= 2047) {
    return 2047;
  }
  return value;
}

int _clampSignedEac11(int value) {
  if (value <= -1023) {
    return -1023;
  }
  if (value >= 1023) {
    return 1023;
  }
  return value;
}

int _readCompressedUint16Le(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _readCompressedUint32Le(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

int _readCompressedUint32Be(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int _readCompressedUint64Le(Uint8List bytes, int offset) {
  return _readCompressedUint32Le(bytes, offset) |
      (_readCompressedUint32Le(bytes, offset + 4) << 32);
}

int _readCompressed48Le(Uint8List bytes, int offset) {
  var value = 0;
  for (var index = 0; index < 6; index++) {
    value |= bytes[offset + index] << (index * 8);
  }
  return value;
}

int _readCompressed48Be(Uint8List bytes, int offset) {
  var value = 0;
  for (var index = 0; index < 6; index++) {
    value = (value << 8) | bytes[offset + index];
  }
  return value;
}

int _readCompressedInt8(Uint8List bytes, int offset) {
  final value = bytes[offset];
  return value >= 0x80 ? value - 0x100 : value;
}

const List<int> _etc1ModifierTable = <int>[
  2,
  8,
  -2,
  -8,
  5,
  17,
  -5,
  -17,
  9,
  29,
  -9,
  -29,
  13,
  42,
  -13,
  -42,
  18,
  60,
  -18,
  -60,
  24,
  80,
  -24,
  -80,
  33,
  106,
  -33,
  -106,
  47,
  183,
  -47,
  -183,
];

const List<int> _etc1DiffLookup = <int>[0, 1, 2, 3, -4, -3, -2, -1];

const List<List<int>> _etcOpaqueModifierTables = <List<int>>[
  <int>[2, 8, -2, -8],
  <int>[5, 17, -5, -17],
  <int>[9, 29, -9, -29],
  <int>[13, 42, -13, -42],
  <int>[18, 60, -18, -60],
  <int>[24, 80, -24, -80],
  <int>[33, 106, -33, -106],
  <int>[47, 183, -47, -183],
];

const List<List<int>> _etcNonOpaquePunchThroughModifierTables = <List<int>>[
  <int>[0, 8, 0, -8],
  <int>[0, 17, 0, -17],
  <int>[0, 29, 0, -29],
  <int>[0, 42, 0, -42],
  <int>[0, 60, 0, -60],
  <int>[0, 80, 0, -80],
  <int>[0, 106, 0, -106],
  <int>[0, 183, 0, -183],
];

const List<int> _etc2DistanceTable = <int>[3, 6, 11, 16, 23, 32, 41, 64];

const List<List<int>> _eacModifierTable = <List<int>>[
  <int>[-3, -6, -9, -15, 2, 5, 8, 14],
  <int>[-3, -7, -10, -13, 2, 6, 9, 12],
  <int>[-2, -5, -8, -13, 1, 4, 7, 12],
  <int>[-2, -4, -6, -13, 1, 3, 5, 12],
  <int>[-3, -6, -8, -12, 2, 5, 7, 11],
  <int>[-3, -7, -9, -11, 2, 6, 8, 10],
  <int>[-4, -7, -8, -11, 3, 6, 7, 10],
  <int>[-3, -5, -8, -11, 2, 4, 7, 10],
  <int>[-2, -6, -8, -10, 1, 5, 7, 9],
  <int>[-2, -5, -8, -10, 1, 4, 7, 9],
  <int>[-2, -4, -8, -10, 1, 3, 7, 9],
  <int>[-2, -5, -7, -10, 1, 4, 6, 9],
  <int>[-3, -4, -7, -10, 2, 3, 6, 9],
  <int>[-1, -2, -3, -10, 0, 1, 2, 9],
  <int>[-4, -6, -8, -9, 3, 5, 7, 8],
  <int>[-3, -5, -7, -9, 2, 4, 6, 8],
];

int _clampCompressedByte(int value) {
  if (value <= 0) {
    return 0;
  }
  if (value >= 255) {
    return 255;
  }
  return value;
}

int _convertEtc4To8(int value) {
  final nibble = value & 0xf;
  return (nibble << 4) | nibble;
}

int _convertEtc5To8(int value) {
  final bits = value & 0x1f;
  return (bits << 3) | (bits >> 2);
}

int _convertEtc6To8(int value) {
  final bits = value & 0x3f;
  return (bits << 2) | (bits >> 4);
}

int _convertEtc7To8(int value) {
  final bits = value & 0x7f;
  return (bits << 1) | (bits >> 6);
}

int _convertEtcDiff(int base, int diff) {
  return _convertEtc5To8((base & 0x1f) + _etc1DiffLookup[diff & 0x7]);
}
