/// IO abstractions that work safely on both native and web platforms
library;

// Conditional imports for platform-specific functionality
import 'io_abstractions_web.dart'
    if (dart.library.io) 'io_abstractions_io.dart'
    as io_impl;

/// Platform-safe way to get stdout stream
dynamic get stdout => io_impl.stdout;

/// Platform-safe way to get stderr stream
dynamic get stderr => io_impl.stderr;

/// Platform-safe way to get stdin stream
dynamic get stdin => io_impl.stdin;

/// Platform-safe way to get system temp directory
String getSystemTempDirectory() => io_impl.getSystemTempDirectory();

/// Platform-safe way to create a temporary file path
String createTempFilePath(String prefix) => io_impl.createTempFilePath(prefix);

/// Platform-safe way to exit the process
void exitProcess(int code) => io_impl.exitProcess(code);

/// Result of a process execution
class ProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  ProcessResult(this.exitCode, this.stdout, this.stderr);
}

/// Platform-safe way to run a process synchronously
ProcessResult runProcessSync(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => io_impl.runProcessSync(
  executable,
  arguments,
  workingDirectory: workingDirectory,
);

/// Platform-safe way to extract an OS error code from an exception
/// Returns 0 if not available on the current platform or exception type.
int extractOsErrorCode(Object e) => io_impl.extractOsErrorCode(e);
