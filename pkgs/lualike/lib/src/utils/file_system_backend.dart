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
