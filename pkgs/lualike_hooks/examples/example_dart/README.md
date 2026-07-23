# lualike_hooks example (Dart CLI)

[![Pub Version](https://img.shields.io/pub/v/lualike_hooks)](https://pub.dev/packages/lualike_hooks)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)


Compiles Lua at build time and loads the bytecode from `build/lua/` or the CLI bundle.

## Build and run

```bash
cd example_dart
dart build cli --target=bin/main.dart
./build/cli/linux_x64/bundle/bin/main
```

If you delete `build/lua/`, rebuild before running again.
