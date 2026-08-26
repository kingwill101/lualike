# Performance Investigation Workflow

This document describes how to investigate performance in the live `love2d_gpu`
demo and the `love2d` engine at the same time.

The goal is not to guess. The goal is to reproduce, profile, patch one likely
bottleneck, and verify the effect with the same input pattern.

## What We Are Optimizing

There are usually several different problems mixed together:

- renderer work in `flutter_gpu` or Impeller
- host-side bridge work in `love2d` and `lualike`
- widget tree churn and semantics churn in the Flutter harness
- shader warmup or shader jank
- logging or tracing that is too expensive for a hot path
- avoidable allocations, especially repeated unwrapping and copying of values

Do not assume the frame drop comes from the draw backend just because the
rendering path is involved.

## Run The Demo

Start the demo with the master Flutter toolchain:

```bash
fvm flutter run -d linux --enable-impeller --enable-flutter-gpu
```

Use the running app as the baseline. Keep the scene and the input pattern as
stable as possible while you measure.

For frame-phase regions, use a profile build and opt in explicitly:

```bash
fvm flutter run -d linux --profile \
  --dart-define=LOVE2D_PROFILE_MAIN_LOOP_MS=30000 \
  --dart-define=LOVE2D_PROFILE_FRAME_PHASES=true
```

This adds DevTools regions for the main-loop phases (`resize`, `signals`,
`events`, `update`, `draw`, and `commit`). Run one profile without the phase
flag for the timing baseline, then a separate diagnostic run with it enabled;
the extra regions and region bookkeeping can change frame timings.

The GPU backend requests 4x offscreen MSAA when the device supports it. The
multisampled color target is resolved into a single-sample texture before it is
presented to Flutter. Devices that reject the MSAA texture or depth target
automatically fall back to the single-sample path.

The demo reports the selected lualike engine in `love2d.getRenderState`.
`LOVE_ENGINE_MODE=ast` is the compatibility baseline; `ir` can be used for a
separate profile A/B trial against the same source and input pattern. Do not
combine AST and IR samples in one timing series.

For an A/B comparison without MSAA, run:

```bash
fvm flutter run -d linux --profile \
  --dart-define=LOVE2D_GPU_MSAA=false \
  --enable-impeller --enable-flutter-gpu
```

The GPU demo starts in a synchronized Canvas-versus-GPU comparison mode when
the GPU backend is available. Both panes receive the same immutable LOVE draw
snapshot from one runtime frame. The control cycles through the comparison,
GPU-only, and Canvas-only views. Use the comparison mode for visual checks;
use GPU-only or Canvas-only for cleaner renderer timing measurements.

## Automated Renderer Checks

The demo includes `marionette_flutter` in debug mode. Marionette and Flutter
Driver are mutually exclusive: use the normal debug run for Marionette, and
pass `--dart-define=ENABLE_FLUTTER_DRIVER=true` only for legacy Driver flows.

The demo registers these Marionette extensions:

- `love2d.getRenderState` returns readiness, renderer mode, MSAA state, command
  count, effective GPU sample count, and rolling CPU frame timing.
- `love2d.setRenderMode` accepts `comparison`, `gpu`, or `canvas`.
- `love2d.resetFrameTiming` clears the rolling timing window before a trial.
- `love2d.setVirtualKey` presses or releases a LOVE key for deterministic
  interaction tests and walking trials.
- `love2d.resetInputState` clears interrupted pointer/key state before a trial.

In comparison mode, pointer input is mapped back through the same pane layout
used for rendering. The left and right panes therefore deliver identical LOVE
coordinates for corresponding screen positions; pointer deltas are scaled by
the pane scale as well. The render-state extension includes the delivered
mouse coordinates and pressed scancodes, which makes this behavior observable
in automation.

The app also emits Love2D-specific VM extension events on the `Love2D` stream:
`harness_attached`, `frame_ready`, `render_mode_changed`, and
`frame_timing_reset`. Sampled frame events are opt-in because per-frame event
traffic can perturb a performance run:

```bash
fvm flutter run -d linux --debug \
  --dart-define=LOVE2D_DTD_FRAME_EVENTS=true \
  --enable-impeller --enable-flutter-gpu \
  --print-dtd
```

Use `frame_ready` as the synchronization point before taking a screenshot;
do not sleep for an arbitrary number of milliseconds. Query
`love2d.getRenderState` after each mode change and include the returned
`presentedFrame` and timing sample count with the screenshot evidence.
The events are emitted with `dart:developer.postEvent` on the VM Extension
stream named `Love2D`; the app does not open a DTD connection itself.

## Neon Relay Workload

The bundled `assets/main.lua` is a repeatable technical-game workload rather
than a static shape gallery. It combines four generated RGBA textures, a
dynamic `SpriteBatch` for eight enemies, a colored mesh reticle, alpha-blended
shapes, lines, arcs, text, pointer input, and fixed-capacity pools for 24
projectiles and 72 particles. The simulation uses deterministic enemy phases
and a reset key so visual and timing trials can start from the same state.

Run this exact source through native LOVE as a visual reference:

```bash
cd pkgs/love2d_gpu/example
love assets
bash tool/capture_native_love.sh \
  --project assets \
  --output /tmp/love2d-benchmark/neon-relay-native.png
```

The Flutter run should use its default `assets/main.lua` entrypoint for this
comparison. `flutter_lualike` reports the four indexed art files during startup;
that lookup and prewarm cost is intentionally outside the rolling frame window.

The generated art is indexed and prewarmed through `flutter_lualike`'s
`AssetBundleFileSystemBackend`, while LOVE continues to use its runtime
filesystem adapter for script and image loads. Keep this split explicit when
profiling: the Flutter asset manifest lookup belongs to startup, not the frame
loop.

Relic Breach is the native-LOVE reference workload. Run the same source with
`love ../../love2d/example/assets/relic_breach`, then run the Flutter demo with
`LOVE_ENTRY_ASSET` pointing at that checkout's `main.lua`. This avoids comparing
two different scenes or hiding asset-decoding and blend-state problems behind a
synthetic benchmark.

The sample intentionally uses `add` + `alphamultiply` for light masks. The GPU
backend now maps straight-alpha sources to the correct source-alpha blend
factor, preserves destination alpha for additive/subtractive color modes, and
passes LOVE image tint colors into textured draws. The Canvas backend may still
take its software fallback for that combination, so record the separate
comparison counters when interpreting timing results rather than treating the
two pane timings as interchangeable.

Comparison-mode `love2d.getRenderState` includes `comparisonStats.canvas` and
`comparisonStats.gpu`; each reports rendered commands, software fallbacks,
atlas work, text cache activity, and save-layer counts. The aggregate timing
fields remain useful for total frame cost, while the per-pane counters identify
which backend owns a fallback or unsupported feature.

## Establish A Repeatable Repro

Pick one action that clearly reproduces the slowdown:

- idle render
- mouse movement over the window
- resize
- text-heavy interaction
- scene change

For this project, cursor motion is currently a useful repro because it pushes
the frame rate down hard enough to show up in both the app and the profiler.

Walking Relic Breach is the preferred active-scene repro when comparing the
runtime and renderer together. The benchmark helper can hold a LOVE key during
each mode's timing window:

```bash
bash tool/benchmark_relic_breach.sh \
  --vm 'http://127.0.0.1:PORT/AUTH_TOKEN=' \
  --samples 240 \
  --hold-key d \
  --warmup-seconds 2
```

This holds `d` through the Canvas, GPU, and comparison trials, then releases
it after each window. It exercises LOVE keyboard state, physics, camera
tracking, animation, command recording, and both render backends without
depending on host-specific OS key injection.

When you reproduce, keep the motion pattern consistent:

- same scene
- same cursor sweep
- same duration
- same window size

If the app prints every frame, treat that as a separate bug. The logs should
summarize, not dominate the hot path.

## Profile The Running App

Attach DevTools or the profiler to the live VM service from the `flutter run`
output.

Use the CPU profiler first:

- capture a short idle baseline
- capture a second sample during the slowdown
- compare the same scene with and without the input stimulus

Then inspect:

- bottom-up self time
- call tree total time
- whether the top frame is Dart, Flutter framework, or native engine code
- whether work is concentrated in build/layout/semantics, input dispatch,
  rendering, or shader compilation

If the problem only appears while moving the mouse, check whether hover events
are causing rebuilds, cursor sync, semantics work, or repeated listener churn.

## What To Look For

### Flutter-side hotspots

These are common signs that the harness is doing too much:

- `build` or `LayoutBuilder` showing up repeatedly
- `PipelineOwner.flushSemantics`
- `_RenderObjectSemantics.updateChildren`
- repeated `MouseRegion`, `Listener`, or focus updates
- large widget rebuilds from pointer movement

### Engine-side hotspots

These are common signs that the runtime or renderer is doing too much:

- `LuaBytecodeVm._executeFrame`
- `Interpreter.constantPrimitiveValue`
- `Value._getRegisteredTableMetatable`
- `GpuShapeHandler._ellipseVertices`
- `GpuShapeHandler._outlineToQuads`
- `GpuHostBufferPool._toByteData`
- shader compilation or first-use pipeline work

### Value conversion hotspots

If a hot path is repeatedly calling `unwrap()` on nested LuaLike values, check
whether a shallow raw access is enough.

Prefer the cheapest form that still preserves correctness:

- `value.rawObject`
- a local helper that only unwraps one layer
- direct typed access when the call site already knows the shape

Avoid recursive unwrap chains in draw loops, input loops, and per-frame state
sync.

## Decide What To Fix First

Fix the highest-leverage bottleneck first:

1. logging on a hot frame path
2. semantics or widget churn caused by pointer motion
3. repeated allocations or conversions in draw or input loops
4. shader warmup or pipeline jank
5. renderer path inefficiency

The easiest win is not always the real win. Choose the change that has the
highest chance of removing the actual sampled hotspot.

## Change One Thing At A Time

Make a narrow change and keep the diff easy to reason about.

Good examples:

- remove redundant value unwrapping
- deduplicate fallback logging
- cache repeated geometry
- move expensive sync work off the per-frame path
- prewarm a texture or shader that is known to be hot

Avoid broad refactors while profiling. They make it impossible to know which
change mattered.

## Verify The Result

After each change:

1. hot restart if the change affects runtime state
2. rerun the same repro
3. capture a fresh profiler sample
4. compare the same metrics as before

Look for:

- lower average frame time
- fewer spikes
- less time in the same hotspot
- less work triggered by mouse motion
- lower allocation pressure

If the frame rate improves but the hotspot just moved elsewhere, keep
iterating.

## Practical Rules For This Codebase

- Keep logging summarized, not per-frame.
- Prefer `rawObject` or a shallow helper over repeated `unwrap()` chains on hot
  values.
- Do not add widget wrappers that look cheaper unless profiling shows they are
  safe and useful.
- Treat semantics churn as a real performance cost.
- Profile both the `love2d_gpu` renderer and the `love2d` runtime when a
  slowdown crosses the bridge between them.
- When the profiler and the logs disagree, trust the profiler first.

## Suggested Loop

1. run the demo
2. reproduce the slowdown
3. profile the live app
4. identify the top hotspot
5. make the smallest credible fix
6. hot restart
7. profile again
8. repeat until the hotspot changes or the frame time stops improving

That loop is the intended investigative workflow for the current renderer work.

## Current Findings

From the latest live profiles:

- the corrected demo-window repro no longer shows the earlier extreme cursor
  cliff
- the newest attach sample still has a large native chunk, but the visible Dart
  hot path is consistently `LuaBytecodeVm._executeFrame` and
  `Interpreter.constantPrimitiveValue`
- `Value._getRegisteredTableMetatable`, `Value.tableWeakMode`,
  `GpuHostBufferPool._toByteData`, and `LoveSpriteBatch.LoveSpriteBatch._copy`
  are still present, but at much smaller weights than the Lua VM path
- the memory profile for the latest sample shows `LuaValueMetadata` and
  `Value` allocations dominating, which points at wrapper churn rather than a
  single renderer allocation spike
- the steady-state hot path is still dominated by native render work plus Lua
  runtime execution
- `GpuShapeHandler._ellipseVertices`, `GpuShapeHandler._outlineToQuads`, and
  `GpuHostBufferPool._toByteData` are still visible on the hot path
- `Value._getRegisteredTableMetatable`, `Interpreter.constantPrimitiveValue`,
  and `NumberUtils.doubleToRawBits` still show runtime allocation/conversion
  pressure
- fallback description formatting can surface in renderer profiles, so keep the
  summary logger deduped and avoid per-frame spam when the fallback set is
  stable
- the fallback description cache moved repeated `describeGpuFallbackCommand`
  work out of the hot frame path, but `GpuFallbackHandler.renderFallback` is
  still the more expensive part when unsupported commands are present
- weak-table handling still shows up in `Value.tableWeakMode` and related GC
  code, so reuse cached weak-mode strings inside a single branch instead of
  re-reading the same property multiple times
- the latest binding-layer pass points at `_optionalNumber` and
  `_standardTransform` as repeated hot helpers in the text draw path, so the
  parser now reads indexed arguments directly instead of bouncing through the
  generic helper chain for each component
- the weak-mode caching pass reduced repeated getter work, but it did not move
  the headline profile away from `LuaBytecodeVm._executeFrame`
- the latest attach sample still shows `Interpreter.constantPrimitiveValue`,
  `LuaBytecodeRuntime.constantPrimitiveValue`, and
  `NumberUtils.doubleToRawBits` near the top, which keeps the primitive wrapper
  and numeric conversion path as the main runtime focus
- the renderer side still has real weight in `_renderFlameAtlasBatch`,
  `GpuShapeHandler._drawVertices`, and `GpuHostBufferPool._toByteData`, so the
  GPU-side work is not done yet even though the text binding helper no longer
  dominates the profile
- cached primitive metatables now have a generation stamp so repeated
  `constantPrimitiveValue` lookups can skip redundant default-metatable sync
- the GPU buffer packers now use typed float buffers directly, which already
  lowered `GpuHostBufferPool._toByteData` in the latest idle profile
- `PipelineOwner.flushSemantics` and `_RenderObjectSemantics.updateChildren`
  remain present, so semantics churn is still worth watching
- `tracePhase` exists only as conditional profiling overhead and is not the
  main problem when frame tracing is disabled
- there is still some room to simplify binding-side value conversion, but the
  current profile says that the bigger win is still in the runtime/value cache
  path rather than in a blanket unwrap refactor
- the `_cachedDoubleValues` map changed from `Map<BigInt, Value>` to
  `Map<double, Value>` so that `constantPrimitiveValue` for doubles no longer
  calls `NumberUtils.doubleToRawBits`. The `putIfAbsent` lookup still has
  overhead, but the BigInt allocation chain (`BigInt.from(high) << 32 |
  BigInt.from(low)`) is eliminated. A follow-up profile should confirm whether
  `doubleToRawBits` drops out of the hot list entirely or moves to a different
  caller.

The current code changes are aimed at reducing generic list churn in the GPU
buffer packing path first, because that is low-risk and directly reflected in
the profiler.

## Walking Measurement Gate

The active renderer/runtime repro is walking the native Relic Breach source
while holding `d`. Use a profile build, a fixed 1280x720 window, a two-second
warmup, and 240 samples per mode. Keep AST and IR in separate launches and
record the entry path, presentation rectangle, average command count, and
software-fallback count with every result.

The timing fields have distinct meanings:

- `p95UpdateMicros` covers the Flame/LOVE update callback and helps identify
  simulation or VM work.
- `p95RenderMicros` covers command replay into the selected backend.
- `p95CpuFrameMicros` is the sum of the recorded update and render regions.
- `maxCpuFrameMicros` is the stutter signal; inspect it alongside p95 rather
  than using average FPS alone.

Use Canvas-only and GPU-only windows for backend decisions. Comparison mode is
valuable for visual parity and total “both backends at once” cost, but it
intentionally doubles replay work and has a larger tail, so it is not a clean
GPU-versus-Canvas timing sample.

The latest AST walking baseline and optimized trial illustrate the required
interpretation. The baseline was Canvas/GPU/comparison p95 CPU times of
765/2457/3458 microseconds with approximately 146/136/278 commands. The first
trial after replacing physics binding `Value.multi` allocations with the
internal `LuaResults` carrier measured 571/2152/2721 microseconds at the same
geometry and with zero software fallbacks. A repeat measured
1893/2167/5088 microseconds, demonstrating that the first result is not by
itself proof of a stable win. Keep the allocation fix because it preserves
multi-return semantics and removes GC-tracked `Value` wrappers from the hot
physics crossings, but require repeated trials and profiler/allocation evidence
before claiming a headline frame-time improvement.

The profiler evidence that motivated this narrow change showed `Box`,
`Environment`, `Value`, and `LoveImageCommand` allocations during walking, with
physics wrapper helpers in the call tree. The next tuning change should be
chosen from a fresh profile, not from the renderer numbers alone.

## Neon Relay Stroke Tessellation Trial

The synchronized comparison exposed a GPU-only raster mismatch that was easy
to miss in aggregate timing: one-pixel circles and arcs looked perforated while
the Canvas pane and native LOVE 11.5 produced continuous rings. The GPU path
was expanding every polyline segment into an independent quad, so adjacent
segments had no shared join geometry. Its arc step rule also emitted roughly
855 quads for a full 68-pixel ring.

The retained trial uses one reusable stroke tessellator. Miter joins share an
identical vertex pair, bevel joins fill the outer wedge, and `none` preserves
disconnected segments. Arc subdivision now uses a 0.125-logical-pixel chord
error bound, which selects about 52 segments for that same 68-pixel ring.

The profile A/B used the bundled Neon Relay source in AST mode, GPU-only
rendering, 4x MSAA, a fixed 1280x720 outer window, an 822.67x617 presentation
rectangle, a two-second warmup, and five 240-frame windows per revision. The
baseline was commit `9015339b`; both revisions rendered 65 GPU commands with
zero software fallbacks.

| Metric (median of five windows) | Baseline | Joined stroke mesh | Change |
| --- | ---: | ---: | ---: |
| p95 CPU frame | 5247 us | 2042 us | -61.1% |
| p95 render | 5219 us | 1995 us | -61.8% |
| maximum CPU frame | 10505 us | 5657 us | -46.1% |
| p95 update | 58 us | 51 us | -12.1% |

This is evidence for the Neon Relay renderer workload, not a universal engine
speedup. Keep the Relic Breach walking gate separate. The visual proof is the
same immutable draw snapshot replayed into Canvas and Flutter GPU in comparison
mode, plus the identical `assets/main.lua` project captured through the native
`love` CLI. At full GPU resolution the revised rings are continuous; any
remaining one-pixel intensity difference in the reduced side-by-side panes is
partly the different downsampling path and should not be mistaken for missing
segments.

## Standalone Bytecode Stress Profiles

Used `devtools-profiler` against standalone Lua stress scripts run with the
`--lua-bytecode` engine. These are not Flutter-frame profiles; they isolate the
Lua runtime path so renderer/harness noise does not hide VM hotspots.

### Methodology

- profiler: `devtools_profiler_profile_run`
- workload: `bench/closure_stress.lua`, `bench/call_stress.lua`,
  `bench/table_stress.lua`, `bench/loop_stress.lua`
- engine: `dart run bin/main.dart --lua-bytecode <script>`
- settings: `hideRuntimeHelpers=true`, `includeCallTree=true`,
  `includeBottomUpTree=true`, `includeMethodTable=true`

### Wins

- `NumberUtils.doubleToRawBits` and `BigInt.from` are no longer the dominant
  numeric-conversion cost in the hot path; the new `(int, int)` record cache
  key in `Interpreter.constantPrimitiveValue` dropped that allocation chain.
- `Value._getRegisteredTableMetatable` and `Value.tableWeakMode` churn is
  reduced by the weak-mode cache and metatable-generation stamp.
- `_cloneBytecodeValue` is still present, but its weight dropped compared with
  earlier profiles after keeping only the safe clone path.

### Losses / Remaining Hotspots

- `_executeFrame` remains the headline Dart hotspot in every workload, with
  total weights between ~7% and ~25%. That means the per-instruction dispatch
  overhead still dominates.
- `_runFrame` frame setup/teardown is 7–11% total across workloads; for
  closure-heavy and call-heavy scripts this is pure overhead because most of
  the metadata/call-stack/debug work is not needed in steady-state execution.
- `_invokePreparedCall` + `_callAt` together contribute ~10–15% total in
  call-heavy workloads; call dispatch is still expensive.
- `handleValueCallback`, `_Future._propagateToListeners`, and
  `_microtaskLoop` show up strongly in call stress: the async/await-based VM
  path adds Future/microtask overhead that a tighter synchronous dispatch path
  would avoid.
- `constantPrimitiveValue` is still costly in loop stress: ~1.1% self,
  ~13.7% total. Caching helps, but the function is still called for every
  constant load and still does map work plus metatable sync checks.
- `_syncDebugLocals`, `_fireFrameCallHook`, and debug-hook checks remain on
  the hot path even when no debugger is attached.
- `_closeFrameForCoroutine` is executed for ordinary frames too; it shows up
  as per-frame overhead even in non-coroutine scripts.
- `LuaBytecodeOpcodes.byCode` reverse lookup and per-instruction register
  read/write helpers add small but consistent overhead on every opcode.

### Next Targets

1. hot-path fast lane in `_runFrame` / `_executeFrame` when no debug hooks,
   no coroutines, and no GC safepoint work is required
2. hoist `_debugInterpreter` checks out of the instruction loop so debug
   locals/hook sync is skipped entirely in release runs
3. make `_closeFrameForCoroutine` a no-op for normal frames instead of
   unconditional finally-block cleanup
4. reduce `constantPrimitiveValue` churn by avoiding redundant map/GC/metatable
   work on cache hits
5. replace the per-instruction `LuaBytecodeOpcodes.byCode` lookup with a
   direct opcode dispatch structure if the opcode space is dense enough
