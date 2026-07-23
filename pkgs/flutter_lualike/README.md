# flutter_lualike

Flutter integration for `lualike`.

This package gives you two things:

1. **A Flutter asset-bundle filesystem backend** for `require()`, `dofile()`,
   and `io.open()`.
2. **A hooks re-export** so Flutter projects can write build hooks without
   depending on `lualike_hooks` directly.

## What it solves

Use `flutter_lualike` when you want Lua scripts to live inside a Flutter app,
loaded from assets, while still using the same `lualike` runtime on Dart and
Flutter.

## Install

```yaml
dependencies:
  flutter_lualike:
    path: path/to/flutter_lualike
```

## Runtime setup

Configure `lualike` to read from Flutter assets:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_lualike/flutter_lualike.dart';

await useAssetBundle(rootBundle, assetRoot: 'build/lua');
```

After that, `require('hello')` and `dofile('script.lua')` resolve from the
asset bundle.

## Build hooks

`flutter_lualike` re-exports `lualike_hooks`, so your `hook/build.dart` can be:

```dart
import 'package:hooks/hooks.dart';
import 'package:flutter_lualike/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = LuaBuilder(
      sources: ['assets/lua/'],
      mode: CompileMode.bytecode,
    );
    await builder.run(input: input, output: output, logger: null);
  });
}
```

## Asset layout

A typical Flutter project looks like this:

```text
my_app/
  assets/
    lua/
      hello.lua
  hook/
    build.dart
  lib/
    main.dart
  pubspec.yaml
```

And `pubspec.yaml` should include the compiled output:

```yaml
flutter:
  assets:
    - build/lua/
```

## Modes

The re-exported hooks API supports:

- `CompileMode.bytecode` -- compile to bytecode files in `build/lua/`
- `CompileMode.dartSource` -- generate Dart source files
- `CompileMode.dartEmbed` -- generate Dart files with embedded bytecode bytes

## Example

See [`example/`](example/) for a full Flutter app using `flutter_lualike`
with hooks and runtime execution.
