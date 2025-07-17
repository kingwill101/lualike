/// Web implementation of file system utilities
library;

/// Platform-safe way to check if a file exists - always false on web
Future<bool> fileExists(String path) async => false;

/// Platform-safe way to check if a directory exists - always false on web
Future<bool> directoryExists(String path) async => false;

/// Platform-safe way to read a file as string - always null on web
Future<String?> readFileAsString(String path) async => null;

/// Platform-safe way to read a file as bytes - always null on web
Future<List<int>?> readFileAsBytes(String path) async => null;

/// Platform-safe way to get current working directory - null on web
String? getCurrentDirectory() => null;

/// Platform-safe way to write a file - no-op on web
Future<void> writeFile(String path, String content) async {
  // No-op on web
}

/// Platform-safe way to list directory contents - empty list on web
Future<List<String>> listDirectory(String path) async => <String>[];

/// Platform-safe way to delete a file - not supported on web
Future<void> deleteFile(String path) async {
  throw UnsupportedError('File deletion is not supported on web platform');
}

/// Platform-safe way to rename/move a file - not supported on web
Future<void> renameFile(String oldPath, String newPath) async {
  throw UnsupportedError('File renaming is not supported on web platform');
}
