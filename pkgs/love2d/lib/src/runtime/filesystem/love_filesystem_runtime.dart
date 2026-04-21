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

const String loveFilesystemDefaultRequirePath = '?.lua;?/init.lua';
const String loveFilesystemDefaultCRequirePath = '??';

String formatLoveFilesystemLoadSyntaxError(String? errorMessage) {
  final normalized = errorMessage ?? 'unknown';
  return 'Syntax error: ${normalized.endsWith('\n') ? normalized : '$normalized\n'}';
}

abstract interface class LoveFilesystemAdapter {
  String? get workingDirectory;

  String? get userDirectory;

  String? get appdataDirectory;

  String? get executablePath;

  bool get isWindows;

  bool get isLinux;

  bool get isMacOS;

  Future<IODevice> openFile(String path, String mode);

  Future<bool> fileExists(String path);

  Future<bool> directoryExists(String path);

  Future<List<int>?> readFileBytes(String path);

  Future<List<String>> listDirectory(String path);

  Future<DateTime?> modified(String path);

  Future<int?> fileSize(String path);

  Future<bool> createDirectory(String path, {bool recursive = true});

  Future<bool> deletePath(String path, {bool recursive = true});
}

class LoveLualikeFilesystemAdapter implements LoveFilesystemAdapter {
  LoveLualikeFilesystemAdapter({
    FileSystemProvider? fileSystemProvider,
    Map<String, String>? environment,
    bool? isWindows,
    bool? isLinux,
    bool? isMacOS,
    String? resolvedExecutablePath,
    String Function()? workingDirectoryProvider,
  }) : _fileSystemProvider = fileSystemProvider ?? FileSystemProvider(),
       _environment = environment,
       _isWindows = isWindows,
       _isLinux = isLinux,
       _isMacOS = isMacOS,
       _resolvedExecutablePath = resolvedExecutablePath,
       _workingDirectoryProvider = workingDirectoryProvider;

  final FileSystemProvider _fileSystemProvider;
  final Map<String, String>? _environment;
  final bool? _isWindows;
  final bool? _isLinux;
  final bool? _isMacOS;
  final String? _resolvedExecutablePath;
  final String Function()? _workingDirectoryProvider;

  @override
  String? get workingDirectory =>
      _workingDirectoryProvider?.call() ?? fs_utils.getCurrentDirectory();

  @override
  String? get userDirectory {
    final home = _environmentValue('HOME');
    if (home != null && home.isNotEmpty) {
      return home;
    }

    final userProfile = _environmentValue('USERPROFILE');
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }

    return workingDirectory;
  }

  @override
  String? get appdataDirectory {
    if (_platformIsWindows) {
      final appData = _environmentValue('APPDATA');
      if (appData != null && appData.isNotEmpty) {
        return appData;
      }
    }

    final userDir = userDirectory;
    if (userDir == null || userDir.isEmpty) {
      return workingDirectory;
    }

    if (_platformIsMacOS) {
      return path.join(userDir, 'Library', 'Application Support');
    }

    if (_platformIsLinux) {
      final xdgDataHome = _environmentValue('XDG_DATA_HOME');
      if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
        return xdgDataHome;
      }

      return path.join(userDir, '.local', 'share');
    }

    return userDir;
  }

  @override
  String? get executablePath {
    final resolved =
        _resolvedExecutablePath ?? platform_utils.resolvedExecutablePath;
    return resolved.isEmpty ? null : resolved;
  }

  @override
  bool get isWindows => _platformIsWindows;

  @override
  bool get isLinux => _platformIsLinux;

  @override
  bool get isMacOS => _platformIsMacOS;

  @override
  Future<IODevice> openFile(String path, String mode) {
    return _fileSystemProvider.openFile(path, mode);
  }

  @override
  Future<bool> fileExists(String path) => fs_utils.fileExists(path);

  @override
  Future<bool> directoryExists(String path) => fs_utils.directoryExists(path);

  @override
  Future<List<int>?> readFileBytes(String path) =>
      fs_utils.readFileAsBytes(path);

  @override
  Future<List<String>> listDirectory(String path) =>
      fs_utils.listDirectory(path);

  @override
  Future<DateTime?> modified(String path) => fs_utils.getLastModified(path);

  @override
  Future<int?> fileSize(String path) => fs_utils.fileSize(path);

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) {
    return fs_utils.createDirectory(path, recursive: recursive);
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) {
    return fs_utils.deletePath(path, recursive: recursive);
  }

  String? _environmentValue(String name) {
    return _environment?[name] ?? platform_utils.getEnvironmentVariable(name);
  }

  bool get _platformIsWindows => _isWindows ?? platform_utils.isWindows;

  bool get _platformIsLinux => _isLinux ?? platform_utils.isLinux;

  bool get _platformIsMacOS => _isMacOS ?? platform_utils.isMacOS;
}

enum LoveFilesystemNodeType { file, directory, symlink, other }

class LoveFilesystemInfo {
  const LoveFilesystemInfo({required this.type, this.size, this.modtime});

  final LoveFilesystemNodeType type;
  final int? size;
  final int? modtime;
}

class LoveFilesystemFileData {
  LoveFilesystemFileData({required List<int> bytes, required this.filename})
    : bytes = List<int>.unmodifiable(bytes);

  final List<int> bytes;
  final String filename;

  String get extension {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      return '';
    }

    return filename.substring(dotIndex + 1);
  }

  int get size => bytes.length;

  LoveFilesystemFileData clone() {
    return LoveFilesystemFileData(bytes: bytes, filename: filename);
  }
}

class _LoveReadableHandle {
  const _LoveReadableHandle({required this.device, this.path});

  final IODevice device;
  final String? path;
}

String _filesystemAdapterErrorMessage(Object error) {
  return switch (error) {
    StateError(:final message) => message,
    UnsupportedError(:final message?) => message,
    ArgumentError(:final message?) when message != null => '$message',
    _ => '$error',
  }.trim();
}

StateError _openFileStateError(String logicalPath, Object error) {
  final message = _filesystemAdapterErrorMessage(error);
  if (message.isEmpty) {
    return StateError('Could not open file $logicalPath.');
  }

  if (message.startsWith('Could not open file ') ||
      message == 'Could not set write directory.') {
    return StateError(message);
  }

  return StateError('Could not open file $logicalPath ($message)');
}

Future<IODevice> _openFilesystemDeviceOrThrow(
  LoveFilesystemAdapter adapter,
  String physicalPath,
  String mode, {
  required String logicalPath,
}) async {
  try {
    return await adapter.openFile(physicalPath, mode);
  } catch (error) {
    throw _openFileStateError(logicalPath, error);
  }
}

class LoveFilesystemFile {
  LoveFilesystemFile({required this.state, required this.filename});

  final LoveFilesystemState state;
  final String filename;

  IODevice? _device;
  String _mode = 'c';
  BufferMode _bufferMode = BufferMode.none;
  int _bufferSize = 0;
  String? _openedPath;

  bool get isOpen => _device != null;

  String get mode => _mode;

  String? get openedPath => _openedPath;

  BufferMode get bufferMode => _bufferMode;

  int get bufferSize => _bufferSize;

  String get extension {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      return '';
    }

    return filename.substring(dotIndex + 1);
  }

  Future<bool> open(String mode) async {
    if (mode == 'c') {
      return true;
    }

    if (isOpen) {
      return false;
    }

    late final IODevice device;
    String? openedPath;

    if (mode == 'r') {
      final readable = await state._openReadable(filename);
      if (readable == null) {
        throw StateError('Could not open file $filename. Does not exist.');
      }
      device = readable.device;
      openedPath = readable.path;
    } else {
      final physicalPath = await state.resolveWritablePhysicalPath(filename);
      if (physicalPath == null) {
        throw StateError('Could not set write directory.');
      }

      if (!await state._ensureSaveDirectoryExists()) {
        throw StateError('Could not set write directory.');
      }

      final parent = path.dirname(physicalPath);
      final saveDirectory = state.getSaveDirectory();
      if (path.normalize(parent) != path.normalize(saveDirectory) &&
          !await state.adapter.directoryExists(parent)) {
        throw StateError('Could not open file $filename.');
      }

      device = await _openFilesystemDeviceOrThrow(
        state.adapter,
        physicalPath,
        mode,
        logicalPath: filename,
      );
      openedPath = physicalPath;
    }

    await device.setBuffering(
      _bufferMode,
      _bufferSize > 0 ? _bufferSize : null,
    );

    _device = device;
    _mode = mode;
    _openedPath = openedPath;
    if (openedPath != null) {
      state._registerOpenPath(openedPath);
    }
    return true;
  }

  Future<bool> close() async {
    final device = _device;
    if (device == null) {
      return false;
    }

    await device.close();
    final openedPath = _openedPath;
    if (openedPath != null) {
      state._unregisterOpenPath(openedPath);
    }
    _device = null;
    _mode = 'c';
    _openedPath = null;
    return true;
  }

  Future<List<int>> readBytes([int size = -1]) async {
    final wasOpen = isOpen;
    if (wasOpen && _mode != 'r') {
      throw StateError('File is not opened for reading.');
    }
    if (!wasOpen) {
      final opened = await open('r');
      if (!opened) {
        throw StateError('Could not open file.');
      }
    }

    try {
      final device = _device!;
      final result = await device.read(size < 0 ? 'a' : '$size');
      if (!result.isSuccess) {
        throw StateError(result.error ?? 'Could not read from file.');
      }
      if (result.value == null && size == 0) {
        return const <int>[];
      }

      return _bytesFromIODeviceValue(result.value);
    } finally {
      if (!wasOpen) {
        await close();
      }
    }
  }

  Future<List<int>?> readLineBytes({bool includeLineTerminator = false}) async {
    final wasOpen = isOpen;
    if (wasOpen && _mode != 'r') {
      throw StateError('File is not opened for reading.');
    }
    if (!wasOpen) {
      final opened = await open('r');
      if (!opened) {
        throw StateError('Could not open file.');
      }
    }

    try {
      final device = _device!;
      final result = await device.read(includeLineTerminator ? 'L' : 'l');
      if (!result.isSuccess) {
        throw StateError(result.error ?? 'Could not read from file.');
      }

      final value = result.value;
      if (value == null) {
        return null;
      }

      return _bytesFromIODeviceValue(value);
    } finally {
      if (!wasOpen) {
        await close();
      }
    }
  }

  Future<bool> writeBytes(List<int> bytes) async {
    final device = _device;
    if (device == null || (_mode != 'w' && _mode != 'a')) {
      throw StateError('File is not opened for writing.');
    }

    final result = await device.writeBytes(bytes);
    if (!result.success) {
      if (result.error != null && result.error!.isNotEmpty) {
        throw StateError(result.error!);
      }
      return false;
    }

    return true;
  }

  Future<bool> flush() async {
    final device = _device;
    if (device == null || (_mode != 'w' && _mode != 'a')) {
      throw StateError('File is not opened for writing.');
    }

    await device.flush();
    return true;
  }

  Future<bool> isEOF() async {
    final device = _device;
    if (device == null) {
      return true;
    }

    return device.isEOF();
  }

  Future<int> tell() async {
    final device = _device;
    if (device == null) {
      return -1;
    }

    return device.getPosition();
  }

  Future<bool> seek(int position) async {
    final device = _device;
    if (device == null || position < 0) {
      return false;
    }

    await device.seek(SeekWhence.set, position);
    return true;
  }

  Future<bool> setBuffer(BufferMode mode, int size) async {
    if (size < 0) {
      return false;
    }

    _bufferMode = mode;
    _bufferSize = size;

    final device = _device;
    if (device != null) {
      await device.setBuffering(mode, size > 0 ? size : null);
    }

    return true;
  }

  Future<int?> getSize() async {
    final wasOpen = isOpen;
    if (!wasOpen) {
      final opened = await open('r');
      if (!opened) {
        throw StateError('Could not open file.');
      }
    }

    try {
      final openedPath = _openedPath;
      if (openedPath != null) {
        return state.adapter.fileSize(openedPath);
      }

      return (await state.getInfo(
        filename,
        filterType: LoveFilesystemNodeType.file,
      ))?.size;
    } finally {
      if (!wasOpen) {
        await close();
      }
    }
  }
}

class LoveFilesystemDroppedFile extends LoveFilesystemFile {
  LoveFilesystemDroppedFile({required super.state, required String filename})
    : super(filename: path.normalize(filename));

  String get physicalPath => filename;

  @override
  Future<bool> open(String mode) async {
    if (mode == 'c') {
      return true;
    }

    if (isOpen) {
      return false;
    }

    late final IODevice device;
    if (mode == 'r') {
      if (!await state.adapter.fileExists(physicalPath)) {
        throw StateError('Could not open file $physicalPath. Does not exist.');
      }
      device = await _openFilesystemDeviceOrThrow(
        state.adapter,
        physicalPath,
        mode,
        logicalPath: physicalPath,
      );
    } else {
      device = await _openFilesystemDeviceOrThrow(
        state.adapter,
        physicalPath,
        mode,
        logicalPath: physicalPath,
      );
    }

    await device.setBuffering(bufferMode, bufferSize > 0 ? bufferSize : null);

    _device = device;
    _mode = mode;
    _openedPath = physicalPath;
    return true;
  }

  @override
  Future<int?> getSize() async {
    final wasOpen = isOpen;
    if (!wasOpen) {
      final opened = await open('r');
      if (!opened) {
        throw StateError('Could not open file.');
      }
    }

    try {
      return state.adapter.fileSize(physicalPath);
    } finally {
      if (!wasOpen) {
        await close();
      }
    }
  }
}

class _LoveFilesystemVirtualNode {
  _LoveFilesystemVirtualNode.file({required List<int> bytes, this.modtime})
    : type = LoveFilesystemNodeType.file,
      bytes = List<int>.unmodifiable(bytes);

  const _LoveFilesystemVirtualNode.directory({this.modtime})
    : type = LoveFilesystemNodeType.directory,
      bytes = null;

  final LoveFilesystemNodeType type;
  final List<int>? bytes;
  final DateTime? modtime;

  int? get size => bytes?.length;
}

class _LoveFilesystemRoot {
  _LoveFilesystemRoot.physical({
    required this.key,
    required this.physicalRoot,
    required this.mountpoint,
    required this.realDirectory,
  }) : virtualNodes = null;

  _LoveFilesystemRoot.virtual({
    required this.key,
    required this.mountpoint,
    required this.realDirectory,
    required Map<String, _LoveFilesystemVirtualNode> virtualNodes,
  }) : physicalRoot = null,
       virtualNodes = Map<String, _LoveFilesystemVirtualNode>.unmodifiable(
         virtualNodes,
       );

  final String key;
  final String? physicalRoot;
  final String mountpoint;
  final String? realDirectory;
  final Map<String, _LoveFilesystemVirtualNode>? virtualNodes;

  bool get isVirtual => virtualNodes != null;

  bool appliesTo(String logicalPath) {
    if (mountpoint.isEmpty) {
      return true;
    }

    return logicalPath == mountpoint || logicalPath.startsWith('$mountpoint/');
  }

  String relativePathFor(String logicalPath) {
    if (mountpoint.isEmpty) {
      return logicalPath;
    }

    if (logicalPath == mountpoint) {
      return '';
    }

    return logicalPath.substring(mountpoint.length + 1);
  }

  String? physicalPathFor(String relativePath) {
    final root = physicalRoot;
    if (root == null) {
      return null;
    }

    return _joinPhysicalPath(root, relativePath);
  }

  _LoveFilesystemVirtualNode? virtualNodeFor(String relativePath) {
    return virtualNodes?[relativePath];
  }

  List<String> listVirtualDirectory(String relativePath) {
    final nodes = virtualNodes;
    if (nodes == null) {
      return const <String>[];
    }

    final prefix = relativePath.isEmpty ? '' : '$relativePath/';
    final items = <String>{};
    for (final key in nodes.keys) {
      if (key == relativePath || !key.startsWith(prefix)) {
        continue;
      }

      final remainder = key.substring(prefix.length);
      if (remainder.isEmpty) {
        continue;
      }

      items.add(remainder.split('/').first);
    }

    final sorted = items.toList()..sort();
    return sorted;
  }
}

class _LoveResolvedPath {
  const _LoveResolvedPath({
    required this.root,
    required this.relativePath,
    required this.realDirectory,
    this.physicalPath,
  });

  final _LoveFilesystemRoot root;
  final String relativePath;
  final String? realDirectory;
  final String? physicalPath;

  Future<bool> exists(LoveFilesystemAdapter adapter) async {
    if (root.isVirtual) {
      return root.virtualNodeFor(relativePath) != null;
    }

    final candidatePath = physicalPath;
    if (candidatePath == null) {
      return false;
    }

    return await adapter.fileExists(candidatePath) ||
        await adapter.directoryExists(candidatePath);
  }

  Future<LoveFilesystemInfo?> getInfo(LoveFilesystemAdapter adapter) async {
    if (root.isVirtual) {
      final node = root.virtualNodeFor(relativePath);
      if (node == null) {
        return null;
      }

      return LoveFilesystemInfo(
        type: node.type,
        size: node.size,
        modtime: _secondsSinceEpoch(node.modtime),
      );
    }

    final candidatePath = physicalPath;
    if (candidatePath == null) {
      return null;
    }

    if (await adapter.fileExists(candidatePath)) {
      return LoveFilesystemInfo(
        type: LoveFilesystemNodeType.file,
        size: await adapter.fileSize(candidatePath),
        modtime: _secondsSinceEpoch(await adapter.modified(candidatePath)),
      );
    }

    if (await adapter.directoryExists(candidatePath)) {
      return LoveFilesystemInfo(
        type: LoveFilesystemNodeType.directory,
        modtime: _secondsSinceEpoch(await adapter.modified(candidatePath)),
      );
    }

    return null;
  }

  Future<List<String>?> listDirectory(LoveFilesystemAdapter adapter) async {
    if (root.isVirtual) {
      final node = root.virtualNodeFor(relativePath);
      if (node == null || node.type != LoveFilesystemNodeType.directory) {
        return null;
      }

      return root.listVirtualDirectory(relativePath);
    }

    final candidatePath = physicalPath;
    if (candidatePath == null ||
        !await adapter.directoryExists(candidatePath)) {
      return null;
    }

    final entries = await adapter.listDirectory(candidatePath);
    return entries.map(path.basename).toList(growable: false);
  }

  Future<List<int>?> readFileBytes(LoveFilesystemAdapter adapter) async {
    if (root.isVirtual) {
      final node = root.virtualNodeFor(relativePath);
      if (node == null || node.type != LoveFilesystemNodeType.file) {
        return null;
      }

      return List<int>.from(node.bytes!);
    }

    final candidatePath = physicalPath;
    if (candidatePath == null) {
      return null;
    }

    return adapter.readFileBytes(candidatePath);
  }

  Future<String?> resolveExistingPhysicalPath(
    LoveFilesystemAdapter adapter,
  ) async {
    final candidatePath = physicalPath;
    if (candidatePath == null) {
      return null;
    }

    if (await adapter.fileExists(candidatePath) ||
        await adapter.directoryExists(candidatePath)) {
      return candidatePath;
    }

    return null;
  }

  Future<_LoveReadableHandle?> openReadable(
    LoveFilesystemAdapter adapter,
  ) async {
    if (root.isVirtual) {
      final node = root.virtualNodeFor(relativePath);
      if (node == null || node.type != LoveFilesystemNodeType.file) {
        return null;
      }

      return _LoveReadableHandle(
        device: LoveReadonlyBytesIODevice(node.bytes!),
      );
    }

    final candidatePath = physicalPath;
    if (candidatePath == null || !await adapter.fileExists(candidatePath)) {
      return null;
    }

    return _LoveReadableHandle(
      device: await _openFilesystemDeviceOrThrow(
        adapter,
        candidatePath,
        'r',
        logicalPath: relativePath,
      ),
      path: candidatePath,
    );
  }
}

class LoveFilesystemState {
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
  final Map<String, int> _openPathCounts = <String, int>{};
  final Set<String> _allowedMountPaths = <String>{};

  bool _initialized = false;
  bool _symlinksEnabled = true;
  bool _androidSaveExternal = false;
  bool _fused = false;
  bool _fusedSet = false;
  String _identity = '';
  String _source = '';
  List<String> _requirePath = loveFilesystemDefaultRequirePath.split(';');
  List<String> _cRequirePath = loveFilesystemDefaultCRequirePath.split(';');

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

  static LoveFilesystemState of(LuaRuntime runtime) {
    return _states[runtime] ?? attach(runtime);
  }

  LoveFilesystemAdapter get adapter => _adapter;

  bool get initialized => _initialized;

  bool get symlinksEnabled => _symlinksEnabled;

  bool get androidSaveExternal => _androidSaveExternal;

  bool get fused => _fused;

  String get identity => _identity;

  String get source => _source;

  List<String> get requirePath => List<String>.unmodifiable(_requirePath);

  List<String> get cRequirePath => List<String>.unmodifiable(_cRequirePath);

  void replaceAdapter(LoveFilesystemAdapter adapter) {
    _adapter = adapter;
  }

  void init([String? arg0]) {
    _initialized = true;
    _symlinksEnabled = true;
  }

  void setFused(bool fused) {
    if (_fusedSet) {
      return;
    }
    _fused = fused;
    _fusedSet = true;
  }

  void setAndroidSaveExternal(bool useExternal) {
    _androidSaveExternal = useExternal;
  }

  void setSymlinksEnabled(bool enabled) {
    _symlinksEnabled = enabled;
  }

  void allowMountingForPath(String physicalPath) {
    final normalized = path.normalize(physicalPath);
    if (normalized.isEmpty || normalized == '.') {
      return;
    }

    _allowedMountPaths.add(normalized);
  }

  bool setIdentity(String value, {bool appendToPath = false}) {
    _identity = value;
    final saveDirectory = getSaveDirectory();
    if (saveDirectory.isEmpty) {
      return false;
    }

    _replaceRoot(
      _LoveFilesystemRoot.physical(
        key: '__save__',
        physicalRoot: saveDirectory,
        mountpoint: '',
        realDirectory: saveDirectory,
      ),
      append: appendToPath,
    );
    return true;
  }

  bool setSource(String value) {
    if (_source.isNotEmpty) {
      return false;
    }

    final normalized = path.normalize(value);
    final cachedRoot = _resolvedSourceRoot(normalized);
    if (cachedRoot != null) {
      _source = normalized;
      _replaceRoot(cachedRoot, append: true);
      return true;
    }

    if (_looksLikeArchivePath(normalized)) {
      return false;
    }

    _source = normalized;
    final physicalRoot = _sourcePhysicalRoot(normalized);
    _replaceRoot(
      _LoveFilesystemRoot.physical(
        key: '__source__',
        physicalRoot: physicalRoot,
        mountpoint: '',
        realDirectory: physicalRoot,
      ),
      append: true,
    );
    return true;
  }

  Future<bool> setSourceFromFilesystem(String value) async {
    if (_source.isNotEmpty) {
      return false;
    }

    final normalized = path.normalize(value);
    final root = await _sourceRootFromFilesystem(normalized);
    if (root == null) {
      return false;
    }

    if (root.isVirtual) {
      _cacheResolvedSourceRoot(normalized, root);
    }

    _source = normalized;
    _replaceRoot(root, append: true);
    return true;
  }

  void setRequirePath(String value) {
    _requirePath = _splitPathTemplates(value);
  }

  void setCRequirePath(String value) {
    _cRequirePath = _splitPathTemplates(value);
  }

  String getRequirePathString() => _requirePath.join(';');

  String getCRequirePathString() => _cRequirePath.join(';');

  String getWorkingDirectory() => adapter.workingDirectory ?? '';

  String getUserDirectory() => adapter.userDirectory ?? '';

  String getAppdataDirectory() => adapter.appdataDirectory ?? '';

  String getExecutablePath() => adapter.executablePath ?? '';

  String getSaveDirectory() {
    final baseDirectory = getAppdataDirectory();
    if (baseDirectory.isEmpty) {
      return '';
    }

    final folder = _loveAppdataFolderName();
    if (_fused) {
      return path.normalize(path.join(baseDirectory, _identity));
    }

    return path.normalize(path.join(baseDirectory, folder, _identity));
  }

  String getSourceBaseDirectory() {
    if (_source.isEmpty) {
      return '';
    }

    final normalizedSource = _source.replaceAll('\\', '/');
    final trimmedSource =
        normalizedSource.length > 1 && normalizedSource.endsWith('/')
        ? normalizedSource.substring(0, normalizedSource.length - 1)
        : normalizedSource;
    final lastSeparator = trimmedSource.lastIndexOf('/');
    if (lastSeparator < 0) {
      return '';
    }
    if (lastSeparator == 0) {
      return '/';
    }

    return trimmedSource.substring(0, lastSeparator);
  }

  Future<bool> mount(
    String archive, {
    required String mountpoint,
    bool appendToPath = false,
  }) async {
    if (_isUnsafeMountArchivePath(archive)) {
      return false;
    }

    final normalizedMountpoint = _normalizeLogicalPath(mountpoint);
    final resolvedArchive = await _resolveMountArchivePath(archive);
    if (resolvedArchive == null) {
      return false;
    }

    if (!_isAbsoluteFilesystemPath(archive) &&
        _isInPhysicalSourceRoot(resolvedArchive)) {
      return false;
    }

    final key = 'mount::$resolvedArchive';
    if (_hasRoot(key)) {
      return true;
    }

    if (await adapter.directoryExists(resolvedArchive)) {
      _replaceRoot(
        _LoveFilesystemRoot.physical(
          key: key,
          physicalRoot: resolvedArchive,
          mountpoint: normalizedMountpoint,
          realDirectory: resolvedArchive,
        ),
        append: appendToPath,
      );
      return true;
    }

    if (!await adapter.fileExists(resolvedArchive)) {
      return false;
    }

    final bytes = await _readPhysicalBytesIfPresent(resolvedArchive);
    final nodes = bytes == null
        ? null
        : _decodeArchiveNodes(bytes, archiveName: resolvedArchive);
    if (nodes == null) {
      return false;
    }

    _replaceRoot(
      _LoveFilesystemRoot.virtual(
        key: key,
        mountpoint: normalizedMountpoint,
        realDirectory: resolvedArchive,
        virtualNodes: nodes,
      ),
      append: appendToPath,
    );
    return true;
  }

  Future<bool> mountArchiveBytes(
    List<int> bytes, {
    required Object sourceIdentity,
    required String archiveName,
    required String mountpoint,
    bool appendToPath = false,
  }) async {
    final nodes = _decodeArchiveNodes(bytes, archiveName: archiveName);
    if (nodes == null) {
      return false;
    }

    final normalizedMountpoint = _normalizeLogicalPath(mountpoint);
    final key = _dataMountKey(archiveName);
    if (_hasRoot(key)) {
      final previousSourceIdentity = _dataMountSources[key];
      if (previousSourceIdentity != null &&
          !identical(previousSourceIdentity, sourceIdentity)) {
        _detachDataMountKey(previousSourceIdentity, key);
      }

      final sourceKeys = _dataMountKeys[sourceIdentity] ??= <String>[];
      if (!sourceKeys.contains(key)) {
        sourceKeys.add(key);
      }
      _dataMountSources[key] = sourceIdentity;
      return true;
    }

    final sourceKeys = _dataMountKeys[sourceIdentity] ??= <String>[];
    if (!sourceKeys.contains(key)) {
      sourceKeys.add(key);
    }
    _dataMountSources[key] = sourceIdentity;

    _replaceRoot(
      _LoveFilesystemRoot.virtual(
        key: key,
        mountpoint: normalizedMountpoint,
        realDirectory: null,
        virtualNodes: nodes,
      ),
      append: appendToPath,
    );
    return true;
  }

  Future<bool> unmount(String archive) async {
    if (_isUnsafeMountArchivePath(archive)) {
      return false;
    }

    final normalizedArchive = path.normalize(archive);
    if (_removeDataMountByKey(_dataMountKey(normalizedArchive))) {
      return true;
    }

    if (_removeRoot('mount::$normalizedArchive')) {
      return true;
    }

    final resolvedArchive = await _resolveMountArchivePath(archive);
    if (resolvedArchive != null &&
        _removeRoot('mount::${path.normalize(resolvedArchive)}')) {
      return true;
    }

    return false;
  }

  bool unmountData(Object sourceIdentity) {
    final keys = _dataMountKeys[sourceIdentity];
    if (keys == null || keys.isEmpty) {
      return false;
    }

    final key = (keys.toList()..sort()).first;
    return _removeDataMountByKey(key);
  }

  Future<String?> getRealDirectory(String logicalPath) async {
    final normalized = _normalizeLogicalPath(logicalPath);

    for (final candidate in await _readCandidates(normalized)) {
      if (await candidate.exists(adapter)) {
        return candidate.realDirectory;
      }
    }

    final projectedRoot = _projectedRoot(normalized);
    return projectedRoot?.realDirectory;
  }

  Future<LoveFilesystemInfo?> getInfo(
    String logicalPath, {
    LoveFilesystemNodeType? filterType,
  }) async {
    final normalized = _normalizeLogicalPath(logicalPath);

    for (final candidate in await _readCandidates(normalized)) {
      final info = await candidate.getInfo(adapter);
      if (info != null) {
        if (filterType == null || filterType == info.type) {
          return info;
        }
        return null;
      }
    }

    if (_isProjectedDirectory(normalized)) {
      final info = const LoveFilesystemInfo(
        type: LoveFilesystemNodeType.directory,
      );
      if (filterType == null || filterType == info.type) {
        return info;
      }
    }

    return null;
  }

  Future<List<String>> getDirectoryItems(String logicalPath) async {
    final normalized = _normalizeLogicalPath(logicalPath);
    final items = <String>{..._projectedEntries(normalized)};

    for (final candidate in await _readCandidates(normalized)) {
      final entries = await candidate.listDirectory(adapter);
      if (entries == null) {
        continue;
      }
      for (final entry in entries) {
        items.add(entry);
      }
    }

    final sorted = items.toList()..sort();
    return sorted;
  }

  Future<bool> createDirectory(String logicalPath) async {
    final targetPath = await resolveWritablePhysicalPath(logicalPath);
    if (targetPath == null) {
      return false;
    }

    if (await _hasFileAncestorInSaveDirectory(targetPath) ||
        await adapter.fileExists(targetPath) ||
        await adapter.directoryExists(targetPath)) {
      return false;
    }

    return adapter.createDirectory(targetPath, recursive: true);
  }

  Future<bool> remove(String logicalPath) async {
    final targetPath = await resolveWritablePhysicalPath(logicalPath);
    if (targetPath == null) {
      return false;
    }

    if (_openPathCounts.containsKey(path.normalize(targetPath))) {
      return false;
    }

    return adapter.deletePath(targetPath, recursive: false);
  }

  Future<List<int>?> readAllBytes(String logicalPath, {int size = -1}) async {
    return readAllBytesIfExistsOrThrow(logicalPath, size: size);
  }

  Future<bool> writeBytes(
    String logicalPath,
    List<int> bytes, {
    required bool append,
  }) async {
    try {
      await writeBytesOrThrow(logicalPath, bytes, append: append);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> writeBytesOrThrow(
    String logicalPath,
    List<int> bytes, {
    required bool append,
  }) async {
    final targetPath = await resolveWritablePhysicalPath(logicalPath);
    if (targetPath == null) {
      throw StateError('Could not set write directory.');
    }

    if (!await _ensureSaveDirectoryExists()) {
      throw StateError('Could not set write directory.');
    }

    final parent = path.dirname(targetPath);
    final saveDirectory = getSaveDirectory();
    if (path.normalize(parent) != path.normalize(saveDirectory) &&
        !await adapter.directoryExists(parent)) {
      throw StateError('Could not open file $logicalPath.');
    }

    final device = await _openFilesystemDeviceOrThrow(
      adapter,
      targetPath,
      append ? 'a' : 'w',
      logicalPath: logicalPath,
    );
    try {
      final result = await device.writeBytes(bytes);
      if (!result.success) {
        throw StateError(result.error ?? 'Data could not be written.');
      }
      await device.flush();
    } finally {
      await device.close();
    }
  }

  Future<LoveFilesystemFileData?> readFileData(
    String logicalPath, {
    int size = -1,
    String? filename,
  }) async {
    final bytes = await readAllBytesIfExistsOrThrow(logicalPath, size: size);
    if (bytes == null) {
      return null;
    }

    return LoveFilesystemFileData(
      bytes: bytes,
      filename: filename ?? logicalPath,
    );
  }

  Future<LoveFilesystemFileData?> readFileDataIfExistsOrThrow(
    String logicalPath, {
    int size = -1,
    String? filename,
  }) async {
    final bytes = await readAllBytesIfExistsOrThrow(logicalPath, size: size);
    if (bytes == null) {
      return null;
    }

    return LoveFilesystemFileData(
      bytes: bytes,
      filename: filename ?? logicalPath,
    );
  }

  Future<LoveFilesystemFileData> readFileDataOrThrow(
    String logicalPath, {
    int size = -1,
    String? filename,
  }) async {
    final bytes = await readAllBytesOrThrow(logicalPath, size: size);
    return LoveFilesystemFileData(
      bytes: bytes,
      filename: filename ?? logicalPath,
    );
  }

  Future<String?> resolveReadablePhysicalPath(String logicalPath) async {
    final normalized = _normalizeLogicalPath(logicalPath);
    for (final candidate in await _readCandidates(normalized)) {
      final candidatePath = await candidate.resolveExistingPhysicalPath(
        adapter,
      );
      if (candidatePath != null) {
        return candidatePath;
      }
    }

    return null;
  }

  Future<String?> _resolveMountArchivePath(String archive) async {
    final normalizedArchive = path.normalize(archive);

    if (_allowedMountPaths.contains(normalizedArchive)) {
      return normalizedArchive;
    }

    if (fused &&
        normalizedArchive == path.normalize(getSourceBaseDirectory())) {
      return normalizedArchive;
    }

    if (_isAbsoluteFilesystemPath(normalizedArchive)) {
      return null;
    }

    final realDirectory = await getRealDirectory(normalizedArchive);
    if (realDirectory == null || realDirectory.isEmpty) {
      return null;
    }

    final resolvedArchive = path.normalize(
      path.join(realDirectory, _logicalToPlatformPath(normalizedArchive)),
    );

    if (await adapter.fileExists(resolvedArchive) ||
        await adapter.directoryExists(resolvedArchive)) {
      return resolvedArchive;
    }

    return null;
  }

  bool _isInPhysicalSourceRoot(String physicalPath) {
    final sourceRoot = _currentPhysicalSourceRoot();
    if (sourceRoot == null || sourceRoot.isEmpty) {
      return false;
    }

    final normalizedSourceRoot = path.normalize(sourceRoot);
    final normalizedPhysicalPath = path.normalize(physicalPath);
    return normalizedPhysicalPath == normalizedSourceRoot ||
        path.isWithin(normalizedSourceRoot, normalizedPhysicalPath);
  }

  String? _currentPhysicalSourceRoot() {
    for (final root in _roots) {
      if (root.key == '__source__' && root.physicalRoot != null) {
        return root.physicalRoot;
      }
    }

    return null;
  }

  Future<_LoveReadableHandle?> _openReadable(String logicalPath) async {
    final normalized = _normalizeLogicalPath(logicalPath);
    for (final candidate in await _readCandidates(normalized)) {
      final readable = await candidate.openReadable(adapter);
      if (readable != null) {
        return readable;
      }
    }

    return null;
  }

  Future<_LoveFilesystemRoot?> _sourceRootFromFilesystem(
    String normalizedSource,
  ) async {
    if (await adapter.directoryExists(normalizedSource)) {
      return _LoveFilesystemRoot.physical(
        key: '__source__',
        physicalRoot: normalizedSource,
        mountpoint: '',
        realDirectory: normalizedSource,
      );
    }

    if (await adapter.fileExists(normalizedSource)) {
      final bytes = await _readPhysicalBytesIfPresent(normalizedSource);
      if (bytes != null) {
        final nodes = _decodeArchiveNodes(bytes, archiveName: normalizedSource);
        if (nodes != null) {
          return _LoveFilesystemRoot.virtual(
            key: '__source__',
            mountpoint: '',
            realDirectory: normalizedSource,
            virtualNodes: nodes,
          );
        }
      }

      if (_looksLikeArchivePath(normalizedSource)) {
        return null;
      }

      return null;
    }

    return null;
  }

  Future<String?> resolveWritablePhysicalPath(String logicalPath) async {
    final saveDirectory = getSaveDirectory();
    if (saveDirectory.isEmpty) {
      return null;
    }

    final normalized = _normalizeLogicalPath(logicalPath);
    final platformRelative = normalized.isEmpty
        ? ''
        : path.joinAll(normalized.split('/'));
    final resolved = normalized.isEmpty
        ? saveDirectory
        : path.normalize(path.join(saveDirectory, platformRelative));

    if (resolved != saveDirectory && !path.isWithin(saveDirectory, resolved)) {
      return null;
    }

    return resolved;
  }

  Future<bool> _ensureSaveDirectoryExists() async {
    final saveDirectory = getSaveDirectory();
    if (saveDirectory.isEmpty) {
      return false;
    }

    return adapter.createDirectory(saveDirectory, recursive: true);
  }

  Future<bool> _hasFileAncestorInSaveDirectory(String targetPath) async {
    final saveDirectory = path.normalize(getSaveDirectory());
    var current = path.normalize(path.dirname(targetPath));

    while (current.isNotEmpty &&
        current != '.' &&
        current != saveDirectory &&
        path.isWithin(saveDirectory, current)) {
      if (await adapter.fileExists(current)) {
        return true;
      }

      final parent = path.dirname(current);
      if (parent == current) {
        break;
      }
      current = parent;
    }

    return false;
  }

  Future<_LoveResolvedPath?> _readableFileCandidate(String logicalPath) async {
    final normalized = _normalizeLogicalPath(logicalPath);
    for (final candidate in await _readCandidates(normalized)) {
      if (candidate.root.isVirtual) {
        final node = candidate.root.virtualNodeFor(candidate.relativePath);
        if (node != null && node.type == LoveFilesystemNodeType.file) {
          return candidate;
        }
        continue;
      }

      final candidatePath = candidate.physicalPath;
      if (candidatePath != null && await adapter.fileExists(candidatePath)) {
        return candidate;
      }
    }

    return null;
  }

  Future<List<int>> _readCandidateBytesOrThrow(
    _LoveResolvedPath candidate, {
    required String logicalPath,
    required int size,
  }) async {
    if (candidate.root.isVirtual) {
      final node = candidate.root.virtualNodeFor(candidate.relativePath);
      if (node == null || node.type != LoveFilesystemNodeType.file) {
        throw StateError('Could not open file $logicalPath. Does not exist.');
      }

      final bytes = List<int>.from(node.bytes!);
      if (size >= 0 && bytes.length > size) {
        return bytes.sublist(0, size);
      }
      return bytes;
    }

    final candidatePath = candidate.physicalPath;
    if (candidatePath == null || !await adapter.fileExists(candidatePath)) {
      throw StateError('Could not open file $logicalPath. Does not exist.');
    }

    try {
      final bytes = await adapter.readFileBytes(candidatePath);
      if (bytes != null) {
        if (size >= 0 && bytes.length > size) {
          return bytes.sublist(0, size);
        }
        return bytes;
      }
    } catch (_) {
      // Fall through to the IODevice path below so we can surface a LOVE-style
      // open/read error instead of a raw adapter exception.
    }

    final device = await _openFilesystemDeviceOrThrow(
      adapter,
      candidatePath,
      'r',
      logicalPath: logicalPath,
    );
    try {
      final result = await device.read(size < 0 ? 'a' : '$size');
      if (!result.isSuccess) {
        throw StateError(result.error ?? 'Could not read from file.');
      }

      return _bytesFromIODeviceValue(result.value);
    } finally {
      await device.close();
    }
  }

  Future<List<int>?> _readPhysicalBytesIfPresent(String physicalPath) async {
    try {
      final bytes = await adapter.readFileBytes(physicalPath);
      if (bytes != null) {
        return bytes;
      }
    } catch (_) {
      // Fall through to the IODevice path below so archive mounts can still
      // succeed when direct byte reads are unavailable in the adapter.
    }

    late final IODevice device;
    try {
      device = await _openFilesystemDeviceOrThrow(
        adapter,
        physicalPath,
        'r',
        logicalPath: physicalPath,
      );
    } on StateError {
      return null;
    }

    try {
      final result = await device.read('a');
      if (!result.isSuccess) {
        return null;
      }
      return _bytesFromIODeviceValue(result.value);
    } finally {
      await device.close();
    }
  }

  Future<List<int>?> readAllBytesIfExistsOrThrow(
    String logicalPath, {
    int size = -1,
  }) async {
    final candidate = await _readableFileCandidate(logicalPath);
    if (candidate == null) {
      return null;
    }

    return _readCandidateBytesOrThrow(
      candidate,
      logicalPath: logicalPath,
      size: size,
    );
  }

  Future<List<int>> readAllBytesOrThrow(
    String logicalPath, {
    int size = -1,
  }) async {
    final bytes = await readAllBytesIfExistsOrThrow(logicalPath, size: size);
    if (bytes == null) {
      throw StateError('Could not open file $logicalPath. Does not exist.');
    }

    return bytes;
  }

  Future<Value?> loadChunk(LuaRuntime runtime, String logicalPath) async {
    final bytes = await readAllBytesOrThrow(logicalPath);

    final result = await runtime.loadChunk(
      LuaChunkLoadRequest(
        source: runtime.constantStringValue(bytes),
        chunkName: '@$logicalPath',
      ),
    );
    if (!result.isSuccess) {
      throw LuaError(formatLoveFilesystemLoadSyntaxError(result.errorMessage));
    }
    return result.chunk;
  }

  void _replaceRoot(_LoveFilesystemRoot root, {required bool append}) {
    _removeRoot(root.key);
    if (append) {
      _roots.add(root);
    } else {
      _roots.insert(0, root);
    }
  }

  bool _hasRoot(String key) {
    return _roots.any((root) => root.key == key);
  }

  bool _removeRoot(String key) {
    final before = _roots.length;
    _roots.removeWhere((root) => root.key == key);
    return _roots.length != before;
  }

  void _cacheResolvedSourceRoot(
    String normalizedSource,
    _LoveFilesystemRoot root,
  ) {
    final cache = _resolvedSourceRoots[_adapter] ??=
        <String, _LoveFilesystemRoot>{};
    cache[normalizedSource] = _cloneSourceRoot(root);
  }

  _LoveFilesystemRoot? _resolvedSourceRoot(String normalizedSource) {
    final root = _resolvedSourceRoots[_adapter]?[normalizedSource];
    if (root == null) {
      return null;
    }

    return _cloneSourceRoot(root);
  }

  _LoveFilesystemRoot _cloneSourceRoot(_LoveFilesystemRoot root) {
    if (root.isVirtual) {
      return _LoveFilesystemRoot.virtual(
        key: '__source__',
        mountpoint: '',
        realDirectory: root.realDirectory,
        virtualNodes: root.virtualNodes!,
      );
    }

    return _LoveFilesystemRoot.physical(
      key: '__source__',
      physicalRoot: root.physicalRoot!,
      mountpoint: '',
      realDirectory: root.realDirectory ?? root.physicalRoot!,
    );
  }

  String _dataMountKey(String archiveName) {
    return 'mount-data::${_normalizeDataMountArchiveName(archiveName)}';
  }

  bool _removeDataMountByKey(String key) {
    final removed = _removeRoot(key);
    if (!removed) {
      return false;
    }

    final sourceIdentity = _dataMountSources.remove(key);
    if (sourceIdentity != null) {
      _detachDataMountKey(sourceIdentity, key);
    }
    return true;
  }

  void _detachDataMountKey(Object sourceIdentity, String key) {
    final keys = _dataMountKeys[sourceIdentity];
    if (keys == null) {
      return;
    }

    keys.remove(key);
    if (keys.isEmpty) {
      _dataMountKeys.remove(sourceIdentity);
    }
  }

  void _registerOpenPath(String physicalPath) {
    final normalized = path.normalize(physicalPath);
    _openPathCounts.update(normalized, (count) => count + 1, ifAbsent: () => 1);
  }

  void _unregisterOpenPath(String physicalPath) {
    final normalized = path.normalize(physicalPath);
    final count = _openPathCounts[normalized];
    if (count == null) {
      return;
    }

    if (count <= 1) {
      _openPathCounts.remove(normalized);
      return;
    }

    _openPathCounts[normalized] = count - 1;
  }

  Future<List<_LoveResolvedPath>> _readCandidates(String logicalPath) async {
    final candidates = <_LoveResolvedPath>[];

    for (final root in _roots) {
      if (!root.appliesTo(logicalPath)) {
        continue;
      }

      final relative = root.relativePathFor(logicalPath);
      final physical = root.physicalPathFor(relative);
      candidates.add(
        _LoveResolvedPath(
          root: root,
          relativePath: relative,
          physicalPath: physical,
          realDirectory: root.realDirectory,
        ),
      );
    }

    return candidates;
  }

  bool _isProjectedDirectory(String logicalPath) {
    if (logicalPath.isEmpty) {
      return _roots.any((root) => root.mountpoint.isNotEmpty);
    }

    return _roots.any(
      (root) =>
          root.mountpoint == logicalPath ||
          root.mountpoint.startsWith('$logicalPath/'),
    );
  }

  Set<String> _projectedEntries(String logicalPath) {
    final entries = <String>{};

    for (final root in _roots) {
      final mountpoint = root.mountpoint;
      if (mountpoint.isEmpty) {
        continue;
      }

      if (logicalPath.isEmpty) {
        entries.add(mountpoint.split('/').first);
        continue;
      }

      if (!mountpoint.startsWith('$logicalPath/')) {
        continue;
      }

      final remainder = mountpoint.substring(logicalPath.length + 1);
      if (remainder.isEmpty) {
        continue;
      }

      entries.add(remainder.split('/').first);
    }

    return entries;
  }

  _LoveFilesystemRoot? _projectedRoot(String logicalPath) {
    for (final root in _roots) {
      if (root.mountpoint == logicalPath ||
          root.mountpoint.startsWith('$logicalPath/')) {
        return root;
      }
    }

    return null;
  }

  String _loveAppdataFolderName() {
    if (adapter.isWindows || adapter.isMacOS) {
      return 'LOVE';
    }

    if (adapter.isLinux) {
      return 'love';
    }

    return '.love';
  }

  String _sourcePhysicalRoot(String source) {
    final extension = path.extension(source);
    if (extension.isEmpty) {
      return source;
    }

    return path.dirname(source);
  }

  bool _looksLikeArchivePath(String input) {
    final normalized = input.toLowerCase();
    return normalized.endsWith('.love') ||
        normalized.endsWith('.zip') ||
        normalized.endsWith('.tar') ||
        normalized.endsWith('.tgz') ||
        normalized.endsWith('.tar.gz') ||
        normalized.endsWith('.tbz') ||
        normalized.endsWith('.tbz2') ||
        normalized.endsWith('.tar.bz2') ||
        normalized.endsWith('.txz') ||
        normalized.endsWith('.tar.xz');
  }

  bool _isAbsoluteFilesystemPath(String input) {
    final normalized = input.replaceAll('\\', '/');
    return path.posix.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
  }

  bool _isUnsafeMountArchivePath(String input) {
    if (input.isEmpty || input == '/') {
      return true;
    }

    return input.replaceAll('\\', '/').contains('..');
  }

  String _normalizeDataMountArchiveName(String archiveName) {
    if (archiveName.isEmpty) {
      return '';
    }

    final normalized = path.normalize(archiveName);
    return normalized == '.' ? archiveName : normalized;
  }
}

Map<String, _LoveFilesystemVirtualNode>? _decodeArchiveNodes(
  List<int> bytes, {
  String? archiveName,
}) {
  for (final decoder in _archiveDecodersFor(bytes, archiveName: archiveName)) {
    try {
      final archive = decoder(bytes);
      if (archive == null || archive.isEmpty) {
        continue;
      }

      return _archiveNodesFromArchive(archive);
    } catch (_) {
      continue;
    }
  }

  return null;
}

Map<String, _LoveFilesystemVirtualNode> _archiveNodesFromArchive(
  Archive archive,
) {
  final nodes = <String, _LoveFilesystemVirtualNode>{
    '': const _LoveFilesystemVirtualNode.directory(),
  };

  for (final entry in archive) {
    if (entry.isSymbolicLink) {
      continue;
    }

    final normalized = _normalizeArchiveEntry(entry.name);
    if (normalized.isEmpty) {
      continue;
    }

    final modtime = _archiveEntryModtime(entry);
    _insertVirtualParents(nodes, normalized, modtime: modtime);

    if (entry.isDirectory) {
      nodes.putIfAbsent(
        normalized,
        () => _LoveFilesystemVirtualNode.directory(modtime: modtime),
      );
      continue;
    }

    nodes[normalized] = _LoveFilesystemVirtualNode.file(
      bytes: entry.readBytes() ?? entry.content,
      modtime: modtime,
    );
  }

  return nodes;
}

Iterable<Archive? Function(List<int> bytes)> _archiveDecodersFor(
  List<int> bytes, {
  String? archiveName,
}) sync* {
  final normalizedName = archiveName?.toLowerCase();
  final preferGzipTar =
      normalizedName?.endsWith('.tar.gz') == true ||
      normalizedName?.endsWith('.tgz') == true;
  final preferBzipTar =
      normalizedName?.endsWith('.tar.bz2') == true ||
      normalizedName?.endsWith('.tbz') == true ||
      normalizedName?.endsWith('.tbz2') == true;
  final preferXzTar =
      normalizedName?.endsWith('.tar.xz') == true ||
      normalizedName?.endsWith('.txz') == true;
  final preferTar = normalizedName?.endsWith('.tar') == true;
  final preferZip =
      normalizedName?.endsWith('.zip') == true ||
      normalizedName?.endsWith('.love') == true;

  if (preferGzipTar) {
    yield _decodeGzipTarArchive;
  }
  if (preferBzipTar) {
    yield _decodeBzipTarArchive;
  }
  if (preferXzTar) {
    yield _decodeXzTarArchive;
  }
  if (preferTar) {
    yield _decodeTarArchiveLenient;
  }
  if (preferZip) {
    yield _decodeZipArchive;
    yield _decodePrefixedZipArchive;
  }

  if (_looksLikeZipArchive(bytes) && !preferZip) {
    yield _decodeZipArchive;
  }
  if (_hasPrefixedZipArchive(bytes) && !preferZip) {
    yield _decodePrefixedZipArchive;
  }
  if (_looksLikeGzipArchive(bytes) && !preferGzipTar) {
    yield _decodeGzipTarArchive;
  }
  if (_looksLikeBzipArchive(bytes) && !preferBzipTar) {
    yield _decodeBzipTarArchive;
  }
  if (_looksLikeXzArchive(bytes) && !preferXzTar) {
    yield _decodeXzTarArchive;
  }
  if (_looksLikeTarArchive(bytes) && !preferTar) {
    yield _decodeTarArchive;
  }
}

Archive? _decodeZipArchive(List<int> bytes) {
  if (!_looksLikeZipArchive(bytes)) {
    return null;
  }

  return ZipDecoder().decodeBytes(bytes);
}

Archive? _decodePrefixedZipArchive(List<int> bytes) {
  for (final offset in _prefixedZipArchiveOffsets(bytes)) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes.sublist(offset));
      if (archive.isNotEmpty) {
        return archive;
      }
    } catch (_) {
      continue;
    }
  }

  return null;
}

Archive? _decodeTarArchive(List<int> bytes) {
  if (!_looksLikeTarArchive(bytes)) {
    return null;
  }

  return TarDecoder().decodeBytes(bytes);
}

Archive? _decodeTarArchiveLenient(List<int> bytes) {
  if (bytes.length < 512) {
    return null;
  }

  return TarDecoder().decodeBytes(bytes);
}

Archive? _decodeGzipTarArchive(List<int> bytes) {
  if (!_looksLikeGzipArchive(bytes)) {
    return null;
  }

  return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
}

Archive? _decodeBzipTarArchive(List<int> bytes) {
  if (!_looksLikeBzipArchive(bytes)) {
    return null;
  }

  return TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
}

Archive? _decodeXzTarArchive(List<int> bytes) {
  if (!_looksLikeXzArchive(bytes)) {
    return null;
  }

  return TarDecoder().decodeBytes(XZDecoder().decodeBytes(bytes));
}

bool _looksLikeZipArchive(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
}

bool _hasPrefixedZipArchive(List<int> bytes) {
  for (final _ in _prefixedZipArchiveOffsets(bytes)) {
    return true;
  }

  return false;
}

Iterable<int> _prefixedZipArchiveOffsets(List<int> bytes) sync* {
  for (var i = 1; i <= bytes.length - 4; i++) {
    if (bytes[i] != 0x50 || bytes[i + 1] != 0x4b) {
      continue;
    }

    if (bytes[i + 2] == 0x03 && bytes[i + 3] == 0x04) {
      yield i;
    }
  }
}

bool _looksLikeGzipArchive(List<int> bytes) {
  return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
}

bool _looksLikeBzipArchive(List<int> bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0x42 &&
      bytes[1] == 0x5a &&
      bytes[2] == 0x68;
}

bool _looksLikeXzArchive(List<int> bytes) {
  return bytes.length >= 6 &&
      bytes[0] == 0xfd &&
      bytes[1] == 0x37 &&
      bytes[2] == 0x7a &&
      bytes[3] == 0x58 &&
      bytes[4] == 0x5a &&
      bytes[5] == 0x00;
}

bool _looksLikeTarArchive(List<int> bytes) {
  if (bytes.length < 512) {
    return false;
  }

  final signature = String.fromCharCodes(bytes.sublist(257, 262));
  return signature == 'ustar';
}

void _insertVirtualParents(
  Map<String, _LoveFilesystemVirtualNode> nodes,
  String entryPath, {
  DateTime? modtime,
}) {
  var current = '';
  final segments = entryPath.split('/');
  for (var index = 0; index < segments.length - 1; index++) {
    current = current.isEmpty ? segments[index] : '$current/${segments[index]}';
    nodes.putIfAbsent(
      current,
      () => _LoveFilesystemVirtualNode.directory(modtime: modtime),
    );
  }
}

DateTime? _archiveEntryModtime(ArchiveFile entry) {
  try {
    return entry.lastModDateTime;
  } catch (_) {
    return null;
  }
}

String _normalizeArchiveEntry(String input) {
  final normalized = path.posix.normalize(input.replaceAll('\\', '/'));
  if (normalized == '.' || normalized == '/') {
    return '';
  }

  return normalized
      .replaceFirst(RegExp(r'^/+'), '')
      .replaceFirst(RegExp(r'/+$'), '');
}

String _logicalToPlatformPath(String logicalPath) {
  if (logicalPath.isEmpty) {
    return '';
  }

  return path.joinAll(logicalPath.split('/'));
}

String _normalizeLogicalPath(String input) {
  final normalized = path.posix.normalize(input.replaceAll('\\', '/'));
  if (normalized == '.' || normalized == '/') {
    return '';
  }

  return normalized.replaceFirst(RegExp(r'^/+'), '');
}

String _joinPhysicalPath(String basePath, String relativePath) {
  if (relativePath.isEmpty) {
    return path.normalize(basePath);
  }

  return path.normalize(
    path.join(basePath, path.joinAll(relativePath.split('/'))),
  );
}

List<String> _splitPathTemplates(String rawPath) {
  if (rawPath.isEmpty) {
    return <String>[];
  }

  final entries = rawPath.split(';');
  if (rawPath.endsWith(';')) {
    entries.removeLast();
  }
  return entries;
}

List<int> _bytesFromIODeviceValue(Object? value) {
  return switch (value) {
    null => const <int>[],
    LuaString(:final bytes) => List<int>.from(bytes),
    final String text => utf8.encode(text),
    final List<int> bytes => List<int>.from(bytes),
    _ => utf8.encode(value.toString()),
  };
}

int? _secondsSinceEpoch(DateTime? value) {
  if (value == null) {
    return null;
  }
  return value.millisecondsSinceEpoch ~/ 1000;
}
