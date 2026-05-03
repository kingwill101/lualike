# love2d

Run LOVE 11.5-style Lua games on top of LuaLike, with a Flutter/Flame app
embedding path and a headless runtime path for tests and tooling.

## Table Of Contents

- [What Is This?](#what-is-this)
- [What You Can Do Today](#what-you-can-do-today)
- [Quick Start](#quick-start)
- [Asset Management](#asset-management)
- [Other Ways To Use It](#other-ways-to-use-it)
- [Example App](#example-app)
- [Current Status](#current-status)
- [Advanced Topics](#advanced-topics)
- [Regenerating The Audit](#regenerating-the-audit)
- [Generating Dart Stubs](#generating-dart-stubs)

## What Is This?

`package:love2d` is a compatibility layer that presents a LOVE-like runtime on
top of `lualike`.

Today, the main use case is embedding LOVE-style Lua projects inside a Flutter
app with Flame handling the viewport and frame loop. The package also supports
headless execution, which is useful for smoke tests, benchmarks, and scripted
runtime checks.

If you want to:

- load a `main.lua` entrypoint from Flutter assets
- run `love.load`, `love.update`, and `love.draw`
- use LOVE-style filesystem, input, audio, graphics, and video hooks
- smoke-test games without a full app shell

this package is the current integration surface for that work.

## What You Can Do Today

You can already use this package to:

- embed a LOVE-style game in a Flutter widget with `LoveFlameHarness`
- run LOVE-style scripts headlessly with `LoveScriptRuntime`
- mount game files from Flutter assets or the local filesystem
- route keyboard, mouse, touch, and joystick/gamepad input into the runtime
- provide video frame support for `love.graphics.newVideo`
- launch a working multi-demo example app from [`example/`](./example)

## Quick Start

For most users, the best starting point is `LoveFlameHarness`.

```dart
import 'package:flutter/material.dart';
import 'package:love2d/love2d.dart';

void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: LoveFlameHarness(
          entryAsset: 'assets/my_game/main.lua',
        ),
      ),
    ),
  );
}
```

What this gives you:

- a Flutter widget that boots a LOVE-style entry asset
- automatic `conf.lua` loading when present
- a Flame-driven frame loop for update and draw callbacks
- asset-backed source loading from your app bundle

Remember to register the game assets in `pubspec.yaml`.

## Asset Management

The easiest way to get a LOVE project running is to keep its directory structure
intact under one asset root, register that root in `pubspec.yaml`, and point
`entryAsset` at the game's `main.lua`.

### Working Pattern

1. Copy the game into your Flutter app's assets directory.
2. Keep `main.lua` and any sibling folders in the same relative layout the game
   expects.
3. Register every file or directory the game reads through LOVE filesystem APIs,
   `require`, image loads, audio loads, and similar relative lookups.
4. Point `LoveFlameHarness.entryAsset` at that `main.lua` file.

### Modern Pong Example

The example app vendors Modern Pong like this:

```text
assets/
  modern_pong/
    main.lua
    libs/
    sounds/
    sprites/
    states/
```

The matching `pubspec.yaml` entries are:

```yaml
flutter:
  assets:
    - assets/modern_pong/main.lua
    - assets/modern_pong/libs/
    - assets/modern_pong/sounds/
    - assets/modern_pong/sprites/
    - assets/modern_pong/states/
```

And the harness points at it like this:

```dart
LoveFlameHarness(
  entryAsset: 'assets/modern_pong/main.lua',
)
```

That single `entryAsset` path is what tells the runtime where the mounted LOVE
source tree starts. In this case, the runtime treats `assets/modern_pong/` as
the source root, so the game's relative file access continues to work.

### Practical Rules

- Do not flatten the game into unrelated asset folders.
- Keep `main.lua` next to the folders it expects to load from.
- If the game has a `conf.lua`, register it beside `main.lua` too.
- If the game uses shaders on Flutter, register those shader files in
  `flutter: shaders:` as well, like a normal Flutter app.
- If the game loads nested directories such as `sprites/`, `states/`, `src/`,
  or `audio/`, register those directories in Flutter assets.
- If you move the game to a different asset root, update only the asset keys
  and `entryAsset`; the internal Lua paths can usually stay the same.

### Games With `conf.lua`

Some demos in this repository, such as Pocket Bomber, also ship a `conf.lua`.
In that case, register both files and the supporting directories:

```yaml
flutter:
  assets:
    - assets/pocket_bomber/conf.lua
    - assets/pocket_bomber/main.lua
    - assets/pocket_bomber/src/
    - assets/pocket_bomber/src/states/
```

When `LoveFlameHarness` boots the game, it will load `conf.lua` automatically
when that file is present in the mounted source tree.

## Other Ways To Use It

If Flutter embedding is not the right fit, there are two other common paths.

### Headless Runtime

Use `LoveScriptRuntime` when you want to drive the runtime yourself from Dart.

```dart
import 'dart:convert' show utf8;

import 'package:love2d/love2d.dart';

final runtime = LoveScriptRuntime(
  host: LoveHeadlessHost(),
  filesystemAdapter: LoveLualikeFilesystemAdapter(),
);

final filesystem = LoveFilesystemState.of(runtime.runtime);
final source = 'example/assets/my_game/main.lua';

if (!filesystem.setSource(source)) {
  throw StateError('Unable to mount $source');
}

await runtime.loadConfIfPresent();

final entry = await filesystem.readFileData('main.lua', filename: source);
await runtime.execute(
  utf8.decode(entry!.bytes),
  scriptPath: entry.filename,
);

await runtime.callLoadIfDefined();
await runtime.callUpdateIfDefined(1 / 60);
runtime.context.beginDrawFrame();
await runtime.callDrawIfDefined();
```

This is the right path for:

- smoke runners
- automated tests
- headless benchmarks
- scripted runtime experiments

### Manual Installation

If you already own the Lua runtime lifecycle yourself, you can work at a lower
level with:

- `installLove2d(...)`
- `attachLoveHost(...)`

Use `installLove2d(...)` to install the generated LOVE API surface plus runtime
bindings into an existing `LuaRuntime`.

Use `attachLoveHost(...)` when the LOVE bindings are already installed and you
only need to swap or configure host/filesystem state.

## Example App

A runnable Flutter/Flame example app lives in [`example/`](./example).

```bash
cd example
flutter run -d linux
```

The example launches a single-entrypoint game center and currently includes:

- LOVE Example Browser
- Modern Pong
- Pocket Bomber
- Shader Explorer
- Relic Breach

The example app also demonstrates:

- responsive game-center layout
- small-screen scrolling behavior
- per-demo touch controls on compact screens
- vendored demo asset registration

See [`example/README.md`](./example/README.md) for demo-specific details.

## Current Status

This package is already usable, but it is still being built toward broader LOVE
11.5 parity.

Current source-of-truth references:

- API inventory:
  [`doc/love_11_5_api_audit.md`](./doc/love_11_5_api_audit.md)
- compatibility matrix:
  [`doc/love_11_5_compatibility_matrix.md`](./doc/love_11_5_compatibility_matrix.md)
- generated reference and stubs:
  [`lib/src/generated/`](./lib/src/generated/)

In practice, the package is strongest today as:

- a Flutter/Flame LOVE-style harness
- a headless script runtime for tests and tooling
- a compatibility playground for real demos

## Advanced Topics

### Flutter Harness Options

`LoveFlameHarness` is the highest-level integration surface.

Useful options include:

- `entryAsset`
- `bundle`
- `filesystemAdapter`
- `audioBackendFactory`
- `videoFrameProviderFactory`
- `onInputAdaptersReady`
- `onQuitRequested`
- `engineMode`
- `automaticGc`
- `imageWarmupAssetKeys`
- `debugOnGameCreated`

The default engine mode for the Flame harness is `EngineMode.luaBytecode`.

### Filesystem And Assets

The two most common filesystem adapters are:

- `LoveAssetBundleFilesystemAdapter`
  - reads packaged Flutter assets
- `LoveLualikeFilesystemAdapter`
  - reads from the underlying runtime/local filesystem environment

Example:

```dart
import 'package:flutter/services.dart';
import 'package:love2d/love2d.dart';

final filesystemAdapter = await LoveAssetBundleFilesystemAdapter.load(
  bundle: rootBundle,
  fallback: LoveLualikeFilesystemAdapter(),
);
```

`LoveFilesystemState.setSource(...)` is the key mount step. Point it at the
LOVE entry asset or mounted source root before executing game code that depends
on relative filesystem access, `require`, `conf.lua`, or bundled assets.

When `LoveFlameHarness` runs an asset-backed source on non-web platforms, it
wraps that source with a writable Flutter save-path fallback so
`love.filesystem.write` and save identity behavior can still work.

For direct writable Flutter-path access outside that harness behavior, use
`LoveFlutterFilesystemAdapter.load()`.

### Video Support

If a game uses `love.graphics.newVideo`, provide a video frame provider factory.

The packaged implementation is `media_kit`-backed:

```dart
LoveFlameHarness(
  entryAsset: 'assets/my_game/main.lua',
  videoFrameProviderFactory: loveMediaKitVideoFrameProviderFactory(),
)
```

Notes:

- `loveMediaKitVideoFrameProviderFactory()` lazily initializes `media_kit`
- call `ensureLoveMediaKitInitialized()` yourself only if you want eager setup
- the same factory can be supplied through `LoveHeadlessHost` for headless use

### Shaders

Shader support on the Flutter backend follows Flutter's fragment-program
runtime-effect model, not full arbitrary LOVE shader compilation.

In practice, that means:

- register shader files in `flutter: shaders:` in `pubspec.yaml`
- keep using asset keys for those shader files consistently
- expect some LOVE shaders to need adaptation before they work on Flutter

The working example in this repository is `Shader Explorer`.

Its `pubspec.yaml` registers shader files like a normal Flutter app:

```yaml
flutter:
  shaders:
    - assets/shader_explorer/shaders/gradient.frag
    - assets/shader_explorer/shaders/lava.frag
    - assets/shader_explorer/shaders/water.frag
```

Those shader files use Flutter runtime-effect includes, for example:

```glsl
#include <flutter/runtime_effect.glsl>
```

The current shader bridge used by the example reads the shader source text and
binds it against a registered Flutter shader asset:

```lua
local raw = assert(love.filesystem.read("shaders/gradient.frag"))
local shader = love.graphics._newRegisteredFragmentShader(
  "assets/shader_explorer/shaders/gradient.frag",
  raw
)
```

Important limitation:

- some LOVE shaders will not work immediately on Flutter
- arbitrary runtime LOVE shader source is not fully supported on the Flutter
  backend yet
- the most reliable path today is using shader files that match Flutter's
  supported fragment-shader/runtime-effect model and registering them in
  `pubspec.yaml`

### Input And Controllers

For normal Flutter keyboard and pointer integration, `LoveFlameHarness` already
creates and wires the input adapters for you.

If you want custom controller injection, use
`LoveFlameHarness.onInputAdaptersReady` to access:

- `LoveFlameInputAdapter`
- `LoveJoystickInputAdapter`

Use the virtual-pad approach when the Lua game expects `love.keyboard`.

Use joystick/gamepad registration when the Lua game expects `love.joystick`.

The example app demonstrates both the idea of on-screen controls and the split
between keyboard-style virtual pads and joystick/gamepad devices.

### Performance Hooks

The Flame harness exposes a few useful startup and instrumentation hooks:

- `imageWarmupAssetKeys`
  - prewarms selected images before entering the running state
- `automaticGc`
  - enables Lualike automatic GC safe points
- `debugOnGameCreated`
  - exposes the created `LoveFlameHarnessGame`

These are useful when profiling startup cost, frame timing, and render stats in
larger demos.

## Regenerating The Audit

The audit is generated from the `love2d-community/love-api` repository, which
tracks the official LOVE wiki in a machine-readable Lua table.

```bash
lua tool/generate_love_api_audit.lua
```

## Generating Dart Stubs

The Dart stub layer is generated from a checked-in normalized snapshot of the
LOVE API. The snapshot is updated with a Dart script and the Dart source is
then generated with `build_runner`. The generated code keeps reference metadata
and runtime registration separate from the hand-editable override map in
[`lib/src/love_api_overrides.dart`](./lib/src/love_api_overrides.dart).

```bash
dart run tool/update_love_api_snapshot.dart
dart run build_runner build --delete-conflicting-outputs
```

Manual status overrides live in
[`tool/love_compatibility_overrides.lua`](./tool/love_compatibility_overrides.lua).
