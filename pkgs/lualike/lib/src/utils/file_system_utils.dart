/// File system utilities that work safely on both native and web platforms
library;

// Conditional imports for platform-specific functionality
import 'file_system_utils_io.dart'
    if (dart.library.js_interop) 'file_system_utils_web.dart'
    as fs_impl;

import 'file_system_backend.dart';

FileSystemBackend? _customBackend;

/// Set a custom [FileSystemBackend] to override all filesystem operations.
///
/// Pass `null` to restore the default platform-specific implementation.
void setFileSystemBackend(FileSystemBackend? backend) {
  _customBackend = backend;
}

/// The current custom backend, or `null` if using the default.
FileSystemBackend? get currentFileSystemBackend => _customBackend;

/// Platform-safe way to check if a file exists
Future<bool> fileExists(String path) {
  if (_customBackend != null) return _customBackend!.fileExists(path);
  return fs_impl.fileExists(path);
}

/// Platform-safe way to check if a directory exists
Future<bool> directoryExists(String path) {
  if (_customBackend != null) return _customBackend!.directoryExists(path);
  return fs_impl.directoryExists(path);
}

/// Platform-safe way to read a file as string
Future<String?> readFileAsString(String path) {
  if (_customBackend != null) return _customBackend!.readFileAsString(path);
  return fs_impl.readFileAsString(path);
}

/// Platform-safe way to read a file as bytes
Future<List<int>?> readFileAsBytes(String path) {
  if (_customBackend != null) return _customBackend!.readFileAsBytes(path);
  return fs_impl.readFileAsBytes(path);
}

/// Platform-safe way to get the last modified time for a file.
Future<DateTime?> getLastModified(String path) {
  if (_customBackend != null) return _customBackend!.getLastModified(path);
  return fs_impl.getLastModified(path);
}

/// Platform-safe way to get current working directory
String? getCurrentDirectory() {
  if (_customBackend != null) return _customBackend!.getCurrentDirectory();
  return fs_impl.getCurrentDirectory();
}

/// Platform-safe way to create a directory.
Future<bool> createDirectory(String path, {bool recursive = true}) {
  if (_customBackend != null) {
    return _customBackend!.createDirectory(path, recursive: recursive);
  }
  return fs_impl.createDirectory(path, recursive: recursive);
}

/// Platform-safe way to write a file
Future<void> writeFile(String path, String content) {
  if (_customBackend != null) return _customBackend!.writeFile(path, content);
  return fs_impl.writeFile(path, content);
}

/// Platform-safe way to list directory contents
Future<List<String>> listDirectory(String path) {
  if (_customBackend != null) return _customBackend!.listDirectory(path);
  return fs_impl.listDirectory(path);
}

/// Platform-safe way to get a file's size in bytes.
Future<int?> fileSize(String path) {
  if (_customBackend != null) return _customBackend!.fileSize(path);
  return fs_impl.fileSize(path);
}

/// Platform-safe way to delete a file
Future<void> deleteFile(String path) {
  if (_customBackend != null) return _customBackend!.deleteFile(path);
  return fs_impl.deleteFile(path);
}

/// Platform-safe way to delete either a file or a directory.
Future<bool> deletePath(String path, {bool recursive = true}) {
  if (_customBackend != null) {
    return _customBackend!.deletePath(path, recursive: recursive);
  }
  return fs_impl.deletePath(path, recursive: recursive);
}

/// Platform-safe way to rename/move a file
Future<void> renameFile(String oldPath, String newPath) {
  if (_customBackend != null) {
    return _customBackend!.renameFile(oldPath, newPath);
  }
  return fs_impl.renameFile(oldPath, newPath);
}
