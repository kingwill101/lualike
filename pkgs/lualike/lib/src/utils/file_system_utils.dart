/// File system utilities that work safely on both native and web platforms
library;

// Conditional imports for platform-specific functionality
import 'file_system_utils_web.dart'
    if (dart.library.io) 'file_system_utils_io.dart'
    as fs_impl;

/// Platform-safe way to check if a file exists
Future<bool> fileExists(String path) => fs_impl.fileExists(path);

/// Platform-safe way to check if a directory exists
Future<bool> directoryExists(String path) => fs_impl.directoryExists(path);

/// Platform-safe way to read a file as string
Future<String?> readFileAsString(String path) => fs_impl.readFileAsString(path);

/// Platform-safe way to read a file as bytes
Future<List<int>?> readFileAsBytes(String path) =>
    fs_impl.readFileAsBytes(path);

/// Platform-safe way to get current working directory
String? getCurrentDirectory() => fs_impl.getCurrentDirectory();

/// Platform-safe way to write a file
Future<void> writeFile(String path, String content) =>
    fs_impl.writeFile(path, content);

/// Platform-safe way to list directory contents
Future<List<String>> listDirectory(String path) => fs_impl.listDirectory(path);

/// Platform-safe way to delete a file
Future<void> deleteFile(String path) => fs_impl.deleteFile(path);

/// Platform-safe way to rename/move a file
Future<void> renameFile(String oldPath, String newPath) =>
    fs_impl.renameFile(oldPath, newPath);
