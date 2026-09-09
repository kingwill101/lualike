# lualike_hooks example (Dart CLI + data assets)

[![Pub Version](https://img.shields.io/pub/v/lualike_hooks)](https://pub.dev/packages/lualike_hooks)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)


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
