library;

import 'dart:math' as math;

import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart'
    show
        Box,
        BuiltinFunction,
        LuaChunkLoadRequest,
        LuaError,
        LuaRuntime,
        LuaString,
        NumberUtils,
        Value;
import 'package:lualike/src/io/io_device.dart' show BufferMode;

import '../../love_api_support.dart';
import '../love_runtime.dart' show LoveDataPointer;
import 'love_filesystem_package_loader.dart';
import 'love_filesystem_runtime.dart';

part 'love_filesystem_binding_dispatch.dart';
part 'love_filesystem_binding_line_helpers.dart';
part 'love_filesystem_binding_module_methods.dart';
part 'love_filesystem_binding_object_methods.dart';
part 'love_filesystem_binding_data_helpers.dart';
part 'love_filesystem_binding_value_helpers.dart';
part 'love_filesystem_binding_wrappers.dart';

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
}
