/// Platform utilities that work safely on both native and web platforms
library;

// Conditional imports for platform-specific functionality
import 'platform_utils_web.dart'
    if (dart.library.io) 'platform_utils_io.dart'
    as platform_impl;

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
const bool isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Platform-safe way to check if we're on Windows
bool get isWindows => platform_impl.isWindows;

/// Platform-safe way to check if we're on Linux
bool get isLinux => platform_impl.isLinux;

/// Platform-safe way to check if we're on macOS
bool get isMacOS => platform_impl.isMacOS;

/// Platform-safe way to get environment variables
Map<String, String> get environment => platform_impl.environment;

/// Platform-safe way to get a specific environment variable
String? getEnvironmentVariable(String name) =>
    platform_impl.getEnvironmentVariable(name);

/// Platform-safe way to get path separator
String get pathSeparator => platform_impl.pathSeparator;

/// Platform-safe way to get the executable name/path
String get executableName => platform_impl.executableName;

/// Platform-safe way to get the script path
String? get scriptPath => platform_impl.scriptPath;
