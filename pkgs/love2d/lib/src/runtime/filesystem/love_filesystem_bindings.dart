library;

import 'dart:math' as math;

import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart'
    show
        Box,
        BuiltinFunction,
        LuaChunkLoadRequest,
        LuaError,
        NumberUtils,
        LuaRuntime,
        LuaString,
        Value;
import 'package:lualike/src/io/io_device.dart' show BufferMode;

import '../../love_api_support.dart';
import '../love_runtime.dart' show LoveDataPointer;
import 'love_filesystem_package_loader.dart';
import 'love_filesystem_runtime.dart';

bool _filesystemBindingsLoaded = false;

const String _loveFilesystemFileObjectKey = '__love2d_filesystem_file__';
const String _loveFilesystemFileDataObjectKey =
    '__love2d_filesystem_filedata__';
const String _loveFilesystemObjectTypeKey = '__love2d_filesystem_type__';
const String _loveFilesystemObjectHierarchyKey =
    '__love2d_filesystem_hierarchy__';
const int _loveFilesystemLuaNumberLimit = 0x20000000000000;
const double _loveFilesystemLuaNumberLimitDouble = 9007199254740992.0;

final Expando<Value> _loveFilesystemFileWrapperCache = Expando<Value>(
  'love2dFilesystemFileWrapper',
);
final Expando<Value> _loveFilesystemDroppedFileWrapperCache = Expando<Value>(
  'love2dFilesystemDroppedFileWrapper',
);
final Expando<Value> _loveFilesystemFileDataWrapperCache = Expando<Value>(
  'love2dFilesystemFileDataWrapper',
);
final Expando<Value> _loveFilesystemDataPointerCache = Expando<Value>(
  'love2dFilesystemDataPointer',
);
final Expando<bool> _loveFilesystemReleased = Expando<bool>(
  'love2dFilesystemReleased',
);

enum _LoveFilesystemContainerType { string, data }

class _LoveFilesystemMountedData {
  const _LoveFilesystemMountedData({
    required this.sourceIdentity,
    required this.bytes,
    this.archiveName,
  });

  final Object sourceIdentity;
  final List<int> bytes;
  final String? archiveName;
}

void ensureLoveFilesystemRuntimeBindingsLoaded() {
  if (_filesystemBindingsLoaded) {
    return;
  }

  _filesystemBindingsLoaded = true;
  loveApiBindingFactories.addAll(<String, LoveApiBindingFactory>{
    'love.filesystem.append': _bindFilesystemAppend,
    'love.filesystem.areSymlinksEnabled': _bindFilesystemAreSymlinksEnabled,
    'love.filesystem.createDirectory': _bindFilesystemCreateDirectory,
    'love.filesystem.getAppdataDirectory': _bindFilesystemGetAppdataDirectory,
    'love.filesystem.getCRequirePath': _bindFilesystemGetCRequirePath,
    'love.filesystem.getDirectoryItems': _bindFilesystemGetDirectoryItems,
    'love.filesystem.getIdentity': _bindFilesystemGetIdentity,
    'love.filesystem.getInfo': _bindFilesystemGetInfo,
    'love.filesystem.getRealDirectory': _bindFilesystemGetRealDirectory,
    'love.filesystem.getRequirePath': _bindFilesystemGetRequirePath,
    'love.filesystem.getSaveDirectory': _bindFilesystemGetSaveDirectory,
    'love.filesystem.getSource': _bindFilesystemGetSource,
    'love.filesystem.getSourceBaseDirectory':
        _bindFilesystemGetSourceBaseDirectory,
    'love.filesystem.getUserDirectory': _bindFilesystemGetUserDirectory,
    'love.filesystem.getWorkingDirectory': _bindFilesystemGetWorkingDirectory,
    'love.filesystem.init': _bindFilesystemInit,
    'love.filesystem.isFused': _bindFilesystemIsFused,
    'love.filesystem.lines': _bindFilesystemLines,
    'love.filesystem.load': _bindFilesystemLoad,
    'love.filesystem.mount': _bindFilesystemMount,
    'love.filesystem.newFile': _bindFilesystemNewFile,
    'love.filesystem.newFileData': _bindFilesystemNewFileData,
    'love.filesystem.read': _bindFilesystemRead,
    'love.filesystem.remove': _bindFilesystemRemove,
    'love.filesystem.setCRequirePath': _bindFilesystemSetCRequirePath,
    'love.filesystem.setIdentity': _bindFilesystemSetIdentity,
    'love.filesystem.setRequirePath': _bindFilesystemSetRequirePath,
    'love.filesystem.setSource': _bindFilesystemSetSource,
    'love.filesystem.setSymlinksEnabled': _bindFilesystemSetSymlinksEnabled,
    'love.filesystem.unmount': _bindFilesystemUnmount,
    'love.filesystem.write': _bindFilesystemWrite,
    'File:close': _bindFileClose,
    'File:flush': _bindFileFlush,
    'File:getBuffer': _bindFileGetBuffer,
    'File:getExtension': _bindFileGetExtension,
    'File:getFilename': _bindFileGetFilename,
    'File:getMode': _bindFileGetMode,
    'File:getSize': _bindFileGetSize,
    'File:isEOF': _bindFileIsEOF,
    'File:isOpen': _bindFileIsOpen,
    'File:lines': _bindFileLines,
    'File:open': _bindFileOpen,
    'File:read': _bindFileRead,
    'File:seek': _bindFileSeek,
    'File:setBuffer': _bindFileSetBuffer,
    'File:tell': _bindFileTell,
    'File:write': _bindFileWrite,
    'FileData:clone': _bindFileDataClone,
    'FileData:getExtension': _bindFileDataGetExtension,
    'FileData:getFilename': _bindFileDataGetFilename,
    'Data:getSize': _bindDataGetSize,
    'Data:getString': _bindDataGetString,
    'Object:release': _bindObjectRelease,
    'Object:type': _bindObjectType,
    'Object:typeOf': _bindObjectTypeOf,
  });
}

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

class _LoveFilesystemBindings {
  _LoveFilesystemBindings(this.context)
    : _builder = BuiltinFunctionBuilder(context);

  final LibraryRegistrationContext context;
  final BuiltinFunctionBuilder _builder;

  LuaRuntime get runtime {
    final interpreter = context.interpreter;
    if (interpreter == null) {
      throw StateError('No Lua runtime available for LOVE filesystem');
    }
    return interpreter;
  }

  LoveFilesystemState get state => LoveFilesystemState.attach(runtime);

  Value bindSymbol(String symbol, String publicName) {
    return bindLoveApiFunction(
      context,
      symbol: symbol,
      publicName: publicName,
      implementations: const <String, LoveApiImplementation>{},
    );
  }

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

  LoveApiImplementation append() {
    return (args) async {
      final filename = _requireString(args, 0, 'love.filesystem.append');
      final explicitSize = _optionalTruncatedInt(args, 2);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid write size.');
      }
      final bytes = _sliceBytes(
        await _dataBytes(
          _valueAt(args, 1),
          'love.filesystem.append',
          bindings: this,
          argumentIndex: 2,
        ),
        explicitSize,
      );
      try {
        await state.writeBytesOrThrow(filename, bytes, append: true);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
      return true;
    };
  }

  LoveApiImplementation areSymlinksEnabled() {
    return (args) => state.symlinksEnabled;
  }

  LoveApiImplementation createDirectory() {
    return (args) async {
      final path = _requireString(args, 0, 'love.filesystem.createDirectory');
      return state.createDirectory(path);
    };
  }

  LoveApiImplementation getAppdataDirectory() {
    return (args) => state.getAppdataDirectory();
  }

  LoveApiImplementation getCRequirePath() {
    return (args) => state.getCRequirePathString();
  }

  LoveApiImplementation getDirectoryItems() {
    return (args) async {
      final directory = _requireString(
        args,
        0,
        'love.filesystem.getDirectoryItems',
      );
      final items = await state.getDirectoryItems(directory);
      return _arrayTable(items);
    };
  }

  LoveApiImplementation getIdentity() {
    return (args) => state.identity;
  }

  LoveApiImplementation getInfo() {
    return (args) async {
      final targetPath = _requireString(args, 0, 'love.filesystem.getInfo');
      LoveFilesystemNodeType? filterType;
      Value? wrappedTable;
      Map<dynamic, dynamic>? infoTable;
      var tableArgumentIndex = 1;

      if (args.length >= 2) {
        final typeName = _luaStringLike(_valueAt(args, 1));
        if (typeName != null) {
          filterType = _fileType(typeName, 'love.filesystem.getInfo');
          tableArgumentIndex = 2;
        }
      }

      if (args.length > tableArgumentIndex) {
        final tableTarget = _tableTargetIfPresent(
          _valueAt(args, tableArgumentIndex),
        );
        if (tableTarget != null) {
          wrappedTable = tableTarget.$1;
          infoTable = tableTarget.$2;
        }
      }

      final info = await state.getInfo(targetPath, filterType: filterType);
      if (info == null) {
        return null;
      }

      final table = infoTable ?? <Object?, Object?>{};
      table['type'] = _fileTypeName(info.type);
      if (_hasKnownFilesystemNumber(info.size)) {
        table['size'] = _clampLuaFilesystemNumber(info.size!);
      }
      if (_hasKnownFilesystemNumber(info.modtime)) {
        table['modtime'] = _clampLuaFilesystemNumber(info.modtime!);
      }

      if (wrappedTable != null) {
        return wrappedTable;
      }
      if (infoTable != null) {
        return infoTable;
      }
      return Value(table);
    };
  }

  LoveApiImplementation getRealDirectory() {
    return (args) async {
      final targetPath = _requireString(
        args,
        0,
        'love.filesystem.getRealDirectory',
      );
      final realDirectory = await state.getRealDirectory(targetPath);
      if (realDirectory == null) {
        return _ioError('File does not exist on disk.');
      }
      return realDirectory;
    };
  }

  LoveApiImplementation getRequirePath() {
    return (args) => state.getRequirePathString();
  }

  LoveApiImplementation getSaveDirectory() {
    return (args) => state.getSaveDirectory();
  }

  LoveApiImplementation getSource() {
    return (args) => state.source;
  }

  LoveApiImplementation getSourceBaseDirectory() {
    return (args) => state.getSourceBaseDirectory();
  }

  LoveApiImplementation getUserDirectory() {
    return (args) => state.getUserDirectory();
  }

  LoveApiImplementation getWorkingDirectory() {
    return (args) => state.getWorkingDirectory();
  }

  LoveApiImplementation init() {
    return (args) {
      final arg0 = _requireString(args, 0, 'love.filesystem.init');
      state.init(arg0);
      return null;
    };
  }

  LoveApiImplementation isFused() {
    return (args) => state.fused;
  }

  LoveApiImplementation lines() {
    return (args) async {
      final filename = _luaStringLike(_valueAt(args, 0));
      if (filename == null) {
        throw LuaError('love.filesystem.lines expected filename.');
      }
      try {
        return await _createLinesIterator(filename);
      } on LuaError {
        throw LuaError('Could not open file.');
      }
    };
  }

  LoveApiImplementation load() {
    return (args) async {
      final filename = _requireString(args, 0, 'love.filesystem.load');
      late final List<int> bytes;
      try {
        bytes = await state.readAllBytesOrThrow(filename);
      } on StateError catch (error) {
        return _ioError(error.message);
      }

      final result = await runtime.loadChunk(
        LuaChunkLoadRequest(
          source: runtime.constantStringValue(bytes),
          chunkName: '@$filename',
        ),
      );
      if (!result.isSuccess) {
        throw LuaError(
          formatLoveFilesystemLoadSyntaxError(result.errorMessage),
        );
      }
      return result.chunk;
    };
  }

  LoveApiImplementation mount() {
    return (args) async {
      final droppedFile = _droppedFileIfPresent(_valueAt(args, 0));
      if (droppedFile != null) {
        final mountpoint = _requireString(args, 1, 'love.filesystem.mount');
        final appendToPath = _optionalBool(args, 2, defaultValue: false);
        return state.mount(
          droppedFile.physicalPath,
          mountpoint: mountpoint,
          appendToPath: appendToPath,
        );
      }

      final mountedData = await _mountedDataIfPresent(
        _valueAt(args, 0),
        symbol: 'love.filesystem.mount',
        argumentIndex: 1,
        bindings: this,
      );
      if (mountedData != null) {
        late final String archiveName;
        late final String mountpoint;
        late final bool appendToPath;

        if (mountedData.archiveName != null &&
            !(args.length >= 3 && _luaStringLike(_valueAt(args, 2)) != null)) {
          archiveName = mountedData.archiveName!;
          mountpoint = _requireString(args, 1, 'love.filesystem.mount');
          appendToPath = _optionalBool(args, 2, defaultValue: false);
        } else {
          archiveName = _requireString(args, 1, 'love.filesystem.mount');
          mountpoint = _requireString(args, 2, 'love.filesystem.mount');
          appendToPath = _optionalBool(args, 3, defaultValue: false);
        }

        return state.mountArchiveBytes(
          mountedData.bytes,
          sourceIdentity: mountedData.sourceIdentity,
          archiveName: archiveName,
          mountpoint: mountpoint,
          appendToPath: appendToPath,
        );
      }

      final archive = _requireString(args, 0, 'love.filesystem.mount');
      final mountpoint = _requireString(args, 1, 'love.filesystem.mount');
      final appendToPath = _optionalBool(args, 2, defaultValue: false);
      return state.mount(
        archive,
        mountpoint: mountpoint,
        appendToPath: appendToPath,
      );
    };
  }

  LoveApiImplementation newFile() {
    return (args) async {
      final filename = _requireString(args, 0, 'love.filesystem.newFile');
      final file = LoveFilesystemFile(state: state, filename: filename);

      final modeName = _luaStringLike(_valueAt(args, 1));
      if (modeName != null) {
        final mode = _fileMode(modeName, 'love.filesystem.newFile');
        try {
          final opened = await file.open(mode);
          if (!opened) {
            return _ioError('Could not open file.');
          }
        } on StateError catch (error) {
          return _ioError(error.message);
        }
      }

      return wrapFile(file);
    };
  }

  LoveApiImplementation newFileData() {
    return (args) async {
      if (args.length == 1) {
        final source = _valueAt(args, 0);
        final filename = _luaStringLike(source);
        if (filename != null) {
          try {
            return wrapFileData(
              await state.readFileDataOrThrow(filename, filename: filename),
            );
          } on StateError catch (error) {
            return _ioError(error.message);
          }
        }

        final file = _fileIfPresent(source);
        if (file == null) {
          throw LuaError(
            'love.filesystem.newFileData expected filename or File at argument 1',
          );
        }

        try {
          final bytes = await file.readBytes();
          return wrapFileData(
            LoveFilesystemFileData(bytes: bytes, filename: file.filename),
          );
        } on StateError catch (error) {
          return _ioError(error.message);
        }
      }

      final bytes = await _dataBytes(
        _valueAt(args, 0),
        'love.filesystem.newFileData',
        bindings: this,
        argumentIndex: 1,
      );
      final filename = _requireString(args, 1, 'love.filesystem.newFileData');
      return wrapFileData(
        LoveFilesystemFileData(bytes: bytes, filename: filename),
      );
    };
  }

  LoveApiImplementation read() {
    return (args) async {
      var startIndex = 0;
      var containerType = _LoveFilesystemContainerType.string;
      if (args.length >= 2 && _exactStringLike(_valueAt(args, 1)) != null) {
        containerType = _containerType(
          _requireString(args, 0, 'love.filesystem.read'),
          'love.filesystem.read',
        );
        startIndex = 1;
      }

      final filename = _requireString(args, startIndex, 'love.filesystem.read');
      final explicitSize = _optionalTruncatedInt(args, startIndex + 1);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid read size.');
      }
      final size = explicitSize ?? -1;
      late final List<int> bytes;
      try {
        bytes = await state.readAllBytesOrThrow(filename, size: size);
      } on StateError catch (error) {
        return _ioError(error.message);
      }

      return _readResult(
        bytes,
        filename: filename,
        containerType: containerType,
      );
    };
  }

  LoveApiImplementation remove() {
    return (args) async {
      final targetPath = _requireString(args, 0, 'love.filesystem.remove');
      return state.remove(targetPath);
    };
  }

  LoveApiImplementation setCRequirePath() {
    return (args) {
      final value = _requireString(args, 0, 'love.filesystem.setCRequirePath');
      state.setCRequirePath(value);
      syncLoveFilesystemPackageInterop(runtime);
      return null;
    };
  }

  LoveApiImplementation setIdentity() {
    return (args) {
      final identity = _requireString(args, 0, 'love.filesystem.setIdentity');
      final appendToPath = _optionalBool(args, 1, defaultValue: false);
      if (!state.setIdentity(identity, appendToPath: appendToPath)) {
        throw LuaError('Could not set write directory.');
      }
      return null;
    };
  }

  LoveApiImplementation setRequirePath() {
    return (args) {
      final value = _requireString(args, 0, 'love.filesystem.setRequirePath');
      state.setRequirePath(value);
      syncLoveFilesystemPackageInterop(runtime);
      return null;
    };
  }

  LoveApiImplementation setSource() {
    return (args) async {
      final source = _requireString(args, 0, 'love.filesystem.setSource');
      if (!await state.setSourceFromFilesystem(source)) {
        throw LuaError('Could not set source.');
      }
      return null;
    };
  }

  LoveApiImplementation setSymlinksEnabled() {
    return (args) {
      state.setSymlinksEnabled(
        _requireBoolean(args, 0, 'love.filesystem.setSymlinksEnabled'),
      );
      return null;
    };
  }

  LoveApiImplementation unmount() {
    return (args) async {
      final sourceIdentity = await _mountedDataIdentityIfPresent(
        _valueAt(args, 0),
        bindings: this,
      );
      if (sourceIdentity != null) {
        return state.unmountData(sourceIdentity);
      }

      final archive = _requireString(args, 0, 'love.filesystem.unmount');
      return await state.unmount(archive);
    };
  }

  LoveApiImplementation write() {
    return (args) async {
      final filename = _requireString(args, 0, 'love.filesystem.write');
      final explicitSize = _optionalTruncatedInt(args, 2);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid write size.');
      }
      final bytes = _sliceBytes(
        await _dataBytes(
          _valueAt(args, 1),
          'love.filesystem.write',
          bindings: this,
          argumentIndex: 2,
        ),
        explicitSize,
      );
      try {
        await state.writeBytesOrThrow(filename, bytes, append: false);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
      return true;
    };
  }

  LoveApiImplementation fileClose() {
    return (args) => _requireFile(args, 0, 'File:close').close();
  }

  LoveApiImplementation fileFlush() {
    return (args) async {
      try {
        return await _requireFile(args, 0, 'File:flush').flush();
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  LoveApiImplementation fileGetBuffer() {
    return (args) {
      final file = _requireFile(args, 0, 'File:getBuffer');
      return Value.multi(<Object?>[
        _bufferModeName(file.bufferMode),
        file.bufferSize,
      ]);
    };
  }

  LoveApiImplementation fileGetFilename() {
    return (args) => _requireFile(args, 0, 'File:getFilename').filename;
  }

  LoveApiImplementation fileGetExtension() {
    return (args) => _requireFile(args, 0, 'File:getExtension').extension;
  }

  LoveApiImplementation fileGetMode() {
    return (args) => _requireFile(args, 0, 'File:getMode').mode;
  }

  LoveApiImplementation fileGetSize() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:getSize');
      late final int? size;
      try {
        size = await file.getSize();
      } on StateError catch (error) {
        return _ioError(error.message);
      }
      if (!_hasKnownFilesystemNumber(size)) {
        return _ioError('Could not determine file size.');
      }
      final knownSize = size!;
      if (knownSize >= _loveFilesystemLuaNumberLimit) {
        return _ioError('Size is too large.');
      }
      return knownSize;
    };
  }

  LoveApiImplementation fileIsEOF() {
    return (args) => _requireFile(args, 0, 'File:isEOF').isEOF();
  }

  LoveApiImplementation fileIsOpen() {
    return (args) => _requireFile(args, 0, 'File:isOpen').isOpen;
  }

  LoveApiImplementation fileLines() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:lines');
      final restoreUserPosition = file.mode != 'c';
      final userPosition = restoreUserPosition && file.mode == 'r'
          ? math.max(0, await file.tell())
          : 0;

      if (file.mode != 'r') {
        if (file.mode != 'c') {
          await file.close();
        }

        try {
          final opened = await file.open('r');
          if (!opened) {
            throw LuaError('Could not open file.');
          }
        } on StateError {
          throw LuaError('Could not open file.');
        }
      }

      return _fileLinesIterator(
        file,
        restoreUserPosition: restoreUserPosition,
        userPosition: userPosition,
      );
    };
  }

  LoveApiImplementation fileOpen() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:open');
      final mode = _fileMode(_requireString(args, 1, 'File:open'), 'File:open');
      try {
        return await file.open(mode);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  LoveApiImplementation fileRead() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:read');
      var startIndex = 1;
      var containerType = _LoveFilesystemContainerType.string;
      if (_exactStringLike(_valueAt(args, 1)) != null) {
        containerType = _containerType(
          _requireString(args, 1, 'File:read'),
          'File:read',
        );
        startIndex = 2;
      }

      final explicitSize = _optionalTruncatedInt(args, startIndex);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid read size.');
      }
      final size = explicitSize ?? -1;
      try {
        final bytes = await file.readBytes(size);
        return _readResult(
          bytes,
          filename: file.filename,
          containerType: containerType,
        );
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  LoveApiImplementation fileSeek() {
    return (args) {
      final file = _requireFile(args, 0, 'File:seek');
      final position = _numberValue(args, 1, 'File:seek');
      if (position < 0 || position >= _loveFilesystemLuaNumberLimitDouble) {
        return false;
      }
      return file.seek(position.toInt());
    };
  }

  LoveApiImplementation fileSetBuffer() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:setBuffer');
      final mode = _bufferMode(
        _requireString(args, 1, 'File:setBuffer'),
        'File:setBuffer',
      );
      final size = _optionalTruncatedInt(args, 2) ?? 0;
      try {
        return await file.setBuffer(mode, size);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  LoveApiImplementation fileTell() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:tell');
      final position = await file.tell();
      if (position < 0) {
        return _ioError('Invalid position.');
      }
      if (position >= _loveFilesystemLuaNumberLimit) {
        return _ioError('Number is too large.');
      }
      return position;
    };
  }

  LoveApiImplementation fileWrite() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:write');
      final explicitSize = _optionalTruncatedInt(args, 2);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid write size.');
      }
      final bytes = _sliceBytes(
        await _dataBytes(
          _valueAt(args, 1),
          'File:write',
          bindings: this,
          argumentIndex: 2,
          expectedTypeDescription: 'string or data',
        ),
        explicitSize,
      );
      try {
        return await file.writeBytes(bytes);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  LoveApiImplementation fileDataGetExtension() {
    return (args) =>
        _requireFileData(args, 0, 'FileData:getExtension').extension;
  }

  LoveApiImplementation fileDataGetFilename() {
    return (args) => _requireFileData(args, 0, 'FileData:getFilename').filename;
  }

  LoveApiImplementation fileDataClone() {
    return (args) {
      final data = _requireFileData(args, 0, 'FileData:clone');
      return wrapFileData(data.clone());
    };
  }

  LoveApiImplementation dataGetSize() {
    return (args) => _requireFileData(args, 0, 'Data:getSize').size;
  }

  LoveApiImplementation dataGetString() {
    return (args) {
      final data = _requireFileData(args, 0, 'Data:getString');
      return runtime.constantStringValue(data.bytes);
    };
  }

  LoveApiImplementation objectRelease() {
    return (args) async {
      final rawObject = _wrapperObject(args, 0, 'Object:release');
      if (_loveFilesystemReleased[rawObject] == true) {
        return false;
      }

      _loveFilesystemReleased[rawObject] = true;
      if (rawObject is LoveFilesystemFile && rawObject.isOpen) {
        await rawObject.close();
      }
      return true;
    };
  }

  LoveApiImplementation objectType() {
    return (args) => _wrapperTypeName(args, 0, 'Object:type');
  }

  LoveApiImplementation objectTypeOf() {
    return (args) {
      final hierarchy = _wrapperHierarchy(args, 0, 'Object:typeOf');
      final typeName = _requireString(args, 1, 'Object:typeOf');
      return hierarchy.contains(typeName);
    };
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

  Future<Value> _createLinesIterator(
    String filename, {
    int startOffset = 0,
  }) async {
    try {
      final bytes = await state.readAllBytesOrThrow(filename);
      return _linesIterator(bytes, startOffset: startOffset);
    } on StateError catch (error) {
      throw LuaError(error.message);
    }
  }

  Value _linesIterator(List<int> bytes, {int startOffset = 0}) {
    final cursor = _LoveFilesystemLineCursor(bytes, startOffset: startOffset);
    return Value(
      _builder.create((args) {
        final line = cursor.next();
        if (line == null) {
          return null;
        }
        return runtime.constantStringValue(line);
      }),
      functionName: 'lines',
    );
  }

  Value _fileLinesIterator(
    LoveFilesystemFile file, {
    required bool restoreUserPosition,
    required int userPosition,
  }) {
    final cursor = _LoveFilesystemFileLineCursor(
      file: file,
      restoreUserPosition: restoreUserPosition,
      userPosition: userPosition,
    );
    return Value(
      _builder.create((args) async {
        final line = await cursor.next();
        if (line == null) {
          return null;
        }
        return runtime.constantStringValue(line);
      }),
      functionName: 'lines',
    );
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

LoveApiImplementation _bindFilesystemAppend(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).append();

LoveApiImplementation _bindFilesystemAreSymlinksEnabled(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).areSymlinksEnabled();

LoveApiImplementation _bindFilesystemCreateDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).createDirectory();

LoveApiImplementation _bindFilesystemGetAppdataDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getAppdataDirectory();

LoveApiImplementation _bindFilesystemGetCRequirePath(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getCRequirePath();

LoveApiImplementation _bindFilesystemGetDirectoryItems(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getDirectoryItems();

LoveApiImplementation _bindFilesystemGetIdentity(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getIdentity();

LoveApiImplementation _bindFilesystemGetInfo(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getInfo();

LoveApiImplementation _bindFilesystemGetRealDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getRealDirectory();

LoveApiImplementation _bindFilesystemGetRequirePath(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getRequirePath();

LoveApiImplementation _bindFilesystemGetSaveDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getSaveDirectory();

LoveApiImplementation _bindFilesystemGetSource(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getSource();

LoveApiImplementation _bindFilesystemGetSourceBaseDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getSourceBaseDirectory();

LoveApiImplementation _bindFilesystemGetUserDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getUserDirectory();

LoveApiImplementation _bindFilesystemGetWorkingDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getWorkingDirectory();

LoveApiImplementation _bindFilesystemInit(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).init();

LoveApiImplementation _bindFilesystemIsFused(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).isFused();

LoveApiImplementation _bindFilesystemLines(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).lines();

LoveApiImplementation _bindFilesystemLoad(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).load();

LoveApiImplementation _bindFilesystemMount(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).mount();

LoveApiImplementation _bindFilesystemNewFile(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).newFile();

LoveApiImplementation _bindFilesystemNewFileData(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).newFileData();

LoveApiImplementation _bindFilesystemRead(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).read();

LoveApiImplementation _bindFilesystemRemove(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).remove();

LoveApiImplementation _bindFilesystemSetCRequirePath(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setCRequirePath();

LoveApiImplementation _bindFilesystemSetIdentity(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setIdentity();

LoveApiImplementation _bindFilesystemSetRequirePath(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setRequirePath();

LoveApiImplementation _bindFilesystemSetSource(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setSource();

LoveApiImplementation _bindFilesystemSetSymlinksEnabled(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setSymlinksEnabled();

LoveApiImplementation _bindFilesystemUnmount(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).unmount();

LoveApiImplementation _bindFilesystemWrite(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).write();

LoveApiImplementation _bindFileClose(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileClose();

LoveApiImplementation _bindFileFlush(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileFlush();

LoveApiImplementation _bindFileGetBuffer(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileGetBuffer();

LoveApiImplementation _bindFileGetFilename(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).fileGetFilename();

LoveApiImplementation _bindFileGetExtension(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).fileGetExtension();

LoveApiImplementation _bindFileGetMode(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileGetMode();

LoveApiImplementation _bindFileGetSize(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileGetSize();

LoveApiImplementation _bindFileIsEOF(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileIsEOF();

LoveApiImplementation _bindFileIsOpen(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileIsOpen();

LoveApiImplementation _bindFileLines(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileLines();

LoveApiImplementation _bindFileOpen(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileOpen();

LoveApiImplementation _bindFileRead(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileRead();

LoveApiImplementation _bindFileSeek(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileSeek();

LoveApiImplementation _bindFileSetBuffer(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileSetBuffer();

LoveApiImplementation _bindFileTell(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileTell();

LoveApiImplementation _bindFileWrite(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileWrite();

LoveApiImplementation _bindFileDataClone(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileDataClone();

LoveApiImplementation _bindFileDataGetExtension(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).fileDataGetExtension();

LoveApiImplementation _bindFileDataGetFilename(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).fileDataGetFilename();

LoveApiImplementation _bindDataGetSize(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).dataGetSize();

LoveApiImplementation _bindDataGetString(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).dataGetString();

LoveApiImplementation _bindObjectRelease(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).objectRelease();

LoveApiImplementation _bindObjectType(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).objectType();

LoveApiImplementation _bindObjectTypeOf(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).objectTypeOf();

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

Value? _callableValue(Object? value) {
  return switch (value) {
    final Value wrapped => wrapped,
    final BuiltinFunction builtin => Value(builtin),
    final Function function => Value(function),
    _ => null,
  };
}

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

List<int> _sliceBytes(List<int> bytes, int? size) {
  if (size == null || size < 0 || size >= bytes.length) {
    return bytes;
  }
  return bytes.sublist(0, math.max(0, size));
}

Value _arrayTable(List<String> values) {
  return Value(<Object?, Object?>{
    for (var index = 0; index < values.length; index++)
      index + 1: values[index],
  });
}

Value _ioError(String message) {
  return Value.multi(<Object?>[null, message]);
}

class _LoveFilesystemLineCursor {
  _LoveFilesystemLineCursor(List<int> bytes, {required int startOffset})
    : _bytes = List<int>.unmodifiable(bytes),
      _offset = startOffset.clamp(0, bytes.length);

  final List<int> _bytes;
  int _offset;

  List<int>? next() {
    if (_offset >= _bytes.length) {
      return null;
    }

    final start = _offset;
    var end = start;
    while (end < _bytes.length && _bytes[end] != 10) {
      end++;
    }

    _offset = end < _bytes.length ? end + 1 : _bytes.length;

    var lineEnd = end;
    if (lineEnd > start && _bytes[lineEnd - 1] == 13) {
      lineEnd--;
    }

    return _bytes.sublist(start, lineEnd);
  }
}

class _LoveFilesystemFileLineCursor {
  _LoveFilesystemFileLineCursor({
    required this.file,
    required this.restoreUserPosition,
    required this.userPosition,
  });

  final LoveFilesystemFile file;
  final bool restoreUserPosition;
  final int userPosition;
  int _iteratorPosition = 0;
  bool _exhausted = false;

  Future<List<int>?> next() async {
    if (_exhausted) {
      return null;
    }

    if (file.mode != 'r') {
      throw LuaError('File needs to stay in read mode.');
    }

    try {
      var currentUserPosition = userPosition;
      if (restoreUserPosition) {
        currentUserPosition = await file.tell();
        if (currentUserPosition != _iteratorPosition) {
          await file.seek(_iteratorPosition);
        }
      }

      final line = await file.readLineBytes();
      if (line == null) {
        _exhausted = true;
        if (file.isOpen) {
          await file.close();
        }
        return null;
      }

      if (restoreUserPosition && file.isOpen) {
        _iteratorPosition = await file.tell();
        await file.seek(currentUserPosition);
      }

      if (line.isNotEmpty && line.last == 13) {
        return line.sublist(0, line.length - 1);
      }

      return line;
    } on StateError catch (error) {
      _exhausted = true;
      throw LuaError(error.message);
    }
  }
}
