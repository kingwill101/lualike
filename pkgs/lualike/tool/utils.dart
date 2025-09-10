import 'dart:io';

/// Get the proper executable name for the current platform
///
/// On Windows, adds the .exe extension to the base name.
/// On other platforms, returns the base name unchanged.
///
/// Example:
/// ```dart
/// getExecutableName('lua') // Returns 'lua.exe' on Windows, 'lua' on Unix
/// getExecutableName('dart') // Returns 'dart.exe' on Windows, 'dart' on Unix
/// ```
String getExecutableName(String baseName) {
  return Platform.isWindows ? '$baseName.exe' : baseName;
}
