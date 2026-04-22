part of '../love_api_bindings.dart';

/// Binds `Data:clone`.
///
/// This clones any LOVE data object supported by the runtime wrapper layer.
LoveApiImplementation _bindDataClone(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'Data:clone';
    final value = _valueAt(args, 0);
    if (_byteDataIfPresent(value) case final byteData?) {
      return _wrapByteData(context, byteData.clone());
    }
    if (_dataViewIfPresent(value) case final dataView?) {
      return _wrapDataView(context, dataView.clone());
    }
    if (_compressedDataIfPresent(value) case final compressedData?) {
      return _wrapCompressedData(context, compressedData.clone());
    }
    if (_soundDataIfPresent(value) case final soundData?) {
      return _wrapSoundData(context, soundData.clone());
    }
    if (_glyphDataIfPresent(value) case final glyphData?) {
      return _wrapGlyphData(context, glyphData.clone());
    }
    if (_filesystemFileDataCompatIfPresent(value) case final fileData?) {
      return _wrapFilesystemFileDataCompat(context, fileData.clone());
    }

    throw LuaError('$symbol expected a Data at argument 1');
  };
}

/// Binds `love.data.compress`.
LoveApiImplementation _bindDataCompress(LibraryRegistrationContext context) {
  return (args) {
    final symbol = 'love.data.compress';
    final container = _requireDataContainerType(args, 0, symbol);
    final format = _requireCompressedDataFormat(args, 1, symbol);
    final sourceBytes = _requireBinaryBytes(args, 2, symbol);
    final level = args.length >= 4 ? _requireRoundedInt(args, 3, symbol) : -1;

    try {
      final compressed = loveCompressData(format, sourceBytes, level: level);
      return _dataContainerResult(
        context,
        container,
        compressed.bytes,
        compressedData: compressed,
      );
    } on UnsupportedError catch (error) {
      throw LuaError('$symbol ${error.message}');
    } on ArgumentError catch (error) {
      throw LuaError('$symbol ${error.message}');
    }
  };
}

/// Binds `love.data.decode`.
LoveApiImplementation _bindDataDecode(LibraryRegistrationContext context) {
  return (args) {
    final symbol = 'love.data.decode';
    final container = _requireDataContainerType(args, 0, symbol);
    final format = _requireDataEncodeFormat(args, 1, symbol);
    final sourceBytes = _requireBinaryBytes(args, 2, symbol);

    try {
      return _dataContainerResult(
        context,
        container,
        loveDecodeData(format, sourceBytes),
      );
    } on FormatException catch (error) {
      throw LuaError('$symbol ${error.message}');
    }
  };
}

/// Binds `love.data.decompress`.
///
/// LOVE accepts either `CompressedData` directly or an explicit compression
/// format plus raw bytes.
LoveApiImplementation _bindDataDecompress(LibraryRegistrationContext context) {
  return (args) {
    final symbol = 'love.data.decompress';
    final container = _requireDataContainerType(args, 0, symbol);

    try {
      if (_compressedDataIfPresent(_valueAt(args, 1)) case final compressed?) {
        return _dataContainerResult(
          context,
          container,
          loveDecompressData(compressed.format, compressed.bytes),
        );
      }

      final format = _requireCompressedDataFormat(args, 1, symbol);
      final sourceBytes = _requireBinaryBytes(args, 2, symbol);
      return _dataContainerResult(
        context,
        container,
        loveDecompressData(format, sourceBytes),
      );
    } on UnsupportedError catch (error) {
      throw LuaError('$symbol ${error.message}');
    } on FormatException catch (error) {
      throw LuaError('$symbol ${error.message}');
    } on ArgumentError catch (error) {
      throw LuaError('$symbol ${error.message}');
    }
  };
}

/// Binds `love.data.encode`.
LoveApiImplementation _bindDataEncode(LibraryRegistrationContext context) {
  return (args) {
    final symbol = 'love.data.encode';
    final container = _requireDataContainerType(args, 0, symbol);
    final format = _requireDataEncodeFormat(args, 1, symbol);
    final sourceBytes = _requireBinaryBytes(args, 2, symbol);
    final lineLength = args.length >= 4
        ? _requireRoundedInt(args, 3, symbol)
        : 0;

    return _dataContainerResult(
      context,
      container,
      loveEncodeData(format, sourceBytes, lineLength: lineLength),
    );
  };
}

/// Binds `love.data.getPackedSize`.
LoveApiImplementation _bindDataGetPackedSize(
  LibraryRegistrationContext context,
) {
  return (args) async {
    return await _callStringLibrary(context, 'packsize', <Object?>[
      _requireString(args, 0, 'love.data.getPackedSize'),
    ], debugName: 'love.data.getPackedSize');
  };
}

/// Binds `love.data.hash`.
LoveApiImplementation _bindDataHash(LibraryRegistrationContext context) {
  return (args) {
    final symbol = 'love.data.hash';
    final interpreter = context.interpreter;
    if (interpreter == null) {
      throw StateError('No Lua runtime available for $symbol');
    }

    final function = _requireDataHashFunction(args, 0, symbol);
    final bytes = _requireBinaryBytes(args, 1, symbol);
    return interpreter.constantStringValue(loveHashData(function, bytes));
  };
}

/// Binds `love.data.newByteData`.
///
/// LOVE overloads this call to accept an existing `Data` object plus offset and
/// size, a byte count, or a string-like byte source.
LoveApiImplementation _bindDataNewByteData(LibraryRegistrationContext context) {
  return (args) {
    final symbol = 'love.data.newByteData';
    if (args.isEmpty) {
      throw LuaError('$symbol expects at least 1 argument');
    }

    final sourceData = _dataBytesIfPresent(_valueAt(args, 0));
    if (sourceData != null) {
      if (sourceData.isEmpty) {
        throw LuaError('$symbol Data size must be greater than zero.');
      }

      final offset = args.length >= 2 ? _requireRoundedInt(args, 1, symbol) : 0;
      if (offset < 0) {
        throw LuaError('$symbol Offset argument must not be negative.');
      }

      final size = args.length >= 3
          ? _requireRoundedInt(args, 2, symbol)
          : sourceData.length - offset;
      if (size <= 0) {
        throw LuaError('$symbol Size argument must be greater than zero.');
      }
      if (offset + size > sourceData.length) {
        throw LuaError(
          '$symbol Offset and size arguments must fit within the given Data\'s size.',
        );
      }

      return _wrapByteData(
        context,
        LoveByteData.fromBytes(loveDataSlice(sourceData, offset, size)),
      );
    }

    final first = _rawValue(args.first);
    if (first is num) {
      final size = first.round();
      if (size <= 0) {
        throw LuaError('$symbol Data size must be a positive number.');
      }
      return _wrapByteData(context, LoveByteData.withSize(size));
    }

    final sourceBytes = _stringBytesIfPresent(args.first);
    if (sourceBytes == null) {
      throw LuaError('$symbol expected a string, Data, or size at argument 1');
    }
    return _wrapByteData(context, LoveByteData.fromBytes(sourceBytes));
  };
}

/// Binds `love.data.newDataView`.
LoveApiImplementation _bindDataNewDataView(LibraryRegistrationContext context) {
  return (args) {
    final symbol = 'love.data.newDataView';
    final sourceBytes = _requireDataBytes(args, 0, symbol);
    final offset = _requireRoundedInt(args, 1, symbol);
    final size = _requireRoundedInt(args, 2, symbol);
    if (offset < 0 || size < 0) {
      throw LuaError('$symbol DataView offset and size must not be negative.');
    }
    if (size == 0) {
      throw LuaError('$symbol DataView size must be greater than 0.');
    }
    if (offset >= sourceBytes.length ||
        size > sourceBytes.length ||
        offset + size > sourceBytes.length) {
      throw LuaError(
        '$symbol Offset and size of Data View must fit within the original Data\'s size.',
      );
    }

    return _wrapDataView(
      context,
      LoveDataView.fromBytes(loveDataSlice(sourceBytes, offset, size)),
    );
  };
}

/// Binds `love.data.pack`.
LoveApiImplementation _bindDataPack(LibraryRegistrationContext context) {
  return (args) async {
    final symbol = 'love.data.pack';
    final container = _requireDataContainerType(args, 0, symbol);
    final format = _requireString(args, 1, symbol);
    final packed = await _callStringLibrary(context, 'pack', <Object?>[
      format,
      ...args.skip(2),
    ], debugName: symbol);
    final bytes = _requireBinaryBytesFromValue(packed, symbol);
    return _dataContainerResult(context, container, bytes);
  };
}

/// Binds `love.data.unpack`.
LoveApiImplementation _bindDataUnpack(LibraryRegistrationContext context) {
  return (args) async {
    final symbol = 'love.data.unpack';
    final format = _requireString(args, 0, symbol);
    final sourceBytes = _dataBytesIfPresent(_valueAt(args, 1));
    final source = sourceBytes == null
        ? _valueAt(args, 1)
        : context.interpreter!.constantStringValue(sourceBytes);
    return await _callStringLibrary(context, 'unpack', <Object?>[
      format,
      source,
      if (args.length >= 3) _valueAt(args, 2),
    ], debugName: symbol);
  };
}

/// The output container types supported by LOVE's data codec helpers.
enum _LoveDataContainerType { data, string }

/// Returns the validated data container type at [index].
_LoveDataContainerType _requireDataContainerType(
  List<Object?> args,
  int index,
  String symbol,
) {
  return switch (_requireString(args, index, symbol)) {
    'data' => _LoveDataContainerType.data,
    'string' => _LoveDataContainerType.string,
    final value => throw LuaError('$symbol invalid container type "$value"'),
  };
}

/// Returns the validated data encode format at [index].
LoveDataEncodeFormat _requireDataEncodeFormat(
  List<Object?> args,
  int index,
  String symbol,
) {
  return switch (_requireString(args, index, symbol)) {
    'base64' => LoveDataEncodeFormat.base64,
    'hex' => LoveDataEncodeFormat.hex,
    final value => throw LuaError('$symbol invalid encode format "$value"'),
  };
}

/// Returns the validated compressed-data format at [index].
LoveCompressedDataFormat _requireCompressedDataFormat(
  List<Object?> args,
  int index,
  String symbol,
) {
  return switch (_requireString(args, index, symbol)) {
    'lz4' => LoveCompressedDataFormat.lz4,
    'zlib' => LoveCompressedDataFormat.zlib,
    'gzip' => LoveCompressedDataFormat.gzip,
    'deflate' => LoveCompressedDataFormat.deflate,
    final value => throw LuaError(
      '$symbol invalid compressed data format "$value"',
    ),
  };
}

/// Returns the validated data hash function at [index].
LoveDataHashFunction _requireDataHashFunction(
  List<Object?> args,
  int index,
  String symbol,
) {
  return switch (_requireString(args, index, symbol)) {
    'md5' => LoveDataHashFunction.md5,
    'sha1' => LoveDataHashFunction.sha1,
    'sha224' => LoveDataHashFunction.sha224,
    'sha256' => LoveDataHashFunction.sha256,
    'sha384' => LoveDataHashFunction.sha384,
    'sha512' => LoveDataHashFunction.sha512,
    final value => throw LuaError('$symbol invalid hash function "$value"'),
  };
}

/// Returns LOVE's string name for a compressed data [format].
String _compressedDataFormatName(LoveCompressedDataFormat format) {
  return switch (format) {
    LoveCompressedDataFormat.lz4 => 'lz4',
    LoveCompressedDataFormat.zlib => 'zlib',
    LoveCompressedDataFormat.gzip => 'gzip',
    LoveCompressedDataFormat.deflate => 'deflate',
  };
}

/// Wraps [bytes] in the LOVE container requested by [container].
///
/// When [compressedData] is provided and the caller requested `data`, this
/// returns wrapped `CompressedData` instead of plain `ByteData`.
Object? _dataContainerResult(
  LibraryRegistrationContext context,
  _LoveDataContainerType container,
  List<int> bytes, {
  LoveCompressedData? compressedData,
}) {
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No Lua runtime available for love.data result');
  }

  return switch (container) {
    _LoveDataContainerType.data when compressedData != null =>
      _wrapCompressedData(context, compressedData),
    _LoveDataContainerType.data => _wrapByteData(
      context,
      LoveByteData.fromBytes(bytes),
    ),
    _LoveDataContainerType.string => interpreter.constantStringValue(bytes),
  };
}

/// Returns byte values for a Lua string-like [value], if possible.
List<int>? _stringBytesIfPresent(Object? value) {
  return switch (_valueAt(<Object?>[value], 0)) {
    final Value wrapped when wrapped.raw is LuaString => List<int>.from(
      (wrapped.raw as LuaString).bytes,
    ),
    final LuaString stringValue => List<int>.from(stringValue.bytes),
    final String stringValue => List<int>.from(
      LuaString.fromDartString(stringValue).bytes,
    ),
    _ => null,
  };
}

/// Returns byte values from a LOVE `Data`-like [value], if possible.
List<int>? _dataBytesIfPresent(Object? value) {
  final data = _loveDataObjectIfPresent(value);
  if (data != null) {
    return List<int>.from(data.bytes);
  }

  final fileData = _filesystemFileDataCompatIfPresent(value);
  if (fileData != null) {
    return List<int>.from(fileData.bytes);
  }

  return null;
}

/// Returns the required `Data` bytes at [index] or throws a [LuaError].
List<int> _requireDataBytes(List<Object?> args, int index, String symbol) {
  final bytes = _dataBytesIfPresent(_valueAt(args, index));
  if (bytes != null) {
    return bytes;
  }

  throw LuaError('$symbol expected a Data at argument ${index + 1}');
}

/// Returns required binary bytes from either a string or `Data` argument.
List<int> _requireBinaryBytes(List<Object?> args, int index, String symbol) {
  final dataBytes = _dataBytesIfPresent(_valueAt(args, index));
  if (dataBytes != null) {
    return dataBytes;
  }

  final stringBytes = _stringBytesIfPresent(_valueAt(args, index));
  if (stringBytes != null) {
    return stringBytes;
  }

  throw LuaError('$symbol expected a string or Data at argument ${index + 1}');
}

/// Returns required binary bytes from a string- or data-like result value.
List<int> _requireBinaryBytesFromValue(Object? value, String symbol) {
  final dataBytes = _dataBytesIfPresent(value);
  if (dataBytes != null) {
    return dataBytes;
  }

  final stringBytes = _stringBytesIfPresent(value);
  if (stringBytes != null) {
    return stringBytes;
  }

  throw LuaError('$symbol expected a string result');
}

/// Calls `string.[name]` inside the Lua runtime.
///
/// This is used to preserve LOVE's pack and unpack semantics by delegating to
/// Lua's own string library implementation.
Future<Object?> _callStringLibrary(
  LibraryRegistrationContext context,
  String name,
  List<Object?> args, {
  required String debugName,
}) async {
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No Lua runtime available for $debugName');
  }

  final stringTable = _tableIfPresent(
    interpreter.getCurrentEnv().get('string'),
  );
  final callable = stringTable?[name];
  if (callable == null) {
    throw StateError('Lua string.$name is not available');
  }

  return await interpreter.callFunction(
    switch (callable) {
      final Value wrapped => wrapped,
      final BuiltinFunction function => Value(function),
      _ => throw StateError('Lua string.$name is not callable'),
    },
    args
        .map((arg) => _luaStringLibraryArgument(interpreter, arg))
        .toList(growable: false),
    debugName: debugName,
    debugNameWhat: 'function',
  );
}

/// Converts [value] into the form expected by the Lua string library.
Value _luaStringLibraryArgument(LuaRuntime interpreter, Object? value) {
  return switch (value) {
    final Value wrapped => wrapped,
    final LuaString luaString => Value(luaString),
    final String stringValue => interpreter.constantStringValue(
      LuaString.fromDartString(stringValue).bytes,
    ),
    _ => Value(value),
  };
}
