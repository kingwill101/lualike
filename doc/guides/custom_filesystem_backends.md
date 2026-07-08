# Custom Filesystem Backends

LuaLike uses a pluggable `FileSystemBackend` interface for all filesystem
operations — `dofile()`, `require()`, `io.open()`, `os.remove()`, and module
loading. Swap the backend to change where Lua scripts read and write files.

## Table of Contents

- [Interface](#interface)
- [Built-in backends](#built-in-backends)
- [Composite backend](#composite-backend)
- [Flutter asset bundle backend](#flutter-asset-bundle-backend)
- [Writing a custom backend](#writing-a-custom-backend)
- [IO device provider](#io-device-provider)

## Interface

```dart
abstract class FileSystemBackend {
  Future<bool> fileExists(String path);
  Future<bool> directoryExists(String path);
  Future<String?> readFileAsString(String path);
  Future<List<int>?> readFileAsBytes(String path);
  Future<DateTime?> getLastModified(String path);
  String? getCurrentDirectory();
  Future<bool> createDirectory(String path, {bool recursive});
  Future<void> writeFile(String path, String content);
  Future<List<String>> listDirectory(String path);
  Future<int?> fileSize(String path);
  Future<void> deleteFile(String path);
  Future<bool> deletePath(String path, {bool recursive});
  Future<void> renameFile(String oldPath, String newPath);
}
```

Set the active backend with `setFileSystemBackend()`:

```dart
import 'package:lualike/lualike.dart';

setFileSystemBackend(MyCustomBackend());
```

Pass `null` to restore the default platform implementation.

## Built-in backends

### PackageFileSystemBackend

Wraps any `package:file` `FileSystem` implementation — local disk, SFTP,
in-memory.

```dart
import 'package:file/local.dart';
import 'package:file_lualike/file_lualike.dart';

setFileSystemBackend(PackageFileSystemBackend(LocalFileSystem()));
```

For `io.open()` support, also wire the IO device provider:

```dart
final provider = FileSystemProvider();
provider.setIODeviceFactory(
  (path, mode) => PackageFileIODevice.open(fs, path, mode),
);
setFileSystemProvider(provider);
```

The one-call helper `useFileSystem()` does both at once:

```dart
await useFileSystem(LocalFileSystem());
```

### AssetBundleFileSystemBackend

Read-only backend that serves files from a Flutter `AssetBundle`. All
write/delete/rename operations are no-ops.

```dart
import 'package:flutter_lualike/flutter_lualike.dart';

await useAssetBundle(rootBundle, assetRoot: 'assets');
```

Supports `io.open()` in mode `"r"` via `AssetBundleIODevice`.

## Composite backend

Chain multiple backends in priority order. The first backend that succeeds
for a read wins. For writes, backends are tried in order until one succeeds.

```dart
import 'package:lualike/lualike.dart';

setFileSystemBackend(CompositeFileSystemBackend([
  primaryBackend,
  fallbackBackend,
]));
```

This is useful on desktop platforms where some files live in the app bundle
and others on the local filesystem:

```dart
import 'package:file/local.dart';
import 'package:file_lualike/file_lualike.dart';
import 'package:flutter_lualike/flutter_lualike.dart';

setFileSystemBackend(CompositeFileSystemBackend([
  AssetBundleFileSystemBackend(rootBundle, assetRoot: 'assets'),
  PackageFileSystemBackend(LocalFileSystem()),
]));
```

## Flutter asset bundle backend

The `flutter_lualike` package provides a full Flutter integration.

### Setup

```dart
import 'package:flutter_lualike/flutter_lualike.dart';

await useAssetBundle(rootBundle, assetRoot: 'assets');
```

After setup, `dofile('config.lua')` resolves to `assets/config.lua`,
`require('helpers.utils')` resolves through the asset manifest, and
`io.open('data.json', 'r')` returns a read-only device.

### Android / iOS / web

Assets are bundled at build time and read-only at runtime. Works on all
Flutter platforms without additional setup.

### Desktop with writable storage

For desktop, combine with a local filesystem backend:

```dart
final backend = CompositeFileSystemBackend([
  AssetBundleFileSystemBackend(rootBundle, assetRoot: 'assets'),
  PackageFileSystemBackend(LocalFileSystem()),
]);
setFileSystemBackend(backend);
```

## Writing a custom backend

Implement `FileSystemBackend` for any storage — cloud storage, encrypted
archives, HTTP remotes, or custom game save formats.

### Example: in-memory backend

```dart
class MemoryBackend implements FileSystemBackend {
  final Map<String, String> _files = {};

  @override
  Future<bool> fileExists(String path) async => _files.containsKey(path);

  @override
  Future<bool> directoryExists(String path) async =>
      _files.keys.any((k) => k.startsWith('$path/'));

  @override
  Future<String?> readFileAsString(String path) async => _files[path];

  @override
  Future<List<int>?> readFileAsBytes(String path) async {
    final content = _files[path];
    return content?.codeUnits;
  }

  @override
  Future<DateTime?> getLastModified(String path) async => null;

  @override
  String? getCurrentDirectory() => '/memory';

  @override
  Future<bool> createDirectory(String path, {bool recursive}) async => true;

  @override
  Future<void> writeFile(String path, String content) async {
    _files[path] = content;
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    final prefix = path.endsWith('/') ? path : '$path/';
    return _files.keys.where((k) => k.startsWith(prefix)).toList();
  }

  @override
  Future<int?> fileSize(String path) async => _files[path]?.length;

  @override
  Future<void> deleteFile(String path) async => _files.remove(path);

  @override
  Future<bool> deletePath(String path, {bool recursive}) async =>
      _files.remove(path) != null;

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    final content = _files.remove(oldPath);
    if (content != null) _files[newPath] = content;
  }
}
```

Usage:

```dart
setFileSystemBackend(MemoryBackend());
```

## IO device provider

The `FileSystemBackend` handles metadata operations. For `io.open()` and
`io.lines()` you also need an `IODeviceFactory` registered via
`FileSystemProvider`:

```dart
final provider = FileSystemProvider();
provider.setIODeviceFactory(
  (path, mode) => MyIODevice.open(path, mode),
);
setFileSystemProvider(provider);
```

The `useFileSystem()` and `useAssetBundle()` helpers register both the
backend and the provider in a single call.
