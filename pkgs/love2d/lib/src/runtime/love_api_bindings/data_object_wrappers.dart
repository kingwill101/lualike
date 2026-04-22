part of '../love_api_bindings.dart';

/// Reuses transient pointer wrappers for the same backing data identity.
final Expando<Value> _loveDataPointerCache = Expando<Value>(
  'love2dDataPointer',
);

T _requireLoveDataSubtype<T extends Object>(
  List<Object?> args,
  int index,
  String symbol, {
  required String expected,
  required T? Function(Object? value) resolver,
}) {
  final value = _valueAt(args, index);
  final data = resolver(value);
  if (data != null) {
    if (_loveDataReleased[data] == true) {
      _throwReleasedObjectError();
    }
    return data;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: expected,
    actual: value,
  );
}

Object? _dataWrapperObjectByKey(Object? value, String objectKey) {
  final table = _tableIdentityIfPresent(value);
  return table?[objectKey];
}

/// Wraps [data] as a Lua-facing `ByteData` object table.
Value _wrapByteData(LibraryRegistrationContext context, LoveByteData data) {
  final cached = _loveByteDataWrapperCache[data];
  if (cached != null) {
    return cached;
  }

  final table = _wrapLoveDataObject(
    context,
    rawObject: data,
    objectKey: _loveByteDataObjectKey,
    typeName: 'ByteData',
    hierarchy: const <String>{'ByteData', 'Data', 'Object'},
    clone: (args) =>
        _wrapByteData(context, _requireByteData(args, 0, 'Data:clone').clone()),
  );
  _loveByteDataWrapperCache[data] = table;
  return table;
}

/// Wraps [data] as a Lua-facing `DataView` object table.
Value _wrapDataView(LibraryRegistrationContext context, LoveDataView data) {
  final cached = _loveDataViewWrapperCache[data];
  if (cached != null) {
    return cached;
  }

  final table = _wrapLoveDataObject(
    context,
    rawObject: data,
    objectKey: _loveDataViewObjectKey,
    typeName: 'DataView',
    hierarchy: const <String>{'DataView', 'Data', 'Object'},
    clone: (args) =>
        _wrapDataView(context, _requireDataView(args, 0, 'Data:clone').clone()),
  );
  _loveDataViewWrapperCache[data] = table;
  return table;
}

/// Wraps [data] as a Lua-facing `CompressedData` object table.
Value _wrapCompressedData(
  LibraryRegistrationContext context,
  LoveCompressedData data,
) {
  final cached = _loveCompressedDataWrapperCache[data];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = _wrapLoveDataObject(
    context,
    rawObject: data,
    objectKey: _loveCompressedDataObjectKey,
    typeName: 'CompressedData',
    hierarchy: const <String>{'CompressedData', 'Data', 'Object'},
    clone: (args) => _wrapCompressedData(
      context,
      _requireCompressedData(args, 0, 'Data:clone').clone(),
    ),
    extraEntries: <Object?, Object?>{
      'getFormat': Value(
        builder.create(
          (args) => _compressedDataFormatName(
            _requireCompressedData(args, 0, 'CompressedData:getFormat').format,
          ),
        ),
        functionName: 'getFormat',
      ),
    },
  );
  _loveCompressedDataWrapperCache[data] = table;
  return table;
}

/// Builds the common Lua object table used by LÖVE `Data` subtypes.
Value _wrapLoveDataObject(
  LibraryRegistrationContext context, {
  required Object rawObject,
  required String objectKey,
  required String typeName,
  required Set<String> hierarchy,
  required Object? Function(List<Object?> args) clone,
  Map<Object?, Object?> extraEntries = const <Object?, Object?>{},
}) {
  final builder = BuiltinFunctionBuilder(context);
  final pointerGetter = builder.create(
    (args) => _wrapDataPointer(
      context,
      identity: _requireLoveDataObject(args, 0, 'Data:getPointer'),
      bytes: _requireLoveDataObject(args, 0, 'Data:getPointer').bytes,
    ),
  );
  return ValueClass.table(<Object?, Object?>{
    objectKey: rawObject,
    'clone': Value(builder.create(clone), functionName: 'clone'),
    'getPointer': Value(pointerGetter, functionName: 'getPointer'),
    'getFFIPointer': Value(pointerGetter, functionName: 'getFFIPointer'),
    'getSize': Value(
      builder.create(
        (args) => _requireLoveDataObject(args, 0, 'Data:getSize').size,
      ),
      functionName: 'getSize',
    ),
    'getString': Value(
      builder.create((args) {
        final interpreter = context.interpreter;
        if (interpreter == null) {
          throw StateError('No Lua runtime available for Data:getString');
        }

        return interpreter.constantStringValue(
          _requireLoveDataObject(args, 0, 'Data:getString').bytes,
        );
      }),
      functionName: 'getString',
    ),
    'release': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        final object = _dataWrapperObjectByKey(receiver, objectKey);
        if (object == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: typeName,
            actual: receiver,
          );
        }
        if (_loveDataReleased[object] == true) {
          return false;
        }

        _loveDataReleased[object] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_dataWrapperObjectByKey(receiver, objectKey) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: typeName,
            actual: receiver,
          );
        }
        return typeName;
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_dataWrapperObjectByKey(receiver, objectKey) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: typeName,
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
    ...extraEntries,
  });
}

/// Wraps a transient pointer view for a `Data` object.
Value _wrapDataPointer(
  LibraryContext context, {
  required Object identity,
  required List<int> bytes,
}) {
  final cached = _loveDataPointerCache[identity];
  if (cached != null) {
    return cached;
  }

  final pointer = Value(
    Box<LoveDataPointer>(
      LoveDataPointer(identity: identity, bytes: bytes),
      isTransient: true,
      interpreter: context.interpreter,
    ),
  );
  _loveDataPointerCache[identity] = pointer;
  return pointer;
}

/// Returns a transient [LoveDataPointer] when [value] wraps one.
LoveDataPointer? _dataPointerIfPresent(Object? value) {
  final raw = _rawValue(value);
  if (raw is Box<dynamic> && raw.value is LoveDataPointer) {
    return raw.value as LoveDataPointer;
  }

  return null;
}

/// Returns wrapped [LoveByteData] when [value] is a ByteData table.
LoveByteData? _byteDataIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveByteDataObjectKey];
  return data is LoveByteData ? data : null;
}

/// Returns wrapped [LoveDataView] when [value] is a DataView table.
LoveDataView? _dataViewIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveDataViewObjectKey];
  return data is LoveDataView ? data : null;
}

/// Returns wrapped [LoveCompressedData] when [value] is a CompressedData table.
LoveCompressedData? _compressedDataIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveCompressedDataObjectKey];
  return data is LoveCompressedData ? data : null;
}

/// Returns compatibility `FileData` produced by filesystem bridge wrappers.
LoveFilesystemFileData? _filesystemFileDataCompatIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveFilesystemFileDataObjectKeyCompat];
  return data is LoveFilesystemFileData ? data : null;
}

/// Returns any wrapped LÖVE `Data` subtype stored in [value].
LoveDataObject? _loveDataObjectIfPresent(Object? value) {
  return _byteDataIfPresent(value) ??
      _dataViewIfPresent(value) ??
      _glyphDataIfPresent(value) ??
      _soundDataIfPresent(value) ??
      _compressedDataIfPresent(value);
}

/// Returns a required `Data` receiver.
LoveDataObject _requireLoveDataObject(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requireLoveDataSubtype(
    args,
    index,
    symbol,
    expected: 'Data',
    resolver: _loveDataObjectIfPresent,
  );
}

/// Returns a required `ByteData` receiver.
LoveByteData _requireByteData(List<Object?> args, int index, String symbol) {
  return _requireLoveDataSubtype(
    args,
    index,
    symbol,
    expected: 'ByteData',
    resolver: _byteDataIfPresent,
  );
}

/// Returns a required `DataView` receiver.
LoveDataView _requireDataView(List<Object?> args, int index, String symbol) {
  return _requireLoveDataSubtype(
    args,
    index,
    symbol,
    expected: 'DataView',
    resolver: _dataViewIfPresent,
  );
}

/// Returns a required `CompressedData` receiver.
LoveCompressedData _requireCompressedData(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requireLoveDataSubtype(
    args,
    index,
    symbol,
    expected: 'CompressedData',
    resolver: _compressedDataIfPresent,
  );
}
