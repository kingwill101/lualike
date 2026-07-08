/// Abstract interface for filesystem operations.
///
/// Allows plugging in custom filesystem implementations (e.g., SFTP, in-memory,
/// cloud storage) without changing the core lualike code.
abstract class FileSystemBackend {
  Future<bool> fileExists(String path);

  Future<bool> directoryExists(String path);

  Future<String?> readFileAsString(String path);

  Future<List<int>?> readFileAsBytes(String path);

  Future<DateTime?> getLastModified(String path);

  String? getCurrentDirectory();

  Future<bool> createDirectory(String path, {bool recursive = true});

  Future<void> writeFile(String path, String content);

  Future<List<String>> listDirectory(String path);

  Future<int?> fileSize(String path);

  Future<void> deleteFile(String path);

  Future<bool> deletePath(String path, {bool recursive = true});

  Future<void> renameFile(String oldPath, String newPath);
}

/// Chains multiple [FileSystemBackend] instances in priority order.
///
/// For reads ([fileExists], [readFileAsString], etc.), each backend is
/// queried in order and the first successful result is returned. For writes
/// ([writeFile], [createDirectory], etc.), all backends are tried in order
/// so the first writable backend handles the operation.
///
/// Useful on platforms where files may be spread across multiple sources —
/// for example, bundled assets plus a writable local directory.
///
/// ```dart
/// setFileSystemBackend(CompositeFileSystemBackend([
///   AssetBundleFileSystemBackend(rootBundle),
///   PackageFileSystemBackend(LocalFileSystem()),
/// ]));
/// ```
class CompositeFileSystemBackend implements FileSystemBackend {
  /// The backends in priority order (first wins for reads).
  final List<FileSystemBackend> backends;

  /// Creates a composite that tries [backends] in order.
  CompositeFileSystemBackend(this.backends);

  @override
  Future<bool> fileExists(String path) async {
    for (final backend in backends) {
      if (await backend.fileExists(path)) return true;
    }
    return false;
  }

  @override
  Future<bool> directoryExists(String path) async {
    for (final backend in backends) {
      if (await backend.directoryExists(path)) return true;
    }
    return false;
  }

  @override
  Future<String?> readFileAsString(String path) async {
    for (final backend in backends) {
      final result = await backend.readFileAsString(path);
      if (result != null) return result;
    }
    return null;
  }

  @override
  Future<List<int>?> readFileAsBytes(String path) async {
    for (final backend in backends) {
      final result = await backend.readFileAsBytes(path);
      if (result != null) return result;
    }
    return null;
  }

  @override
  Future<DateTime?> getLastModified(String path) async {
    for (final backend in backends) {
      final result = await backend.getLastModified(path);
      if (result != null) return result;
    }
    return null;
  }

  @override
  String? getCurrentDirectory() {
    for (final backend in backends) {
      final result = backend.getCurrentDirectory();
      if (result != null) return result;
    }
    return null;
  }

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async {
    for (final backend in backends) {
      if (await backend.createDirectory(path, recursive: recursive)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> writeFile(String path, String content) async {
    for (final backend in backends) {
      try {
        await backend.writeFile(path, content);
        return;
      } catch (_) {
        // try next backend
      }
    }
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    for (final backend in backends) {
      final result = await backend.listDirectory(path);
      if (result.isNotEmpty) return result;
    }
    return <String>[];
  }

  @override
  Future<int?> fileSize(String path) async {
    for (final backend in backends) {
      final result = await backend.fileSize(path);
      if (result != null) return result;
    }
    return null;
  }

  @override
  Future<void> deleteFile(String path) async {
    for (final backend in backends) {
      try {
        await backend.deleteFile(path);
        return;
      } catch (_) {
        // try next backend
      }
    }
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async {
    for (final backend in backends) {
      if (await backend.deletePath(path, recursive: recursive)) return true;
    }
    return false;
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    for (final backend in backends) {
      try {
        await backend.renameFile(oldPath, newPath);
        return;
      } catch (_) {
        // try next backend
      }
    }
  }
}
