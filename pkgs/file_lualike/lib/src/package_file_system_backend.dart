/// Adapter that bridges a [package:file] [FileSystem] into lualike's
/// [FileSystemBackend] metadata interface.
///
/// {@category Filesystem}
library;

import 'package:file/file.dart' as pkg_file;
import 'package:lualike/lualike.dart';

/// A [FileSystemBackend] that delegates all operations to a
/// [package:file] [FileSystem].
///
/// Works with any implementation — `LocalFileSystem`, `SftpFileSystem`,
/// `MemoryFileSystem`, etc. Every method returns a safe default (`false`,
/// `null`, or an empty list) instead of throwing on failure.
///
/// ```dart
/// final sftp = SftpFileSystem(...);
/// final backend = PackageFileSystemBackend(sftp);
/// setFileSystemBackend(backend);
/// ```
class PackageFileSystemBackend implements FileSystemBackend {
  /// The underlying [package:file] filesystem instance.
  final pkg_file.FileSystem fs;

  /// Creates a backend that delegates to [fs].
  PackageFileSystemBackend(this.fs);

  @override
  Future<bool> fileExists(String path) async {
    try {
      return await fs.file(path).exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> directoryExists(String path) async {
    try {
      return await fs.directory(path).exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> readFileAsString(String path) async {
    try {
      return await fs.file(path).readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<int>?> readFileAsBytes(String path) async {
    try {
      return await fs.file(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DateTime?> getLastModified(String path) async {
    try {
      return await fs.file(path).lastModified();
    } catch (_) {
      return null;
    }
  }

  @override
  String? getCurrentDirectory() {
    try {
      return fs.currentDirectory.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async {
    try {
      await fs.directory(path).create(recursive: recursive);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> writeFile(String path, String content) async {
    try {
      await fs.file(path).writeAsString(content);
    } catch (_) {}
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    try {
      final entities = await fs.directory(path).list().toList();
      return entities.map((e) => e.path).toList();
    } catch (_) {
      return <String>[];
    }
  }

  @override
  Future<int?> fileSize(String path) async {
    try {
      return await fs.file(path).length();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      final file = fs.file(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      throw Exception('Failed to delete file: $path');
    }
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async {
    try {
      final file = fs.file(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      final dir = fs.directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: recursive);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    try {
      final file = fs.file(oldPath);
      if (await file.exists()) {
        await file.rename(newPath);
      } else {
        throw Exception('File does not exist: $oldPath');
      }
    } catch (e) {
      throw Exception('Failed to rename file: $oldPath -> $newPath');
    }
  }
}
