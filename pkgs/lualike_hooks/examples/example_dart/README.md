# lualike_hooks example (Dart CLI)

Compiles Lua at build time and loads the bytecode from `build/lua/` or the CLI bundle.

## Build and run

```bash
cd example_dart
dart build cli --target=bin/main.dart
./build/cli/linux_x64/bundle/bin/main
```

If you delete `build/lua/`, rebuild before running again.
