# Neon Relay renderer demo

This is a small top-down technical game used to compare the `love2d` Canvas
renderer with the experimental Flutter GPU renderer. It loads the arena,
player, drone, and relay-beacon art through the Flutter asset bundle, then runs
the same LOVE draw snapshot through either backend or both side by side.
Relay-cell pickups add deterministic collection, energy, particle, respawn, and
second-SpriteBatch behavior without changing the shared source path.

Controls:

- WASD or arrow keys: move the skiff
- Space or left click: fire
- Fly over relay cells: recharge energy and score
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
touch callbacks are queued. The `love2d.setVirtualKey` and
`love2d.setVirtualPointer` diagnostic extensions provide deterministic walking
and aim state through Marionette in debug builds and the VM service in profile
builds.

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

The helper floats the native window at 1280x720 by default so repeated native
captures use the same presentation size. Pass `--window-size current` only when
the compositor-controlled tiled size is intentionally part of the comparison.

Capture the Flutter window with the Flutter development helper, then inspect
the native frame beside the Canvas/GPU comparison:

```bash
python3 ~/.codex/skills/flutter-dev/scripts/flutter_capture.py window \
  lualike_love2d_neon com.example.love2d_gpu_demo \
  /tmp/love2d-benchmark/neon-relay-flutter.png
```

For a renderer-to-renderer pixel metric, keep the app in comparison mode and
use the checked-in capture helper. It resizes the window so the 800x600 LOVE
surface is presented at exactly 1:1, removes fractional pane alignment from the
measurement, crops the synchronized Canvas/GPU panes, and records normalized
RMSE:

```bash
bash tool/capture_renderer_comparison.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=' \
  --output-prefix /tmp/love2d-benchmark/neon-relay-comparison
```

The default `--chrome-height 103` matches this Linux/Hyprland Flutter window.
Override it when window decorations differ; the helper rejects fractional pane
geometry rather than producing a misleading comparison. With `--vm`, it also
switches to comparison mode, waits for `ready=true` with a non-empty command
snapshot, resets input and the scene, fixes the logical pointer, and waits for
the reset frame. Omit `--vm` only when that synchronization was performed by a
different harness.

The generated images are project assets, not placeholders: `flutter_lualike`
indexes and prewarms all five files under `assets/art/`, while native LOVE
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
  --pointer 640,360 \
  --warmup-seconds 2
```

The helper waits for each renderer replacement to report `ready`, clears stale
input, moves LOVE's logical pointer to the requested coordinate, settles the
scene, presses `r` and waits for the reset frame, resets the rolling window,
then writes compact Canvas, GPU, and comparison records to
`/tmp/love2d-benchmark/relic-timings.jsonl`. Omit `--hold-key` for an idle trial,
or pass `--reset-key none` when the current world state is intentional. Timing
history is a 240-frame ring, so `--samples` accepts 1 through 240 and rejects
larger windows instead of waiting for a count that cannot be retained.
Pass `--pointer none` only when preserving interactive aim state is intentional.

For Value/Environment and garbage-churn work, capture VM allocation counters
around that same deterministic window:

```bash
bash tool/profile_relic_allocations.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=' \
  --samples 240 \
  --mode gpu \
  --hold-key d \
  --pointer 640,360 \
  --reset-key r \
  --output-prefix /tmp/love2d-benchmark/relic-allocations
```

Run this against a fresh profile-mode app. It writes the raw reset/profile
responses, timing JSONL, and a compact summary including maps, fixed lists, and
growable lists per `Environment`. Those normalized ratios remain useful when absolute
allocation counts differ because a world state or sampling interval changed.
