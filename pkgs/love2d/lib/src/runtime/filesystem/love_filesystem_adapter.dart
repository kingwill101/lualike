part of 'love_filesystem_runtime.dart';

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
