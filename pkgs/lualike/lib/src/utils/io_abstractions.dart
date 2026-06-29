/// IO abstractions that work safely on both native and web platforms
///
/// Provides a [ProcessBackend] injection point so callers can replace process
/// execution (used by [os.execute] etc.) with custom backends such as SSH,
/// Docker, or test mocks.
library;

// Conditional imports for platform-specific functionality
import 'io_abstractions_io.dart'
    if (dart.library.js_interop) 'io_abstractions_web.dart'
    as io_impl;
import 'process_backend.dart';

ProcessBackend? _customProcessBackend;

/// Overrides process execution with a custom [ProcessBackend].
///
/// Pass `null` to restore the platform default (`dart:io` on native,
/// throws on web).
void setProcessBackend(ProcessBackend? backend) {
  _customProcessBackend = backend;
}

/// The currently installed [ProcessBackend], or `null` if the platform default
/// is in use.
ProcessBackend? get currentProcessBackend => _customProcessBackend;

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

/// Runs a process synchronously.
///
/// Delegates to the custom [ProcessBackend] when one is installed via
/// [setProcessBackend]; otherwise falls back to the platform default
/// (`dart:io` on native, throws on web).
ProcessResult runProcessSync(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  final backend = _customProcessBackend;
  if (backend != null) {
    final cmd = '$executable ${arguments.join(' ')}'.trim();
    final result = backend.runSync(cmd);
    return ProcessResult(result.exitCode, result.stdout, result.stderr);
  }
  return io_impl.runProcessSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
}

/// Same as [runProcessSync], but allows backends to perform async I/O
/// (e.g., SSH channel reads) and return a [Future].
Future<ProcessResult> runProcessAsync(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final backend = _customProcessBackend;
  if (backend != null) {
    final cmd = '$executable ${arguments.join(' ')}'.trim();
    final result = await backend.run(cmd);
    return ProcessResult(result.exitCode, result.stdout, result.stderr);
  }
  return io_impl.runProcessSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
}

/// Platform-safe way to extract an OS error code from an exception
/// Returns 0 if not available on the current platform or exception type.
int extractOsErrorCode(Object e) => io_impl.extractOsErrorCode(e);
