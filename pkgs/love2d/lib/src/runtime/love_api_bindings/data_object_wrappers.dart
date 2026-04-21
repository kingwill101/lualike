part of '../love_api_bindings.dart';

final Expando<Value> _loveDataPointerCache = Expando<Value>(
  'love2dDataPointer',
);

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
        final object = _loveDataObjectIdentity(
          _valueAt(args, 0),
          symbol: 'Object:release',
        );
        if (_loveDataReleased[object] == true) {
          return false;
        }

        _loveDataReleased[object] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(builder.create((args) => typeName), functionName: 'type'),
    'typeOf': Value(
      builder.create((args) {
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
    ...extraEntries,
  });
}

Value _wrapDataPointer(
  LibraryRegistrationContext context, {
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

LoveDataPointer? _dataPointerIfPresent(Object? value) {
  final raw = _rawValue(value);
  if (raw is Box<dynamic> && raw.value is LoveDataPointer) {
    return raw.value as LoveDataPointer;
  }

  return null;
}

LoveByteData? _byteDataIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveByteDataObjectKey];
  return data is LoveByteData ? data : null;
}

LoveDataView? _dataViewIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveDataViewObjectKey];
  return data is LoveDataView ? data : null;
}

LoveCompressedData? _compressedDataIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveCompressedDataObjectKey];
  return data is LoveCompressedData ? data : null;
}

LoveFilesystemFileData? _filesystemFileDataCompatIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveFilesystemFileDataObjectKeyCompat];
  return data is LoveFilesystemFileData ? data : null;
}

LoveDataObject? _loveDataObjectIfPresent(Object? value) {
  return _byteDataIfPresent(value) ??
      _dataViewIfPresent(value) ??
      _glyphDataIfPresent(value) ??
      _soundDataIfPresent(value) ??
      _compressedDataIfPresent(value);
}

Object _loveDataObjectIdentity(Object? value, {required String symbol}) {
  final data = _loveDataObjectIfPresent(value);
  if (data != null) {
    return data;
  }

  final compat = _filesystemFileDataCompatIfPresent(value);
  if (compat != null) {
    return compat;
  }

  throw LuaError('$symbol expected a LOVE Object at argument 1');
}

LoveDataObject _requireLoveDataObject(
  List<Object?> args,
  int index,
  String symbol,
) {
  final data = _loveDataObjectIfPresent(_valueAt(args, index));
  if (data != null) {
    return data;
  }

  throw LuaError('$symbol expected a Data at argument ${index + 1}');
}

LoveByteData _requireByteData(List<Object?> args, int index, String symbol) {
  final data = _byteDataIfPresent(_valueAt(args, index));
  if (data != null) {
    return data;
  }

  throw LuaError('$symbol expected a ByteData at argument ${index + 1}');
}

LoveDataView _requireDataView(List<Object?> args, int index, String symbol) {
  final data = _dataViewIfPresent(_valueAt(args, index));
  if (data != null) {
    return data;
  }

  throw LuaError('$symbol expected a DataView at argument ${index + 1}');
}

LoveCompressedData _requireCompressedData(
  List<Object?> args,
  int index,
  String symbol,
) {
  final data = _compressedDataIfPresent(_valueAt(args, index));
  if (data != null) {
    return data;
  }

  throw LuaError('$symbol expected a CompressedData at argument ${index + 1}');
}
