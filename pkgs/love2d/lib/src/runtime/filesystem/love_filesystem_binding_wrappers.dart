part of 'love_filesystem_bindings.dart';

final class _RuntimeFilesystemBuiltin extends BuiltinFunction {
  _RuntimeFilesystemBuiltin(this._implementation);

  final FutureOr<Object?> Function(List<Object?> args) _implementation;

  @override
  FutureOr<Object?> call(List<Object?> args) => _implementation(args);
}

/// Wraps a dropped file for runtime-dispatched filesystem callbacks.
Future<Value> wrapLoveFilesystemDroppedFileForRuntime(
  LuaRuntime runtime,
  LoveFilesystemDroppedFile file,
) async {
  LoveFilesystemState.attach(runtime).allowMountingForPath(file.physicalPath);

  final cached = _loveFilesystemDroppedFileWrapperCache[file];
  if (cached != null) {
    return cached;
  }

  final filesystemTable = _filesystemModuleTable(runtime);
  final newFileEntry = filesystemTable?['newFile'];
  final newFile = switch (newFileEntry) {
    final Value value when value.raw is BuiltinFunction =>
      value.raw as BuiltinFunction,
    final BuiltinFunction function => function,
    _ => null,
  };
  if (newFile == null) {
    throw StateError('love.filesystem.newFile is not installed');
  }

  final result = newFile.call(<Object?>[file.filename]);
  final resolved = result is Future<Object?> ? await result : result;
  final wrapper = switch (resolved) {
    final Value value when value.isMulti =>
      ((value.raw as List<Object?>).isNotEmpty
          ? (value.raw as List<Object?>).first
          : null),
    _ => resolved,
  };
  final wrapperTable = _tableIfPresent(wrapper);
  if (wrapperTable == null) {
    throw StateError('love.filesystem.newFile did not return a File wrapper');
  }

  final droppedWrapper = ValueClass.table(<Object?, Object?>{
    ...wrapperTable,
    _loveFilesystemFileObjectKey: file,
    _loveFilesystemObjectTypeKey: 'DroppedFile',
    _loveFilesystemObjectHierarchyKey: const <String>{
      'DroppedFile',
      'File',
      'Object',
    },
    'release': Value(
      _RuntimeFilesystemBuiltin((args) async {
        final rawObject = _wrapperObject(args, 0, 'Object:release');
        if (_loveFilesystemReleased[rawObject] == true) {
          return false;
        }

        _loveFilesystemReleased[rawObject] = true;
        if (rawObject is LoveFilesystemFile && rawObject.isOpen) {
          await rawObject.close();
        }
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      _RuntimeFilesystemBuiltin(
        (args) => _wrapperTypeName(args, 0, 'Object:type'),
      ),
      functionName: 'type',
    ),
    'typeOf': Value(
      _RuntimeFilesystemBuiltin((args) {
        final hierarchy = _wrapperHierarchy(args, 0, 'Object:typeOf');
        final typeName = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(typeName);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveFilesystemDroppedFileWrapperCache[file] = droppedWrapper;
  return droppedWrapper;
}

/// Builds Lua wrapper tables for filesystem objects exposed by the bindings.
extension _LoveFilesystemBindingWrappers on _LoveFilesystemBindings {
  /// Wraps [file] as either a `File` or `DroppedFile` Lua object table.
  Value wrapFile(LoveFilesystemFile file) {
    if (file is LoveFilesystemDroppedFile) {
      return wrapDroppedFile(file);
    }

    final cached = _loveFilesystemFileWrapperCache[file];
    if (cached != null) {
      return cached;
    }

    final table = ValueClass.table(<Object?, Object?>{
      _loveFilesystemFileObjectKey: file,
      _loveFilesystemObjectTypeKey: 'File',
      _loveFilesystemObjectHierarchyKey: const <String>{'File', 'Object'},
      'close': bindSymbol('File:close', 'close'),
      'flush': bindSymbol('File:flush', 'flush'),
      'getBuffer': bindSymbol('File:getBuffer', 'getBuffer'),
      'getExtension': bindSymbol('File:getExtension', 'getExtension'),
      'getFilename': bindSymbol('File:getFilename', 'getFilename'),
      'getMode': bindSymbol('File:getMode', 'getMode'),
      'getSize': bindSymbol('File:getSize', 'getSize'),
      'isEOF': bindSymbol('File:isEOF', 'isEOF'),
      'isOpen': bindSymbol('File:isOpen', 'isOpen'),
      'lines': bindSymbol('File:lines', 'lines'),
      'open': bindSymbol('File:open', 'open'),
      'read': bindSymbol('File:read', 'read'),
      'release': Value(
        _builder.create((args) async {
          final receiver = _valueAt(args, 0);
          final file = _fileIfPresent(receiver);
          if (file == null) {
            _throwFilesystemLuaTypeError(
              symbol: 'Object:release',
              index: 0,
              expected: 'File',
              actual: receiver,
            );
          }
          if (_loveFilesystemReleased[file] == true) {
            return false;
          }

          _loveFilesystemReleased[file] = true;
          if (file.isOpen) {
            await file.close();
          }
          return true;
        }),
        functionName: 'release',
      ),
      'seek': bindSymbol('File:seek', 'seek'),
      'setBuffer': bindSymbol('File:setBuffer', 'setBuffer'),
      'tell': bindSymbol('File:tell', 'tell'),
      'type': Value(
        _builder.create((args) {
          final receiver = _valueAt(args, 0);
          if (_fileIfPresent(receiver) == null) {
            _throwFilesystemLuaTypeError(
              symbol: 'Object:type',
              index: 0,
              expected: 'File',
              actual: receiver,
            );
          }
          return 'File';
        }),
        functionName: 'type',
      ),
      'typeOf': Value(
        _builder.create((args) {
          final receiver = _valueAt(args, 0);
          if (_fileIfPresent(receiver) == null) {
            _throwFilesystemLuaTypeError(
              symbol: 'Object:typeOf',
              index: 0,
              expected: 'File',
              actual: receiver,
            );
          }
          final typeName = _requireString(args, 1, 'Object:typeOf');
          return const <String>{'File', 'Object'}.contains(typeName);
        }),
        functionName: 'typeOf',
      ),
      'write': bindSymbol('File:write', 'write'),
    });
    _loveFilesystemFileWrapperCache[file] = table;
    return table;
  }

  /// Wraps [file] as a Lua-facing `DroppedFile` object table.
  Value wrapDroppedFile(LoveFilesystemDroppedFile file) {
    state.allowMountingForPath(file.physicalPath);

    final cached = _loveFilesystemDroppedFileWrapperCache[file];
    if (cached != null) {
      return cached;
    }

    final table = ValueClass.table(<Object?, Object?>{
      _loveFilesystemFileObjectKey: file,
      _loveFilesystemObjectTypeKey: 'DroppedFile',
      _loveFilesystemObjectHierarchyKey: const <String>{
        'DroppedFile',
        'File',
        'Object',
      },
      'close': bindSymbol('File:close', 'close'),
      'flush': bindSymbol('File:flush', 'flush'),
      'getBuffer': bindSymbol('File:getBuffer', 'getBuffer'),
      'getExtension': bindSymbol('File:getExtension', 'getExtension'),
      'getFilename': bindSymbol('File:getFilename', 'getFilename'),
      'getMode': bindSymbol('File:getMode', 'getMode'),
      'getSize': bindSymbol('File:getSize', 'getSize'),
      'isEOF': bindSymbol('File:isEOF', 'isEOF'),
      'isOpen': bindSymbol('File:isOpen', 'isOpen'),
      'lines': bindSymbol('File:lines', 'lines'),
      'open': bindSymbol('File:open', 'open'),
      'read': bindSymbol('File:read', 'read'),
      'release': bindSymbol('Object:release', 'release'),
      'seek': bindSymbol('File:seek', 'seek'),
      'setBuffer': bindSymbol('File:setBuffer', 'setBuffer'),
      'tell': bindSymbol('File:tell', 'tell'),
      'type': bindSymbol('Object:type', 'type'),
      'typeOf': bindSymbol('Object:typeOf', 'typeOf'),
      'write': bindSymbol('File:write', 'write'),
    });
    _loveFilesystemDroppedFileWrapperCache[file] = table;
    return table;
  }

  /// Wraps [data] as a Lua-facing `FileData` object table.
  Value wrapFileData(LoveFilesystemFileData data) {
    final cached = _loveFilesystemFileDataWrapperCache[data];
    if (cached != null) {
      return cached;
    }

    final table = ValueClass.table(<Object?, Object?>{
      _loveFilesystemFileDataObjectKey: data,
      _loveFilesystemObjectTypeKey: 'FileData',
      _loveFilesystemObjectHierarchyKey: const <String>{
        'FileData',
        'Data',
        'Object',
      },
      'clone': bindSymbol('FileData:clone', 'clone'),
      'getExtension': bindSymbol('FileData:getExtension', 'getExtension'),
      'getFilename': bindSymbol('FileData:getFilename', 'getFilename'),
      'getPointer': Value(
        _builder.create((args) {
          final data = _requireFileData(args, 0, 'Data:getPointer');
          return _wrapDataPointer(data);
        }),
        functionName: 'getPointer',
      ),
      'getFFIPointer': Value(
        _builder.create((args) {
          final data = _requireFileData(args, 0, 'Data:getFFIPointer');
          return _wrapDataPointer(data);
        }),
        functionName: 'getFFIPointer',
      ),
      'getSize': bindSymbol('Data:getSize', 'getSize'),
      'getString': bindSymbol('Data:getString', 'getString'),
      'release': Value(
        _builder.create((args) {
          final receiver = _valueAt(args, 0);
          final fileData = _fileDataIfPresent(receiver);
          if (fileData == null) {
            _throwFilesystemLuaTypeError(
              symbol: 'Object:release',
              index: 0,
              expected: 'FileData',
              actual: receiver,
            );
          }
          if (_loveFilesystemReleased[fileData] == true) {
            return false;
          }
          _loveFilesystemReleased[fileData] = true;
          return true;
        }),
        functionName: 'release',
      ),
      'type': Value(
        _builder.create((args) {
          final receiver = _valueAt(args, 0);
          if (_fileDataIfPresent(receiver) == null) {
            _throwFilesystemLuaTypeError(
              symbol: 'Object:type',
              index: 0,
              expected: 'FileData',
              actual: receiver,
            );
          }
          return 'FileData';
        }),
        functionName: 'type',
      ),
      'typeOf': Value(
        _builder.create((args) {
          final receiver = _valueAt(args, 0);
          if (_fileDataIfPresent(receiver) == null) {
            _throwFilesystemLuaTypeError(
              symbol: 'Object:typeOf',
              index: 0,
              expected: 'FileData',
              actual: receiver,
            );
          }
          final typeName = _requireString(args, 1, 'Object:typeOf');
          return const <String>{
            'FileData',
            'Data',
            'Object',
          }.contains(typeName);
        }),
        functionName: 'typeOf',
      ),
    });
    _loveFilesystemFileDataWrapperCache[data] = table;
    return table;
  }

  /// Wraps [data] as a transient `Data` pointer object.
  Value _wrapDataPointer(LoveFilesystemFileData data) {
    final cached = _loveFilesystemDataPointerCache[data];
    if (cached != null) {
      return cached;
    }

    final pointer = Value(
      Box<LoveDataPointer>(
        LoveDataPointer(identity: data, bytes: data.bytes),
        isTransient: true,
        interpreter: runtime,
      ),
    );
    _loveFilesystemDataPointerCache[data] = pointer;
    return pointer;
  }

  /// Returns the Lua result tuple for bytes read from a filesystem object.
  Object? _readResult(
    List<int> bytes, {
    required String filename,
    required _LoveFilesystemContainerType containerType,
  }) {
    final data = switch (containerType) {
      _LoveFilesystemContainerType.data => wrapFileData(
        LoveFilesystemFileData(bytes: bytes, filename: filename),
      ),
      _LoveFilesystemContainerType.string => runtime.constantStringValue(bytes),
    };
    return Value.multi(<Object?>[data, bytes.length]);
  }
}
