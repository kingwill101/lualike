/// Web implementation of IO abstractions
library;

import 'io_abstractions.dart' show ProcessResult;

/// Mock stdout for web
class MockStdout {
  void write(String data) {
    // No-op on web
  }
  void writeln(String data) {
    // No-op on web
  }
  void flush() {
    // No-op on web
  }
}

/// Platform-safe way to get stdout stream - mock on web
dynamic get stdout => MockStdout();

/// Platform-safe way to get stderr stream - mock on web
dynamic get stderr => MockStdout();

/// Platform-safe way to get stdin stream - mock on web
dynamic get stdin => MockStdout();

/// Platform-safe way to get system temp directory - default on web
String getSystemTempDirectory() => '/tmp';

/// Platform-safe way to create a temporary file path - simple on web
String createTempFilePath(String prefix) =>
    '/tmp/${prefix}_${DateTime.now().millisecondsSinceEpoch}';

/// Platform-safe way to exit the process - not supported on web
void exitProcess(int code) {
  throw UnsupportedError('Process exit is not supported on web platform');
}

/// Platform-safe way to run a process synchronously - not supported on web
ProcessResult runProcessSync(String executable, List<String> arguments) {
  throw UnsupportedError('Process execution is not supported on web platform');
}

/// Web does not expose OS error codes
int extractOsErrorCode(Object e) => 0;
