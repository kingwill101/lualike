# process_lualike

[![Pub Version](https://img.shields.io/pub/v/process_lualike)](https://pub.dev/packages/process_lualike)
[![Pub Version](https://img.shields.io/pub/v/lualike)](https://pub.dev/packages/lualike)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)

Bridges remote process execution into the [LuaLike](https://github.com/kingwill101/lualike) scripting runtime. Enables `os.execute()` over SSH, Docker, or any custom backend — so Lua scripts can run commands on remote machines without changing a single line of Lua code.

## Install

```yaml
dependencies:
  lualike: ^0.2.4
  process_lualike: ^0.1.1
```

Then run:

```bash
dart pub get
```

## Quick start

```dart
import 'package:lualike/lualike.dart';
import 'package:process_lualike/process_lualike.dart';
import 'package:dartssh2/dartssh2.dart';

Future<void> main() async {
  final lua = LuaLike();

  final client = await connect(
    SSHClient(
      await SSHSocket.connect('example.com', 22),
      keys: [SSHKeyPair.fromPrivateKey(privateKey)],
    ),
  );

  await useProcessBackend(SshProcessBackend(client));

  lua.expose('greet', (List<Object?> args) {
    return Value('Hello, ${args.first ?? 'world'}!');
  });

  final result = await lua.execute('''
    local ok, _, code = os.execute("whoami")
    return greet("remote command ran")
  ''');

  print((result as Value).unwrap());
}
```

## Usage

### Wiring into lualike

Call `useProcessBackend(backend)` once during setup. It routes `os.execute()` and `process.exec()` through the backend instead of local `dart:io`.

```dart
await useProcessBackend(backend);
```

### SSH backend (remote execution)

```dart
import 'package:process_lualike/process_lualike.dart';
import 'package:dartssh2/dartssh2.dart';

final client = await connect(SSHClient(socket, keys: [keyPair]));
final backend = SshProcessBackend(client);

await useProcessBackend(backend);
```

All Lua `os.execute()` calls now run inside the SSH session. Stdout, stderr, and exit codes are captured and returned to Lua just like local execution.

### Custom backend

Implement the `ProcessBackend` interface to route execution through Docker, Kubernetes, RPC, or any other transport:

```dart
class MyBackend implements ProcessBackend {
  @override
  bool get isShellAvailable => true;

  @override
  ProcessRunResult runSync(String command) {
    // Remote execution logic...
  }

  @override
  Future<ProcessRunResult> run(String command) async {
    return runSync(command);
  }

  @override
  Future<int> runStreaming(
    String command, {
    void Function(List<int> chunk)? onStdout,
    void Function(List<int> chunk)? onStderr,
    void Function()? onDone,
  }) async {
    final result = runSync(command);
    onStdout?.call(result.stdout.codeUnits);
    onStderr?.call(result.stderr.codeUnits);
    onDone?.call();
    return result.exitCode;
  }
}

await useProcessBackend(MyBackend());
```

### Live streaming output

`runStreaming` delivers stdout/stderr chunks as they arrive — useful for long-running commands or interactive sessions:

```dart
await backend.runStreaming(
  'tail -f /var/log/syslog',
  onStdout: (chunk) => print(utf8.decode(chunk)),
  onStderr: (chunk) => print('ERR: ${utf8.decode(chunk)}'),
);
```

### Resetting to local processes

Pass `null` to restore the default `dart:io` process execution:

```dart
await useProcessBackend(null);
```
