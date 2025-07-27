/// Native IO implementation of IO abstractions
library;

import 'dart:io' as io;
import 'dart:math';
import 'io_abstractions.dart' show ProcessResult;

/// Platform-safe way to get stdout stream
dynamic get stdout => io.stdout;

/// Platform-safe way to get stderr stream
dynamic get stderr => io.stderr;

/// Platform-safe way to get stdin stream
dynamic get stdin => io.stdin;

/// Platform-safe way to get system temp directory
String getSystemTempDirectory() => io.Directory.systemTemp.path;

/// Platform-safe way to create a temporary file path
String createTempFilePath(String prefix) {
  final random = Random();
  final tempDir = io.Directory.systemTemp.path;
  return '$tempDir/${prefix}_${random.nextInt(1000000)}.tmp';
}

/// Platform-safe way to exit the process
void exitProcess(int code) => io.exit(code);

/// Platform-safe way to run a process synchronously
ProcessResult runProcessSync(String executable, List<String> arguments) {
  final result = io.Process.runSync(executable, arguments);
  return ProcessResult(
    result.exitCode,
    result.stdout.toString(),
    result.stderr.toString(),
  );
}
