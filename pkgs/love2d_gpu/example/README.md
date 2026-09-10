# Neon Relay renderer demo

This is a small top-down technical game used to compare the `love2d` Canvas
renderer with the experimental Flutter GPU renderer. It loads the arena,
player, drone, and relay-beacon art through the Flutter asset bundle, then runs
the same LOVE draw snapshot through either backend or both side by side.

## Linux renderer policy

Native LOVE is the visual authority for this demo. On Linux, use the Canvas
backend without Impeller as the supported Flutter control and treat
`love2d_gpu` through Impeller as an experimental diagnostics lane. Current
Flutter Linux Impeller still has an open vector anti-aliasing defect and its
desktop Vulkan backend remains under development:

- <https://github.com/flutter/flutter/issues/191171>
- <https://github.com/flutter/flutter/issues/183495>

Do not attribute a full-scene Linux GPU residual to Lualike unless the same
difference survives in a reduced, source-identical probe and can be traced to
our command encoding, resource state, or shader. Linux GPU tests still enforce
command semantics, resource lifetime, and frame-tail budgets; they do not
claim byte-identical native LOVE rasterization.

Run the Linux Canvas control without initializing `flutter_gpu`:

```bash
fvm flutter run -d linux --profile --no-enable-impeller --print-dtd \
  --dart-define=LOVE2D_DEMO_FORCE_CANVAS=true
```

`love2d.getRenderState` reports `gpuInitializationDisabled=true`,
`gpuAvailable=false`, and `mode=canvas` for this lane.

Capture native LOVE and this non-Impeller Canvas lane at exact 800x600 with:

```bash
mkdir -p ../../../.tmp/parity
TMPDIR="$PWD/../../../.tmp" bash tool/capture_renderer_parity.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=/' \
  --canvas-only \
  --project assets \
  --native-game-arg --parity-freeze \
  --regions assets/neon_relay_regions.json \
  --output-prefix "$PWD/../../../.tmp/parity/neon-relay-skia-canvas"
```

The verified frozen-scene capture measured `0.0199939` native-to-Canvas
full-frame RMSE. That is visually close but not a parity improvement over the
same Canvas commands under Impeller (`0.0128832`) or the direct GPU lane
(`0.00892302`). Use the non-Impeller lane to isolate platform behavior, not as
an assumption that Skia must rasterize closer to native LOVE.

Canvas-only, GPU-only, and side-by-side presentation hot-swap the render
backend on one `LoveFlameHarnessGame`. The LOVE runtime, simulation state,
input adapters, decoded images, and SpriteBatches remain mounted while modes
change. This keeps the two renderers synchronized and prevents renderer
comparison from multiplying the complete asset pack in the Dart heap.
Use
`--dart-define=LOVE2D_DEMO_RECREATE_HARNESS_ON_MODE_SWITCH=true` only to
exercise discarded-runtime resource lifetime in a diagnostic build.
Launch the bytecode diagnostic build in profile mode:

```bash
fvm flutter run -d linux --profile \
  --enable-impeller --enable-flutter-gpu --print-dtd \
  --dart-define=LOVE_ENGINE_MODE=luaBytecode \
  --dart-define=LOVE2D_DEMO_RECREATE_HARNESS_ON_MODE_SWITCH=true
```

Then automate the forced-GC ownership gate with:

```bash
TMPDIR="$PWD/../../../.tmp" bash tool/profile_renderer_lifetime.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=' \
  --cycles 4
```

The helper waits for every replacement to render a non-empty frame, forces two
Dart collections, records the allocation and memory profiles, and fails unless
exactly one bytecode runtime, LOVE runtime context, host, and game survive.
The checked-in gate was replayed through four complete generations with a
250 MB heap ceiling and 32-image ceiling; it retained one of each owner,
185,473,376 heap bytes, and 25 `LoveImage` objects.
Relay-cell pickups add deterministic collection, energy, particle, respawn, and
second-SpriteBatch behavior without changing the shared source path. Eight
drone kills transition into a sentinel encounter with a deterministic expanding
shock ring, aimed five-bolt ion volleys, health bar, damage feedback, and
wave-three completion state. The hostile bolts use a fixed 24-slot dynamic
SpriteBatch so the encounter adds texture pressure without per-frame table
growth. Two timed relay-shield emitters add pickup, respawn, absorption,
hit-feedback, and third-pickup-SpriteBatch behavior while keeping gameplay
state in fixed arrays.

Controls:

- WASD or arrow keys: move the skiff
- Space or left click: fire
- Fly over relay cells: recharge energy and score
- R: reset the deterministic encounter
- B: reset directly into the sentinel benchmark phase
- C: reset into the deterministic CPU-heavy signal-lattice laboratory
- V: reset into the sentinel parity scene and freeze simulation
- The top-right control: cycle comparison, GPU-only, and Canvas-only modes

## Deterministic VM parity gate

The C state runs a fixed-capacity 64-node signal simulation while preserving a
150-command game frame. Neon Relay and the standalone benchmark both load
`assets/shared/signal_lattice.lua`; the packaged Flutter app discovers it
through `flutter_lualike`'s asset filesystem, while native LOVE and the Lualike
CLI load the same file from the project directory. The hot simulation step
mutates preallocated arrays and creates no Lua tables, so the result primarily
measures numeric, indexed-table, and control-flow execution rather than Dart
GC noise.

Run the pure kernel through native LOVE plus every supported Lualike engine:

```bash
mkdir -p ../../../.tmp/signal-lattice
TMP="$PWD/../../../.tmp" TMPDIR="$PWD/../../../.tmp" \
  bash tool/benchmark_signal_lattice.sh \
  --frames 240 \
  --trials 5 \
  --output-prefix "$PWD/../../../.tmp/signal-lattice/kernel-240x5"
```

Every trial must finish at the same tick and checksum or the helper exits
nonzero. The verified 240-frame, five-trial run produced tick `240`, checksum
`255002`, and these medians:

| Engine | Median microseconds/frame |
| --- | ---: |
| Native LOVE 11.5 | 3.86 |
| Lualike IR | 2,207.14 |
| Lualike lua-bytecode | 2,348.42 |
| Lualike AST | 9,144.00 |

This is a behavior-parity gate and an optimization compass, not a claim that
the host processes have equivalent startup or embedding overhead. It puts the
remaining runtime gap outside Impeller: IR and bytecode stay inside a 120 Hz
pure-simulation budget for this kernel, while AST does not.

For the same kernel inside the rendered game, launch the supported Linux
Canvas control in profile mode, then have the timing helper press C and verify
that the reported workload and checksum advance:

```bash
fvm flutter run -d linux --profile --no-enable-impeller --print-dtd \
  --dart-define=LOVE2D_DEMO_FORCE_CANVAS=true \
  --dart-define=LOVE_ENGINE_MODE=luaBytecode

TMP="$PWD/../../../.tmp" TMPDIR="$PWD/../../../.tmp" \
  bash tool/benchmark_relic_breach.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=/' \
  --mode canvas \
  --reset-key c \
  --expected-workload signal-lattice \
  --samples 240 \
  --trials 3 \
  --min-average-commands 140 \
  --output "$PWD/../../../.tmp/signal-lattice/flutter-bytecode-3x240.jsonl"
```

The corrected live run measured median p95/p99 awaited `love.update` times of
5,196/5,639 microseconds, complete runtime-frame p95/p99 of 9,729/10,261
microseconds, and total CPU-frame p95/p99 of 10,546/11,037 microseconds. None
of 720 samples exceeded the 60 Hz budget; 77 exceeded the 120 Hz budget. These
numbers intentionally use Canvas without Impeller so Linux GPU maturity cannot
be mistaken for Lualike VM cost.

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

Neon Relay requests linear mipmaps for the same eleven textures under native
LOVE and Flutter. The GPU backend uploads that authored mip chain only when the
active Flutter GPU context reports manual-mipmap support. For a matched
base-level-only build, add:

```bash
--dart-define=LOVE2D_GPU_MIPMAP_UPLOADS=false
```

`love2d.getRenderState` records both `gpuMipmapUploads` and
`gpuManualMipmapsSupported`, so screenshots and timing files prove which path
actually ran.

The normal debug path initializes `marionette_flutter`; Flutter Driver is
available only when `--dart-define=ENABLE_FLUTTER_DRIVER=true` is supplied.
The `love2d.getRenderState` Marionette/VM extension is the synchronization
point for automated screenshots and timing trials.
`love2d.setCapturePresentation` temporarily hides the demo-only renderer
control, harness status badge, and virtual cursor overlay so a screenshot
contains only the LOVE surface. Loading and runtime-error diagnostics remain
visible.

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
Override it when window decorations differ; one-pixel compositor resize
rounding is reconciled from the actual window geometry and recorded in the
summary, while larger mismatches and fractional pane geometry are rejected.
With `--vm`, it also
switches to comparison mode, waits for `ready=true` with a non-empty command
snapshot, resets input and the scene, fixes the logical pointer, and waits for
the reset frame. Omit `--vm` only when that synchronization was performed by a
different harness.

The generated images are project assets, not placeholders: `flutter_lualike`
indexes and prewarms all eleven files under `assets/art/`, while native LOVE
loads the same files through its regular filesystem.

## Generated-stroke performance A/B

Animated circle and arc outlines can use reusable typed coordinate buffers
instead of allocating a Dart point record for every generated vertex. Ordinary
builds use the typed path and compile out live tuning. To collect an
order-balanced comparison inside one profile-mode process, launch with:

```bash
fvm flutter run -d linux --profile \
  --enable-impeller --enable-flutter-gpu --print-dtd \
  --dart-define=LOVE2D_GPU_RUNTIME_STROKE_TUNING=true
```

Then run:

```bash
TMPDIR="$PWD/../../../.tmp" \
  bash tool/benchmark_generated_strokes_ab.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=' \
  --pairs 7 \
  --output-prefix "$PWD/../../../.tmp/generated-strokes-ab"
```

The helper alternates records-first and typed-first pairs, requires exact 1:1
presentation and the sentinel command floor, and reports both raw medians and
paired deltas. `LOVE2D_GPU_TYPED_GENERATED_STROKES=false` remains the
production-build rollback when a host-specific regression must be isolated.

Odd-width rough lines use one shared, allocation-free pixel-alignment rule in
Canvas and GPU. A device axis is shifted by half a pixel only when every
transformed point on that axis is integral; authored or transformed half-pixel
coordinates remain untouched. This matches LÖVE's pixel-corner convention
without over-correcting already centered strokes. Use
`--dart-define=LOVE_CANVAS_ROUGH_LINE_PIXEL_SNAP=false` or
`--dart-define=LOVE2D_GPU_ROUGH_LINE_PIXEL_SNAP=false` for backend-specific
rollback.

Canvas rough circles and open arcs use LOVE's transform-aware automatic point
counts instead of Flutter's analytically smooth curve primitives. Normalized
unit paths are cached by point count and sweep, then positioned and scaled at
draw time, so animated radii do not rebuild Dart paths or recompute
trigonometry every frame. In the frozen Neon Relay comparison this reduced
native-to-Canvas full-frame RMSE from `0.0228939` to `0.0128832` while an
eight-pair walking benchmark retained zero 120 Hz overruns and improved the
aggregate p95, p99, and maximum-frame medians. Use
`--dart-define=LOVE_CANVAS_ROUGH_CURVE_TESSELLATION=false` for the production
rollback.

For an order-balanced A/B in one profile process, launch with
`--dart-define=LOVE_CANVAS_RUNTIME_ROUGH_CURVE_TUNING=true`, then pass either
`--canvas-rough-curves=true` or `--canvas-rough-curves=false` to
`tool/benchmark_relic_breach.sh`. `love2d.getRenderState` records both
`canvasRoughCurveTessellation` and `canvasRuntimeRoughCurveTuning`, and the
Marionette/DTD event `canvas_rough_curve_path_changed` is emitted when the
diagnostic path changes.

Canvas normally filters Flutter's premultiplied image pixels. LOVE filters
straight RGB and alpha before blending, so transparent texture edges can lose
color and appear darker in Canvas. The optional straight-alpha texture path
reconstructs that behavior with one cached runtime shader and an opaque-RGB
companion image selected from the existing LOVE mip chain. It is limited to
transparent, linearly filtered direct image draws projected between 80 and 512
pixels; SpriteBatch draws and unsupported images keep the normal Canvas path.

In the frozen Neon Relay comparison, this reduced native-to-Canvas full-frame
RMSE from `0.0128832` to `0.0100513` (22.0%). The warmed game retained nine
companions using approximately 4.92 MB. In an eight-pair walking A/B, enabling
the path retained zero 120 Hz overruns; aggregate median p95 moved from
`931.5 us` to `945 us`, while the paired-median p95 delta was `+85 us`. Because
this trades a small frame cost and resident memory for closer texture parity,
it remains disabled by default. Enable it with:

```bash
--dart-define=LOVE_CANVAS_STRAIGHT_ALPHA_TEXTURES=true
```

`LOVE_CANVAS_STRAIGHT_ALPHA_RGB_MAX_DIMENSION` and
`LOVE_CANVAS_STRAIGHT_ALPHA_MIN_PROJECTED_DIMENSION` tune the companion-mip
ceiling and projected-size floor. For a same-process A/B, also launch with
`LOVE_CANVAS_RUNTIME_STRAIGHT_ALPHA_TEXTURE_TUNING=true`, then pass
`--canvas-straight-alpha-textures=true|false` to
`tool/benchmark_relic_breach.sh`. Render state records the selected path,
binding count, and estimated bytes; the Marionette/DTD event
`canvas_straight_alpha_texture_path_changed` records runtime changes.

## Sprite geometry performance A/B

SpriteBatch and particle commands normally expand their quads into one reused
typed buffer with direct 2D affine math. This avoids a new vertex array plus
temporary Matrix4, Offset, and LoveColor objects for every batch entry. To
compare the retained path with the legacy matrix-heavy expansion inside one
profile process, launch with:

```bash
fvm flutter run -d linux --profile \
  --enable-impeller --enable-flutter-gpu --print-dtd \
  --dart-define=LOVE2D_GPU_RUNTIME_SPRITE_GEOMETRY_TUNING=true
```

Then run:

```bash
TMPDIR="$PWD/../../../.tmp" \
  bash tool/benchmark_sprite_geometry_ab.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=' \
  --pairs 7 \
  --output-prefix "$PWD/../../../.tmp/sprite-geometry-ab"
```

The helper alternates legacy-first and direct-first windows, pins the same
sentinel workload and pointer, and rejects non-1:1 presentation or insufficient
command pressure. `LOVE2D_GPU_DIRECT_SPRITE_GEOMETRY=false` is the exact
production-build rollback.

To isolate the sentinel workload in the timing helper, use `--reset-key b`.
The key now resets the complete fixed-capacity world before activating the
sentinel: clocks, player state, enemies, projectiles, particles, pickups,
health, shock-ring cadence, and motion all begin from the same values.

The native capture helper accepts the same phase key for a source-for-source
visual reference:

```bash
bash tool/capture_native_love.sh \
  --project assets \
  --key v \
  --game-arg --parity-freeze \
  --window-size 800x600 \
  --output /tmp/love2d-benchmark/neon-relay-sentinel-native.png
```

`v` selects the parity-freeze scene: it performs the same complete sentinel
reset as `b`, fixes aim at `(640,360)`, and pauses simulation updates. Use
`--reset-key v` with `capture_renderer_comparison.sh` to capture the exact same
source state through Canvas and Flutter GPU. Press `r` or `b` to resume normal
simulation.

For a full-resolution three-way parity capture, launch the Flutter app in
profile mode and pass its VM service URL to the parity helper:

```bash
mkdir -p ../../../.tmp/parity
TMPDIR="$PWD/../../../.tmp" bash tool/capture_renderer_parity.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=/' \
  --project assets \
  --native-game-arg --parity-freeze \
  --regions assets/neon_relay_regions.json \
  --output-prefix "$PWD/../../../.tmp/parity/neon-relay"
```

The capture helper removes compositor borders and rounding, requires exact
800x600 presentation, and writes both a whole-frame summary and a named-region
report. `tool/score_renderer_regions.sh` can also rescore existing captures.
Use `assets/parity_probe/regions.json` for the pixel-corner probe.

The helper launches native LOVE with the deterministic startup argument and
drives the same `v` scene through both Flutter renderers. The startup argument
keeps native capture reliable when a Wayland synthetic key is dropped. It
resizes each surface to 800x600 at 1:1, suppresses host-only overlays through
`love2d.setCapturePresentation`, and writes native, Canvas, GPU, render-state,
and normalized-RMSE artifacts plus one summary JSON file.
It verifies a zero-offset 800x600 presentation rectangle before every Flutter
capture and corrects a compositor-supplied extra pixel when necessary; this
prevents half-pixel resampling from contaminating parity measurements.
Unwrapped source-backed TrueType text uses LOVE-fitted advance widths by
default. Add `--dart-define=LOVE_FREETYPE_TEXT_SPACING=false` to the Flutter
launch only when performing a reverse spacing A/B; it is a diagnostic switch,
not the recommended rendering mode.
Printable ASCII TrueType text is also pre-rasterized from the source font and
drawn from one cached atlas. Covered `print`, `printf`, and `Text` commands use
the direct GPU path for left, center, and right wrapped alignment; adjacent
commands with a shared atlas and draw state are submitted as one ordered
vertex stream. Justified text, fallback fonts, and uncovered codepoints retain
the TextPainter fallback. Add
`--dart-define=LOVE_FREETYPE_GLYPH_ATLAS=false` only for the matched rollback.
Use `--dart-define=LOVE2D_GPU_FORMATTED_ATLAS_TEXT=false` to retain ordinary
unwrapped atlas text while routing formatted commands through the old fallback.

`assets/formatted_text_probe` is the deterministic native/Canvas/GPU control
for word wrapping, left/center/right alignment, colored spans, explicit
newlines, and `Text:setf` objects. Launch it with
`--dart-define=LOVE_ENTRY_ASSET=assets/formatted_text_probe/main.lua`, then pass
`--project assets/formatted_text_probe` to `capture_renderer_parity.sh`.
`assets/parity_probe` also includes integer- and half-pixel width-1 smooth
lines. The GPU backend reproduces LOVE's reduced opaque core and one-pixel
alpha overdraw for eligible two-point, single-sample, pure-translation lines.
Use `--dart-define=LOVE2D_GPU_SMOOTH_LINE_OVERDRAW=false` to restore the old
opaque stroke for a matched visual or timing rollback.
Eligible axis-aligned odd-width rough lines use one exact pixel-run rectangle,
which preserves native open-cap occupancy without shifting the line left or
up. Use `--dart-define=LOVE2D_GPU_ROUGH_AXIS_RUNS=false` to restore the prior
triangle-and-translation path. For a same-process profile A/B, compile with
`LOVE2D_GPU_RUNTIME_ROUGH_AXIS_RUN_TUNING=true` and run
`tool/benchmark_rough_axis_runs_ab.sh`; the LOVE-specific Marionette/VM control
is `love2d.setRoughAxisRuns`.
The portable glyph rasterizer also calibrates partial edge coverage against a
matched native LOVE capture. Add
`--dart-define=LOVE_FREETYPE_GLYPH_COVERAGE_GAMMA=1.0` to restore its neutral
4x4 coverage for a reverse A/B; zero and fully covered pixels are unchanged.

Mipmapped GPU textures apply LOVE's `mipmapSharpness` semantics directly.
Centered linear mip generation removed the need for the older flutter_gpu
`-0.5` compensation. Use
`--dart-define=LOVE2D_GPU_MIPMAP_LOD_COMPENSATION=-0.5` to reproduce that old
sampling path, or
`--dart-define=LOVE2D_GPU_ADAPTIVE_MIPMAP_LOD_COMPENSATION=false` to apply a
diagnostic compensation uniformly. Lualike generates odd-sized mip levels with
centered linear sampling so their normalized footprint matches a GPU blit; use
`--dart-define=LOVE2D_CENTERED_LINEAR_MIPMAPS=false` for the old uneven
area-partition generator. The
build-hook shader bundle is loaded before the checked-in fallback so local GLSL
changes are included in captures; run `bash ../tools/build_shaders.sh` from the
package directory after editing shader sources.

`assets/texture_probe.lua` isolates that path with the same minified player and
sentinel textures drawn directly and through static SpriteBatches. Launch the
Flutter side with `LOVE_ENTRY_ASSET=assets/texture_probe.lua`, and pass
`--project assets --native-game-arg --texture-probe --regions
assets/texture_probe_regions.json` to `capture_renderer_parity.sh`. The direct
and batched regions should agree; a difference points to geometry or batch
state rather than mip generation. `LOVE2D_GPU_MIPMAP_UPLOADS=false` is a
base-level-only diagnostic rollback, not a recommended rendering mode.

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

Neon Relay's arena, ships, pickups, boss, projectiles, impacts, and central
relay core are original generated PNG assets under `assets/art/`. The packaged
demo discovers and prewarms that directory through
`AssetBundleFileSystemBackend`; the Lua source refers to the same relative
paths that native LOVE resolves from the project directory. The relay-core
sprite was generated with the built-in image-generation workflow using the
existing asset montage as a style reference, with a transparent background and
no text.

For repeatable three-mode timing trials, pass the VM service URL printed by
`flutter run` to the checked-in helper:

```bash
bash tool/benchmark_relic_breach.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=' \
  --samples 240 \
  --trials 5 \
  --hold-key d \
  --pointer 640,360 \
  --min-average-commands 90 \
  --warmup-seconds 2
```

The helper waits for each renderer replacement to report `ready`, clears stale
input, pins LOVE's logical pointer against host mouse events, settles the
scene, presses `r` and waits for the reset frame, resets the rolling window,
then writes compact Canvas, GPU, and comparison records to
`/tmp/love2d-benchmark/relic-timings.jsonl`. Omit `--hold-key` for an idle trial,
or pass `--reset-key none` when the current world state is intentional. Timing
history is a 240-frame ring, so `--samples` accepts 1 through 240 and rejects
larger windows instead of waiting for a count that cannot be retained. Use
`--trials` to collect up to 20 independent windows in one launch; every record
includes `trialIndex`. The helper aborts if the pinned pointer or presentation
geometry changes during the set, preventing desktop activity from silently
invalidating a comparison. For the sentinel workload,
`--min-average-commands 90` also rejects a reset or phase-transition failure
that would otherwise produce a geometrically valid but substantially lighter
trial.
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
  --min-average-commands 90 \
  --output-prefix /tmp/love2d-benchmark/relic-allocations
```

Run this against a fresh profile-mode app. It writes the raw reset/profile
responses, timing JSONL, and a compact summary including maps, fixed lists, and
growable lists per `Environment`. Top-class rows preserve accumulated
`instances`/`bytes` and also report VM `currentInstances`/`currentBytes`, which
is useful for distinguishing allocation churn from retained heap. Those
normalized ratios remain useful when absolute allocation counts differ because
a world state or sampling interval changed.

The demo uses Lualike's Lua-compatible collector by default. To measure a
host-owned runtime that leaves object reclamation entirely to Dart, launch the
same profile build with:

```bash
fvm flutter run -d linux --profile \
  --dart-define=LUALIKE_HOST_MANAGED_GC=true
```

This is an explicit compatibility tradeoff: Lua weak tables act as strong
maps and `__gc` does not run, while lexical `__close` still does. It is meant
for deterministic game runtimes that explicitly close external resources,
not as a universal faster default. Compare it against a fresh default-policy
process at the same frame age and force Dart GC before recording retained
instances.

For exact transient-binding counts, opt in when launching the profile build:

```bash
fvm flutter run -d linux --profile \
  --enable-impeller --enable-flutter-gpu --print-dtd \
  --dart-define=LUALIKE_BINDING_DIAGNOSTICS=true
```

`love2d.getRenderState` then includes `runtimeBindings.created` and
`runtimeBindings.reused`. The timing helper resets both counters with its frame
window. Add `--dart-define=LUALIKE_LOOP_LOCAL_REUSE=false` for the matched
closure-free binding-reuse baseline; ordinary builds compile out the counters.
Use `--dart-define=LUALIKE_AST_CLOSURE_SCAN_CACHE=false` only for the matched
baseline of the AST statement-list closure-analysis cache.
Use `--dart-define=LUALIKE_IDENTIFIER_FRAME_LOOKUP_FAST_PATH=false` for the
matched identifier-frame baseline. The default path scans the call stack
backward without creating a reversed list and reuses that result throughout
one identifier resolution.
Use `--dart-define=LUALIKE_FUNCTION_BINDING_POOL=false` for the matched
function-binding baseline. Eligible function environments were already pooled;
the default path now keeps their uncaptured transient parameter/local boxes in
that pool as well. Debug-hook, closable, captured, and otherwise ineligible
function frames retain the existing allocation path. Bodies that can create a
nested function also stay on the clear-only path, including restored legacy
chunks whose capture metadata cannot prove box ownership.
Use `--dart-define=LUALIKE_BOUNDED_NUMERIC_PRIMITIVE_CACHE=false` for the old
unbounded numeric-wrapper cache. The default keeps at most 4,096 exact wrappers
per numeric key representation; override that limit with
`--dart-define=LUALIKE_NUMERIC_PRIMITIVE_CACHE_LIMIT=<count>`. Eviction changes
only cache ownership: values retained by Lua tables, locals, closures, or Dart
code stay alive, and exact `-0.0` and NaN payload keys remain distinct.
Use `--dart-define=LUALIKE_SINGLE_MAP_ENVIRONMENT_LOOKUP=false` for the old
double-probe `Environment.get` path. The default reads each environment map
once per scope instead of calling `containsKey` before indexing it.
Use `--dart-define=LUALIKE_SYNC_IDENTIFIER_RESULTS=false` for the old
always-async AST identifier visitor. The default returns ordinary local,
upvalue, and direct-global reads synchronously while preserving a `Future` for
yielding `_ENV.__index` lookups. `AstNode.accept` now returns `FutureOr<T>`;
callers that already `await` it need no changes, while callers that require an
exact `Future<T>` can wrap it with `Future.sync`.
Use `--dart-define=LUALIKE_SHARED_BINARY_METAMETHOD_MAP=false` to restore the
old per-expression operator-to-metamethod map. The default shares one immutable
map across non-numeric binary operations, avoiding repeated map construction
without changing lookup or metamethod precedence.
Use `--dart-define=LUALIKE_AST_INLINE_BUILTIN_FRAME=false` to restore managed
AST call frames for every builtin call. The default skips those frames only for
leaf builtins that explicitly opt into the same frame-free contract used by the
bytecode VM, and automatically restores them whenever a debug hook is active.
Use `--dart-define=LUALIKE_AST_INDEXED_LOCAL_FRAME=false` to disable the AST
indexed-local compatibility frame. The default caches resolved local slots and
keeps boxed bindings authoritative, so closure, `<const>`, `<close>`, and
upvalue identity continue to use their existing `Environment` facade.
Use `--dart-define=LUALIKE_AST_SLOT_ONLY_PARAMETERS=false` to restore a Box for
every AST function parameter. The default stores non-`_ENV` parameters directly
in closure-free functions. Logical call frames own the indexed state across
nested calls, tail calls, protected errors, and coroutine suspension.
Use `--dart-define=LUALIKE_AST_SLOT_ONLY_LOCALS=false` to restore a Box for
eligible AST local declarations. The default stores uncaptured locals directly
in closure-free functions, including declarations in blocks, branches, and
loop bodies. Lexical owner checks keep shadowed slots invisible after their
scope exits; `_ENV`, `_G`, attributed, captured, and debug-hook-observable
locals remain boxed. Tables, strings, functions, and userdata retain their
canonical `Value` facade in the slot. Use
`--dart-define=LUALIKE_AST_SLOT_ONLY_IDENTITY_LOCALS=false` to restore Boxes for
those identity-bearing values while leaving primitive direct slots enabled. Use
`--dart-define=LUALIKE_AST_SLOT_ONLY_NESTED_LOCALS=false` to keep only
top-level declarations direct. Use
`--dart-define=LUALIKE_AST_SLOT_ONLY_CALL_CAPABLE_FRAMES=false` for the prior
call-free leaf boundary while leaving the other slot paths enabled.
Use `--dart-define=LUALIKE_NORMALIZE_EMPTY_LOCAL_ATTRIBUTES=false` for the old
parser-attribute path. The default treats the parser's empty attribute string
as no attribute, avoiding unnecessary primitive local-binding clones while
preserving `<const>` and `<close>` handling.

With `--dart-define=LUALIKE_BINDING_DIAGNOSTICS=true`, `love2d.getRenderState`
reports the exact owned-class counters under `runtimeValues`, `runtimeBindings`,
and `runtimeLocalFrames`. The allocation helper validates that schema and can
exit nonzero when required counters or workload invariants are missing; a JSON
file existing on disk is not by itself a successful profile.

The isolated lookup kernel can be reproduced from `pkgs/lualike`:

```bash
mkdir -p ../../.tmp
dart compile exe benchmark/identifier_lookup.dart \
  -o ../../.tmp/identifier_lookup
../../.tmp/identifier_lookup 500000 9
```

The pooled-function allocation kernel uses compile-time flags, so build both
variants from `pkgs/lualike`:

```bash
dart compile exe \
  -DLUALIKE_BINDING_DIAGNOSTICS=true \
  -DLUALIKE_FUNCTION_BINDING_POOL=false \
  -o ../../.tmp/function_binding_pool_off \
  benchmark/function_binding_pool.dart
dart compile exe \
  -DLUALIKE_BINDING_DIAGNOSTICS=true \
  -DLUALIKE_FUNCTION_BINDING_POOL=true \
  -o ../../.tmp/function_binding_pool_on \
  benchmark/function_binding_pool.dart
../../.tmp/function_binding_pool_off 5000 7
../../.tmp/function_binding_pool_on 5000 7
```

The numeric-cache retention kernel should also be built both ways because the
switch is a compile-time constant:

```bash
dart compile exe \
  -DLUALIKE_BOUNDED_NUMERIC_PRIMITIVE_CACHE=false \
  -o ../../.tmp/numeric_cache_off \
  benchmark/numeric_primitive_cache.dart
dart compile exe \
  -DLUALIKE_BOUNDED_NUMERIC_PRIMITIVE_CACHE=true \
  -o ../../.tmp/numeric_cache_on \
  benchmark/numeric_primitive_cache.dart
../../.tmp/numeric_cache_off 100000 7
../../.tmp/numeric_cache_on 100000 7
```

The environment lookup kernel should likewise be built both ways:

```bash
dart compile exe \
  -DLUALIKE_SINGLE_MAP_ENVIRONMENT_LOOKUP=false \
  -o ../../.tmp/environment_lookup_off \
  benchmark/environment_lookup.dart
dart compile exe \
  -DLUALIKE_SINGLE_MAP_ENVIRONMENT_LOOKUP=true \
  -o ../../.tmp/environment_lookup_on \
  benchmark/environment_lookup.dart
../../.tmp/environment_lookup_off 1000000 9
../../.tmp/environment_lookup_on 1000000 9
```

The synchronous-identifier kernel reuses the function-binding workload because
it executes repeated local, parameter, and global reads:

```bash
dart compile exe \
  -DLUALIKE_FUNCTION_BINDING_POOL=true \
  -DLUALIKE_SYNC_IDENTIFIER_RESULTS=false \
  -o ../../.tmp/sync_identifier_off \
  benchmark/function_binding_pool.dart
dart compile exe \
  -DLUALIKE_FUNCTION_BINDING_POOL=true \
  -DLUALIKE_SYNC_IDENTIFIER_RESULTS=true \
  -o ../../.tmp/sync_identifier_on \
  benchmark/function_binding_pool.dart
../../.tmp/sync_identifier_off 5000 1
../../.tmp/sync_identifier_on 5000 1
```

The non-numeric binary dispatch kernel exercises the metamethod lookup path:

```bash
dart compile exe \
  -DLUALIKE_SHARED_BINARY_METAMETHOD_MAP=false \
  -o ../../.tmp/binary_metamethod_map_off \
  benchmark/binary_metamethod_dispatch.dart
dart compile exe \
  -DLUALIKE_SHARED_BINARY_METAMETHOD_MAP=true \
  -o ../../.tmp/binary_metamethod_map_on \
  benchmark/binary_metamethod_dispatch.dart
../../.tmp/binary_metamethod_map_off 5000 1
../../.tmp/binary_metamethod_map_on 5000 1
```
