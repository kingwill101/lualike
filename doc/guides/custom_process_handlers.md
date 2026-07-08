# Custom Process Handlers

LuaLike uses a pluggable `ProcessBackend` for process execution —
`os.execute()`, `io.popen()`, and shell availability checks. Swap the
backend to run commands remotely over SSH, in a container, or restrict
execution in sandboxed environments.

## Table of Contents

- [Interface](#interface)
- [Built-in backends](#built-in-backends)
- [Writing a custom backend](#writing-a-custom-backend)
- [Example: Docker backend](#example-docker-backend)
- [Mock backend for tests](#mock-backend-for-tests)

## Interface

```dart
abstract class ProcessBackend {
  ProcessRunResult runSync(String command);
  Future<ProcessRunResult> run(String command);
  Future<int> runStreaming(
    String command, {
    void Function(List<int> chunk)? onStdout,
    void Function(List<int> chunk)? onStderr,
    void Function()? onDone,
  });
  bool get isShellAvailable;
}

class ProcessRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;
}
```

Set the active backend with `setProcessBackend()`:

```dart
import 'package:lualike/lualike.dart';

setProcessBackend(MyProcessBackend());
```

Pass `null` to restore the default platform implementation.

## Built-in backends

### Platform default

The default backend uses `dart:io` `Process.run()` and `Process.runSync()`.
It is used when no custom backend is set.

### SshProcessBackend

Runs commands over SSH via `dartssh2`. Provided by the `process_lualike`
package.

```dart
import 'package:process_lualike/process_lualike.dart';

final backend = SshProcessBackend(
  host: 'example.com',
  username: 'deploy',
  sshKeyPath: '/home/user/.ssh/id_rsa',
);

setProcessBackend(backend);
```

Now `os.execute('deploy.sh')` runs on the remote host.

One-call setup:

```dart
await useSshProcessBackend(
  host: 'example.com',
  username: 'deploy',
  sshKeyPath: '/home/user/.ssh/id_rsa',
);
```

## Writing a custom backend

Implement `ProcessBackend` to run commands in a container, on a remote API,
or in a simulated environment for testing.

### Example: Docker backend

```dart
class DockerProcessBackend implements ProcessBackend {
  final String containerName;

  DockerProcessBackend(this.containerName);

  @override
  ProcessRunResult runSync(String command) {
    final result = Process.runSync(
      'docker',
      ['exec', containerName, 'sh', '-c', command],
    );
    return ProcessRunResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }

  @override
  Future<ProcessRunResult> run(String command) async {
    final result = await Process.run(
      'docker',
      ['exec', containerName, 'sh', '-c', command],
    );
    return ProcessRunResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }

  @override
  Future<int> runStreaming(
    String command, {
    void Function(List<int> chunk)? onStdout,
    void Function(List<int> chunk)? onStderr,
    void Function()? onDone,
  }) async {
    final process = await Process.start(
      'docker',
      ['exec', containerName, 'sh', '-c', command],
    );

    process.stdout.listen(
      (data) => onStdout?.call(data),
      onDone: () => onDone?.call(),
    );
    process.stderr.listen((data) => onStderr?.call(data));

    return await process.exitCode;
  }

  @override
  bool get isShellAvailable => true;
}
```

Usage:

```dart
setProcessBackend(DockerProcessBackend('my_container'));
// os.execute('ls -la') runs inside the Docker container
```

### Mock backend for tests

```dart
class MockProcessBackend implements ProcessBackend {
  int exitCode = 0;
  String stdout = '';
  String stderr = '';
  String? lastCommand;

  @override
  ProcessRunResult runSync(String command) {
    lastCommand = command;
    return ProcessRunResult(exitCode, stdout, stderr);
  }

  @override
  Future<ProcessRunResult> run(String command) async {
    lastCommand = command;
    return ProcessRunResult(exitCode, stdout, stderr);
  }

  @override
  Future<int> runStreaming(
    String command, {
    void Function(List<int> chunk)? onStdout,
    void Function(List<int> chunk)? onStderr,
    void Function()? onDone,
  }) async {
    lastCommand = command;
    onStdout?.call(stdout.codeUnits);
    onDone?.call();
    return exitCode;
  }

  @override
  bool get isShellAvailable => true;
}
```

Usage in tests:

```dart
test('os.execute uses custom backend', () {
  final mock = MockProcessBackend();
  mock.stdout = 'hello from test';
  setProcessBackend(mock);

  lua.execute('local ok, out = os.execute("echo hi")');

  expect(mock.lastCommand, 'echo hi');
});
```

## Streaming output

The `runStreaming()` method enables real-time output for `io.popen()`.
Chunks are delivered as they arrive rather than buffering the full output:

```dart
class StreamingBackend implements ProcessBackend {
  @override
  Future<int> runStreaming(
    String command, {
    void Function(List<int> chunk)? onStdout,
    void Function(List<int> chunk)? onStderr,
    void Function()? onDone,
  }) async {
    // Spawn process and stream output
    final process = await Process.start(command, [], runInShell: true);
    process.stdout.listen(onStdout);
    process.stderr.listen(onStderr);
    final code = await process.exitCode;
    onDone?.call();
    return code;
  }
  // ...
}
```
