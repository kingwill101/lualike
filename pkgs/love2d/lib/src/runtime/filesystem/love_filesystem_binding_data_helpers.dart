part of 'love_filesystem_bindings.dart';

/// Returns mounted archive data extracted from [value], if it represents LOVE
/// data that can be mounted.
Future<_LoveFilesystemMountedData?> _mountedDataIfPresent(
  Object? value, {
  required String symbol,
  required int argumentIndex,
  required _LoveFilesystemBindings bindings,
}) async {
  final fileData = _fileDataIfPresent(value);
  if (fileData != null) {
    return _LoveFilesystemMountedData(
      sourceIdentity: fileData,
      bytes: List<int>.from(fileData.bytes),
      archiveName: fileData.filename,
    );
  }

  final table = _tableIfPresent(value);
  if (table == null || !await _isLoveDataWrapper(value, bindings: bindings)) {
    return null;
  }

  return _LoveFilesystemMountedData(
    sourceIdentity: table,
    bytes: await _dataBytes(
      value,
      symbol,
      bindings: bindings,
      argumentIndex: argumentIndex,
    ),
  );
}

/// Returns the identity used to unmount mounted archive data represented by
/// [value], if any.
Future<Object?> _mountedDataIdentityIfPresent(
  Object? value, {
  required _LoveFilesystemBindings bindings,
}) async {
  final fileData = _fileDataIfPresent(value);
  if (fileData != null) {
    return fileData;
  }

  final table = _tableIfPresent(value);
  if (table == null || !await _isLoveDataWrapper(value, bindings: bindings)) {
    return null;
  }

  return table;
}

/// Returns whether [value] behaves like a LOVE `Data` wrapper.
Future<bool> _isLoveDataWrapper(
  Object? value, {
  required _LoveFilesystemBindings bindings,
}) async {
  final table = _tableIfPresent(value);
  if (table == null) {
    return false;
  }

  final hierarchy = table[_loveFilesystemObjectHierarchyKey];
  if (hierarchy is Set<String> && hierarchy.contains('Data')) {
    return true;
  }

  final typeOf = _callableValue(table['typeOf']);
  if (typeOf == null) {
    return false;
  }

  final result = await bindings.runtime.callFunction(
    typeOf,
    <Object?>[value, 'Data'],
    debugName: 'love.data.typeOf',
    debugNameWhat: 'method',
  );
  return _rawValue(result) == true;
}

/// Converts [value] to raw bytes accepted by filesystem bindings.
///
/// Throws a [LuaError] when [value] is not compatible with the expected data
/// input for [symbol].
Future<List<int>> _dataBytes(
  Object? value,
  String symbol, {
  _LoveFilesystemBindings? bindings,
  int argumentIndex = 2,
  String expectedTypeDescription = 'string or Data',
}) async {
  final raw = value is Value ? value.raw : value;
  final bytes = switch (raw) {
    final LuaString stringValue => List<int>.from(stringValue.bytes),
    final String stringValue => List<int>.from(
      LuaString.fromDartString(stringValue).bytes,
    ),
    final num numberValue => List<int>.from(
      LuaString.fromDartString(numberValue.toString()).bytes,
    ),
    final List<int> bytes => List<int>.from(bytes),
    _ when value != null && _fileDataIfPresent(value) != null => List<int>.from(
      _fileDataIfPresent(value)!.bytes,
    ),
    _ => null,
  };

  if (bytes != null) {
    return bytes;
  }

  if (value != null && bindings != null) {
    final table = _tableIfPresent(value);
    final getString = table == null ? null : _callableValue(table['getString']);
    if (getString != null &&
        await _isLoveDataWrapper(value, bindings: bindings)) {
      final result = await bindings.runtime.callFunction(
        getString,
        <Object?>[value],
        debugName: 'love.data.getString',
        debugNameWhat: 'method',
      );
      final stringBytes = _stringBytes(result);
      if (stringBytes != null) {
        return stringBytes;
      }
    }
  }

  throw LuaError(
    '$symbol expected $expectedTypeDescription at argument $argumentIndex',
  );
}

/// Wraps invokable Lua values and Dart callables in a [Value].
Value? _callableValue(Object? value) {
  return switch (value) {
    final Value wrapped => wrapped,
    final BuiltinFunction builtin => Value(builtin),
    final Function function => Value(function),
    _ => null,
  };
}

/// Returns the encoded bytes for string-like Lua values.
List<int>? _stringBytes(Object? value) {
  final raw = value is Value ? value.raw : value;
  return switch (raw) {
    final LuaString stringValue => List<int>.from(stringValue.bytes),
    final String stringValue => List<int>.from(
      LuaString.fromDartString(stringValue).bytes,
    ),
    _ => null,
  };
}

/// Returns at most [size] bytes from [bytes].
List<int> _sliceBytes(List<int> bytes, int? size) {
  if (size == null || size < 0 || size >= bytes.length) {
    return bytes;
  }
  return bytes.sublist(0, math.max(0, size));
}

/// Creates a Lua array table from [values].
Value _arrayTable(List<String> values) {
  return Value(<Object?, Object?>{
    for (var index = 0; index < values.length; index++)
      index + 1: values[index],
  });
}

/// Returns a standard LOVE-style `(nil, error)` result.
Value _ioError(String message) {
  return Value.multi(<Object?>[null, message]);
}
