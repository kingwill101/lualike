# file_lualike

[![Pub Version](https://img.shields.io/pub/v/file_lualike)](https://pub.dev/packages/file_lualike)
[![Pub Version](https://img.shields.io/pub/v/lualike)](https://pub.dev/packages/lualike)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)

Bridges [`package:file`](https://pub.dev/packages/file) `FileSystem` implementations into the [LuaLike](https://github.com/kingwill101/lualike) scripting runtime. Enables transparent filesystem backends for `io.open()`, `os.remove()`, `dofile()`, module loading, and all other lualike file operations.

Use any `package:file`-compatible filesystem — local disk, in-memory (`MemoryFileSystem`), SFTP (`file_sftp`), or a custom implementation — without changing a single line of Lua code.

## Install

```yaml
dependencies:
  lualike: ^0.4.0
  file_lualike: ^0.1.3
```

Then run:

```bash
dart pub get
```

## Quick start

```dart
import 'package:lualike/lualike.dart';
import 'package:file_lualike/file_lualike.dart';
import 'package:file/local.dart';

Future<void> main() async {
  final lua = LuaLike();

  // Use the local filesystem (dart:io under the hood)
  await useFileSystem(const LocalFileSystem());

  lua.expose('greet', (List<Object?> args) {
    return Value('Hello, ${args.first ?? 'world'}!');
  });

  final result = await lua.execute('''
    local f = io.open("/tmp/hello.txt", "w")
    f:write("Hello from LuaLike!")
    f:close()
    return greet("file written")
  ''');

  print((result as Value).unwrap());
}
```

## Usage

### Wiring into lualike

Call `useFileSystem(fs)` once during setup. It wires two integration points:

1. **File provider** — `io.open()`, `io.lines()`, etc. create `PackageFileIODevice` instances backed by your `FileSystem`.
2. **Metadata backend** — `os.remove()`, `dofile()`, module loading, and other filesystem metadata operations delegate to your `FileSystem`.

```dart
await useFileSystem(yourFileSystem);
```

### In-memory filesystem (testing)

```dart
import 'package:file/memory.dart';
import 'package:file_lualike/file_lualike.dart';

final fs = MemoryFileSystem();
await useFileSystem(fs);

// All file operations now happen in memory
```

### SFTP filesystem (remote)

```dart
import 'package:file_lualike/file_lualike.dart';
import 'package:file_sftp/file_sftp.dart';

final sftp = SftpFileSystem(SftpConfig(
  host: 'example.com',
  username: 'alice',
  password: 'secret',
  root: '/home/alice/project',
));

await useFileSystem(sftp);

// All file operations transparently go over SFTP
```

### Custom `FileSystemProvider`

For advanced scenarios where you need fine-grained control over the provider:

```dart
final provider = FileSystemProvider();
await useFileSystem(fs, provider: provider);
```

### Targeted provider override

If you need only the metadata backend without changing the I/O provider:

```dart
import 'package:lualike/lualike.dart';

setFileSystemBackend(PackageFileSystemBackend(fs));
```


