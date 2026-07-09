# flutter_lualike

Flutter [AssetBundle](https://api.flutter.dev/flutter/services/AssetBundle-class.html)
filesystem backend for [lualike](https://github.com/kingwill101/lualike). Provides
transparent read-only file access for `dofile()` and module loading from Flutter
assets.

## Install

```yaml
dependencies:
  flutter_lualike: ^0.1.0
  lualike: ^0.3.0
```

Then run:

```bash
flutter pub get
```

## Usage

```dart
import 'package:flutter_lualike/flutter_lualike.dart';

await useAssetBundle(rootBundle, assetRoot: 'assets');

// Now dofile('config.lua') resolves to assets/config.lua
```

## Desktop (local filesystem fallback)

```dart
import 'package:file/local.dart';
import 'package:file_lualike/file_lualike.dart';
import 'package:flutter_lualike/flutter_lualike.dart';
import 'package:lualike/lualike.dart';

final backend = CompositeFileSystemBackend([
  AssetBundleFileSystemBackend(rootBundle, assetRoot: 'assets'),
  PackageFileSystemBackend(LocalFileSystem()),
]);
setFileSystemBackend(backend);
```

## How it works

Two integration points are wired when you call `useAssetBundle()`:

1. **`FileSystemProvider`** — `io.open()` creates `AssetBundleIODevice` instances
   that read from the bundle (read-only, mode `"r"` only).

2. **`FileSystemBackend`** — `dofile()`, `require()`, `os.remove()` and other
   metadata operations delegate to `AssetBundleFileSystemBackend`, which resolves
   paths via the asset manifest.

## Components

| Class | Purpose |
|---|---|
| `AssetBundleFileSystemBackend` | `FileSystemBackend` backed by `AssetBundle` + `AssetManifest` |
| `AssetBundleIODevice` | Read-only `IODevice` for `io.open()` |
| `useAssetBundle()` | One-call setup for both integration points |

For writable storage, combine with `CompositeFileSystemBackend` from core lualike
and `PackageFileSystemBackend` from `file_lualike`.
