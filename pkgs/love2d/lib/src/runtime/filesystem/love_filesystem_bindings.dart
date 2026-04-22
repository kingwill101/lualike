// ignore_for_file: implementation_imports

/// LOVE filesystem API bindings and Lua object wrappers.
library;

import 'dart:async' show FutureOr;
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

/// Whether the filesystem binding factories have already been registered.
bool _filesystemBindingsLoaded = false;

/// The table slot used to store wrapped [LoveFilesystemFile] objects.
const String _loveFilesystemFileObjectKey = '__love2d_filesystem_file__';

/// The table slot used to store wrapped [LoveFilesystemFileData] objects.
const String _loveFilesystemFileDataObjectKey =
    '__love2d_filesystem_filedata__';

/// The table slot used to store a wrapper's LOVE object type name.
const String _loveFilesystemObjectTypeKey = '__love2d_filesystem_type__';

/// The table slot used to store a wrapper's LOVE inheritance hierarchy.
const String _loveFilesystemObjectHierarchyKey =
    '__love2d_filesystem_hierarchy__';

/// The largest integer value that can be represented exactly in Lua doubles.
const int _loveFilesystemLuaNumberLimit = 0x20000000000000;

/// The floating-point form of [_loveFilesystemLuaNumberLimit].
const double _loveFilesystemLuaNumberLimitDouble = 9007199254740992.0;

/// Cached Lua wrappers for filesystem file objects.
final Expando<Value> _loveFilesystemFileWrapperCache = Expando<Value>(
  'love2dFilesystemFileWrapper',
);

/// Cached Lua wrappers for dropped-file objects.
final Expando<Value> _loveFilesystemDroppedFileWrapperCache = Expando<Value>(
  'love2dFilesystemDroppedFileWrapper',
);

/// Cached Lua wrappers for filesystem file-data objects.
final Expando<Value> _loveFilesystemFileDataWrapperCache = Expando<Value>(
  'love2dFilesystemFileDataWrapper',
);

/// Cached Lua wrappers for filesystem-backed data pointers.
final Expando<Value> _loveFilesystemDataPointerCache = Expando<Value>(
  'love2dFilesystemDataPointer',
);

/// Release flags for wrapper instances that implement LOVE object semantics.
final Expando<bool> _loveFilesystemReleased = Expando<bool>(
  'love2dFilesystemReleased',
);

/// The supported container kinds accepted by the filesystem bindings.
enum _LoveFilesystemContainerType { string, data }

/// In-memory archive data prepared for `love.filesystem.mount`.
class _LoveFilesystemMountedData {
  /// Creates mounted archive data from [bytes].
  const _LoveFilesystemMountedData({
    required this.sourceIdentity,
    required this.bytes,
    this.archiveName,
  });

  /// The object identity used to track later `unmountData` calls.
  final Object sourceIdentity;

  /// The archive bytes to mount.
  final List<int> bytes;

  /// The optional archive name supplied alongside [bytes].
  final String? archiveName;
}

/// Registers the LOVE filesystem API bindings once for the current process.
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

/// Shared binding context and helpers for the LOVE filesystem module.
class _LoveFilesystemBindings {
  /// Creates filesystem bindings for a library registration [context].
  _LoveFilesystemBindings(this.context)
    : _builder = BuiltinFunctionBuilder(context);

  /// The registration context that owns these bindings.
  final LibraryRegistrationContext context;

  /// The builder used to produce wrapped builtin functions.
  final BuiltinFunctionBuilder _builder;

  /// The active Lua runtime for [context].
  LuaRuntime get runtime {
    final interpreter = context.interpreter;
    if (interpreter == null) {
      throw StateError('No Lua runtime available for LOVE filesystem');
    }
    return interpreter;
  }

  /// The filesystem runtime state attached to [runtime].
  LoveFilesystemState get state => LoveFilesystemState.attach(runtime);

  /// Binds a filesystem API symbol under [publicName].
  Value bindSymbol(String symbol, String publicName) {
    return bindLoveApiFunction(
      context,
      symbol: symbol,
      publicName: publicName,
      implementations: const <String, LoveApiImplementation>{},
    );
  }
}
