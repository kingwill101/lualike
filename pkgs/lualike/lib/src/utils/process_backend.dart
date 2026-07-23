/// Pluggable backend for process execution.
///
/// Allows customizing how `os.execute` and `io.popen` run external commands.
/// Useful for remote execution (SSH, Docker, container exec), mocking in
/// tests, or restricting execution in sandboxed environments.
abstract class ProcessBackend {
  /// Runs [command] and returns the result.
  ///
  /// Implementations should interpret [command] the same way the platform
  /// default would — typically as a shell command string on native (so
  /// `cd /tmp && ls`) or directly on the remote.
  ProcessRunResult runSync(String command);

  /// Asynchronously runs [command].
  ///
  /// Used by backends that inherently require async I/O (SSH, containers).
  /// Returns a future that completes with the process result.
  Future<ProcessRunResult> run(String command);

  /// Asynchronously runs [command], exposing live [stdout] and [stderr]
  /// streams.
  ///
  /// Listeners on [stdout] and [stderr] receive data chunks as they arrive.
  /// [onDone] fires when the process exits (or errors out).
  ///
  /// Returns a future that completes with the final exit code when
  /// the stream ends.
  Future<int> runStreaming(
    String command, {
    void Function(List<int> chunk)? onStdout,
    void Function(List<int> chunk)? onStderr,
    void Function()? onDone,
  });

  /// Whether a shell is available on this backend.
  bool get isShellAvailable;
}

/// Result of a synchronous process execution.
class ProcessRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ProcessRunResult(this.exitCode, this.stdout, this.stderr);
}
