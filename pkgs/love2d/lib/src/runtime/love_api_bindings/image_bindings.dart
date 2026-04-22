part of '../love_api_bindings.dart';

/// Binds `love.image.isCompressed`.
///
/// LOVE accepts any file-backed input here and reports whether its container
/// matches one of the supported compressed-image headers.
LoveApiImplementation _bindImageIsCompressed(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.image.isCompressed';
    final first = args.isEmpty ? null : args.first;
    final fileData = await _requireResourceFileData(
      context,
      first,
      symbol,
      expectedKinds: 'filename, FileData, or File',
    );
    return _isCompressedImageContainer(fileData.bytes);
  };
}

/// Binds `love.image.newImageData`.
///
/// LOVE overloads this call to decode an encoded image source or to construct
/// blank or raw-backed image data from width and height arguments.
LoveApiImplementation _bindImageNewImageData(
  LibraryRegistrationContext context,
) {
  return (args) {
    const symbol = 'love.image.newImageData';
    final first = args.isEmpty ? null : args.first;

    final fileData = _filesystemFileDataCompatIfPresent(first);
    if (fileData != null) {
      try {
        return _wrapImageData(
          context,
          LoveImageData.decodeEncodedBytes(
            bytes: fileData.bytes,
            source: fileData.filename,
          ),
        );
      } catch (error) {
        throw LuaError(
          '$symbol failed to decode "${fileData.filename}": $error',
        );
      }
    }

    final source = _stringLike(first);
    if (source != null && _rawValue(first) is! num) {
      return _loadImageDataFromSource(context, source, symbol: symbol)
          .then((imageData) => _wrapImageData(context, imageData))
          .then((image) {
            return image;
          })
          .catchError((Object error) {
            if (error is LuaError) {
              throw error;
            }

            throw LuaError('$symbol failed to load "$source": $error');
          });
    }

    if (args.length < 2) {
      throw LuaError(
        '$symbol width/height variants expect at least 2 arguments',
      );
    }

    final width = _requireRoundedInt(args, 0, symbol);
    final height = _requireRoundedInt(args, 1, symbol);
    if (width <= 0 || height <= 0) {
      throw LuaError('$symbol width and height must both be > 0');
    }

    final format = switch (_valueAt(args, 2)) {
      null => 'rgba8',
      final Object value => _stringLike(value),
    };
    if (format == null) {
      throw LuaError('$symbol expected a pixel format string at argument 3');
    }

    final rawBytes = args.length >= 4
        ? _rawBytesIfPresent(_valueAt(args, 3))
        : null;
    if (args.length >= 4 && rawBytes == null) {
      throw LuaError('$symbol expected raw byte data at argument 4');
    }

    return _wrapImageData(
      context,
      rawBytes == null
          ? LoveImageData(width: width, height: height, format: format)
          : LoveImageData.fromRgbaBytes(
              width: width,
              height: height,
              format: format,
              bytes: rawBytes,
            ),
    );
  };
}

/// Binds `love.image.newCompressedData`.
LoveApiImplementation _bindImageNewCompressedData(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.image.newCompressedData';
    final first = args.isEmpty ? null : args.first;
    final fileData = await _requireResourceFileData(
      context,
      first,
      symbol,
      expectedKinds: 'filename, FileData, or File',
    );

    try {
      return _wrapCompressedImageData(
        context,
        _decodeCompressedImageData(
          bytes: fileData.bytes,
          source: fileData.filename,
        ),
      );
    } catch (error) {
      throw LuaError('$symbol failed to decode "${fileData.filename}": $error');
    }
  };
}

/// Returns raw byte data from [value], if it can be interpreted as bytes.
Uint8List? _rawBytesIfPresent(Object? value) {
  final fileData = _filesystemFileDataCompatIfPresent(value);
  if (fileData != null) {
    return Uint8List.fromList(fileData.bytes);
  }

  final raw = _rawValue(value);
  return switch (raw) {
    final Uint8List bytes => bytes,
    final LuaString stringValue => stringValue.bytes,
    final String stringValue => Uint8List.fromList(utf8.encode(stringValue)),
    final List<int> bytes => Uint8List.fromList(bytes),
    _ => null,
  };
}

/// Returns whether [bytes] look like a supported compressed-image container.
///
/// This mirrors LOVE's compressed container sniffing without fully decoding the
/// image payload.
bool _isCompressedImageContainer(List<int> bytes) {
  return _isCompressedDds(bytes) ||
      _isCompressedKtx(bytes) ||
      _isCompressedPkm(bytes) ||
      _isCompressedAstc(bytes) ||
      _isCompressedPvr(bytes);
}

/// Returns whether [bytes] look like a DDS compressed-image container.
bool _isCompressedDds(List<int> bytes) {
  if (bytes.length < 128) {
    return false;
  }

  if (!_matchesBytes(bytes, 0, const <int>[0x44, 0x44, 0x53, 0x20])) {
    return false;
  }

  if (_readUint32Le(bytes, 4) != 124 || _readUint32Le(bytes, 76) != 32) {
    return false;
  }

  const ddpfFourCc = 0x000004;
  final pixelFormatFlags = _readUint32Le(bytes, 80);
  if ((pixelFormatFlags & ddpfFourCc) == 0) {
    return false;
  }

  final fourCc = _readUint32Le(bytes, 84);
  if (fourCc == _fourCc('DX10')) {
    if (bytes.length < 148) {
      return false;
    }

    return _isCompressedDxgiFormat(_readUint32Le(bytes, 128));
  }

  return _compressedLegacyDdsFourCcs.contains(fourCc);
}

/// Returns whether [format] is one of the compressed DXGI format identifiers.
bool _isCompressedDxgiFormat(int format) {
  return switch (format) {
    70 ||
    71 ||
    72 ||
    73 ||
    74 ||
    75 ||
    76 ||
    77 ||
    78 ||
    79 ||
    80 ||
    81 ||
    82 ||
    83 ||
    84 ||
    94 ||
    95 ||
    96 ||
    97 ||
    98 ||
    99 => true,
    _ => false,
  };
}

/// Returns whether [bytes] look like a KTX compressed-image container.
bool _isCompressedKtx(List<int> bytes) {
  if (bytes.length < 64) {
    return false;
  }

  const identifier = <int>[
    0xAB,
    0x4B,
    0x54,
    0x58,
    0x20,
    0x31,
    0x31,
    0xBB,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];
  if (!_matchesBytes(bytes, 0, identifier)) {
    return false;
  }

  final endianness = _readUint32Le(bytes, 12);
  return endianness == 0x04030201 || endianness == 0x01020304;
}

/// Returns whether [bytes] look like a PKM compressed-image container.
bool _isCompressedPkm(List<int> bytes) {
  if (bytes.length <= 16) {
    return false;
  }

  if (!_matchesBytes(bytes, 0, const <int>[0x50, 0x4B, 0x4D, 0x20])) {
    return false;
  }

  final major = bytes[4];
  final minor = bytes[5];
  return (major == 0x31 || major == 0x32) && minor == 0x30;
}

/// Returns whether [bytes] look like an ASTC compressed-image container.
bool _isCompressedAstc(List<int> bytes) {
  if (bytes.length <= 16) {
    return false;
  }

  if (_readUint32Le(bytes, 0) != 0x5CA1AB13) {
    return false;
  }

  final blockZ = bytes[6];
  return blockZ == 1;
}

/// Returns whether [bytes] look like a PVR compressed-image container.
bool _isCompressedPvr(List<int> bytes) {
  if (bytes.length < 52) {
    return false;
  }

  final version = _readUint32Le(bytes, 0);
  return version == 0x03525650 ||
      version == 0x50565203 ||
      version == 0x21525650 ||
      version == 0x50565221;
}

/// Returns whether [pattern] matches [bytes] at [offset].
bool _matchesBytes(List<int> bytes, int offset, List<int> pattern) {
  if (offset < 0 || offset + pattern.length > bytes.length) {
    return false;
  }

  for (var index = 0; index < pattern.length; index++) {
    if (bytes[offset + index] != pattern[index]) {
      return false;
    }
  }

  return true;
}

/// Reads a 32-bit little-endian integer from [bytes] at [offset].
int _readUint32Le(List<int> bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

/// Returns the integer FOURCC value for the four-character [value].
int _fourCc(String value) {
  return value.codeUnitAt(0) |
      (value.codeUnitAt(1) << 8) |
      (value.codeUnitAt(2) << 16) |
      (value.codeUnitAt(3) << 24);
}

/// The legacy DDS FOURCC values accepted as compressed texture formats.
final Set<int> _compressedLegacyDdsFourCcs = <int>{
  _fourCc('DXT1'),
  _fourCc('DXT2'),
  _fourCc('DXT3'),
  _fourCc('DXT4'),
  _fourCc('DXT5'),
  _fourCc('ATI1'),
  _fourCc('BC4U'),
  _fourCc('BC4S'),
  _fourCc('ATI2'),
  _fourCc('BC5U'),
  _fourCc('BC5S'),
};
