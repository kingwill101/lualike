/// Native IO implementation of platform utilities
library;

import 'dart:io';

/// Platform-safe way to check if we're on Windows
bool get isWindows => Platform.isWindows;

/// Platform-safe way to check if we're on Linux
bool get isLinux => Platform.isLinux;

/// Platform-safe way to check if we're on macOS
bool get isMacOS => Platform.isMacOS;

/// Platform-safe way to get environment variables
Map<String, String> get environment => Platform.environment;

/// Platform-safe way to get a specific environment variable
String? getEnvironmentVariable(String name) => Platform.environment[name];

/// Platform-safe way to get path separator
String get pathSeparator => Platform.pathSeparator;

/// Platform-safe way to get the executable name/path
String get executableName => Platform.executable.split(pathSeparator).last;

/// Platform-safe way to get the script path
String? get scriptPath {
  try {
    return Platform.script.toFilePath();
  } catch (e) {
    return null;
  }
}
