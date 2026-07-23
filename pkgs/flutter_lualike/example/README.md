# flutter_lualike example

[![Pub Version](https://img.shields.io/pub/v/flutter_lualike)](https://pub.dev/packages/flutter_lualike)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)


This example shows the intended `flutter_lualike` workflow end to end:

- compile Lua in a Flutter build hook
- load compiled bytecode from Flutter assets
- execute Lua with `LuaBytecodeRuntime`
- use `useAssetBundle()` for `require()` / `dofile()` support
- call Lua functions from Dart (`M.greet`, `M.add`)

## What it runs

The example compiles `assets/lua/hello.lua` into `build/lua/hello.lua`.
At runtime it:

1. loads the bytecode from `rootBundle`
2. executes the module
3. calls `M.greet('Flutter')`
4. calls `M.add(2, 3)`
5. configures the asset-bundle backend for module loading

## Run it

```bash
flutter pub get
flutter test
flutter run
```

## Files to look at

- `hook/build.dart` -- build hook using `package:flutter_lualike/hooks.dart`
- `assets/lua/hello.lua` -- Lua module
- `lib/main.dart` -- runtime example

## Why this example matters

It shows the smallest useful Flutter setup:

- no manual bytecode parsing
- no platform-specific file handling
- no separate `lualike_hooks` dependency in the app
- a single `flutter_lualike` dependency for both runtime and build-time pieces
