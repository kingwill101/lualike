// ignore_for_file: implementation_imports

/// LOVE filesystem runtime support and host adapter integration.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:lualike/lualike.dart'
    show LuaChunkLoadRequest, LuaError, LuaRuntime, LuaString, Value;
import 'package:lualike/src/io/filesystem_provider.dart';
import 'package:lualike/src/io/io_device.dart';
import 'package:lualike/src/utils/file_system_utils.dart' as fs_utils;
import 'package:lualike/src/utils/platform_utils.dart' as platform_utils;
import 'package:path/path.dart' as path;

import 'love_readonly_bytes_io_device.dart';
import 'love_filesystem_archive_7z.dart' as love_filesystem_archive_7z;
import 'love_filesystem_archive_7z_stub.dart'
    if (dart.library.io) 'love_filesystem_archive_7z_io.dart'
    as love_filesystem_archive_7z_host;

part 'love_filesystem_adapter.dart';
part 'love_filesystem_archive_decoding.dart';
part 'love_filesystem_archive_helpers.dart';
part 'love_filesystem_archive_iso.dart';
part 'love_filesystem_file_objects.dart';
part 'love_filesystem_runtime_config.dart';
part 'love_filesystem_runtime_mount_ops.dart';
part 'love_filesystem_runtime_read_write.dart';
part 'love_filesystem_mount_rebinding.dart';
part 'love_filesystem_mount_resolution.dart';
part 'love_filesystem_mount_state.dart';
part 'love_filesystem_path_model.dart';

/// The default Lua module search path used by `require`.
const String loveFilesystemDefaultRequirePath = '?.lua;?/init.lua';

/// The default native module search path used by `require`.
const String loveFilesystemDefaultCRequirePath = '??';

/// Formats a syntax error reported while loading a Lua chunk from the LOVE
/// filesystem.
String formatLoveFilesystemLoadSyntaxError(String? errorMessage) {
  final normalized = errorMessage ?? 'unknown';
  return 'Syntax error: ${normalized.endsWith('\n') ? normalized : '$normalized\n'}';
}

/// Per-runtime LOVE filesystem state.
class LoveFilesystemState {
  /// Creates filesystem state backed by [adapter].
  LoveFilesystemState({LoveFilesystemAdapter? adapter})
    : _adapter = adapter ?? LoveLualikeFilesystemAdapter();

  static final Expando<LoveFilesystemState> _states =
      Expando<LoveFilesystemState>('love2d.filesystem');
  static final Expando<Map<String, _LoveFilesystemRoot>> _resolvedSourceRoots =
      Expando<Map<String, _LoveFilesystemRoot>>(
        'love2d.filesystem.resolvedSourceRoots',
      );

  LoveFilesystemAdapter _adapter;
  final List<_LoveFilesystemRoot> _roots = <_LoveFilesystemRoot>[];
  final HashMap<Object, List<String>> _dataMountKeys =
      HashMap<Object, List<String>>.identity();
  final Map<String, Object> _dataMountSources = <String, Object>{};
  final List<_LoveFilesystemStringMountSpec> _stringMountSpecs =
      <_LoveFilesystemStringMountSpec>[];
  final Map<String, int> _openPathCounts = <String, int>{};
  final Set<String> _allowedMountPaths = <String>{};

  bool _initialized = false;
  bool _symlinksEnabled = true;
  bool _androidSaveExternal = false;
  bool _fused = false;
  bool _fusedSet = false;
  bool _identitySet = false;
  bool _saveRootAppendToPath = false;
  bool _sourceSetFromFilesystem = false;
  bool _sourceRootDirty = false;
  bool _stringMountRootsDirty = false;
  String _identity = '';
  String _source = '';
  List<String> _requirePath = loveFilesystemDefaultRequirePath.split(';');
  List<String> _cRequirePath = loveFilesystemDefaultCRequirePath.split(';');
  Future<void>? _sourceRootRebindFuture;
  Future<void>? _stringMountRootRebindFuture;

  /// Attaches filesystem state to [runtime].
  static LoveFilesystemState attach(
    LuaRuntime runtime, {
    LoveFilesystemAdapter? adapter,
  }) {
    final existing = _states[runtime];
    if (existing != null) {
      if (adapter != null) {
        existing.replaceAdapter(adapter);
      }
      return existing;
    }

    final state = LoveFilesystemState(adapter: adapter);
    _states[runtime] = state;
    return state;
  }

  /// Returns the filesystem state attached to [runtime].
  static LoveFilesystemState of(LuaRuntime runtime) {
    return _states[runtime] ?? attach(runtime);
  }

  /// The host adapter used for physical filesystem access.
  LoveFilesystemAdapter get adapter => _adapter;

  /// Whether initialization has completed.
  bool get initialized => _initialized;

  /// Whether symlink support is enabled.
  bool get symlinksEnabled => _symlinksEnabled;

  /// Whether Android external save storage is enabled.
  bool get androidSaveExternal => _androidSaveExternal;

  /// Whether the runtime is currently running from a fused game archive.
  bool get fused => _fused;

  /// The active LOVE save identity.
  String get identity => _identity;

  /// The mounted LOVE source path.
  String get source => _source;

  /// The current Lua `package.path` template list for LOVE modules.
  List<String> get requirePath => List<String>.unmodifiable(_requirePath);

  /// The current Lua `package.cpath` template list for LOVE modules.
  List<String> get cRequirePath => List<String>.unmodifiable(_cRequirePath);

  /// Reads the file at [logicalPath] as bytes.
  Future<List<int>?> readAllBytes(String logicalPath, {int size = -1}) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).readAllBytes(logicalPath, size: size);
  }

  /// Writes [bytes] to [logicalPath].
  Future<bool> writeBytes(
    String logicalPath,
    List<int> bytes, {
    required bool append,
  }) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).writeBytes(logicalPath, bytes, append: append);
  }

  /// Writes [bytes] to [logicalPath] and throws on failure.
  Future<void> writeBytesOrThrow(
    String logicalPath,
    List<int> bytes, {
    required bool append,
  }) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).writeBytesOrThrow(logicalPath, bytes, append: append);
  }

  /// Reads [logicalPath] as [LoveFilesystemFileData].
  Future<LoveFilesystemFileData?> readFileData(
    String logicalPath, {
    int size = -1,
    String? filename,
  }) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).readFileData(logicalPath, size: size, filename: filename);
  }

  /// Reads [logicalPath] as [LoveFilesystemFileData] when it exists.
  Future<LoveFilesystemFileData?> readFileDataIfExistsOrThrow(
    String logicalPath, {
    int size = -1,
    String? filename,
  }) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).readFileDataIfExistsOrThrow(logicalPath, size: size, filename: filename);
  }

  /// Reads [logicalPath] as [LoveFilesystemFileData] and throws on failure.
  Future<LoveFilesystemFileData> readFileDataOrThrow(
    String logicalPath, {
    int size = -1,
    String? filename,
  }) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).readFileDataOrThrow(logicalPath, size: size, filename: filename);
  }

  /// Resolves [logicalPath] to a readable host path, if one exists.
  Future<String?> resolveReadablePhysicalPath(String logicalPath) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).resolveReadablePhysicalPath(logicalPath);
  }

  /// Resolves [logicalPath] to a writable host path.
  Future<String?> resolveWritablePhysicalPath(String logicalPath) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).resolveWritablePhysicalPath(logicalPath);
  }

  Future<List<int>?> readAllBytesIfExistsOrThrow(
    String logicalPath, {
    int size = -1,
  }) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).readAllBytesIfExistsOrThrow(logicalPath, size: size);
  }

  Future<List<int>> readAllBytesOrThrow(String logicalPath, {int size = -1}) {
    return LoveFilesystemRuntimeReadWrite(
      this,
    ).readAllBytesOrThrow(logicalPath, size: size);
  }

  /// Loads the Lua chunk at [logicalPath] through the LOVE filesystem.
  Future<Value?> loadChunk(LuaRuntime runtime, String logicalPath) {
    return LoveFilesystemRuntimeReadWrite(this).loadChunk(runtime, logicalPath);
  }
}
