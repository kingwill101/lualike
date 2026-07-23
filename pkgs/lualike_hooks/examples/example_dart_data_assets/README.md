# lualike_hooks example (Dart CLI + data assets)

Compiles Lua at build time and prefers the bundled `DataAsset` on a Dart SDK
that supports the experimental `data-assets` hook flag.

## Setup

```bash
cd example_dart_data_assets
fvm install main
fvm use main
fvm dart pub get
```

## Run

```bash
fvm dart --enable-experiment=data-assets run
```

## Build

```bash
fvm dart --enable-experiment=data-assets build cli --target=bin/main.dart
./build/cli/linux_x64/bundle/bin/main
```

If the experiment is unavailable, the example falls back to `build/lua/hello.lua`.
