part of 'love_filesystem_runtime.dart';

/// Host filesystem operations used by [LoveFilesystemState].
abstract interface class LoveFilesystemAdapter {
  /// The current working directory, if the host exposes one.
  String? get workingDirectory;

  /// The current user's home directory, if the host exposes one.
  String? get userDirectory;

  /// The host application data directory, if one is available.
  String? get appdataDirectory;

  /// The resolved executable path, if the host exposes one.
  String? get executablePath;

  /// Whether this host should be treated as Windows.
  bool get isWindows;

  /// Whether this host should be treated as Linux.
  bool get isLinux;

  /// Whether this host should be treated as macOS.
  bool get isMacOS;

  /// Opens [path] with the host-specific [mode].
  Future<IODevice> openFile(String path, String mode);

  /// Returns whether a file exists at [path].
  Future<bool> fileExists(String path);

  /// Returns whether a directory exists at [path].
  Future<bool> directoryExists(String path);

  /// Reads all bytes from [path].
  Future<List<int>?> readFileBytes(String path);

  /// Lists the direct entries in [path].
  Future<List<String>> listDirectory(String path);

  /// Returns the last modification time for [path], if one is available.
  Future<DateTime?> modified(String path);

  /// Returns the file size for [path], if one is available.
  Future<int?> fileSize(String path);

  /// Creates the directory at [path].
  Future<bool> createDirectory(String path, {bool recursive = true});

  /// Deletes the file or directory at [path].
  Future<bool> deletePath(String path, {bool recursive = true});
}

/// A filesystem adapter backed by LuaLike's host file APIs.
class LoveLualikeFilesystemAdapter implements LoveFilesystemAdapter {
  /// Creates a LuaLike-backed filesystem adapter.
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

  /// The host file provider used for file-opening operations.
  final FileSystemProvider _fileSystemProvider;

  /// Environment variable overrides consulted before reading the host process.
  final Map<String, String>? _environment;

  /// An optional Windows platform override for tests.
  final bool? _isWindows;

  /// An optional Linux platform override for tests.
  final bool? _isLinux;

  /// An optional macOS platform override for tests.
  final bool? _isMacOS;

  /// An optional resolved executable path override.
  final String? _resolvedExecutablePath;

  /// A working-directory override used when the host cannot be queried
  /// directly.
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

  /// Returns the environment variable named [name], honoring injected
  /// overrides first.
  String? _environmentValue(String name) {
    return _environment?[name] ?? platform_utils.getEnvironmentVariable(name);
  }

  /// Whether this adapter should behave as a Windows host.
  bool get _platformIsWindows => _isWindows ?? platform_utils.isWindows;

  /// Whether this adapter should behave as a Linux host.
  bool get _platformIsLinux => _isLinux ?? platform_utils.isLinux;

  /// Whether this adapter should behave as a macOS host.
  bool get _platformIsMacOS => _isMacOS ?? platform_utils.isMacOS;
}
