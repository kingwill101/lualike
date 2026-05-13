library;

// ignore_for_file: implementation_imports

import 'package:lualike/src/io/io_device.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'love_filesystem_runtime.dart';

/// The timeout used when querying Flutter app directories from platform APIs.
const Duration _loveFlutterDirectoryLookupTimeout = Duration(seconds: 1);

/// Flutter-specific filesystem adapter that delegates actual file IO to an
/// existing [LoveFilesystemAdapter] while exposing app-scoped directories from
/// Flutter platform APIs.
///
/// This keeps LOVE's writable save path off of implicit host environment
/// lookups and makes the storage policy explicit in Flutter apps.
class LoveFlutterFilesystemAdapter implements LoveFilesystemAdapter {
  /// Creates a filesystem adapter that exposes Flutter app directories.
  LoveFlutterFilesystemAdapter({
    LoveFilesystemAdapter? delegate,
    String? workingDirectory,
    String? userDirectory,
    String? appdataDirectory,
    String? executablePath,
  }) : _delegate = delegate ?? LoveLualikeFilesystemAdapter(),
       _workingDirectory = workingDirectory,
       _userDirectory = userDirectory,
       _appdataDirectory = appdataDirectory,
       _executablePath = executablePath;

  /// Loads directory information from Flutter platform services.
  static Future<LoveFlutterFilesystemAdapter> load({
    LoveFilesystemAdapter? delegate,
    String? workingDirectory,
    String? userDirectory,
    String? appdataDirectory,
    String? executablePath,
    PathProviderPlatform? pathProviderPlatform,
  }) async {
    final resolved =
        (workingDirectory != null &&
            userDirectory != null &&
            appdataDirectory != null)
        ? const _LoveFlutterResolvedDirectories()
        : await _resolveDirectories(pathProviderPlatform: pathProviderPlatform);

    return LoveFlutterFilesystemAdapter(
      delegate: delegate,
      workingDirectory: workingDirectory ?? resolved.workingDirectory,
      userDirectory: userDirectory ?? resolved.userDirectory,
      appdataDirectory: appdataDirectory ?? resolved.appdataDirectory,
      executablePath: executablePath,
    );
  }

  /// The adapter that performs the actual host file operations.
  final LoveFilesystemAdapter _delegate;

  /// The working directory exposed to LOVE, if one was resolved.
  final String? _workingDirectory;

  /// The user directory exposed to LOVE, if one was resolved.
  final String? _userDirectory;

  /// The app data directory exposed to LOVE, if one was resolved.
  final String? _appdataDirectory;

  /// The executable path exposed to LOVE, if one was provided.
  final String? _executablePath;

  @override
  String? get workingDirectory => _workingDirectory;

  @override
  String? get userDirectory => _userDirectory;

  @override
  String? get appdataDirectory => _appdataDirectory;

  @override
  String? get executablePath => _executablePath;

  @override
  bool get isWindows => _delegate.isWindows;

  @override
  bool get isLinux => _delegate.isLinux;

  @override
  bool get isMacOS => _delegate.isMacOS;

  @override
  Future<IODevice> openFile(String path, String mode) {
    return _delegate.openFile(path, mode);
  }

  @override
  Future<bool> fileExists(String path) => _delegate.fileExists(path);

  @override
  Future<bool> directoryExists(String path) => _delegate.directoryExists(path);

  @override
  Future<List<int>?> readFileBytes(String path) =>
      _delegate.readFileBytes(path);

  @override
  Future<List<String>> listDirectory(String path) =>
      _delegate.listDirectory(path);

  @override
  Future<DateTime?> modified(String path) => _delegate.modified(path);

  @override
  Future<int?> fileSize(String path) => _delegate.fileSize(path);

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) {
    return _delegate.createDirectory(path, recursive: recursive);
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) {
    return _delegate.deletePath(path, recursive: recursive);
  }

  /// Resolves app-scoped directories from Flutter platform services.
  static Future<_LoveFlutterResolvedDirectories> _resolveDirectories({
    PathProviderPlatform? pathProviderPlatform,
  }) async {
    final provider = pathProviderPlatform ?? PathProviderPlatform.instance;
    final results = await Future.wait<String?>(<Future<String?>>[
      _safeDirectoryPath(provider.getApplicationSupportPath),
      _safeDirectoryPath(provider.getApplicationDocumentsPath),
      _safeDirectoryPath(provider.getTemporaryPath),
    ]);
    final appSupport = results[0];
    final documents = results[1];
    final temporary = results[2];

    return _LoveFlutterResolvedDirectories(
      workingDirectory: temporary ?? appSupport,
      userDirectory: documents,
      appdataDirectory: appSupport,
    );
  }

  /// Safely loads a directory path, returning `null` on timeout or failure.
  static Future<String?> _safeDirectoryPath(
    Future<String?> Function() loader,
  ) async {
    try {
      final path = await loader().timeout(_loveFlutterDirectoryLookupTimeout);
      return path == null || path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }
}

/// The resolved Flutter app directories exposed through this filesystem adapter.
class _LoveFlutterResolvedDirectories {
  /// Creates a resolved Flutter directory bundle.
  const _LoveFlutterResolvedDirectories({
    this.workingDirectory,
    this.userDirectory,
    this.appdataDirectory,
  });

  /// The working directory that LOVE should use for relative host lookups.
  final String? workingDirectory;

  /// The user directory that LOVE should treat as the home path.
  final String? userDirectory;

  /// The app data directory that LOVE should treat as the save root parent.
  final String? appdataDirectory;
}
