import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:lualike/lualike.dart';

/// [ProcessBackend] that executes commands over SSH via [dartssh2].
///
/// [SSHClient] must already be authenticated. Each call to [run] opens a new
/// SSH exec channel, captures stdout/stderr, and returns the result.
class SshProcessBackend implements ProcessBackend {
  final SSHClient _client;

  SshProcessBackend(this._client);

  @override
  bool get isShellAvailable => true;

  @override
  ProcessRunResult runSync(String command) {
    throw UnsupportedError('''
SshProcessBackend requires async I/O under the hood.
Use the async `run()` method instead.
''');
  }

  @override
  Future<ProcessRunResult> run(String command) async {
    final result = await _client.runWithResult(command);
    return ProcessRunResult(
      result.exitCode ?? -1,
      utf8.decode(result.stdout),
      utf8.decode(result.stderr),
    );
  }

  @override
  Future<int> runStreaming(
    String command, {
    void Function(List<int> chunk)? onStdout,
    void Function(List<int> chunk)? onStderr,
    void Function()? onDone,
  }) async {
    final session = await _client.execute(command);

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    session.stdout.listen(
      (chunk) => onStdout?.call(chunk),
      onDone: stdoutDone.complete,
      onError: stdoutDone.completeError,
    );
    session.stderr.listen(
      (chunk) => onStderr?.call(chunk),
      onDone: stderrDone.complete,
      onError: stderrDone.completeError,
    );

    await stdoutDone.future;
    await stderrDone.future;
    await session.done;

    var exitCode = session.exitCode;
    while (exitCode == null) {
      await Future.delayed(const Duration(milliseconds: 10));
      exitCode = session.exitCode;
    }

    onDone?.call();
    return exitCode;
  }
}
