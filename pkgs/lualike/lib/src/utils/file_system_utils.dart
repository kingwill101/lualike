/// File system utilities that work safely on both native and web platforms
library;

// Conditional imports for platform-specific functionality
import 'file_system_utils_io.dart'
    if (dart.library.js_interop) 'file_system_utils_web.dart'
    as fs_impl;

import 'file_system_backend.dart';
import '../runtime/lua_runtime.dart';

FileSystemBackend? _customBackend;
final Expando<_FileSystemBackendOverride> _runtimeBackends = Expando(
  'lualikeFileSystemBackend',
);

class _FileSystemBackendOverride {
  final FileSystemBackend? backend;

  _FileSystemBackendOverride(this.backend);
}

FileSystemBackend? _backendFor(LuaRuntime? interpreter) {
  if (interpreter == null) return _customBackend;
  final override = _runtimeBackends[interpreter];
  if (override != null) return override.backend;
  return _customBackend;
}

/// Set a custom [FileSystemBackend] to override filesystem operations.
///
/// When [interpreter] is supplied, the override is owned by that runtime and
/// concurrent runtimes keep their own backend. Without it, the backend is the
/// process-wide fallback for runtimes that do not set an override.
///
/// Pass `null` to restore the default platform-specific implementation.
void setFileSystemBackend(
  FileSystemBackend? backend, {
  LuaRuntime? interpreter,
}) {
  if (interpreter == null) {
    _customBackend = backend;
  } else {
    _runtimeBackends[interpreter] = _FileSystemBackendOverride(backend);
  }
}

/// The current custom backend, or `null` if using the default.
FileSystemBackend? get currentFileSystemBackend => _customBackend;

/// Returns the filesystem backend selected for [interpreter].
FileSystemBackend? currentFileSystemBackendFor(LuaRuntime? interpreter) =>
    _backendFor(interpreter);

/// Platform-safe way to check if a file exists
Future<bool> fileExists(String path, {LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.fileExists(path);
  return fs_impl.fileExists(path);
}

/// Platform-safe way to check if a directory exists
Future<bool> directoryExists(String path, {LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.directoryExists(path);
  return fs_impl.directoryExists(path);
}

/// Platform-safe way to read a file as string
Future<String?> readFileAsString(String path, {LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.readFileAsString(path);
  return fs_impl.readFileAsString(path);
}

/// Platform-safe way to read a file as bytes
Future<List<int>?> readFileAsBytes(String path, {LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.readFileAsBytes(path);
  return fs_impl.readFileAsBytes(path);
}

/// Platform-safe way to get the last modified time for a file.
Future<DateTime?> getLastModified(String path, {LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.getLastModified(path);
  return fs_impl.getLastModified(path);
}

/// Platform-safe way to get current working directory
String? getCurrentDirectory({LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.getCurrentDirectory();
  return fs_impl.getCurrentDirectory();
}

/// Platform-safe way to create a directory.
Future<bool> createDirectory(
  String path, {
  bool recursive = true,
  LuaRuntime? interpreter,
}) {
  final backend = _backendFor(interpreter);
  if (backend != null) {
    return backend.createDirectory(path, recursive: recursive);
  }
  return fs_impl.createDirectory(path, recursive: recursive);
}

/// Platform-safe way to write a file
Future<void> writeFile(String path, String content, {LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.writeFile(path, content);
  return fs_impl.writeFile(path, content);
}

/// Platform-safe way to list directory contents
Future<List<String>> listDirectory(String path, {LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.listDirectory(path);
  return fs_impl.listDirectory(path);
}

/// Platform-safe way to get a file's size in bytes.
Future<int?> fileSize(String path, {LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.fileSize(path);
  return fs_impl.fileSize(path);
}

/// Platform-safe way to delete a file
Future<void> deleteFile(String path, {LuaRuntime? interpreter}) {
  final backend = _backendFor(interpreter);
  if (backend != null) return backend.deleteFile(path);
  return fs_impl.deleteFile(path);
}

/// Platform-safe way to delete either a file or a directory.
Future<bool> deletePath(
  String path, {
  bool recursive = true,
  LuaRuntime? interpreter,
}) {
  final backend = _backendFor(interpreter);
  if (backend != null) {
    return backend.deletePath(path, recursive: recursive);
  }
  return fs_impl.deletePath(path, recursive: recursive);
}

/// Platform-safe way to rename/move a file
Future<void> renameFile(
  String oldPath,
  String newPath, {
  LuaRuntime? interpreter,
}) {
  final backend = _backendFor(interpreter);
  if (backend != null) {
    return backend.renameFile(oldPath, newPath);
  }
  return fs_impl.renameFile(oldPath, newPath);
}
