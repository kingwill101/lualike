part of 'love_filesystem_bindings.dart';

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
  });
  _loveFilesystemDroppedFileWrapperCache[file] = droppedWrapper;
  return droppedWrapper;
}

extension _LoveFilesystemBindingWrappers on _LoveFilesystemBindings {
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
      'release': bindSymbol('Object:release', 'release'),
      'seek': bindSymbol('File:seek', 'seek'),
      'setBuffer': bindSymbol('File:setBuffer', 'setBuffer'),
      'tell': bindSymbol('File:tell', 'tell'),
      'type': bindSymbol('Object:type', 'type'),
      'typeOf': bindSymbol('Object:typeOf', 'typeOf'),
      'write': bindSymbol('File:write', 'write'),
    });
    _loveFilesystemFileWrapperCache[file] = table;
    return table;
  }

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
      'release': bindSymbol('Object:release', 'release'),
      'type': bindSymbol('Object:type', 'type'),
      'typeOf': bindSymbol('Object:typeOf', 'typeOf'),
    });
    _loveFilesystemFileDataWrapperCache[data] = table;
    return table;
  }

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
