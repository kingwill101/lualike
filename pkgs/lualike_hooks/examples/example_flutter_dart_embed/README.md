# example_flutter_dart_embed

This Flutter example shows **CompileMode.dartEmbed**.

Lua is compiled to bytecode at build time, then wrapped in a generated Dart
file under `lib/generated/lua/` so it can be imported directly.

## What this demonstrates

- no asset bundle for the Lua output
- generated Dart source under `lib/generated/lua/hello.lua.dart`
- runtime loading with `LuaBytecodeRuntime`
- calling `M.greet()` and `M.add()` from Dart

## Build flow

```text
assets/lua/hello.lua
  ↓ build hook
lib/generated/lua/hello.lua.dart
  ↓ import
LuaBytecodeRuntime.loadBytecode(helloLuaModule)
```

## Run it

```bash
flutter pub get
flutter test
flutter run
```

## Files to inspect

- `hook/build.dart` -- build hook
- `lib/main.dart` -- runtime example
- `assets/lua/hello.lua` -- Lua module

## Notes

The generated Dart file is intentionally placed inside `lib/generated/` so it
can be imported by package code.
