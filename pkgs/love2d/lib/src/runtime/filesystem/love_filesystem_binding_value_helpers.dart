part of 'love_filesystem_bindings.dart';

Object? _valueAt(List<Object?> args, int index) {
  return index < args.length ? args[index] : null;
}

Object? _rawValue(Object? value) {
  if (value is Value) {
    return value.unwrap();
  }
  if (value is LuaString) {
    return value.toString();
  }
  return value;
}

String? _luaStringLike(Object? value) {
  final raw = value is Value ? value.raw : value;
  return switch (raw) {
    final String stringValue => stringValue,
    final LuaString stringValue => stringValue.toString(),
    final num numberValue => numberValue.toString(),
    _ => null,
  };
}

String? _exactStringLike(Object? value) {
  final raw = value is Value ? value.raw : value;
  return switch (raw) {
    final String stringValue => stringValue,
    final LuaString stringValue => stringValue.toString(),
    _ => null,
  };
}

String _requireString(List<Object?> args, int index, String symbol) {
  final value = _luaStringLike(_valueAt(args, index));
  if (value != null) {
    return value;
  }

  throw LuaError('$symbol expected a string at argument ${index + 1}');
}

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

double _numberValue(List<Object?> args, int index, String symbol) {
  final raw = _rawValue(_valueAt(args, index));
  try {
    return NumberUtils.toDouble(raw);
  } catch (_) {
    throw LuaError('$symbol expected a number at argument ${index + 1}');
  }
}

int _clampLuaFilesystemNumber(int value) {
  return value > _loveFilesystemLuaNumberLimit
      ? _loveFilesystemLuaNumberLimit
      : value;
}

bool _hasKnownFilesystemNumber(int? value) => value != null && value >= 0;

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

bool _requireBoolean(List<Object?> args, int index, String symbol) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw is bool) {
    return raw;
  }

  throw LuaError('$symbol expected a boolean at argument ${index + 1}');
}

LoveFilesystemFile _requireFile(List<Object?> args, int index, String symbol) {
  final raw = _wrapperObject(args, index, symbol);
  if (raw is LoveFilesystemFile) {
    return raw;
  }

  throw LuaError('$symbol expected File at argument ${index + 1}');
}

LoveFilesystemFileData _requireFileData(
  List<Object?> args,
  int index,
  String symbol,
) {
  final raw = _wrapperObject(args, index, symbol);
  if (raw is LoveFilesystemFileData) {
    return raw;
  }

  throw LuaError('$symbol expected FileData at argument ${index + 1}');
}

LoveFilesystemFile? _fileIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  final raw = table?[_loveFilesystemFileObjectKey];
  return raw is LoveFilesystemFile ? raw : null;
}

LoveFilesystemDroppedFile? _droppedFileIfPresent(Object? value) {
  final file = _fileIfPresent(value);
  return file is LoveFilesystemDroppedFile ? file : null;
}

LoveFilesystemFileData? _fileDataIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  final raw = table?[_loveFilesystemFileDataObjectKey];
  return raw is LoveFilesystemFileData ? raw : null;
}

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

String _wrapperTypeName(List<Object?> args, int index, String symbol) {
  final table = _tableIfPresent(_valueAt(args, index));
  final typeName = table?[_loveFilesystemObjectTypeKey];
  if (typeName is String) {
    return typeName;
  }
  throw LuaError('$symbol expected LOVE object at argument ${index + 1}');
}

Set<String> _wrapperHierarchy(List<Object?> args, int index, String symbol) {
  final table = _tableIfPresent(_valueAt(args, index));
  final hierarchy = table?[_loveFilesystemObjectHierarchyKey];
  if (hierarchy is Set<String>) {
    return hierarchy;
  }
  throw LuaError('$symbol expected LOVE object at argument ${index + 1}');
}

Map<dynamic, dynamic>? _tableIfPresent(Object? value) {
  if (value case final Value wrapped when wrapped.raw is Map) {
    return wrapped.raw as Map<dynamic, dynamic>;
  }
  if (value is Map<dynamic, dynamic>) {
    return value;
  }
  return null;
}

Map<dynamic, dynamic>? _filesystemModuleTable(LuaRuntime runtime) {
  final loveTable = _tableIfPresent(runtime.getCurrentEnv().get('love'));
  return _tableIfPresent(loveTable?['filesystem']);
}

(Value?, Map<dynamic, dynamic>)? _tableTargetIfPresent(Object? value) {
  if (value case final Value wrapped when wrapped.raw is Map) {
    return (wrapped, wrapped.raw as Map<dynamic, dynamic>);
  }
  if (value is Map<dynamic, dynamic>) {
    return (null, value);
  }
  return null;
}

String _fileMode(String value, String symbol) {
  return switch (value) {
    'c' || 'r' || 'w' || 'a' => value,
    _ => throw LuaError('$symbol invalid file mode "$value"'),
  };
}

BufferMode _bufferMode(String value, String symbol) {
  return switch (value) {
    'none' => BufferMode.none,
    'line' => BufferMode.line,
    'full' => BufferMode.full,
    _ => throw LuaError('$symbol invalid file buffer mode "$value"'),
  };
}

String _bufferModeName(BufferMode value) {
  return switch (value) {
    BufferMode.none => 'none',
    BufferMode.line => 'line',
    BufferMode.full => 'full',
  };
}

_LoveFilesystemContainerType _containerType(String value, String symbol) {
  return switch (value) {
    'string' => _LoveFilesystemContainerType.string,
    'data' => _LoveFilesystemContainerType.data,
    _ => throw LuaError('$symbol invalid container type "$value"'),
  };
}

LoveFilesystemNodeType _fileType(String value, String symbol) {
  return switch (value) {
    'file' => LoveFilesystemNodeType.file,
    'directory' => LoveFilesystemNodeType.directory,
    'symlink' => LoveFilesystemNodeType.symlink,
    'other' => LoveFilesystemNodeType.other,
    _ => throw LuaError('$symbol invalid file type "$value"'),
  };
}

String _fileTypeName(LoveFilesystemNodeType value) {
  return switch (value) {
    LoveFilesystemNodeType.file => 'file',
    LoveFilesystemNodeType.directory => 'directory',
    LoveFilesystemNodeType.symlink => 'symlink',
    LoveFilesystemNodeType.other => 'other',
  };
}
