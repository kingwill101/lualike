part of 'love_filesystem_bindings.dart';

/// Returns the positional argument at [index], if present.
Object? _valueAt(List<Object?> args, int index) {
  return index < args.length ? args[index] : null;
}

/// Unwraps common Lua wrapper values to plain Dart values.
Object? _rawValue(Object? value) {
  if (value is Value) {
    return value.unwrap();
  }
  if (value is LuaString) {
    return value.toString();
  }
  return value;
}

/// Returns the required string argument for [symbol] at [index].
String _requireString(List<Object?> args, int index, String symbol) {
  final value = loveStringLike(_valueAt(args, index));
  if (value != null) {
    return value;
  }

  throw LuaError('$symbol expected a string at argument ${index + 1}');
}

/// Returns the optional integer argument at [index], truncating numeric input.
int? _optionalTruncatedInt(List<Object?> args, int index) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw == null) {
    return null;
  }
  try {
    return NumberUtils.toInt(raw);
  } catch (_) {
    throw LuaError('expected a number at argument ${index + 1}');
  }
}

/// Returns the numeric argument for [symbol] at [index] as a double.
double _numberValue(List<Object?> args, int index, String symbol) {
  final raw = _rawValue(_valueAt(args, index));
  try {
    return NumberUtils.toDouble(raw);
  } catch (_) {
    throw LuaError('$symbol expected a number at argument ${index + 1}');
  }
}

/// Clamps [value] to the largest integer that Lua can represent exactly.
int _clampLuaFilesystemNumber(int value) {
  return value > _loveFilesystemLuaNumberLimit
      ? _loveFilesystemLuaNumberLimit
      : value;
}

/// Whether [value] is a known non-negative filesystem number.
bool _hasKnownFilesystemNumber(int? value) => value != null && value >= 0;

/// Returns the optional boolean argument at [index], defaulting to
/// [defaultValue].
bool _optionalBool(
  List<Object?> args,
  int index, {
  required bool defaultValue,
}) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw == null) {
    return defaultValue;
  }
  if (raw is bool) {
    return raw;
  }
  return defaultValue;
}

/// Returns the required boolean argument for [symbol] at [index].
bool _requireBoolean(List<Object?> args, int index, String symbol) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw is bool) {
    return raw;
  }

  throw LuaError('$symbol expected a boolean at argument ${index + 1}');
}

/// Returns the required wrapped [LoveFilesystemFile] for [symbol].
LoveFilesystemFile _requireFile(List<Object?> args, int index, String symbol) {
  final raw = _wrapperObject(args, index, symbol);
  if (raw is LoveFilesystemFile) {
    return raw;
  }

  throw LuaError('$symbol expected File at argument ${index + 1}');
}

/// Returns the required wrapped [LoveFilesystemFileData] for [symbol].
LoveFilesystemFileData _requireFileData(
  List<Object?> args,
  int index,
  String symbol,
) {
  final raw = _wrapperObject(args, index, symbol);
  if (raw is LoveFilesystemFileData) {
    if (_loveFilesystemReleased[raw] == true) {
      throw LuaError('Cannot use object after it has been released.');
    }
    return raw;
  }

  throw LuaError('$symbol expected FileData at argument ${index + 1}');
}

String _filesystemLuaTypeName(Object? value) {
  final raw = _rawValue(value);
  return switch (raw) {
    null => 'nil',
    bool _ => 'boolean',
    num _ => 'number',
    String _ || LuaString _ => 'string',
    Map<dynamic, dynamic> _ => 'table',
    BuiltinFunction _ || Function _ => 'function',
    _ => raw.runtimeType.toString(),
  };
}

Never _throwFilesystemLuaTypeError({
  required String symbol,
  required int index,
  required String expected,
  required Object? actual,
}) {
  final separatorIndex = math.max(
    symbol.lastIndexOf('.'),
    symbol.lastIndexOf(':'),
  );
  final callable = separatorIndex >= 0
      ? symbol.substring(separatorIndex + 1)
      : symbol;
  throw LuaError(
    "bad argument #${index + 1} to '$callable' "
    "($expected expected, got ${_filesystemLuaTypeName(actual)})",
  );
}

/// Returns the wrapped file object stored in [value], if any.
LoveFilesystemFile? _fileIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  final raw = table?[_loveFilesystemFileObjectKey];
  return raw is LoveFilesystemFile ? raw : null;
}

/// Returns the wrapped dropped-file object stored in [value], if any.
LoveFilesystemDroppedFile? _droppedFileIfPresent(Object? value) {
  final file = _fileIfPresent(value);
  return file is LoveFilesystemDroppedFile ? file : null;
}

/// Returns the wrapped file-data object stored in [value], if any.
LoveFilesystemFileData? _fileDataIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  final raw = table?[_loveFilesystemFileDataObjectKey];
  return raw is LoveFilesystemFileData ? raw : null;
}

/// Returns the wrapped LOVE object stored at [index].
Object _wrapperObject(List<Object?> args, int index, String symbol) {
  final table = _tableIfPresent(_valueAt(args, index));
  final raw =
      table?[_loveFilesystemFileObjectKey] ??
      table?[_loveFilesystemFileDataObjectKey];
  if (raw != null) {
    return raw;
  }

  throw LuaError('$symbol expected LOVE object at argument ${index + 1}');
}

/// Returns the wrapped LOVE type name stored at [index].
String _wrapperTypeName(List<Object?> args, int index, String symbol) {
  final table = _tableIfPresent(_valueAt(args, index));
  final typeName = table?[_loveFilesystemObjectTypeKey];
  if (typeName is String) {
    return typeName;
  }
  throw LuaError('$symbol expected LOVE object at argument ${index + 1}');
}

/// Returns the wrapped LOVE type hierarchy stored at [index].
Set<String> _wrapperHierarchy(List<Object?> args, int index, String symbol) {
  final table = _tableIfPresent(_valueAt(args, index));
  final hierarchy = table?[_loveFilesystemObjectHierarchyKey];
  if (hierarchy is Set<String>) {
    return hierarchy;
  }
  throw LuaError('$symbol expected LOVE object at argument ${index + 1}');
}

/// Returns the Lua table represented by [value], if any.
Map<dynamic, dynamic>? _tableIfPresent(Object? value) {
  return loveTableIfPresent(value);
}

/// Returns a writable table target for in-place updates, if [value] is a Lua
/// table wrapper.
(Value?, Map<dynamic, dynamic>)? _tableTargetIfPresent(Object? value) {
  return loveTableTargetIfPresent(value);
}

/// Validates a LOVE file mode string.
String _fileMode(String value, String symbol) {
  return switch (value) {
    'c' || 'r' || 'w' || 'a' => value,
    _ => throw LuaError('$symbol invalid file mode "$value"'),
  };
}

/// Validates a LOVE file buffer mode string.
BufferMode _bufferMode(String value, String symbol) {
  return switch (value) {
    'none' => BufferMode.none,
    'line' => BufferMode.line,
    'full' => BufferMode.full,
    _ => throw LuaError('$symbol invalid file buffer mode "$value"'),
  };
}

/// Returns the LOVE string name for [value].
String _bufferModeName(BufferMode value) {
  return switch (value) {
    BufferMode.none => 'none',
    BufferMode.line => 'line',
    BufferMode.full => 'full',
  };
}

/// Validates a filesystem read container type string.
_LoveFilesystemContainerType _containerType(String value, String symbol) {
  return switch (value) {
    'string' => _LoveFilesystemContainerType.string,
    'data' => _LoveFilesystemContainerType.data,
    _ => throw LuaError('$symbol invalid container type "$value"'),
  };
}

/// Validates a filesystem node type string.
LoveFilesystemNodeType _fileType(String value, String symbol) {
  return switch (value) {
    'file' => LoveFilesystemNodeType.file,
    'directory' => LoveFilesystemNodeType.directory,
    'symlink' => LoveFilesystemNodeType.symlink,
    'other' => LoveFilesystemNodeType.other,
    _ => throw LuaError('$symbol invalid file type "$value"'),
  };
}

/// Returns the LOVE string name for filesystem node type [value].
String _fileTypeName(LoveFilesystemNodeType value) {
  return switch (value) {
    LoveFilesystemNodeType.file => 'file',
    LoveFilesystemNodeType.directory => 'directory',
    LoveFilesystemNodeType.symlink => 'symlink',
    LoveFilesystemNodeType.other => 'other',
  };
}
