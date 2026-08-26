# Neon Relay renderer demo

This is a small top-down technical game used to compare the `love2d` Canvas
renderer with the experimental Flutter GPU renderer. It loads the arena,
player, drone, and relay-beacon art through the Flutter asset bundle, then runs
the same LOVE draw snapshot through either backend or both side by side.

Controls:

- WASD or arrow keys: move the skiff
- Space or left click: fire
- R: reset the deterministic encounter
- The top-right control: cycle comparison, GPU-only, and Canvas-only modes

Run it from this directory:

```bash
fvm flutter run -d linux --debug \
  --enable-impeller --enable-flutter-gpu --print-dtd
```

The default `LOVE_ENGINE_MODE=ast` keeps compatibility behavior unchanged.
The real game can also be tested with the lualike IR runtime:

```bash
fvm flutter run -d linux --profile \
  --enable-impeller --enable-flutter-gpu \
  --dart-define=LOVE_ENGINE_MODE=ir
```

Treat IR as an experimental A/B trial: record the `engineMode` field from
`love2d.getRenderState` and keep it separate from AST timing records.

The normal debug path initializes `marionette_flutter`; Flutter Driver is
available only when `--dart-define=ENABLE_FLUTTER_DRIVER=true` is supplied.
The `love2d.getRenderState` Marionette/VM extension is the synchronization
point for automated screenshots and timing trials.

In comparison mode, corresponding points in either pane are converted back to
the same LOVE coordinate before `love.mousemoved`, `love.mousepressed`, and
touch callbacks are queued. The debug-only `love2d.setVirtualKey` extension
can hold a LOVE key for repeatable walking and performance trials.

## Benchmark the native LOVE samples

The bundled Neon Relay workload is also a native LOVE project. Run the exact
same `assets/main.lua` source with the installed LOVE CLI:

```bash
love assets
```

On a Hyprland/Wayland host, the capture helper waits for the LOVE window and
saves a post-startup screenshot:

```bash
bash tool/capture_native_love.sh \
  --project assets \
  --output /tmp/love2d-benchmark/neon-relay-native.png
```

Capture the Flutter window with the Flutter development helper, then inspect
the native frame beside the Canvas/GPU comparison:

```bash
python3 ~/.codex/skills/flutter-dev/scripts/flutter_capture.py window \
  lualike_love2d_neon com.example.love2d_gpu_demo \
  /tmp/love2d-benchmark/neon-relay-flutter.png
```

The generated images are project assets, not placeholders: `flutter_lualike`
indexes and prewarms all four files under `assets/art/`, while native LOVE
loads the same files through its regular filesystem.

For a renderer benchmark grounded in a real LOVE workload, run the vendored
Relic Breach source directly through the installed LOVE CLI:

```bash
love ../../love2d/example/assets/relic_breach
```

The Flutter demo can consume that same checkout tree in debug mode without
copying its asset pack:

```bash
fvm flutter run -d linux --debug \
  --enable-impeller --enable-flutter-gpu --print-dtd \
  --dart-define=LOVE_ENTRY_ASSET="$PWD/../../love2d/example/assets/relic_breach/main.lua"
```

This host-source mode uses `LoveLualikeFilesystemAdapter` for the physical Lua
and image files, while packaged demo runs continue to use
`flutter_lualike`'s `AssetBundleFileSystemBackend`. Capture the native LOVE
window and the Flutter comparison with the same scene state; query
`love2d.getRenderState` after `frame_ready` so the screenshot and timing sample
refer to a known frame. Comparison-mode state also reports separate Canvas and
GPU render counters, including software-surface fallbacks.

For repeatable three-mode timing trials, pass the VM service URL printed by
`flutter run` to the checked-in helper:

```bash
bash tool/benchmark_relic_breach.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=' \
  --samples 240 \
  --hold-key d \
  --warmup-seconds 2
```

The helper waits for each renderer replacement to report `ready`, settles the
scene, resets the rolling window, then writes compact Canvas, GPU, and
comparison records to `/tmp/love2d-benchmark/relic-timings.jsonl`. Omit
`--hold-key` for an idle trial.
