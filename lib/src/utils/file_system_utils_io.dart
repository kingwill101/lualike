/// Native IO implementation of file system utilities
library;

import 'dart:io';

/// Platform-safe way to check if a file exists
Future<bool> fileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (e) {
    return false;
  }
}

/// Platform-safe way to check if a directory exists
Future<bool> directoryExists(String path) async {
  try {
    return await Directory(path).exists();
  } catch (e) {
    return false;
  }
}

/// Platform-safe way to read a file as string
Future<String?> readFileAsString(String path) async {
  try {
    return await File(path).readAsString();
  } catch (e) {
    return null;
  }
}

/// Platform-safe way to read a file as bytes
Future<List<int>?> readFileAsBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } catch (e) {
    return null;
  }
}

/// Platform-safe way to get current working directory
String? getCurrentDirectory() {
  try {
    return Directory.current.path;
  } catch (e) {
    return null;
  }
}

/// Platform-safe way to write a file
Future<void> writeFile(String path, String content) async {
  try {
    await File(path).writeAsString(content);
  } catch (e) {
    // Ignore errors on write
  }
}

/// Platform-safe way to list directory contents
Future<List<String>> listDirectory(String path) async {
  try {
    final dir = Directory(path);
    final entities = await dir.list().toList();
    return entities.map((e) => e.path).toList();
  } catch (e) {
    return <String>[];
  }
}

/// Platform-safe way to delete a file
Future<void> deleteFile(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (e) {
    throw Exception('Failed to delete file: $path');
  }
}

/// Platform-safe way to rename/move a file
Future<void> renameFile(String oldPath, String newPath) async {
  try {
    final file = File(oldPath);
    if (await file.exists()) {
      await file.rename(newPath);
    } else {
      throw Exception('File does not exist: $oldPath');
    }
  } catch (e) {
    throw Exception('Failed to rename file: $oldPath -> $newPath');
  }
}
