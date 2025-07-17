/// Platform utilities that work safely on both native and web platforms
library;

/// Detect if we're running in product mode (compiled executable)
///
/// When a Dart program is compiled with `dart compile exe`, the resulting binary
/// is built in product mode, and this constant will be true.
/// When running via `dart run` (JIT mode), this will be false.
const bool isProductMode = bool.fromEnvironment(
  'dart.vm.product',
  defaultValue: false,
);

/// Detect if we're running on the web platform
const bool isWeb = bool.fromEnvironment('dart.library.js_util');

/// Platform-safe way to check if we're on Windows
bool get isWindows {
  // Always return false on web since there's no file system anyway
  if (isWeb) return false;

  // For native platforms, we need to be careful about imports
  // Use a simple heuristic that works without importing dart:io
  return false; // Default to Unix-like behavior for compatibility
}

/// Platform-safe way to get environment variables
Map<String, String> get environment {
  // Web has no environment variables
  if (isWeb) return <String, String>{};

  // For native platforms, return empty map as fallback
  // The specific libraries that need environment variables can import dart:io directly
  return <String, String>{};
}

/// Platform-safe way to get path separator
String get pathSeparator {
  // Web uses Unix-style paths
  if (isWeb) return '/';

  // Default to Unix-style for compatibility
  return '/';
}
