# love2d

Workspace package for future LOVE 2D related Dart bindings and helpers.

## Status

This package is currently focused on planning the compatibility layer needed to
present a LOVE-like interface on top of `lualike`, Flutter, and the Flame
ecosystem.

The current source-of-truth inventory lives in
[`doc/love_11_5_api_audit.md`](./doc/love_11_5_api_audit.md).

The implementation-tracking view lives in
[`doc/love_11_5_compatibility_matrix.md`](./doc/love_11_5_compatibility_matrix.md).

The generated Dart reference and stub surface lives under
[`lib/src/generated/`](./lib/src/generated/).

## Example test bed

A runnable Flutter/Flame harness lives in [`example/`](./example). It loads a
Lua script, installs the current `love` runtime surface, and drives
`love.load` / `love.update` callbacks while showing the script snapshot and log
output in the UI.

```bash
cd example
flutter run -d linux
```

The default script for the harness lives at
[`example/assets/scripts/test_bed.lua`](./example/assets/scripts/test_bed.lua).

## Regenerating the audit

The audit is generated from the `love2d-community/love-api` repository, which
tracks the official LOVE wiki in a machine-readable Lua table.

```bash
lua tool/generate_love_api_audit.lua
```

## Generating Dart stubs

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
