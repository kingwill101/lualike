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

The GPU backend follows the effective LOVE window mode. The native
`t.window.msaa = 0` default uses a single-sample target; a request above one
selects the supported 4x offscreen path and resolves into a single-sample
texture before presentation. Devices that reject the multisampled color or
depth target automatically fall back to one sample.

The demo reports the selected lualike engine in `love2d.getRenderState`.
`LOVE_ENGINE_MODE=ast` is the compatibility baseline; `ir` can be used for a
separate profile A/B trial against the same source and input pattern. Do not
combine AST and IR samples in one timing series.

To hard-disable MSAA even when a game requests it, run:

```bash
fvm flutter run -d linux --profile \
  --dart-define=LOVE2D_GPU_MSAA=false \
  --enable-impeller --enable-flutter-gpu
```

`LOVE2D_GPU_MSAA` is a backend capability gate, not a replacement for
`t.window.msaa`. `love2d.getRenderState` records both the requested result in
`gpuMsaa` and the allocated `gpuSampleCount`.

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
it after each window. Before each trial the helper presses `r` and waits for
the reset to reach a presented frame, so every mode begins from the same world
state. It exercises LOVE keyboard state, physics, camera tracking, animation,
command recording, and both render backends without depending on host-specific
OS key injection. Use `--reset-key none` only for a deliberately continuous
world-state measurement.

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
- `p99CpuFrameMicros` exposes the slowest few frames without relying on one
  potentially noisy maximum.
- `maxCpuFrameMicros` is the stutter signal; inspect it alongside p95 rather
  than using average FPS alone.
- `cpuFramesOver120HzBudget` and `cpuFramesOver60HzBudget` count samples whose
  recorded update-plus-render CPU work exceeded 8.333 ms or 16.667 ms.

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

## Lazy Environment Storage Trial

The AST walking allocation profile showed that every short-lived
`Environment` eagerly owned one explicit-global map and two close-resource
lists even though ordinary function calls never use them. Those containers are
now materialized only on their first write. Read-only lookup, GC traversal,
debug inspection, coroutine cleanup, and bytecode call-name inference use
non-materializing accessors, while the existing mutable map/list API remains
available for callers that need it.

The allocation A/B compared parent commit `cd2189a7` with the lazy-storage
working tree. Both ran the same Relic Breach source in AST mode, GPU-only with
4x MSAA, at a fixed 1280x720 window. The reset-aware helper pressed `r`, waited
for presented frames, held `d`, warmed for two seconds, and measured 240-frame
windows. VM allocation totals varied with service-GC and simulation catch-up,
so the retained gate is the number of generic containers per allocated
`Environment`, not the absolute object count.

| Allocation ratio | Eager storage | Lazy storage | Change |
| --- | ---: | ---: | ---: |
| `_Map` per `Environment` | 2.100 | 1.101 | -47.6% |
| `_GrowableList` per `Environment` | 2.074 | 0.062 | -97.0% |

Five independent reset-aware GPU timing windows did not establish a frame-time
speedup: median p95 update was 43 microseconds on both revisions. Total CPU and
render p95s varied between launches and remained renderer-dominated, so retain
this change for its measured allocation reduction rather than claiming lower
frame time. The full Lualike suite passed 1,937 tests with three expected skips.

Use `tool/profile_relic_allocations.sh` for follow-up Value/Environment work.
It resets allocation accumulators around the same deterministic timing helper
and writes both raw VM responses and a normalized summary. Run it against a
fresh profile-mode app; it intentionally avoids a service GC because that pause
can perturb the game workload being measured.

## Neon Relay Asset, Sampling, and Trace Trial

The expanded Neon Relay source now loads five art assets through
`flutter_lualike`, including the generated transparent relay-cell sprite. The
same `assets/main.lua` project was run with native LOVE 11.5 and the Flutter
Canvas/GPU comparison. The VM-synchronized capture helper waited for a ready
80-command source snapshot, reset the scene and virtual pointer, and captured
392x294 integer-aligned panes. The normalized Canvas/GPU RMSE was `0.0522899`.
This metric covers the complete frame; text antialiasing and strongly minified
rotated textures remain the most visible differences.

The GPU renderer previously ignored each `LoveImage` filter and wrap state and
used one hard-coded nearest/clamp sampler. Image, SpriteBatch, particle, and
mesh draws now reuse an identity-cached `SamplerOptions` derived from the LOVE
minification, magnification, and per-axis wrap modes. Flutter GPU has no
transparent-border address mode, so LOVE `clampzero` remains an explicit clamp
approximation. The synchronized comparison and native capture are the visual
gate; the sampler tests are the state-mapping gate.

The same AST/GPU walking profile identified repeated source-line resolution in
`recordTrace`. Parsed AST nodes now cache their debug-hook and error-trace line
once, invalidating the cache when their span changes. Before the change,
`_debugHookLineForNode` and `_traceLineForNode` accounted for 1.78% and 0.59%
self CPU in a 4,715-sample profile. Both disappeared from the post-change hot
list while 105 focused debug-info, hook, traceback, and source-engine tests
passed.

Three 240-frame backend-only windows were recorded before and after the trace
cache. The GPU update p99 median moved from 90 to 66 microseconds and Canvas
update p95 from 55 to 47 microseconds. Total renderer timing also improved in
that launch, but it varied independently between runs, so it is not attributed
to this AST-only change. Every measured window had zero 8.333 ms and 16.667 ms
CPU-budget violations and zero software fallbacks.

An attempted shortcut that skipped the identity-index probe in
`Generation.add` was rejected. Weak-table collection can temporarily clear an
object's `gcSpace` while its generation index still contains the identity; the
100-test GC suite caught the duplicate insertion assertion. Keep the probe
until generation membership has one authoritative state representation.

## Direct Hybrid Text Fallback Trial

Neon Relay emits nine text commands in its normal 80-command frame. The GPU
backend handles the other 71 commands directly, then uses the Canvas backend's
cached `TextPainter`s for text parity. The old hybrid path nevertheless built a
fallback summary map, searched the fallback index list for every command,
allocated another command list and surface snapshot, and wrapped the entire
800x600 overlay in a `saveLayer` every frame.

The retained path reuses one sorted fallback-index buffer, advances through it
linearly during GPU dispatch, and asks `LoveCanvasRenderBackend` to replay the
selected commands directly over the presented GPU frame. Text rasterization,
transforms, clipping, and painter caching are unchanged. Unusual blend, color
mask, or stencil states still route through the existing transparent surface
snapshot and software-fallback planner. `hybridFallbackCommands` now reports
this work separately from true software-surface fallback.

The A/B used AST mode, GPU-only rendering, 4x MSAA, the normal `r` reset,
pointer 640,360, a two-second warmup, and five independent 240-frame windows
per revision. Every window stayed below both CPU frame budgets.

| Metric (median of five windows) | Wrapped fallback | Direct replay | Change |
| --- | ---: | ---: | ---: |
| p95 CPU frame | 2035 us | 1479 us | -27.3% |
| p95 render | 2015 us | 1417 us | -29.7% |
| p99 CPU frame | 3077 us | 3261 us | +6.0% |
| p99 render | 3047 us | 3235 us | +6.2% |
| maximum CPU frame | 5058 us | 4537 us | -10.3% |

The p95 and maximum moved in the intended direction, while the p99 median did
not. Retain the change for the removed per-frame allocations, eliminated
full-viewport layer, and strong p95 result, but do not describe it as a
universal tail-latency win. The synchronized Canvas/GPU capture remained
visually aligned and reported nine hybrid fallback commands, zero software
surface fallbacks, and zero fallback save layers.

## Sentinel Technical-Game Workload

The sixth generated art asset is a transparent top-down sentinel boss. It is
loaded through the same `flutter_lualike` asset-bundle backend as the arena,
player, drones, beacon, and relay cells, while native LOVE reads the identical
PNG and `assets/main.lua` directly. Eight drone kills enter wave two; `b`
resets directly into the same boss phase for automation. The phase adds
deterministic boss motion, a health bar, hit feedback, an expanding shock-ring
hazard, a score completion state, and another rotated linear-filtered texture.

The native LOVE 11.5 capture at 800x600 and the synchronized Flutter
comparison both rendered the boss correctly. The default capture helper now
derives effective chrome height from actual Hyprland geometry when a requested
resize is rounded by one pixel. The resulting Canvas/GPU comparison recorded a
normalized RMSE of `0.0540582`; the remaining error is concentrated in text
antialiasing and highly minified rotated texture edges, not missing boss
geometry.

Five 240-frame `--reset-key b` trials characterize the workload. Command count
varies slightly as the shock ring and burst particles enter and leave the
snapshot, so these numbers are not an A/B optimization claim.

| Metric (median of five windows) | Canvas | Flutter GPU |
| --- | ---: | ---: |
| p95 update | 41 us | 36 us |
| p95 CPU frame | 544 us | 1842 us |
| p95 render | 513 us | 1824 us |
| p99 CPU frame | 1535 us | 3892 us |
| maximum CPU frame | 2936 us | 4480 us |

All ten windows had zero frames over 8.333 ms or 16.667 ms. Typical GPU frames
handled 76 commands directly and overlaid ten cached text commands. This keeps
the boss phase useful as a higher-complexity parity and frame-pacing gate while
the normal 80-command scene remains the stable renderer A/B baseline.

## Sentinel Ion-Volley and Host-Transient Trial

The seventh generated asset is a transparent top-down ion-lance projectile.
The sentinel now launches deterministic aimed five-bolt volleys from a fixed
24-slot dynamic SpriteBatch. Projectile state is held in preallocated numeric
arrays; collision, energy damage, and particle feedback add gameplay and
texture/batch pressure without per-frame table growth. `flutter_lualike`
prewarms all seven art files, and native LOVE 11.5 loads the identical PNG and
`assets/main.lua` from disk.

The synchronized 392x294 Canvas/GPU panes rendered the same volley state with
normalized RMSE `0.0552151`. The GPU pane handled 95 commands directly,
overlaid ten cached text commands, and used no software surfaces or fallback
save layers. Native LOVE rendered the same five-lance attack at 800x600. The
remaining pixel error is still concentrated in minified rotated texture edges
and text rasterization rather than missing geometry.

Allocation profiling showed that excluded execution objects were still held
strongly by the custom generations. A rejected pressure-pulse experiment added
one collector trigger per 4,096 excluded registrations, but each trigger bought
far fewer sweep units than the number of newly retained objects. Heap growth
continued, so the pulse was removed.

The retained boundary keeps `Box` objects enrolled because the broad GC suite
caught an all-weak generational-step regression when boxes were omitted.
`Environment` frames instead remain reachable through active interpreter roots
and closure references without entering the strong generations. Scalar
number/bool/nil `Value` facades also stay host-managed until a tracked
container calls `ensureTracked`; tables, strings, functions, upvalues, and
boxes keep their existing custom-GC behavior. All 101 GC tests and 93 focused
loop, const, closure, and base-library tests passed this boundary.

The scalar A/B used AST mode, GPU-only rendering, 4x MSAA, the ion-volley boss
reset, pointer 640,360, a two-second warmup, and five independent 240-frame
windows per revision. Both revisions already used untracked environments, so
the comparison isolates scalar enrollment. Every window stayed below both CPU
frame budgets.

| Metric (median of five windows) | Environments host-managed | Scalars + environments host-managed | Change |
| --- | ---: | ---: | ---: |
| p95 update | 34 us | 32 us | -5.9% |
| p99 update | 50 us | 50 us | 0.0% |
| p95 CPU frame | 1704 us | 1462 us | -14.2% |
| p99 CPU frame | 3231 us | 2207 us | -31.7% |
| p95 render | 1684 us | 1445 us | -14.2% |
| p99 render | 3217 us | 2191 us | -31.9% |
| maximum CPU frame | 3395 us | 2588 us | -23.8% |

Whole-session captures of 10.36 and 10.41 seconds reduced normalized heap
growth from about 6.14 MiB/s to 4.08 MiB/s (`-33.5%`). Retained `Value`
growth fell from about 18,781 to 12,851 instances/s (`-31.6%`). `Environment`
was absent from the live-growth leaders after its enrollment was removed. Box
growth remained effectively unchanged in this A/B; its separate closure-safe
numeric-loop reuse reduced normalized Box growth by about 59% in the earlier
loop trial.

## Closure-Free Branch Binding Reuse and Relay Shield Trial

The ion-volley workload still created tens of thousands of transient `Box`
objects even after `Environment` and scalar `Value` objects moved to host
management. A fresh 240-frame allocation profile created 70,501 boxes but only
103 environments, which ruled out environment construction itself. Numeric
loop control boxes were already reused; inspection of the game AST showed that
the remaining hot locals live in `if` branch scopes nested inside those loops.

Closure-free numeric-loop and branch scopes now hide completed locals in a
name-keyed recycle pool. A recycled binding is absent from normal lookup until
the next declaration, is re-enrolled with the custom collector before reuse,
and is never pooled when it is captured, closable, or referenced by an upvalue.
Branch environments are cached by stable AST body identity on their lexical
parent, so they cannot migrate into a different scope. Regressions cover outer
name visibility before redeclaration, one-box execution across 200 iterations,
nested branch reuse, and distinct values for escaping closures.

The VM allocation-profile accumulator proved cumulative across repeated
service resets, so this trial added compile-time-elided binding counters. Build
with `LUALIKE_BINDING_DIAGNOSTICS=true` to expose `runtimeBindings.created` and
`runtimeBindings.reused` in `love2d.getRenderState`; `resetFrameTiming` resets
the counters at the same synchronization point as frame timing. Normal builds
compile out the constructor/reuse increments. `LUALIKE_LOOP_LOCAL_REUSE=false`
provides the matched baseline without maintaining a separate source tree.

Both sides used profile mode, AST execution, GPU-only rendering, 4x MSAA, the
sentinel `b` reset, pointer 640,360, a two-second warmup, and five independent
240-frame windows. No window exceeded either CPU frame budget.

Follow-up cache experimentation exposed that host mouse movement could replace
the scripted pointer during a timing window. The benchmark protocol now pins
physical mouse input at the adapter boundary, verifies the final LOVE pointer,
and rejects presentation-geometry drift. `--trials 5` collects the full set in
one invocation with an indexed record per window. This input hardening is part
of the measurement harness and is not included as a runtime performance win.

| Metric (median of five windows) | Reuse disabled | Reuse enabled | Change |
| --- | ---: | ---: | ---: |
| New `Box` objects | 54,728 | 34,622 | -36.7% |
| Reused bindings | 0 | 38,715 | — |
| p95 update | 36 us | 26 us | -27.8% |
| p99 update | 50 us | 41 us | -18.0% |
| p95 CPU frame | 1694 us | 1037 us | -38.8% |
| p99 CPU frame | 2952 us | 1367 us | -53.7% |
| maximum CPU frame | 3326 us | 1517 us | -54.4% |

The eighth generated art asset is a transparent relay-shield emitter. Two
fixed pickup slots grant a six-second shield, respawn on a fixed cadence,
absorb sentinel bolts and shock-ring damage, and drive a cached HUD countdown.
The pickup batch, collision state, and timer use fixed arrays/scalars and are
loaded through `flutter_lualike`; native LOVE 11.5 runs the identical PNG and
`assets/main.lua` directly.

Native LOVE rendered the updated boss scene at 800x600. The synchronized
392x294 Canvas/GPU pickup capture had normalized RMSE `0.0588587`; the active
shield capture had RMSE `0.0580855`. The pickup frame contained 111 Canvas
commands (four SpriteBatch commands and 39 batch items) versus 100 direct GPU
commands plus 11 cached text fallbacks, with no software surface or save-layer
fallback. The remaining difference is still concentrated in text and strongly
minified rotated edges rather than missing shield geometry.

Five GPU-only windows on the expanded eight-asset workload had median p95/p99
CPU frame times of 1,221/1,432 microseconds, median p95/p99 update times of
30/50 microseconds, median maximum CPU time of 1,636 microseconds, and zero
8.333 ms or 16.667 ms budget violations. These numbers characterize the
expanded workload; the feature was added after the binding A/B and is not part
of that causal comparison.

## Raw Numeric Expression Results and Exact Double Cache Keys

A fresh pinned 240-frame allocation profile still created 126,687 `Value`
facades. The AST numeric fast path already computed with raw Dart numbers, but
then immediately called `constantPrimitiveValue` for every intermediate result.
When number metatables and per-value metatables are inactive, those raw results
now propagate to parent expressions and mutable local slots. Public results,
table storage, calls, and metatable-bearing numbers continue through the
existing compatibility wrappers. Build with
`LUALIKE_RAW_NUMERIC_EXPRESSION_RESULTS=false` for the matched baseline.

The same profile also showed one `(int, int)` record allocation per double-cache
lookup. Native Dart now keys that cache with the exact signed 64-bit IEEE-754
bit pattern; JavaScript targets retain the split 32-bit record because their
number representation cannot preserve every 64-bit integer. Direct map lookup
also removes per-call `putIfAbsent` closures. `-0.0`, `0.0`, and distinct NaN
payloads retain separate cache entries. A two-level high/low-word map was
measured and rejected because dynamic values created more than 100,000 inner
maps in one window.

The double-key fresh-process comparison reduced accumulated `_Record` instances
from 138,535 to 11,155 (`-91.9%`) and heap usage from 175,216,224 to
166,348,656 bytes (`-5.1%`). This is allocation evidence; renderer-dominated
frame timing did not establish a p95 speedup for the key change alone.

The raw-result A/B used the deterministic full-world `b` reset, AST execution,
GPU-only rendering, 4x MSAA, held `d`, pointer 640,360, a two-second warmup,
and five independent 240-frame windows. Every window held the same presentation
geometry, averaged at least 96 rendered commands, and stayed below both frame
budgets. The semantic-safe path detaches a raw left temporary before a
function/method-call RHS so `debug.setlocal` can still mutate that suspended
caller local.

| Metric | Wrapped numeric results | Raw numeric results | Change |
| --- | ---: | ---: | ---: |
| Fresh-profile `Value` instances | 126,687 | 75,241 | -40.6% |
| Fresh-profile `Environment` instances | 236 | 173 | -26.7% |
| Fresh-profile heap usage | 168,710,032 B | 159,004,768 B | -5.8% |
| Median p95 update | 43 us | 34 us | -20.9% |
| Median p99 update | 50 us | 52 us | +4.0% |
| Median p95 CPU frame | 1778 us | 1310 us | -26.3% |
| Median p99 CPU frame | 2002 us | 1710 us | -14.6% |
| Median maximum CPU frame | 2230 us | 1922 us | -13.8% |

The p99 update regression means this remains primarily an allocation win; the
frame-tail direction is encouraging but renderer/desktop noise is still large
enough that it is not a universal speedup claim.

Native LOVE 11.5 exposed a separate source-parity failure during this trial:
the expanded monolithic reset exceeded LuaJIT's 60-upvalue function limit.
Reset work is now split across session, projectile, and world helpers. The `v`
parity-freeze key performs that full reset, fixes aim, activates the sentinel,
and pauses simulation so native LOVE, Canvas, and GPU captures refer to the
same source state. Revalidation found that the first reset restored Lua arrays
but left mutable drone/cell/shield SpriteBatch transforms at their previous
frame. Reset now reseeds those batches at canonical elapsed-zero transforms.
On the resulting 392x294 frozen capture, normalized RMSE was `0.0764229` for
native LOVE versus Canvas, `0.0522745` for native LOVE versus Flutter GPU, and
`0.0557484` for Canvas versus GPU. The GPU path is closer to native in this
scene despite its more visible minified/rotated edge aliasing.

Allocation and timing helpers now accept `--min-average-commands`; the sentinel
gate uses 90. This rejects a valid-looking run that accidentally enters a much
lighter phase, which one revalidation attempt exposed at 77 average commands.

## LOVE-authored mipmap upload A/B

The remaining frozen-scene defect was concentrated in strongly minified,
rotated sprite edges. Neon Relay now requests `{ mipmaps = true }` from all
eight `love.graphics.newImage` calls, so native LOVE and lualike receive the
same source intent. The GPU texture cache uploads the decoded LOVE mip chain
only when `GpuContext.doesSupportManuallyMippedTextures` is true, clamps it to
Flutter GPU's current per-texture mip limit, and truncates malformed chains at
their last valid level. `LOVE2D_GPU_MIPMAP_UPLOADS=false` provides a
compile-time-elided base-level-only A/B path. The VM diagnostics record the
build gate and runtime capability.

Synchronous GPU upload previously reconstructed every byte through
`LoveImageData.getPixel`, allocating a `LoveColor` per source pixel. A
copy-safe `toRgbaBytes` export now supplies each texture level directly. This
is a startup/upload-path cleanup; no steady-state speedup is attributed to it.

The matched frozen captures used the same `v` reset, pointer 640,360, an
800x600 LOVE surface, 392x294 panes, 4x MSAA, and OpenGLESSDF. Runtime
diagnostics reported manual mipmap support in both builds. The base-level OFF
capture reproduced Canvas/GPU RMSE `0.0557484`; the ON capture measured
`0.0618955`. Native LOVE is the parity authority: after resizing its same-source
800x600 frame to the pane size, native-vs-GPU RMSE improved from `0.0558721`
to `0.0492378` (`-11.9%`). Native-vs-Canvas was `0.0768347`. The mipmapped GPU
sprites are visibly smoother, with modest softening, and closer to native LOVE
despite moving away from Flutter Canvas.

Steady-state timing used GPU-only AST execution, the sentinel `b` reset,
pointer 640,360, a fixed 800x600 presentation, two-second warmups, and five
independent 240-frame windows per build. Every window averaged 96.1-96.6
rendered commands and had no 8.333 ms or 16.667 ms CPU budget violation.

| Metric (median of five windows) | Uploads off | Uploads on | Change |
| --- | ---: | ---: | ---: |
| p95 update | 56 us | 49 us | -12.5% |
| p99 update | 78 us | 65 us | -16.7% |
| p95 CPU frame | 2029 us | 2106 us | +3.8% |
| p99 CPU frame | 2539 us | 2438 us | -4.0% |
| median maximum CPU frame | 3013 us | 3301 us | +9.6% |
| p95 render | 2006 us | 2083 us | +3.8% |
| p99 render | 2519 us | 2419 us | -4.0% |

The mixed tail directions are desktop noise rather than evidence of a frame
speedup or regression. Retain mip uploads for the native-parity and edge
quality win; continue to gate them on the runtime capability. Flutter GPU has
no sampler LOD-bias equivalent for LOVE's mipmap sharpness, so that remains an
explicit parity gap.

## AST closure-analysis cache

A fresh GPU-only Neon Relay CPU profile found that closure safety was being
recomputed every time an `if` branch with locals executed. The analysis called
`Dumpable.dump()` recursively over the whole branch AST. In the uncached
profile, `AstNode.dumpSpan` consumed 20.0% self CPU,
`dumpedNodeMayCreateClosure` consumed 10.9% self CPU, and
`_bodyMayCreateClosure` carried 41.8% total weight. That serialization is useful
for persistence, not as a per-frame structural query.

Parsed statement lists are immutable during execution. The closure result is
now stored in a weak identity `Expando` keyed by the exact statement list, so
the first structural scan retains existing semantics and later branch entries
perform one identity lookup. `LUALIKE_AST_CLOSURE_SCAN_CACHE=false` preserves
the matched uncached build. A regression test verifies that closures created
inside repeated branches still capture distinct local boxes and produce 123,
not three references to a recycled final binding.

In the cached follow-up profile, `AstNode.dumpSpan`,
`dumpedNodeMayCreateClosure`, and `_bodyMayCreateClosure` disappeared from the
hotspot table. `visitIfStatement` fell from 47.6% to 9.8% total weight and
`_executeIfBranchStatements` from 44.6% to 3.7%. Normalized package sample rate
fell from about 452 to 344 samples/second (`-23.9%`). This profiler reduction is
the direct attribution evidence; renderer frame tails remain noisier.

The timing trial used mipmap uploads enabled, GPU-only AST execution, 4x MSAA,
the sentinel `b` reset, pointer 640,360, an 800x600 presentation, two-second
warmups, and five 240-frame windows per build. To control for desktop drift,
the final leg reversed the build order and ran cache ON immediately after the
OFF control. Workload ranges were 96.1-96.6 rendered commands for OFF and
96.2-96.6 for ON. The cached leg had no CPU budget violation; one OFF frame
exceeded the 8.333 ms budget and none exceeded 16.667 ms.

| Metric (median of reverse-order five-window leg) | Cache off | Cache on | Change |
| --- | ---: | ---: | ---: |
| p95 update | 58 us | 54 us | -6.9% |
| p99 update | 89 us | 81 us | -9.0% |
| p95 CPU frame | 2788 us | 2628 us | -5.7% |
| p99 CPU frame | 3592 us | 3128 us | -12.9% |
| maximum CPU frame | 3974 us | 3614 us | -9.1% |

The earlier ON-then-OFF leg pointed the same way for p95/p99 update and CPU
tails, while its maximum-frame median was mixed. Retain the cache because the
hotspot is eliminated, both ordered timing legs improve the percentile tails,
and closure identity remains covered.

## Identifier frame lookup

After closure-analysis caching, `visitIdentifier` still searched the active
call stack by evaluating `callStack.frames.toList().reversed`. That copied a
list for every lookup. A local miss then entered
`_resolveCurrentFunctionLocalOrDeclaredGlobal`, fetched the same current
function, and repeated the frame search.

`CallStack.findLatestFrameForCallable` now walks the backing frame list by
reverse index. This preserves recursion semantics by returning the newest
identity match without allocating a view copy. `visitIdentifier` resolves the
current function and frame once and passes both into the local/declared-global
search. `LUALIKE_IDENTIFIER_FRAME_LOOKUP_FAST_PATH=false` restores the old
list-copy and duplicate-search path for matched builds. Focused tests cover the
newest recursive frame, nested local shadowing, captured upvalues, and
coroutine yield/resume.

The same GPU-only AST Neon Relay sentinel profile attributed 3.81% self and
4.78% total CPU to `Interpreter.findFrameForCallable` before this change. In
the fast-path profile it carried 0% self and 0.50% total weight, an 89.6%
reduction in total sampled weight. `visitIdentifier` fell from 19.47% to
12.98% total weight. The profile artifacts are:

- `/tmp/love2d-benchmark/closure-scan-cache-on-cpu-profile`
- `/tmp/love2d-benchmark/identifier-frame-on-cpu-profile`

The checked-in `pkgs/lualike/benchmark/identifier_lookup.dart` kernel measures
the exact old and new frame searches in one AOT process. It alternates order,
uses an eight-frame stack with a non-top target, and verifies that both paths
return the same frame identity. Two CPU-pinned runs of nine 500,000-lookup
trials produced these medians:

| Run | Legacy list copy | Reverse-index lookup | Reduction |
| --- | ---: | ---: | ---: |
| 1 | 74,660 us | 14,121 us | 81.1% |
| 2 | 86,521 us | 13,782 us | 84.1% |

The end-to-end Flutter frame trial remained noisy. In the OFF-to-ON leg, median
p95 update improved from 58 to 54 us while p99 moved from 82 to 90 us. In the
reverse ON-to-OFF leg, OFF measured 52 us p95 and 86 us p99. Renderer CPU tails
moved with unrelated desktop contention in both directions. Every valid window
kept an 800x600 presentation and 96.4-97.3 average commands. All synchronized
captures retained the established Canvas/GPU normalized RMSE of `0.0618955`.

Retain this change as a semantics-covered allocation and interpreter-hotspot
win. Do not claim a whole-frame improvement from these Flutter timing windows;
the kernel and CPU attribution prove the targeted gain, while frame tails are
inconclusive.

## Pooled function bindings

The next walking Neon Relay profile still accumulated `Box` objects rapidly.
The AST interpreter already retained one idle `Environment` for a conservative
class of functions: no non-`_ENV` upvalues, no `<close>` variables, at least one
regular parameter, no calls in the body, and no active debug hook. However, the
pool cleared `Environment.values` after every call, so every parameter and
direct local still allocated a new transient `Box` on the next invocation.

Eligible environments now enable their existing transient-local pool. At
return, only uncaptured, non-closable boxes are parked; boxes with upvalue
references are excluded and preserve closure identity. Parking drops the old
value without redundantly re-enrolling the box in the custom collector. The
next declaration performs the one required rebind and GC enrollment.
Functions whose bodies can create nested functions remain on the prior
clear-only path as a second closure-safety gate. This is required for legacy
dumped chunks, whose restored upvalue metadata does not always increment the
captured box's reference count. Regression coverage executes both direct and
reader-loaded nested dumped functions.
`LUALIKE_FUNCTION_BINDING_POOL=false` restores the old clear-and-reallocate
behavior. Tests cover parameter/local reinitialization and two returned
closures retaining distinct captured boxes.

The checked-in `benchmark/function_binding_pool.dart` kernel calls an eligible
four-binding function 5,000 times per trial and records opt-in binding
diagnostics. Matched CPU-pinned AOT runs produced the same checksum and:

| Metric | Pool off | Pool on | Change |
| --- | ---: | ---: | ---: |
| Created boxes per trial | 20,003 | 7 | -99.97% |
| Reused bindings per trial | 0 | 19,996 | +19,996 |
| OFF-then-ON median time | 461,293 us | 463,698 us | +0.5% |
| reverse-order median time | 526,340 us | 447,812 us | -14.9% |

The timing spread shows host drift, so the kernel is allocation proof rather
than a universal elapsed-time claim.

A fresh-process Flutter A/B used GPU-only AST execution, the same `b` reset,
held `d`, pointer 640,360, a 1:1 800x600 presentation, two-second warmup, and
one 240-frame window per build. Both windows rendered about 96-97 commands per
frame with no software-surface fallback:

| Metric | Pool off | Pool on | Change |
| --- | ---: | ---: | ---: |
| Runtime bindings created | 40,792 | 22,126 | -45.8% |
| Allocation-profile `Box` instances | 55,884 | 30,157 | -46.0% |
| Allocation-profile `_HashMapEntry` instances | 77,246 | 49,925 | -35.4% |
| Allocation-profile `Value` instances | 83,201 | 76,858 | -7.6% |
| p95 update | 45 us | 42 us | -6.7% |
| p99 update | 79 us | 58 us | -26.6% |
| p95 CPU frame | 4,109 us | 2,810 us | -31.6% |
| p99 CPU frame | 8,323 us | 3,140 us | -62.3% |
| maximum CPU frame | 12,029 us | 3,858 us | -67.9% |

Retain the binding pool for the direct allocation reduction. The frame-tail
direction is encouraging, but it is a single paired Flutter window and must be
repeated before making a broad frame-time claim.

### Expanded closure-free regular-call pooling

The original eligibility rules still missed the dominant Neon Relay case.
Functions that captured top-level game state, called another Lua or host
function, or had no parameters always allocated a fresh execution environment
and fresh boxes. Those properties do not make an idle frame observable.
Regular AST calls now borrow the same single idle slot when their bodies cannot
create a nested function and contain no `<close>` local. The frame leaves the
slot before execution, so recursion and asynchronous re-entry allocate a
separate active frame. Any active debug hook keeps the previous fresh-frame
behavior. Error exits close the frame before returning it to the pool.

`benchmark/captured_function_binding_pool.dart` exercises a zero-argument
helper that captures mutable state, calls `math.abs`, and declares a local.
Across 11 alternating CPU-pinned AOT pairs with 20,000 calls and three internal
trials per process, every process returned the same checksum:

| Metric | Pool off | Pool on | Change |
| --- | ---: | ---: | ---: |
| Created boxes per process | 20,005 | 6 | -99.97% |
| Reused bindings per process | 0 | 19,999 | +19,999 |
| Independent median time | 966,359 us | 1,005,776 us | +4.1% |

The median paired time reduction was 2.6%, but only 6 of 11 pairs favored the
pool and the independent medians moved in the opposite direction. Treat this
kernel as allocation proof, not an elapsed-time win.

The retention gate used an exact OFF-to-ON-to-OFF profile-mode sandwich: GPU-
only AST Neon Relay, reset `r`, held `d`, pointer 640,360, zero-offset 800x600
presentation, five 240-frame windows per build, and 77 rendered commands in
every window. No trial used software fallback or exceeded either frame budget.
Against the reverse OFF leg, the five-window medians were:

| Metric | Pool off | Pool on | Change |
| --- | ---: | ---: | ---: |
| Runtime bindings created | 36,031 | 7,290 | -79.8% |
| Runtime bindings reused | 12,098 | 42,120 | +248.2% |
| p95 update | 36 us | 33 us | -8.3% |
| p99 update | 50 us | 44 us | -12.0% |
| p95 CPU frame | 1,554 us | 1,549 us | -0.3% |
| p99 CPU frame | 2,141 us | 2,086 us | -2.6% |
| p99 render | 2,121 us | 2,068 us | -2.5% |
| median maximum CPU frame | 3,426 us | 2,743 us | -19.9% |

The first OFF leg was slower than the reverse leg, but ON also improved every
listed tail against that baseline. Retain the expanded pool for the repeatable
79.8% fresh-binding reduction and the non-regressing reverse-order frame gate;
do not characterize the nearly flat p95 CPU result as a throughput win.
Artifacts are under `.tmp/captured-function-pool/` as
`game-off-five-exact.jsonl`, `game-on-five-exact.jsonl`, and
`game-off-reverse-five-exact.jsonl`.

The closure/function/coroutine/debug-focused slice passed 105 tests. The full
Lualike suite completed with 1,962 passes, three skips, and one unrelated
multi-file stack-trace assertion. That assertion expected `mod:3` but received
`main.lua:3`; it failed identically with `LUALIKE_FUNCTION_BINDING_POOL=false`.

## Bounded numeric primitive wrappers

A long-running profile process retained millions of numeric `Value` wrappers
through four interpreter-owned maps. The maps cached every integer, exact
double bit pattern, JavaScript-safe double key, and `BigInt` ever observed for
the lifetime of an interpreter. This made a cache intended to avoid short-lived
allocation into an unbounded long-session heap owner.

The numeric caches now use exact fixed-capacity FIFO retention, independently
bounded to 4,096 entries by default. Cache eviction cannot invalidate a live
Lua value: tables, locals, closures, and host code retain their own references,
while Lua numeric equality is value-based. Native doubles continue to use their
exact signed 64-bit IEEE-754 pattern; JavaScript targets continue to use two
32-bit words. Tests explicitly preserve distinct `0.0`/`-0.0` entries, distinct
NaN payloads, recent-value identity reuse, and the configured retention cap.

`LUALIKE_BOUNDED_NUMERIC_PRIMITIVE_CACHE=false` restores the old unbounded maps
for matched builds. `LUALIKE_NUMERIC_PRIMITIVE_CACHE_LIMIT` changes the per-key-
type cap and defaults to 4,096. `Interpreter.numericPrimitiveCacheDiagnostics()`
reports the exact retained counts without walking the heap.

The checked-in `benchmark/numeric_primitive_cache.dart` kernel inserted 100,000
unique doubles per trial in fresh CPU-pinned AOT processes. Both run orders
showed the same retention result and favored the bounded cache under
high-cardinality churn:

| Run order | Unbounded median | Bounded median | Time reduction | Retained exact doubles |
| --- | ---: | ---: | ---: | ---: |
| OFF then ON | 86,406 us | 34,356 us | 60.2% | 100,002 -> 4,096 |
| ON then OFF | 76,774 us | 42,897 us | 44.1% | 100,002 -> 4,096 |

The direct kernel proves cache retention and cache-churn behavior. A fresh-
process Flutter allocation A/B then exercised the same GPU-only AST Neon Relay
walk at 800x600: `b` reset, `d` held, pointer `(640,360)`, two-second warmup,
240 frames, about 96-97 commands per frame, and no software-surface fallback.

| Allocation metric | Unbounded | Bounded | Change |
| --- | ---: | ---: | ---: |
| Live/accumulated `Value` instances | 79,548 | 68,049 | -14.5% |
| Live/accumulated `_Double` instances | 93,008 | 76,984 | -17.2% |
| VM heap usage | 286,389,472 bytes | 279,822,304 bytes | -2.3% |

Because one initial timing pair favored the unbounded build, frame performance
was followed with an ON-to-OFF-to-ON sandwich of five independent 240-frame
windows per build position. The median windows were:

| Build position | p95 update | p99 update | p95 CPU frame | p99 CPU frame |
| --- | ---: | ---: | ---: | ---: |
| Bounded before | 45 us | 65 us | 2,402 us | 3,327 us |
| Unbounded middle | 60 us | 89 us | 3,254 us | 5,470 us |
| Bounded after | 55 us | 68 us | 3,260 us | 4,301 us |

Both bounded legs improved update p95/p99 and CPU-frame p99 over the middle
unbounded build. CPU-frame p95 improved in the first leg and was neutral in the
second, which contained one visibly contended trial. Every five-trial set had a
median of zero frames over the 120 Hz CPU budget, zero frames over the 60 Hz
budget in all windows, and zero software-surface fallbacks. Retain the bounded
cache primarily for the exact retention guarantee and treat the repeated update
tail improvement as encouraging game-level evidence rather than a universal
renderer claim.

Artifacts:

- `/tmp/love2d-benchmark/numeric-cache-off-matched-summary.json`
- `/tmp/love2d-benchmark/numeric-cache-on-matched-summary.json`
- `/tmp/love2d-benchmark/numeric-cache-on-five-trials.jsonl`
- `/tmp/love2d-benchmark/numeric-cache-off-five-trials.jsonl`
- `/tmp/love2d-benchmark/numeric-cache-on-reverse-five-trials.jsonl`

## Single-map environment lookup

`Environment.get` previously used `values.containsKey(name)` and then
`values[name]`, performing two hash-table probes for every local hit. It now
reads the nullable `Box` once and branches on that result. Environment maps
cannot contain a null box, so this preserves missing/local/parent lookup
semantics while removing redundant map work. The parent reference is also
loaded once before recursive lookup.

`LUALIKE_SINGLE_MAP_ENVIRONMENT_LOOKUP=false` restores the double-probe path
for matched builds. The checked-in `benchmark/environment_lookup.dart` kernel
alternates one local and one parent lookup. In 21 alternating CPU-pinned AOT
process pairs with 2,000,000 lookups per process, the exact compile-time A/B
produced:

| Lookup path | Median time | Change |
| --- | ---: | ---: |
| Legacy contains-plus-index | 341,541 us | baseline |
| Single nullable lookup | 291,059 us | -14.8% |

A five-window ON-to-OFF-to-ON Flutter sandwich used GPU-only AST execution,
the `b` reset, held `d`, pointer 640,360, 800x600 presentation, two-second
warmups, and roughly 96-97 rendered commands per frame:

| Build position | p95 update | p99 update | p95 CPU frame | p99 CPU frame |
| --- | ---: | ---: | ---: | ---: |
| Single lookup before | 54 us | 73 us | 2,681 us | 3,446 us |
| Legacy middle | 59 us | 77 us | 2,338 us | 3,286 us |
| Single lookup after | 62 us | 92 us | 2,787 us | 3,762 us |

The first single-lookup leg improved update tails, but the reverse leg did not;
renderer-inclusive CPU tails also moved independently. All windows stayed
under the 60 Hz CPU budget, every set had a median of zero 120 Hz violations,
and software-surface fallbacks remained zero. Synchronized Canvas/GPU RMSE
stayed between `0.0596252` and `0.0598586`. Retain the change for the exact
environment kernel win and semantics coverage, but do not claim a measured
whole-game improvement from this sandwich.

The canonical package suite then completed with 1,954 passing tests, three
expected skips, and no failures.

Artifacts:

- `/tmp/love2d-benchmark/environment-get-post-five-trials.jsonl`
- `/tmp/love2d-benchmark/environment-get-legacy-five-trials.jsonl`
- `/tmp/love2d-benchmark/environment-get-on-reverse-five-trials.jsonl`

## Synchronous AST identifier results

`Identifier.accept` previously forced every identifier read through an
`async` visitor, even when a local, upvalue, fast local, or direct global was
already available synchronously. The AST visitor boundary now returns
`FutureOr<T>` for identifiers. The ordinary path returns the resolved value
directly; only `_ENV` lookups that can invoke an asynchronous or yielding
`__index` metamethod return a `Future`. Existing callers that `await` an AST
node remain valid. Callers that require an exact `Future<T>` rather than a
`FutureOr<T>` must use `Future.sync` or an async wrapper.

`LUALIKE_SYNC_IDENTIFIER_RESULTS=false` restores the always-async wrapper for
matched builds. Across 21 alternating AOT process pairs with 5,000 eligible
function calls per process, the exact compile-time comparison produced:

| Identifier result path | Median time | Change |
| --- | ---: | ---: |
| Always-async visitor | 291,140 us | baseline |
| Synchronous ordinary reads | 269,868 us | -7.3% |

The median per-pair reduction was 10.6%. The semantics slice verifies direct
local completion without a `Future`, nested shadowing and upvalues, coroutine
state, and a custom `_ENV.__index` that yields and resumes with the identifier
value.

A profile-mode OFF-to-ON-to-OFF sandwich used GPU-only AST Neon Relay, the `b`
reset, held `d`, pointer 640,360, a fixed 800x600 LOVE surface, 4x MSAA,
two-second warmups, five 240-frame windows per build, and a minimum of 90
rendered commands per frame:

| Five-window median | Legacy before | Synchronous | Legacy reverse |
| --- | ---: | ---: | ---: |
| p95 update | 59 us | 53 us | 54 us |
| p99 update | 74 us | 77 us | 72 us |
| p95 CPU frame | 3,034 us | 2,234 us | 2,449 us |
| p99 CPU frame | 4,092 us | 2,662 us | 3,111 us |
| p95 render | 2,988 us | 2,216 us | 2,411 us |
| p99 render | 4,039 us | 2,639 us | 3,092 us |
| Average rendered commands | 96.825 | 96.508 | 97.004 |

The reverse leg confirms the direction at a smaller magnitude: synchronous
identifiers improved p95 CPU frame time by 8.8% and p99 by 14.4% versus the
reverse legacy build. Update p95 was effectively tied and update p99 was 6.9%
worse, so this is evidence for lower whole-frame CPU tails, not a claim that
every Lua update-tail metric improved. All synchronous and reverse-legacy
windows stayed under both frame budgets with zero software-surface fallback.

Fresh matched 240-frame allocation windows showed the intended churn change:

| VM allocation class | Always async | Synchronous | Change |
| --- | ---: | ---: | ---: |
| `_Future` | 14,446 | 620 | -95.7% |
| `_FutureListener` | 5,312 | 217 | -95.9% |
| `_SuspendState` | 5,372 | 227 | -95.8% |
| `_AsyncCallbackEntry` | 5,628 | 259 | -95.4% |
| `_Closure` | 49,132 | 5,132 | -89.6% |
| `Context` | 53,791 | 3,030 | -94.4% |
| Heap usage | 270,681,472 B | 265,531,152 B | -1.9% |

The same samples rendered 97.046 versus 96.658 commands per frame. `Value`
counts moved in the opposite direction (41,132 to 58,951), so do not describe
this as a reduction in every allocation category; the retained result is the
large async-runtime churn reduction plus the repeated AOT and frame-tail wins.

Artifacts are stored under the repo-local `.tmp` directory:

- `sync-identifier-game-off-five.jsonl`
- `sync-identifier-game-on-five.jsonl`
- `sync-identifier-game-off-reverse-five.jsonl`
- `sync-identifier-game-off-alloc-summary.json`
- `sync-identifier-game-on-alloc-summary.json`

The canonical `lualike` package suite completed with 1,958 passing tests, three
expected skips, and no failures after the visitor-contract change.

## Shared binary metamethod dispatch table

The AST binary-expression slow path previously built the same 20-entry
operator-to-metamethod map on every visit. Numeric arithmetic bypasses that
path, but string comparisons, concatenation, and values that can participate
in metamethod dispatch paid both map construction and lookup. The map is now
an immutable library-level constant. Set
`LUALIKE_SHARED_BINARY_METAMETHOD_MAP=false` to restore the per-visit map for
matched builds.

`benchmark/binary_metamethod_dispatch.dart` performs three non-numeric binary
operations per iteration. Across 21 alternating AOT process pairs with 5,000
iterations per process, the exact compile-time comparison produced:

| Binary metamethod map | Median time | Change |
| --- | ---: | ---: |
| Per-expression map | 262,077 us | baseline |
| Shared immutable map | 196,700 us | -24.9% |

The median paired reduction was 26.0%, and every pair favored the shared map.
The full interpreter slice completed with 207 passing tests and no failures;
focused static analysis reported no issues. The canonical package suite then
completed with 1,958 passing tests, three expected skips, and no failures.

A profile-mode OFF-to-ON-to-OFF sandwich used GPU-only AST Neon Relay, the `b`
reset, held `d`, pointer 640,360, a fixed 800x600 LOVE surface presented at
1237.33x928, 4x MSAA, two-second warmups, five 240-frame windows per build, and
a minimum of 90 rendered commands per frame. The demo was isolated on an empty
workspace and each trial rejected presentation drift:

| Five-window median | Per-visit before | Shared map | Per-visit reverse |
| --- | ---: | ---: | ---: |
| p95 update | 72 us | 75 us | 70 us |
| p99 update | 106 us | 99 us | 109 us |
| p95 CPU frame | 3,371 us | 2,527 us | 2,991 us |
| p99 CPU frame | 5,109 us | 3,236 us | 3,878 us |
| p95 render | 3,312 us | 2,511 us | 2,970 us |
| p99 render | 5,079 us | 3,196 us | 3,779 us |
| Average rendered commands | 96.775 | 96.888 | 96.917 |

Against the reverse baseline, the shared map reduced p95 CPU frame time by
15.5% and p99 by 16.6%. Update p95 moved 7.1% in the wrong direction while
update p99 improved 9.2%, so the retained claim is the strong dispatch-kernel
win plus lower repeated whole-frame tails, not a uniform update-tail win. Every
window stayed below the 60 Hz budget and reported zero software-surface
fallbacks.

In a fresh walking CPU profile, `Map._fromLiteral` had zero sampled ticks after
showing 28 self ticks in the post-synchronous-identifier profile. Allocation
captures were not used as evidence because unrelated compositor activity made
the pre-capture process histories unequal.

Artifacts are stored under the repo-local `.tmp` directory:

- `shared-metamethod-map-off-five.jsonl`
- `shared-metamethod-map-on-five.jsonl`
- `shared-metamethod-map-off-reverse-five.jsonl`
- `shared-metamethod-map-game-cpu-profile/`

### Rejected micro-rewrites

The same retention gate rejected nine intuitive rewrites, and their
production changes were removed:

- lifting binary-expression local helpers to top-level functions was 0.6%
  slower at the median across 21 alternating 30,000-iteration AOT pairs;
- caching function-call trace names plus replacing circular-buffer modulo with
  a branch was 5.3% slower across 21 alternating 5,000-call AOT pairs;
- adding an identity shortcut before Lua table-index key equality was 2.9%
  slower across 21 alternating 10,000-iteration AOT pairs;
- bypassing `Box._applyBindingAttributes` for ordinary bindings was 7.7%
  slower across 21 alternating 2,000,000-read AOT pairs;
- retaining a scratch list for transient-binding recycling was 1.8% slower
  across 21 alternating 5,000-call AOT pairs despite removing one small list
  allocation from each observed recycle;
- splitting the common no-work automatic-GC safe point out of its async method
  was 4.2% slower across 21 alternating 5,000-call AOT pairs;
- guarding already-lazy statement logging at the call site was 2.7% slower by
  independent medians and 2.9% slower by median paired deltas across 21
  alternating 5,000-call AOT pairs;
- returning raw scalar payloads from local identifier reads showed only a
  0.5% median paired reduction across 21 alternating 5,000-call AOT pairs and
  3.2% across 11 longer 20,000-call pairs. In the matched full-width GPU game
  leg, update p95 improved from 70 to 66 microseconds and update p99 from 97
  to 96 microseconds, but whole-frame CPU p95 regressed from 2,578 to 2,689
  microseconds and p99 from 3,236 to 3,421 microseconds. The raw-identifier
  path was therefore removed. An exploratory allocation pair was also
  discarded because the compositor changed presentation geometry during the
  candidate capture;
- resolving binary-expression source lines only when a line hook or error
  needed them was 9.3% slower by median paired deltas across 21 alternating
  30,000-iteration AOT pairs, and 0.4% slower by independent medians. The
  compile-time branch and lazy-local state cost more than the eager span reads,
  so the candidate was removed before a Flutter run;
- returning closure-free numeric `for` environments to their parent frame
  reduced a 5,000-call AOT kernel from 10,006 created boxes to 8, improved the
  independent median by 2.3%, improved the median paired delta by 3.0%, and won
  8 of 11 pairs. It also reached zero fresh runtime bindings in every measured
  steady-state game window. The exact 800x600 reverse-order gate nevertheless
  rejected it: versus reverse OFF, update p95/p99 regressed from 33/49 to
  44/73 microseconds, CPU p95/p99 regressed from 1,312/1,477 to 1,680/1,855
  microseconds, and median maximum CPU time regressed from 1,882 to 2,311
  microseconds. The extra scope-pool bookkeeping cost more than the eliminated
  allocations on the real frame path, so the flag, implementation, test, and
  kernel were removed. Artifacts remain under
  `.tmp/numeric-for-environment-pool/`;
- treating the parser's empty attribute string as an ordinary single-local
  declaration allowed scalar locals to store raw payloads, just as the
  existing multi-local path does. Opt-in clone attribution first showed
  11,578 local-binding clones: 10,832 shared scalars, 699 unshared scalars,
  three decorated primitives, and 44 other values. The focused AOT candidate
  then reduced 20,001 local-binding clones per 20,000-call trial to zero with
  an identical checksum, but independent median time regressed 5.0%, median
  paired time regressed 1.7%, and only 3 of 11 pairs favored raw storage. The
  exact OFF-to-ON-to-OFF GPU walking gate confirmed the cost: versus reverse
  OFF, update p95/p99 regressed from 45/66 to 47/78 microseconds, CPU p95/p99
  from 1,673/1,912 to 1,742/2,212 microseconds, and render p99 from 1,865 to
  2,188 microseconds. The raw single-local behavior, toggle, test, and kernel
  were removed. The compile-time-elided clone attribution counters remain for
  future profiling, and trial artifacts remain under
  `.tmp/single-local-raw-slot/`;
- replacing that candidate's full eligibility helper with the existing
  `Value.canStoreAsRawLuaSlot` null checks did not rescue it. The cheaper guard
  still reduced 20,001 clones to zero, but regressed the independent AOT
  median by 4.8%, regressed the median paired time by 3.1%, and won only 5 of
  11 pairs. Because it produced the same raw-local storage policy already
  rejected by the game gate, it was removed without another Flutter run.
  Artifacts remain under `.tmp/fast-single-local-raw-slot/`;
- storing an already-cached shared primitive facade directly in an ordinary
  single-local box avoided the read-side cache penalty of raw storage. In a
  20,000-call AOT kernel it reduced local clones from 40,001 to 20,000 and
  shared-scalar clones from 20,001 to zero. The independent median improved
  5.4%, but median paired time regressed 1.2% and only 5 of 11 pairs favored
  the candidate. The exact GPU game sandwich again rejected it: versus reverse
  OFF, CPU p95/p99 regressed from 1,577/1,735 to 1,608/1,852 microseconds,
  render p99 from 1,694 to 1,832 microseconds, and median maximum CPU time from
  1,841 to 2,143 microseconds. The frozen parity capture also moved from the
  identical OFF normalized RMSE of `0.0439446` to `0.0440584` with the
  candidate, leaving an unexplained direct ON/OFF image delta. The behavior,
  toggle, test, and kernel were removed. Artifacts remain under
  `.tmp/shared-primitive-local-facade/`;
- propagating metatable-free numeric unary negation as a raw number removed an
  intermediate facade from chains such as `-elapsed * 0.22`. A 50,000-step
  AOT kernel improved 2.6% by independent medians and 4.4% by paired medians,
  with 8 of 11 pairs favoring ON and identical checksums. Frozen renderer
  parity stayed exact at normalized Canvas/GPU RMSE `0.0439446`, but the game
  timing gate rejected the candidate. Versus reverse OFF, update p95/p99
  regressed from 40/53 to 42/67 microseconds, CPU p99 from 2,003 to 2,085
  microseconds, render p99 from 1,979 to 2,027 microseconds, and median maximum
  CPU time from 2,496 to 2,563 microseconds. The first OFF leg was faster than
  ON across every reported tail. The flag, implementation, tests, and kernel
  were removed; artifacts remain under `.tmp/raw-numeric-unary/`;
- returning literal values, direct cached table-field reads, and explicitly
  eligible builtin calls synchronously was 17.1% faster by independent medians
  and 12.9% faster by median paired deltas across 11 alternating 50,000-call
  AOT pairs; all 11 pairs favored it. The exact 800x600 GPU walking sandwich did
  not retain that microkernel result. Against the reverse OFF leg, update
  p95/p99 improved only 2.6%/5.4%, while whole-frame CPU p95 regressed 6.9% and
  p99 regressed 24.0%; render tails moved in the same direction. The complete
  synchronous chain, its compile-time flags, and focused tests were therefore
  removed. The rejected game artifacts remain under
  `.tmp/sync-ast-builtin-calls/`.

`benchmark/binary_expression.dart` and `benchmark/table_index_access.dart`
remain as focused kernels so later structural work can be measured without
repeating these assumptions.

## AST inline builtin frames

The walking CPU profile after the shared metamethod-map change attributed
13.43% of sampled time to `visitFunctionCall`; `_callFunction` accounted for
108 of 1,638 total samples, or about 6.6%. LOVE's hot graphics/state bindings
already opt into `BuiltinFunction.canBytecodeInlineWithoutManagedFrame`, and
the bytecode VM already honors that contract. The AST engine now does the same
after evaluating and canonicalizing arguments. Debug hooks still take the
managed-frame path so their call/return observations and stack depth remain
unchanged. Set `LUALIKE_AST_INLINE_BUILTIN_FRAME=false` for the matched old
behavior.

`benchmark/ast_inline_builtin_frame.dart` repeatedly calls `math.abs` through
the AST engine. Across 11 alternating, CPU-pinned AOT process pairs with 20,000
calls and three internal trials per process, the exact compile-time comparison
produced:

| AST eligible builtin calls | Median time | Change |
| --- | ---: | ---: |
| Managed frame for every call | 520,903 us | baseline |
| Explicitly eligible calls inline | 399,625 us | -23.3% |

The median paired reduction was 28.7%, all 11 pairs favored the inline path,
and every process returned the same 959,307 checksum.

The real-game retention gate used an OFF-to-ON-to-OFF sandwich: profile-mode
GPU-only AST Neon Relay, reset `r`, held `d`, pointer 640,360, an exact 800x600
presentation with zero destination offset, five 240-frame windows per build,
and 77 average rendered commands. No window used software fallback or exceeded
the 60 Hz or 120 Hz frame budgets.

| Five-window median | Managed frame before | Eligible calls inline | Managed frame reverse |
| --- | ---: | ---: | ---: |
| p95 update | 43 us | 44 us | 42 us |
| p99 update | 61 us | 59 us | 60 us |
| p95 CPU frame | 1,798 us | 1,366 us | 1,659 us |
| p99 CPU frame | 2,285 us | 1,609 us | 2,274 us |
| p95 render | 1,769 us | 1,339 us | 1,638 us |
| p99 render | 2,258 us | 1,579 us | 2,253 us |
| Median maximum CPU frame | 2,551 us | 1,657 us | 3,233 us |

Against the reverse baseline, inline eligible calls reduced p95 CPU frame time
by 17.7% and p99 by 29.2%; against the first baseline, the reductions were
24.0% and 29.6%. Update tails were effectively flat. Allocation snapshots were
not used as proof because process heap histories and GC schedules differed
substantially. The focused structural test instead observes call-stack depth
directly: eligible calls run at depth zero without a debug hook and retain the
managed frame when a hook is installed.

## Indexed AST frames and direct leaf parameters

The AST compatibility engine now assigns stable indexed slots to parameters and
local declarations. Box-backed slots remain authoritative and preserve the
existing `Environment` behavior, while identifier nodes cache the resolved
layout and slot after their first lexical lookup. Cached assignment targets use
the same path. This is migration infrastructure for the slot-native runtime,
not a claim that AST lexical environments have already been removed.

In the first retained write-cache AOT gate, 21 process pairs favored indexed
writes in 14 cases. The paired median improved 3.0% and independent medians
improved 5.7%. Five-window Relic Breach legs found lower allocation churn and
better p99 tails with roughly flat p95 CPU/render time, so the indexed frame was
retained as the boundary for subsequent direct-slot work.

The first direct-storage slice is intentionally narrower. Non-`_ENV`
parameters live without a Box only when the function body is closure-free and
call-free. `_ENV` always remains a real environment binding. Box-backed slots
always read from their Box; treating the parallel raw cache as authoritative
caused stale weak-table state. Call-capable direct parameters were also rejected
after `cstack.lua` exposed an error/coroutine continuation that resumed under
the wrong ambient frame. Widening that eligibility requires continuation-owned
frame state, not another name-cache exception.

`benchmark/slot_only_parameters.dart` measures a call-free leaf that mutates
one parameter twice. Across 21 alternating AOT process pairs, slot-only
parameters improved the independent median by 5.38% and the paired median by
4.18%; 16 of 21 pairs favored the direct-slot build. For 5,000 calls it removed
one created parameter Box plus 4,999 Box rebinds, and recorded 5,000 direct
parameter binds and 10,000 direct writes with the same checksum.

The real-game gate used the host-source Relic Breach project, AST mode,
Flutter GPU, fixed pointer `(640,360)`, held `d`, reset `r`, 136 average rendered
commands, and an identical 1,649.78 by 928 presentation rectangle. Five ON
windows exercised a median 115,822 direct parameter binds and no direct
parameter writes. Compared with ten OFF windows, update p95 moved from 69 to 72
microseconds while update p99 moved from 120 to 91 microseconds. CPU/render
tails favored ON, but both OFF legs contained large compositor/GPU variance, so
those whole-frame differences are not attributed to the interpreter change.
The slice is retained on the exact structural reduction, the repeatable AOT
win, stable update p95, improved update p99, and the complete upstream Lua suite
passing 30 of 30 files.

## Direct top-level leaf locals and lexical slot ownership

The next AST migration slice stores primitive top-level locals directly in the
indexed frame for closure-free, call-free leaf functions. It deliberately
rejects nested declarations, loop-owned locals, `_ENV`, `_G`, attributes,
identity-bearing values, and debug-hook execution. The parser represents an
ordinary absent local attribute as an empty string, so the retained path first
normalizes that value to no attribute. This prevents the empty marker from
forcing a primitive `Value` clone even when direct storage is disabled.

Indexed bindings now record their lexical Environment owner. Identifier caches
and per-name slot stacks accept a slot only when that owner is in the active
environment chain. This fixed an existing scope leak where a local declared in
a completed `do` block could remain the indexed winner over an outer local,
which in turn produced the wrong Lua-facing method diagnostic.

`benchmark/slot_only_locals.dart` measures a leaf with two primitive locals and
one local write. Across 21 alternating AOT process pairs at 20,000 calls, the
direct-local build improved the independent median from 1,036,997 to 945,962
microseconds (-8.8%). The paired median improved by 92,220 microseconds (-8.9%)
and 17 of 21 pairs favored direct storage.

The real-game gate used an OFF-to-ON-to-OFF sandwich: profile-mode GPU Relic
Breach, AST mode, reset `r`, held `d`, fixed pointer `(640,360)`, five 240-frame
windows per leg, and about 136 rendered commands with zero software-surface
fallbacks. The candidate exercised a median 5,936 direct local binds per
window. Against the ten combined OFF windows, the five-window medians were:

| Median | Box-backed locals | Direct eligible locals | Change |
| --- | ---: | ---: | ---: |
| update p95 | 47 us | 43 us | -8.5% |
| update p99 | 70 us | 65 us | -7.1% |
| CPU frame p95 | 2,433.5 us | 2,163 us | -11.1% |
| CPU frame p99 | 4,005.5 us | 3,018 us | -24.7% |
| render p95 | 2,412.5 us | 2,128 us | -11.8% |
| render p99 | 3,980 us | 2,989 us | -24.9% |

Whole-frame improvements are supporting evidence because compositor variance
was larger than update variance. The update-tail movement, direct-binding
counter, exact AOT result, focused Dart tests, and freshly compiled upstream
Lua suite all agree, so the slice is retained. The compiled `test_runner`
passed all 30 files; the focused interpreter, debug, coroutine, GC, IO, and base
set passed 211 tests.

Use `LUALIKE_AST_SLOT_ONLY_LOCALS=false` for the Box-backed local baseline and
`LUALIKE_NORMALIZE_EMPTY_LOCAL_ATTRIBUTES=false` to isolate the pre-normalized
parser attribute path. Artifacts are stored under repo-local `.tmp` as
`slot-locals-game-off-first.jsonl`, `slot-locals-game-on.jsonl`, and
`slot-locals-game-off-reverse.jsonl`.

Use `LUALIKE_AST_INDEXED_LOCAL_FRAME=false` for the pre-indexed AST path and
`LUALIKE_AST_SLOT_ONLY_PARAMETERS=false` for the Box-backed parameter baseline.
When binding diagnostics are enabled, `runtimeLocalFrames` reports frame
creation/reuse, cache hits, fallback name lookups, direct parameter binds, all
slot writes, and direct-only writes. VM allocation-service counters remain
supporting evidence only: they were observed to move non-monotonically in live
profile sessions, so exact runtime-owned counters and allocation traces are the
authoritative allocation evidence.

The focused interpreter/debug-hook slice completed with 35 passing tests. The
canonical Lualike suite reached 1,958 passes and three skips; one unrelated
multi-file stack-trace assertion failed identically with the optimization on
and off. The LOVE2D suite reached 1,057 passes and two skips; its four native
TrueType glyph/kerning failures also reproduced identically in a compile-time
optimization-off rerun of the affected files.

Artifacts are stored under the repo-local `.tmp` directory:

- `ast-inline-builtin/paired.jsonl`
- `ast-inline-builtin/game-off-five-exact.jsonl`
- `ast-inline-builtin/game-on-five-exact.jsonl`
- `ast-inline-builtin/game-off-reverse-five-exact.jsonl`
- `shared-metamethod-map-game-cpu-profile/overall/summary.json`

## Nested lexical direct locals

The lexical-owner model made the original top-level-only eligibility guard
obsolete for closure-free, call-free leaf functions. Their primitive local
declarations can now use direct frame slots inside `do` blocks, `if`/`elseif`/
`else` branches, and `while`, `repeat`, numeric-for, and generic-for bodies.
The declaration keeps one immutable layout slot across calls and iterations;
each bind updates its owning Environment. Cached reads accept the slot only
while that owner is in the active environment chain, so shadowed inner values
cannot leak after block or loop exit.

This expansion does not include loop control variables, `_ENV`, `_G`, local
attributes, identity-bearing values, debug-hook execution, functions that can
create closures, or functions containing calls. Those cases retain the Box
and Environment contract. Nested functions also own a separate layout and are
never traversed into the enclosing function's declaration set.

`benchmark/slot_only_nested_locals.dart` isolates the expansion with a leaf
that repeatedly binds locals in a numeric loop, both branch arms, and a `do`
block. The baseline sets
`LUALIKE_AST_SLOT_ONLY_NESTED_LOCALS=false`, which keeps the previously retained
top-level direct-local path active. Across 15 alternating AOT process pairs at
1,200 calls, the candidate won 10 pairs. The independent median improved from
515,342 to 463,998 microseconds (-10.0%), and the paired median saved 45,228
microseconds. Exact diagnostics changed from 5,403 to 1,203 created Boxes
(-77.7%); direct local binds increased from 1,200 top-level binds to 40,800
total binds, proving that 39,600 nested declarations used the new path.

The synchronized Relic Breach walking workload is a coverage gap for this
specific expansion: its five candidate windows reported roughly the same
5,844-6,024 direct local binds as the earlier top-level-only build. Therefore
those frame timings are treated as neutral smoke evidence and are not claimed
as a game-speed improvement. The isolated AOT workload, scope/debug/GC tests,
and upstream Lua suite are the retention evidence for this slice. Use
`LUALIKE_AST_SLOT_ONLY_NESTED_LOCALS=false` for the precise reverse A/B.

## Full-resolution native parity capture

Reduced comparison panes mix renderer differences with a second resampling
step: native LOVE is resized after capture while Canvas and GPU render directly
at pane resolution. `tool/capture_renderer_parity.sh` now captures native LOVE,
Canvas-only, and GPU-only at the same 800x600 surface size and the same frozen
`v` scene. It drives profile builds through the LOVE2D VM extensions, and the
same `love2d.setCapturePresentation` control is available through Marionette in
debug mode. Capture presentation hides the renderer toggle, lifecycle badge,
and programmatic cursor only; loading and error diagnostics remain visible.

The helper also sets Hyprland's per-window `border_size` and `rounding` to zero
and disables its shadow before every capture. Without that gate, the native
image's outermost pixels contained the active compositor border while the
Flutter crop contained game pixels, inflating renderer RMSE. Each dynamic
property request must return `ok`; an unsupported compositor API now fails the
capture instead of silently producing contaminated evidence.

The first end-to-end run on 2026-08-26 used LOVE 11.5, AST mode, OpenGLESSDF,
4x MSAA, manual mipmap uploads, 111 commands, and fixed aim `(640,360)`. The
helper completed the native launch and all three captures in 27 seconds:

| 800x600 normalized RMSE | Value |
| --- | ---: |
| Native LOVE vs Flutter GPU | 0.0598718 |
| Native LOVE vs Canvas | 0.0695458 |
| Canvas vs Flutter GPU | 0.0513522 |

Those historical whole-frame values predate the decoration gate and should not
be compared numerically with later clean captures; their region attribution
and qualitative renderer ordering remain useful.

GPU remains closer to native than Canvas. Region decomposition keeps the next
work targeted: native-vs-GPU RMSE is 0.1129 in the top HUD, 0.0795 around the
sentinel beacon, 0.0765 around the boss, 0.0612 around the player, and only
0.0161 in an unobstructed lower-background crop. The remaining whole-frame
error is therefore concentrated in Flutter text rasterization and alpha-edged,
minified art rather than surface placement or simulation drift. Keep these
areas separate when evaluating a text or texture candidate.

Artifacts for this baseline are under
`.tmp/parity/automated/current-{native,canvas,gpu}.png` with matching state and
summary JSON files. The checked-in helper defaults its temporary native LOVE
log to `$TMPDIR`, avoiding a full system `/tmp` during long profiling sessions.

### Small-font text spacing parity

A same-file Vera.ttf sample isolated the largest remaining HUD-text spacing
difference. At 12 pixels, native LOVE measured
`AVATAR 0123456789 // WAVE READY` at 227 pixels while lualike measured 220.
Individual glyph advances already matched. The seven-pixel error came from
using the font's raw `AV`, `VA`, and similar kerning values without FreeType's
[`FT_KERNING_DEFAULT` small-size fitting][freetype-kerning]. FreeType damps
kerning below 25 ppem before pixel rounding; [LOVE requests that fitted
mode][love-truetype-rasterizer] and then converts the value back to logical
pixels. Applying that sequence makes the Vera 12 `AV` and `VA` pairs zero and
the complete sample width 227, matching LOVE 11.5. The existing DPI-normalized
kerning behavior remains covered separately.

Flutter's paragraph shaper still produced a 219.28125-pixel run for the same
text. Exact per-glyph positioning improved the visual match but was rejected:
it increased the five-window Canvas CPU p95 from roughly 271 to 831
microseconds. The retained renderer keeps one cached `TextPainter` paragraph
and, for unwrapped source-backed TrueType text only, caches a horizontal scale
from the paragraph width to LOVE's measured advance width. Wrapped text is not
scaled because line breaking and per-line alignment require separate handling.

At 800x600, the retained path reduced native-vs-Canvas normalized RMSE from
the original 0.0876376 to 0.0858413 (about 2.1%). Native-vs-GPU was 0.0859613,
and Canvas-vs-GPU remained 0.00148543 because both use the same cached text
overlay. The 12-pixel endpoint markers now match native; the remaining error is
primarily glyph hinting and rasterization rather than advance width.

Five 240-frame profile windows at the same 800x600 workload found no frame
budget regression. With the fitting enabled, median Canvas CPU p95/p99 were
253/273 microseconds versus 271/316 with it disabled; GPU was 394/437 versus
435/504. Every leg had zero 120 Hz and 60 Hz CPU-budget overruns. Treat those
small timing differences as neutral launch/run noise, not a speedup claim. The
retained result is a measurable parity improvement with no observed pacing
cost. Use `--dart-define=LOVE_FREETYPE_TEXT_SPACING=false` for a diagnostic
reverse A/B.

[freetype-kerning]: https://freetype.org/freetype2/docs/reference/ft2-glyph_retrieval.html
[love-truetype-rasterizer]: https://github.com/love2d/love/blob/11.5/src/modules/font/freetype/TrueTypeRasterizer.cpp

### Mipmapped texture edge parity

An isolated 800x600 sample drew the same four generated art textures through
LOVE 11.5 and Flutter GPU at game-scale reductions from 0.074 to 0.145, with
rotated, integer-positioned, half-pixel-positioned, and translucent variants.
Before scoring, the parity helper was tightened to require a zero-offset exact
800x600 presentation rectangle. A compositor-supplied extra content pixel had
previously produced a 0.5-pixel destination offset and made a rejected mipmap
candidate look better through accidental full-frame resampling.

The exact baseline native-vs-GPU normalized RMSE was 0.0298343. A direct 2x2
box mip chain was rejected because it worsened the exact result to 0.0300395.
The retained path keeps flutter_gpu's generated mipmaps and applies a fragment
LOD bias. The sweep was:

| Additional LOD bias | Native vs GPU RMSE |
| ---: | ---: |
| 0.00 | 0.0298343 |
| -0.15 | 0.0281049 |
| -0.25 | 0.0272550 |
| -0.35 | 0.0262521 |
| -0.50 | 0.0253680 |
| -0.65 | 0.0254116 |

The selected `-0.50` compensation improves the isolated whole-frame score by
14.97%. It also improves the drone, sentinel, and player regions; the smallest
beacon region becomes worse, so this is a measured compromise rather than a
claim of identical mip generation. In the full Neon Relay frame, comparing
both GPU candidates against the same native capture improved RMSE from
0.0581427 to 0.0578237 (0.55%).

[LOVE's OpenGL renderer][love-opengl-image] applies the negative of
`mipmapSharpness` as its texture LOD bias. The GPU shader now receives
`-image.mipmapSharpness + compensation` for mipmapped images and zero for
single-level images. The value is packed into the existing per-draw uniform
upload, so this adds neither a Dart allocation nor a separate resource bind.
Use `--dart-define=LOVE2D_GPU_MIPMAP_LOD_COMPENSATION=0` for a reverse A/B.

Five 240-frame GPU walking windows per leg found no frame-budget regression.
The retained build's median CPU p95/p99 was 2.033/2.854 milliseconds versus
2.100/2.659 milliseconds with compensation disabled. All 2,400 measured
frames had zero 120 Hz and 60 Hz CPU-budget overruns. Treat the mixed percentile
movement as neutral run noise, not a speedup claim.

A later full-scene regional comparison found that applying the complete bias to
the arena backdrop sharpened it past native LOVE while still helping the much
smaller game sprites. Direct image draws therefore adapt the extra compensation
to their effective texture scale: zero at 0.5x and above, a smooth ramp from
0.5x to 0.25x, and the complete measured compensation at 0.25x and below.
Sprite batches, particles, and meshes retain the complete compensation because
their demonstrated workload is strongly minified. The common saturated scale
cases avoid square-root work.

Against the same byte-identical native capture, adaptive compensation improved
full-frame native-vs-GPU RMSE from 0.0560529 to 0.0556310 (0.75%) and the clean
background region from 0.0176892 to 0.0156494 (11.5%). Every measured boss,
sentinel, drone, player, and aim region was unchanged or slightly better. Five
240-frame walking windows measured median CPU p95/p99 of 1.956/2.506 ms versus
1.971/2.706 ms in a reverse-order fixed-bias run; all frames remained below
both CPU budgets. This is a parity improvement with neutral pacing, not a
timing speedup claim. Set
`LOVE2D_GPU_ADAPTIVE_MIPMAP_LOD_COMPENSATION=false` for the exact rollback.

Shader loading now prefers the build-hook output over the checked-in fallback.
Previously, local shader edits compiled successfully but the demo loaded the
stale fallback asset, invalidating A/B attempts. The final generated bundle is
also copied to the fallback asset for consumers where build-hook output is not
available.

[love-opengl-image]: https://github.com/love2d/love/blob/11.5/src/modules/graphics/opengl/Image.cpp

### Pre-rasterized TrueType atlas and direct GPU text

The full-resolution parity baseline showed that the remaining HUD difference
was glyph coverage rather than command placement. `LoveFlameHost` now
pre-rasterizes printable ASCII from the same TrueType bytes and LOVE metrics
used by the font APIs. The immutable `LoveFontGlyphAtlas` keeps straight RGBA
pixels for GPU upload, a premultiplied host image for Flutter Canvas, and the
physical-pixel bearing and advance for every packed glyph. Font snapshots and
copies share that atlas instead of rebuilding it.

Canvas caches each unwrapped left-aligned atlas layout and renders it with one
`drawAtlas` call. The GPU backend caches the corresponding interleaved vertex
payload and draws it through the existing sprite-batch shader inside the
original render pass. Wrapped text, non-left alignment, configured fallback
fonts, and codepoints outside the atlas remain on the existing TextPainter
fallback, so the optimization does not broaden its semantic assumptions.

A matched 800x600 `v` capture on 2026-08-27 measured:

| Normalized RMSE | TextPainter baseline | Glyph atlas | Change |
| --- | ---: | ---: | ---: |
| Native LOVE vs Canvas | 0.0691551 | 0.0671013 | -2.97% |
| Native LOVE vs GPU | 0.0584850 | 0.0560529 | -4.16% |
| Canvas vs GPU | 0.0447955 | 0.0448236 | +0.06% |

The direct GPU capture rendered all 115 commands with zero hybrid fallback
commands; the prior path replayed 11 text commands over the presented GPU
frame. Five 240-frame walking windows at an exact 800x600 presentation found
median GPU CPU p95/p99 of 1.822/2.318 ms for direct atlas text versus
1.817/2.269 ms for the old TextPainter overlay. All 2,400 compared frames had
zero 120 Hz and 60 Hz CPU-budget overruns. Treat the small percentile movement
as neutral run noise: the retained gains are measurable native visual parity,
correct in-pass draw ordering, and elimination of hybrid text commands, not a
claimed renderer timing speedup.

Use `--dart-define=LOVE_FREETYPE_GLYPH_ATLAS=false` for the matched rollback.
This disables both atlas construction and atlas rendering, restoring the
cached TextPainter path.

### Pure-Dart glyph coverage calibration

[Native LOVE 11.5][LOVE TrueType rasterizer] loads hinted glyphs with
[FreeType][FreeType glyph loading] and renders normal text as an 8-bit
grayscale bitmap. The portable fallback rasterizer reads the same
TrueType outlines but estimates edge coverage with a fixed 4x4 sample grid; it
does not execute the font's TrueType hinting program. The resulting atlas kept
the correct font and text metrics but made partially covered edges heavier than
the native output.

The fallback now applies a measured power curve only to partial grayscale
coverage while preserving zero and fully covered stem pixels. It runs once
during glyph rasterization; cached atlas draws do no extra per-frame work. A
matched exact-800x600 sweep produced:

| Coverage gamma | Native vs GPU RMSE |
| ---: | ---: |
| 1.0 (neutral) | 0.0556310 |
| 1.5 | 0.0549851 |
| 2.0 | 0.0547338 |
| 3.0 | 0.0545523 |

Gamma 3.0 improved the whole frame by 1.94%. It also independently improved
the title, instructions, right HUD, bottom HUD, and boss-label regions, so the
selection is not based on one glyph or crop. Five 240-frame GPU walking windows
reported median CPU p95/p99 of 2.108/2.693 ms, zero 120 Hz or 60 Hz CPU-budget
overruns, 91 average commands, and zero hybrid fallbacks. This is a visual
parity result, not a timing speedup claim. Use
`LOVE_FREETYPE_GLYPH_COVERAGE_GAMMA=1.0` for neutral fallback coverage.

This calibration is not a substitute for FreeType hinting. A future native
rasterizer integration must remain optional and portable, and should replace
the calibration only after matched captures demonstrate a further win.

[LOVE TrueType rasterizer]: https://github.com/love2d/love/blob/11.5/src/modules/font/freetype/TrueTypeRasterizer.cpp
[FreeType glyph loading]: https://freetype.org/freetype2/docs/reference/ft2-glyph_retrieval.html

### Continuation-owned call-capable AST slots

The indexed AST frame now remains authoritative while a closure-free function
makes Lua or host calls. Logical call frames carry their `AstLocalFrame`
through nested calls, tail-call rebinding, coroutine suspension, and debugger
inspection. `pcall` and `xpcall` restore the caller environment, function, and
indexed frame together. The latter invariant is not optional: the first
candidate failed upstream `cstack.lua` when a protected coroutine chain hit the
call-depth guard before the newest callee installed a body frame. The repaired
candidate passes that scenario and the full freshly rebuilt AST upstream suite
30/30.

`LUALIKE_AST_SLOT_ONLY_CALL_CAPABLE_FRAMES=false` is the precise rollback. It
keeps the already-retained call-free parameter/local and nested lexical-slot
paths enabled, so the A/B isolates only the expanded call boundary.

The isolated AOT kernel in
`pkgs/lualike/benchmark/slot_only_call_capable_frames.dart` made 1,200 calls
through nested Lua and math builtins. Fifteen alternating ON/OFF pairs, each
using the median of three internal samples, produced:

| Metric | Call-capable slots off | Call-capable slots on | Change |
| --- | ---: | ---: | ---: |
| Median elapsed time | 1,208,531 us | 1,078,734 us | -10.7% |
| New `Box` objects | 24,606 | 1,204 | -95.1% |
| Direct parameter binds | 0 | 20,400 | +20,400 |
| Direct local binds | 0 | 58,800 | +58,800 |

ON won 11 of 15 pairs; the median paired OFF-minus-ON difference was 138,783
microseconds. This is an attribution kernel, not a game-frame claim.

The Neon Relay walking workload does exercise the expansion. A separate
five-window Canvas diagnostics run changed median new bindings from 6,777 to
3,766, removed 25,602 recycled-box binds, and performed 19,099 direct parameter
plus 28,245 direct local binds. Diagnostics increment counters at every direct
bind, so those builds are allocation evidence only and are not the timing A/B.

The clean timing comparison compiled diagnostics out. Both sides used AST
mode, Canvas-only rendering, the packaged Neon Relay source, reset `r`, held
`d`, pointer `(640,360)`, two seconds of warmup, and seven independent 240-frame
windows:

| Metric (median of seven windows) | Call-capable slots off | Call-capable slots on | Change |
| --- | ---: | ---: | ---: |
| p95 update | 47 us | 41 us | -12.8% |
| p99 update | 61 us | 55 us | -9.8% |
| p95 CPU frame | 688 us | 679 us | -1.3% |
| p99 CPU frame | 810 us | 787 us | -2.8% |
| p95 render | 655 us | 648 us | -1.1% |
| p99 render | 774 us | 763 us | -1.4% |
| median maximum CPU frame | 1,510 us | 888 us | -41.2% |

All 3,360 measured frames stayed below both CPU budgets. GPU-only diagnostics
were renderer-dominated and mixed at the CPU-frame tail, but the reverse leg
kept p95 effectively flat (1.690 ms off versus 1.703 ms on) while update p99
improved from 58 to 47 microseconds. Retain the expansion for the isolated and
clean Canvas wins plus the large binding reduction; do not claim a GPU render
speedup from this interpreter change.

### Direct uncaptured bindings in closure-capable AST functions

A function no longer loses every direct parameter and local merely because its
body creates a nested closure. At function creation, a conservative AST scan
collects every identifier below a nested-function boundary. Parameters and
eligible primitive local declarations whose names are absent from that set use
the existing indexed frame; possible captures keep their Environment/Box
identity. False positives retain boxes, so the scan can reduce coverage without
changing closure semantics. Function bodies are analyzed once, not once per
invocation or frame.

`LUALIKE_AST_SLOT_ONLY_UNCAPTURED_CLOSURE_BINDINGS=false` restores the prior
all-boxed boundary for closure-capable functions while leaving the retained
closure-free slot paths enabled.

`pkgs/lualike/benchmark/slot_only_uncaptured_closure_bindings.dart` measures an
outer transform that creates a nested function capturing one local while its
other parameter and primitive locals remain uncaptured. Fifteen alternating
AOT process pairs, each taking the median of three internal samples, produced:

| Metric | Selective slots off | Selective slots on | Change |
| --- | ---: | ---: | ---: |
| Median elapsed time | 1,024,282 us | 968,816 us | -5.4% |
| New `Box` objects | 7,203 | 3,603 | -50.0% |
| Direct parameter binds | 19,200 | 20,400 | +1,200 |
| Direct local binds | 0 | 20,400 | +20,400 |

ON won 10 of 15 pairs; the median paired OFF-minus-ON difference was 38,876
microseconds. This path benefits initialization and callback-heavy Lua that
defines fallback functions, including Relic Breach. Neon Relay's steady walking
loop does not create these closures, so this result is not a walking-frame
speedup claim.

The broad package gate exposed two debugger regressions from the larger indexed
frame migration, not from this feature flag. Mixed Box-backed and direct locals
were enumerated in storage order, and direct nested-block locals had no
Environment entry to enumerate. `AstLocalFrame` now exposes all live declaration
bindings in stable slot order; `debug.getlocal` and `debug.setlocal` consume that
single ordered view. A separate failing-`assert` regression came from bypassing
the managed builtin frame: successful assertions remain inline, while failed
assertions retain the call-site frame needed to report a required module's
source URL.

After those repairs, the complete lualike Dart suite passed. A freshly compiled
standalone executable then passed the upstream Lua suite 30/30 under AST, 30/30
under IR, and 30/30 under lua-bytecode.

### Direct identity-bearing AST locals

An uncaptured local table, string, function, or userdata now keeps its canonical
`Value` facade directly in the indexed frame instead of allocating a Box. This
is a storage change, not an unwrapping change: table/metatable/function identity
remains on the same facade. Potential captures, `_ENV`, `_G`, `<const>`,
`<close>`, and declarations observed while a debug hook is active remain boxed.
The call frame already roots every direct slot for the custom collector and
preserves the frame across coroutine suspension. Regression tests cover table
identity, a weakly referenced table surviving full collection, a table local
across yield/resume, and mixed direct/boxed debugger ordering.

`LUALIKE_AST_SLOT_ONLY_IDENTITY_LOCALS=false` restores Box-backed identity
locals while leaving primitive slots and the other retained AST frame features
enabled. Diagnostics report both the build flag and
`slotOnlyIdentityLocalBinds` under `runtimeLocalFrames`.

`pkgs/lualike/benchmark/slot_only_identity_locals.dart` creates one table, one
string, and one function local in each of 1,200 transforms. Fifteen alternating
AOT process pairs, each taking the median of three internal samples, produced:

| Metric | Identity slots off | Identity slots on | Change |
| --- | ---: | ---: | ---: |
| Median elapsed time | 829,238 us | 807,757 us | -2.6% |
| New `Box` objects | 4,803 | 1,203 | -75.0% |
| Direct local binds | 1,200 | 4,800 | +3,600 |
| Direct identity-local binds | 0 | 3,600 | +3,600 |

ON won 10 of 15 pairs; the median paired OFF-minus-ON difference was 107,076
microseconds. Treat this as a strong allocation win with a modest, noisy timing
benefit.

A Neon Relay Canvas diagnostics window confirmed a high overall direct-local
bind rate, but normalized activity barely changed between separately launched
ON/OFF builds and their presentation geometry differed. The identity path is
therefore not credited with a walking-frame speedup. It primarily targets
initialization and callback-heavy code until a matched live window reports
nonzero `slotOnlyIdentityLocalBinds` after the timing reset.

The first upstream compatibility run exposed one stripped-chunk debugger
ordering regression: the direct `debug` local was omitted, allowing a later
Box-backed local to appear first. Stripped frames now merge live indexed
declarations into the same stable debugger view. After that repair, the
complete Dart package suite exited successfully and a freshly compiled
standalone runner passed 30/30 AST, 30/30 IR, and 30/30 lua-bytecode cases.

### Rejected: direct local function declarations

A follow-up prototype placed non-recursive, non-captured `local function`
declarations directly in indexed slots. It preserved recursion, later closure
capture, debug mutation, coroutine suspension, weak-table reachability, and
ordinary identity semantics in focused tests. In a diagnostic AOT workload
with two helpers created per transform, it reduced new Boxes from 3,603 to
1,203 and recorded 2,400 direct helper bindings.

The allocation result did not translate into acceptable throughput. Fifteen
alternating AOT process pairs with diagnostics compiled out produced a
1,458,981 us ON median versus 1,393,026 us OFF (+4.7%); ON won only 6/15 pairs,
and the median paired OFF-minus-ON difference was -101,164 us. Separate sampled
JIT profiles suggested lower ending heap growth (27.4 MB versus 33.7 MB), while
AOT peak RSS stayed effectively unchanged near 59.5 MB, but those separately
launched memory observations are weaker than the alternating timing result.
The prototype was removed rather than enabled. Local function declarations
remain Box-backed until the slot-native call path can avoid this throughput
regression.

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
  numeric-conversion cost in the hot path. Native builds now use an exact
  signed 64-bit cache key, while JavaScript retains the split-word key.
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

## Generated Circle and Arc Stroke Buffers

The matched Neon Relay GPU profile attributed most renderer-specific shape
samples to animated circles, open arcs, `_strokeVertices`, and miter
tessellation. The shape handler previously generated a Dart record for every
circle or arc point before immediately copying those coordinates into the
tessellator's reusable typed arrays.

Generated line circles and arcs now populate reusable `Float64List` coordinate
buffers directly. `GpuStrokeTessellator.tessellateCoordinates` feeds those
coordinates through the same duplicate filtering, normal calculation, miter
limit, and vertex writer as the public record-list path. An exact-geometry unit
test compares every output float from both entry points. Existing LOVE line and
polygon commands still use their authored point records.

The deterministic frozen sentinel capture preserved the established
Canvas-versus-GPU normalized RMSE of `0.0454966`. Comparing the previous and
new GPU captures produced normalized RMSE `0.000436651`; visual inspection
showed no changed outline geometry or edge treatment.

### In-process A/B control

Separate profile builds were too sensitive to host load to attribute timing.
`LOVE2D_GPU_RUNTIME_STROKE_TUNING=true` now retains both paths in one explicit
instrumentation build and exposes `love2d.setTypedGeneratedStrokes` through
both Marionette and the VM service. Ordinary builds compile out live tuning.
`tool/benchmark_generated_strokes_ab.sh` alternates records-first and
typed-first 240-frame sentinel windows in one process and verifies exact 1:1
presentation, approximately 112 commands per frame, and the selected path.

The first seven-pair run occurred while the eight-core host was saturated
(load average exceeded 11), so it is not credited as a throughput win:

| Metric | Point records | Typed coordinates |
| --- | ---: | ---: |
| Median p95 CPU frame | 6,159 us | 4,455 us |
| Median p99 CPU frame | 9,297 us | 6,062 us |
| Frames over 120 Hz budget | 106 | 19 |

The order-balanced median paired p95 delta was exactly `0 us`; typed won three
pairs, records won three, and one tied. The median paired p99 delta was
`-320 us`. Retain this as a proven generated-point allocation removal with
pixel parity, not as a claimed frame-time win. Repeat the checked-in A/B on an
unsaturated host before assigning a throughput percentage. The precise
production rollback is `LOVE2D_GPU_TYPED_GENERATED_STROKES=false`.

## Reusable Direct Sprite Geometry

Sprite batches and particle systems previously allocated a new vertex
`Float32List`, a base `Matrix4`, and two more `Matrix4` objects per entry while
expanding textured quads. `GpuSpriteGeometryBuilder` now composes LOVE's 2D
affine coefficients with scalar arithmetic and writes directly into one
grow-only typed scratch buffer. After that buffer reaches the workload's high
water mark, geometry expansion creates none of those temporary vertex or
matrix objects. This is an allocation-footprint result; it does not imply that
the process's retained heap or RSS shrinks because the scratch capacity is
deliberately retained for reuse.

`LOVE2D_GPU_RUNTIME_SPRITE_GEOMETRY_TUNING=true` retains both implementations
in one profile build and exposes `love2d.setDirectSpriteGeometry` through
Marionette and the VM service. Ordinary builds select the direct path by
default and compile out live tuning. `tool/benchmark_sprite_geometry_ab.sh`
alternates the legacy matrix path and direct scalar path in one process while
holding the same Neon Relay input, pointer, exact 1:1 presentation, and roughly
112 rendered commands per frame.

Seven order-balanced 240-frame pairs produced:

| Metric | Legacy matrices | Direct scratch buffer | Change |
| --- | ---: | ---: | ---: |
| Median p95 CPU frame | 2,492 us | 2,303 us | -7.6% |
| Median p99 CPU frame | 4,118 us | 3,799 us | -7.7% |
| Median paired p95 delta | 0 us | -238 us | direct faster |
| Median paired p99 delta | 0 us | -395 us | direct faster |
| Median paired render-p95 delta | 0 us | -240 us | direct faster |
| Frames over 120 Hz budget | 14 | 1 | -13 |

Direct won four of seven p95 pairs. One legacy window contained a severe tail
outlier, so the retained claim is the median improvement on this
SpriteBatch-heavy workload, not a universal frame-time percentage. A frozen
116-command 800x600 GPU capture compared the direct and legacy paths at RMSE
`0` and absolute pixel error `0`. Unit tests also compare every generated
sprite and particle vertex and verify scratch-buffer identity reuse.

The Dart VM allocation-profile snapshots returned non-monotonic accumulated
counters for unrelated VM type classes. Those snapshots are retained as
diagnostic artifacts but are not used as heap evidence. A steady-state RSS or
live-heap reduction remains unproven; the proven memory result is removal of
the per-batch/per-entry temporary geometry objects.

## Synchronous Plain-Table Bytecode Opcodes

The Lua-bytecode VM now keeps plain table reads and writes on its synchronous
lane when no metamethod can yield. A five-trial, matched Neon Relay comparison
at exact 800x600 presentation measured update p95 from 70 to 66 microseconds
(-5.7%), update p99 from 126 to 101 microseconds (-19.8%), and CPU-frame p95
from 1,398 to 1,320 microseconds (-5.6%). Frozen output was pixel-identical
(RMSE 0). Use `tool/benchmark_bytecode_sync_tables_ab.sh` for the checked-in
reverse A/B rather than comparing unrelated launches.

## Host-Managed Lualike GC

`LuaGcPolicy.hostManaged` removes Lualike's tracing, generation enrollment,
write barriers, and finalizer scans while retaining Dart GC. The default
remains `LuaGcPolicy.luaCompatible`. The demo exposes the alternative with
`LUALIKE_HOST_MANAGED_GC=true`.

Five matched 240-frame Canvas trials at exact 800x600 presentation, holding
the same input and averaging about 110 commands per frame, did not establish a
general frame-time win:

| Metric | Lua-compatible | Host-managed | Change |
| --- | ---: | ---: | ---: |
| Median update p95 | 61 us | 62 us | +1.6% |
| Median update p99 | 96 us | 86 us | -10.4% |
| Median CPU-frame p95 | 1,047 us | 1,140 us | +8.9% |
| Median CPU-frame p99 | 1,819 us | 1,610 us | -11.5% |
| Median maximum CPU frame | 2,423 us | 2,008 us | -17.1% |

Both policies sustained the display's 60 Hz cadence. The first observed stable
60 FPS run was the Lua-compatible control, so do not attribute that milestone
to the host-managed policy alone.

The retained-heap comparison is decisive. After roughly 6,140 frames, a
forced Dart GC in fresh same-age processes produced:

| Retained class or heap | Lua-compatible | Host-managed | Change |
| --- | ---: | ---: | ---: |
| Process heap usage | 162,727,984 B | 158,637,200 B | -2.5% |
| `Value` instances | 19,325 | 5,344 | -72.3% |
| `LuaValueMetadata` instances | 14,785 | 844 | -94.3% |
| `_HashMapEntry` instances | 16,070 | 991 | -93.8% |
| `_GrowableList` instances | 21,236 | 7,370 | -65.3% |

The process total includes large engine/AOT allocations, so it understates the
Lua-runtime-state reduction. The control also had automatic collection
disabled; its generation lists therefore retained transient objects even
without running tracing pauses. Host-managed mode prevents that enrollment.

This policy intentionally makes weak tables strong and suppresses `__gc`.
Lexical `__close` remains active. Use explicit closure for files and native
resources, and retain the default policy for scripts that depend on Lua weak
references or finalization.

## Native Rough-Line Pixel Alignment

The deterministic Neon Relay `v` frame exposed a GPU rasterization mismatch
that aggregate screenshots had obscured. Native LÖVE 11.5 placed odd-width
rough lines on one upper/left pixel row, while the triangle-based Flutter GPU
stroke split coverage across both neighboring rows. The effect was especially
visible across the arena's one-pixel grid.

The first GPU-only correction applied an allocation-free `-0.5` device-space
translation to every odd integral-width rough `LoveLineCommand`. It improved
the Neon Relay frame, but an isolated line probe showed that it over-corrected
coordinates authored at half pixels. Canvas had the inverse problem: integral
rough lines were not centered, while half-pixel lines already matched native.

The retained implementation uses `loveRoughLinePixelSnapAxes` in both Canvas
and GPU. It transforms the command points without allocating and selects each
device axis only when all coordinates on that axis are integral. Authored or
transformed half pixels are preserved. Smooth, even-width, and
fractional-width lines are unchanged. The backend rollbacks are
`LOVE_CANVAS_ROUGH_LINE_PIXEL_SNAP=false` and
`LOVE2D_GPU_ROUGH_LINE_PIXEL_SNAP=false`.

The before/after Flutter profile builds used the same native LOVE PNG, frozen
scene, logical pointer, lua-bytecode engine, and exact 800x600 presentation:

| Region | Native vs GPU before | Native vs GPU after | Result |
| --- | ---: | ---: | ---: |
| Full frame | 0.0541903 | 0.0530654 | -2.08% |
| HUD | 0.0940921 | 0.0937104 | improved |
| Boss | 0.0662097 | 0.0654219 | improved |
| Relay core | 0.0598716 | 0.0587513 | improved |
| Player | 0.0410365 | 0.0395826 | improved |
| Left field | 0.0338558 | 0.0308417 | -8.90% |
| Right field | 0.0386074 | 0.0360346 | improved |

No measured region regressed. The Canvas control changed by normalized RMSE
`0.000142672` between captures, small enough to attribute to capture noise.

The checked-in `assets/parity_probe` project isolates integer grids,
half-pixel grids, widths 1/2/3, smooth controls, and default-font text at an
exact 800x600 logical size. Its old Canvas behavior and old unconditional GPU
behavior provide reverse controls for the shared rule:

| Probe region | Native vs Canvas before | Native vs GPU before | Native vs Canvas refined | Native vs GPU refined |
| --- | ---: | ---: | ---: | ---: |
| Integer rough grid | 0.125844 | 0.002518 | 0.003548 | 0.002518 |
| Half-pixel rough grid | 0.003548 | 0.088187 | 0.003548 | 0.002518 |
| Mixed strokes | 0.079484 | 0.050815 | 0.057077 | 0.050815 |

Full-frame Canvas-vs-GPU RMSE fell from `0.0815908` to `0.0317085` (-61.1%).
Default-font Canvas and GPU output remains effectively identical to each other
(`0.00012767`) but differs from native (`~0.08956`), so text rasterization is a
separate parity problem rather than part of line alignment.

A five-trial, 240-frame GPU profile run after the correction held the same
movement key and 92-command workload. Median p95 CPU frame time was 3,623 us,
median p99 was 5,760 us, and no frame exceeded the 60 Hz budget. Eight of
1,200 frames exceeded the 120 Hz budget. This proves the retained path keeps
the scene within its 60 Hz target; it is not a claim that the half-pixel
translation itself improves throughput.

After adding relay-integrity gameplay and the damaged relay asset, a later
five-trial moving GPU run averaged about 113 commands per frame. Median p95 was
3,291 us and median p99 was 4,630 us. Four windows had no 60 Hz misses; one
window had one 20,175 us outlier, for one over-budget frame in 1,200. The result
supports near-sustained 60 Hz with one observed hitch, not a zero-stutter claim.

## Native Default Font and Window MSAA Parity

The implicit 12 px font now uses an immutable atlas exported by native LOVE
11.5 from its bundled Vera.ttf through `newTrueTypeRasterizer(12, "normal", 1)`.
The atlas stores native glyph coverage, bearings, advances, and kerning pairs;
other sizes, hinting modes, DPI scales, and user fonts retain the portable
rasterizer. Disabling `LOVE_NATIVE_DEFAULT_FONT_ATLAS` is the strict reverse
control. In the default-font crop, native-versus-Canvas RMSE improved from
`0.0895696` to `0.0498241` (-44.4%); GPU produced the same improvement.

The same probe then exposed forced 4x GPU MSAA as a separate semantic error.
Neither probe nor Neon Relay requests MSAA, so native LOVE uses one sample.
`LoveWindowMetricsAwareRenderBackend` now forwards effective `love.conf`,
`setMode`, and `updateMode` metrics through direct and side-by-side backends.
The GPU surface pool changes sample count only when `metrics.msaa > 1`, while
`LOVE2D_GPU_MSAA=false` remains the hard capability rollback. Live diagnostics
confirmed one sample for the default mode and four for an explicit
`t.window.msaa = 4` mode.

At exact 800x600 presentation, native-versus-GPU full-frame RMSE improved from
`0.0403479` to `0.0337934` (-16.2%). The half-pixel rough grid improved from
`0.0142244` to `0.000651704`. The remaining mixed-stroke error is concentrated
in smooth lines and odd-width diagonal rough-line rasterization, which need
style-specific treatment rather than global multisampling.

Five 240-frame lua-bytecode GPU walking/boss windows compared the old forced
4x surface with the retained LOVE-default single-sample surface at the same
approximately 113 commands per frame:

| Metric | Forced 4x MSAA | LOVE msaa=0 | Change |
| --- | ---: | ---: | ---: |
| Median p95 CPU frame | 3,287 us | 2,004 us | -39.0% |
| Median p99 CPU frame | 3,938 us | 3,038 us | -22.9% |
| Maximum CPU frame | 6,999 us | 4,790 us | -31.6% |
| Frames over 120 Hz | 0 / 1,200 | 0 / 1,200 | unchanged |
| Frames over 60 Hz | 0 / 1,200 | 0 / 1,200 | unchanged |

This is a credited performance win because the work removes multisample and
resolve work that the LOVE program never requested, while also moving output
toward the native reference.

## Native Rough-Line Shader Rasterization

Single-sample odd-width rough diagonals need pixel occupancy rather than an
antialiased triangle to match native LÖVE. The retained
`GpuRoughLineShaderGeometry` submits one conservative quad and a dedicated
fragment shader applies native-style pixel occupancy with the upper/left tie
break at exact boundaries. It is limited to genuinely sloped two-point lines
with integral device-space endpoints, odd integral widths, and pure
translation. Axis-aligned, even-width, smooth, fractional, transformed, and
polyline strokes retain the established paths.

At exact 800x600 presentation, the sloped-only shader reduced
native-versus-GPU full-frame probe RMSE from `0.0337934` to `0.0238141`
(-29.5%). Width-1 and width-3 diagonal regions improved from `0.183698` to
`0.00113206` and from `0.150505` to `0.00151882`, respectively. Even-width and
smooth controls were unchanged. Keeping axis-aligned lines on the existing
path avoids paying a special-pipeline cost for the arena's roughly 30 grid
lines per frame.

The first per-pixel implementation regressed the Neon Relay five-trial median
p95 CPU frame time from a matched rollback's `1,826 us` to `3,179 us`.
Analytical run generation plus a 16-run fallback reduced that to `2,647 us`,
but still did not meet the no-regression gate. That CPU rasterizer remains an
opt-in diagnostic under `LOVE2D_GPU_ROUGH_LINE_RASTERIZATION=true`.

The single-quad shader passed the throughput gate in a same-process,
interleaved off/on comparison: two sequences of three 240-frame
lua-bytecode walking windows per state, with normal `luaCompatible` GC and
about 112 rendered commands per frame.

| Metric | Shader off | Shader on | Change |
| --- | ---: | ---: | ---: |
| Median p95 CPU frame | 2,131 us | 1,784 us | -16.3% |
| Median p99 CPU frame | 2,753 us | 2,602.5 us | -5.5% |
| Median maximum CPU frame | 4,162 us | 3,612 us | -13.2% |
| Frames over 120 Hz | 0 / 1,440 | 0 / 1,440 | unchanged |
| Frames over 60 Hz | 0 / 1,440 | 0 / 1,440 | unchanged |

The shader is therefore enabled by default. `LOVE2D_GPU_ROUGH_LINE_SHADER=false`
is the compile-time rollback. Diagnostic builds can enable
`LOVE2D_GPU_RUNTIME_ROUGH_LINE_SHADER_TUNING=true` and use
`love2d.setRoughLineShader` or benchmark option `--rough-line-shader` for a
same-process reverse control.

## Formatted Atlas Text and Async Host Calls

The default-font atlas originally handled only unwrapped left-aligned `print`
commands. `printf` and formatted `Text` entries fell back to Flutter text
layout, even when every glyph was present in the native LOVE atlas. In the
pixel-corner probe, the three `printf` commands accounted for 57.4% of the
remaining squared native-versus-GPU error.

`GpuTextHandler` now wraps colored codepoints using LOVE font advances and
kerning, supports left/center/right placement, and floors odd centered spare
widths like native LOVE. Justified rows, missing glyphs, and configured
fallback fonts retain the Canvas fallback. Adjacent commands sharing an atlas
and draw state are copied into one reusable ordered vertex stream, preserving
interleaved shape ordering without one GPU draw per text command.

The original pixel-corner probe improved as follows at exact 800x600:

| Metric | Before formatted atlas | Direct formatted atlas | Change |
| --- | ---: | ---: | ---: |
| Full-frame native-vs-GPU RMSE | 0.0238141 | 0.0155506 | -34.7% |
| `printf` crop RMSE | 0.0844382 | 0.00032761 | -99.6% |
| Hybrid fallback commands | 3 | 0 | eliminated |

The checked-in `assets/formatted_text_probe` expands the control to actual
word wrapping, all three retained alignments, colored spans, explicit
newlines, and `Text:setf`. The compile-time rollback
`LOVE2D_GPU_FORMATTED_ATLAS_TEXT=false` produced native-vs-GPU RMSE `0.100142`;
the retained batched path measured `0.0037242` (-96.3%) with all 29 commands
direct and no hybrid fallback. Canvas measured `0.105405` against native.

The first unbatched direct path exposed a real p95 cost, so it was not retained
unchanged. Five 240-frame profile windows on the static 29-command probe
compared the 12-command Canvas rollback with the final adjacent-command batch:

| Metric | Canvas fallback | Batched direct atlas | Change |
| --- | ---: | ---: | ---: |
| Median p95 CPU frame | 1,106 us | 995 us | -10.0% |
| Median p99 CPU frame | 2,285 us | 2,056 us | -10.0% |
| Median maximum CPU frame | 2,543 us | 2,350 us | -7.6% |
| Frames over 120 Hz | 0 / 1,200 | 0 / 1,200 | unchanged |
| Frames over 60 Hz | 0 / 1,200 | 0 / 1,200 | unchanged |

Building the expanded probe also exposed a lua-bytecode correctness defect:
an inline unmanaged host builtin returning a `Future` was normalized before it
was awaited whenever no GC cycle was active. Nested calls such as
`love.graphics.newText(love.graphics.getFont())` therefore received a raw Dart
future. Both inline invocation paths now await first and normalize second. A
focused bytecode regression covers an asynchronous leaf call used directly as
an outer call argument.

## Native Smooth-Line Alpha Overdraw

The remaining pixel-corner probe error was concentrated in two width-1 smooth
lines. The old GPU path submitted the same opaque triangle geometry as a rough
line, producing one fully covered row. Native LOVE instead reduces the opaque
half-width by `0.3` physical pixels and appends a one-pixel alternating-alpha
triangle strip around both sides and both open caps. This behavior is visible
in the official
[LOVE 11.5 Polyline implementation](https://github.com/love2d/love/blob/11.5/src/modules/graphics/Polyline.cpp).

`GpuSmoothLineTessellator` converts that strip to a 30-vertex triangle list in
one reusable `Float32List`. The ordinary unlit pipeline already multiplies its
uniform tint by per-vertex color, so the path needs no new shader, pipeline, or
per-frame geometry allocation. It is deliberately limited to single-sample,
two-point, pure-translation smooth lines with miter or bevel joins. The command
stream does not preserve LOVE's separate physical-pixel scale stack, so scaled,
sheared, perspective, multisampled, `none`-join, and polyline cases keep the
established fallback until that scale is represented explicitly. Set
`LOVE2D_GPU_SMOOTH_LINE_OVERDRAW=false` for the exact compile-time rollback.

The deterministic 800x600 `assets/parity_probe` capture measured:

| Region | Rollback | Smooth overdraw | Change |
| --- | ---: | ---: | ---: |
| Full-frame native-vs-GPU RMSE | 0.0151037 | 0.00346269 | -77.1% |
| Complete smooth-line band | 0.0767807 | 0.00088647 | -98.8% |
| Integer-position smooth line | 0.129311 | 0.00134649 | -99.0% |
| Half-pixel smooth line | 0.0484924 | 0.000777799 | -98.4% |

At representative line centers, every native and GPU channel differed by at
most one 8-bit level. A visually inspected native/GPU pair showed no remaining
edge-shape difference at normal scale.

Three profile legs of five 240-frame windows used the static 76-command probe
in ON-OFF-ON order. The first ON leg measured median p95/p99 CPU frame times of
1,530/2,130 microseconds, OFF measured 1,764/2,307 microseconds, and the reverse
ON leg measured 1,109/1,664 microseconds. The spread between the two ON legs is
larger than the candidate's plausible cost, so do not credit a throughput win.
All 3,600 frames stayed below both the 120 Hz and 60 Hz CPU budgets, which
establishes the retained no-budget-regression claim for this probe.

## Exact Axis-Aligned Rough Runs

After smooth overdraw, the largest isolated stroke mismatch came from open
caps on horizontal odd-width rough lines. The translated triangle path covered
`x=39..358` for a line authored from `x=40` to `x=360`; native LOVE covered
`x=40..359`. The existing allocation-free rough-run generator already emits
that exact half-open rectangle with one quad, so eligible axis-aligned
two-point lines now use it unconditionally. Sloped CPU run generation remains
diagnostic, and the dedicated sloped rough-line shader is unchanged.

At exact 800x600 presentation this reduced full-frame native-vs-GPU RMSE from
`0.00346269` to `0.00065357` (-81.1%). The complete rough-stroke band improved
from `0.00714749` to `0.000876077` (-87.7%); width-1 and width-3 horizontal
regions improved from `0.0133419`/`0.0217897` to
`0.00103208`/`0.00157653`. Set `LOVE2D_GPU_ROUGH_AXIS_RUNS=false` for the exact
triangle-path rollback.

The retained timing gate alternated seven fallback/exact pairs inside one
profile-mode luaBytecode process while the player walked right through the
normal Neon Relay arena. Every 240-frame window rendered the same average 93
commands at exact 800x600 presentation. The median paired p95 CPU-frame delta
was `-197` microseconds and the median paired p99 delta was `-63` microseconds.
Unpaired medians were 2,145/2,727 microseconds for translated triangles and
1,581/2,738 microseconds for exact runs, illustrating why the paired deltas are
the defensible attribution. All 3,360 measured frames stayed below both the
120 Hz and 60 Hz CPU budgets.

Build with `LOVE2D_GPU_RUNTIME_ROUGH_AXIS_RUN_TUNING=true` to retain both paths
and expose `love2d.setRoughAxisRuns` through Marionette and the VM service. The
`benchmark_rough_axis_runs_ab.sh` helper reverses order on each pair, pins
input/presentation, rejects workloads below 70 commands, and writes the raw
windows plus a paired summary. Ordinary builds compile the runtime switch out.

## Clean Full-Game Regional Gate

The compositor-decoration gate was re-applied to the deterministic Neon Relay
`v` state using the same `assets/main.lua`, twelve indexed art assets, pointer
`(640,360)`, and 800x600 surface in native LOVE 11.5 and lualike luaBytecode.
The frozen frame contained 118 LOVE commands. Native-vs-GPU normalized RMSE
was `0.0289183`, versus `0.0472107` for native-vs-Canvas and `0.0457932` for
Canvas-vs-GPU. Visual inspection confirmed matching simulation and placement;
remaining error is concentrated in strongly minified generated art.

The checked-in `assets/neon_relay_regions.json` manifest and
`score_renderer_regions.sh` now make that attribution repeatable. They reject
wrong-sized captures, duplicate names, non-integral or out-of-bounds regions,
and produce all three pairwise RMSE values for each crop. On the retained GPU
capture, native-vs-GPU RMSE was `0.00803341` in the HUD, `0.0468812` around the
sentinel, `0.0384519` around the relay, `0.0534523` around the player, and only
`0.001362` in an unobstructed arena crop. The parity probe has its own region
manifest covering integer/half-pixel grids, rough and smooth bands, and text.

A clean full-game reverse capture with
`LOVE2D_GPU_MIPMAP_LOD_COMPENSATION=0` worsened native-vs-GPU RMSE to
`0.0302040` (+4.4%). It also worsened the sentinel from `0.0468812` to
`0.0553453` and the player from `0.0534523` to `0.0602168`, although the relay
crop improved. This confirms the retained `-0.5` bias is still the better
whole-scene compromise; no sampling change is retained from this trial.

## Source-Identical Minified Texture Probe

`assets/texture_probe.lua` removes simulation and command-placement variables.
Native LOVE and lualike load the same two PNG files and the same Lua source,
then draw each texture at `0.074x` on integer coordinates and `0.145x` with a
rotation and half-pixel translation. The second row repeats the four draws
through static SpriteBatches. The region manifest scores every panel
independently.

With the retained LOVE-authored mip uploads and `-0.5` LOD compensation,
native-vs-GPU normalized RMSE was `0.0237529`, versus `0.0622818` for
native-vs-Canvas. The mean native-vs-GPU score was `0.0340018` for direct draws
and `0.0339974` for SpriteBatches. Every corresponding direct/batched panel was
within `0.00001`, ruling out batch geometry and state as the remaining source.
The mean integer-small score was `0.0334947`; the rotated-half-pixel score was
`0.0345045`, so the residual is not primarily transform placement either.

A base-level-only reverse build with `LOVE2D_GPU_MIPMAP_UPLOADS=false` worsened
the full-frame native-vs-GPU score to `0.0383498` (+61.5%). It made all eight
sprite regions worse and visually approached the Canvas result. The authored
mip upload remains enabled. This attributed the remaining texture error to mip
texel generation or driver sampling details, not the direct versus SpriteBatch
command paths.

The established CPU generator divided odd dimensions into uneven two- and
three-pixel area buckets. A GPU half-size blit instead samples centered
normalized coordinates across the complete source extent. The retained
`LoveImageData.generateMipmaps` path now performs that centered linear
downsample directly over RGBA bytes. Even-sized levels are byte-identical to
the previous 2x2 averages; odd-sized levels receive the corrected footprint.
Use `LOVE2D_CENTERED_LINEAR_MIPMAPS=false` for the exact rollback.

On the source-identical probe, centered generation reduced full-frame
native-vs-GPU RMSE from `0.0237529` to `0.0131528` (-44.6%). All eight sprite
regions improved: the four direct regions moved from `0.0320909`-`0.0351315`
to `0.0171656`-`0.0199296`, and their SpriteBatch counterparts remained within
`0.00001`. The frozen full Neon Relay scene improved from `0.0289183` to
`0.0229156` (-20.8%). Sentinel, relay, and player regions improved to
`0.0355065`, `0.0359292`, and `0.0383078`; the already-clean HUD and arena
controls moved slightly from `0.00803341`/`0.001362` to
`0.00809815`/`0.00174352`, so the retention decision is based on the strong
whole-scene and sprite improvement rather than universal per-crop movement.

An interleaved nine-pair Flutter benchmark generated complete chains for two
game-sized synthetic images totaling 3,144,646 source pixels. Centered direct
byte generation measured median/p95 `114,078`/`132,453` microseconds versus
`295,641`/`316,898` for the package-image area path, a 61.4% median reduction.
Mip generation occurs at asset load rather than per frame, but this removes a
substantial startup CPU and temporary-object cost while improving native
parity. Reproduce it with
`flutter test benchmark/image_mipmap_generation_test.dart` from `pkgs/love2d`.

The `-0.5` flutter_gpu LOD compensation predated centered mip generation, so it
was re-swept after retaining the new chain. On the source-identical probe,
`-0.25` reduced full-frame native-vs-GPU RMSE to `0.00662481`; zero additional
compensation reduced it further to `0.000955786`. All eight direct and
SpriteBatch crops landed between `0.000885689` and `0.001306`, while paired
direct/batched scores remained effectively identical. The complete frozen Neon
Relay scene also improved from `0.0229156` to `0.0194433`: sentinel, relay, and
player regions moved to `0.0290666`, `0.0299096`, and `0.0270671`, with control
regions unchanged or better. The default now applies only LOVE's own
`-mipmapSharpness`; use `LOVE2D_GPU_MIPMAP_LOD_COMPENSATION=-0.5` to reproduce
the obsolete pre-centered compensation.

## Source-Identical Composition Probe

`assets/composition_probe.lua` separates opaque sprites, alpha-only sprites,
RGB tint plus alpha, translucent fills, repeated overlap, rough strokes, and
player/sentinel-style layered compositions into independently scored regions.
The first exact 800x600 capture ruled out texture modulation and ordinary alpha
blending: opaque, alpha-only, and tinted-alpha regions all measured about
`0.0011` native-vs-GPU normalized RMSE. The dominant residual was generated
stroke geometry. The combined player and sentinel layers measured `0.0274494`
and `0.0183625` before the shape correction.

LOVE 11.5 computes a default ellipse point count as
`floor(sqrt(meanRadius * 20 * transformScale))`, with a minimum of eight. Arc
counts multiply that complete-circle count by the sweep fraction and round to
the nearest integer. The retained GPU path now mirrors those rules, derives
the transform scale from the command matrix, and caches at most 128 unit-circle
tables. This replaces the fixed 48-point circle and custom chord-error arc
rules, so ordinary game shapes upload fewer vertices while occupying the same
single-sample edge pixels as native LOVE.

On the composition probe, full-frame native-vs-GPU RMSE improved from
`0.0248119` to `0.0221755` (-10.6%). Filled primitives improved from
`0.00929219` to `0.0027384`, repeated overlap from `0.00735923` to
`0.00241475`, player layers from `0.0274494` to `0.000635782` (-97.7%), and
sentinel layers from `0.0183625` to `0.00121246` (-93.4%). The complete frozen
Neon Relay frame improved from `0.0194433` to `0.00908778` (-53.3%), or 68.6%
relative to the original `0.0289183` full-game baseline. Relay and player
regions reached `0.00291509` and `0.00203246`; the unobstructed arena control
remained `0.00174352`.

The remaining odd-width sloped rough-line mismatch came from modeling the
stroke as a fixed minor-axis pixel band. LOVE actually submits a perpendicular
Euclidean sleeve around the segment. The retained constant-size rough-line
shader now tests pixel centers against that sleeve and its half-open caps. The
composition probe's combined line/arc region improved from `0.0277468` to
`0.000794973` (-97.1%), and full-probe RMSE improved from `0.0221755` to
`0.0210798`. Opaque, alpha, fill, overlap, and layered controls were unchanged.
The frozen Neon Relay scene was byte-for-byte stable at the scorer level
(`0.00908778`) because that state contains no eligible odd-width sloped
two-point line; the dedicated probe supplies the affected contract.

A five-window profile-mode walking gate then measured 1,200 lua-bytecode GPU
frames at exact 800x600 presentation and a stable average of 93 commands.
Median p95/p99 CPU-frame time was `1,722`/`2,483` microseconds, the maximum was
`2,938` microseconds, and no frame exceeded either the 120 Hz or 60 Hz CPU
budget. This establishes no frame-budget regression; because there was no
interleaved legacy/current switch in that process, it is not presented as an
isolated throughput delta. The renderer suite passed 43/43, and the compiled
standalone runner passed 30/30 AST, 30/30 IR, and 30/30 lua-bytecode cases.

## Current Linux Impeller Parity Boundary

The Linux evidence lanes have different authorities:

1. Native LOVE running the same project is the visual contract.
2. `LoveCanvasRenderBackend` without Impeller is the supported Flutter/Linux
   control. Launch the demo with `--no-enable-impeller` and
   `LOVE2D_DEMO_FORCE_CANVAS=true`; render state must report that GPU
   initialization is disabled.
3. `love2d_gpu` on Linux Impeller is an experimental semantics, ownership, and
   frame-tail lane. It is not a byte-identical raster authority.

This distinction is also supported upstream. Flutter has an open Linux
Impeller vector anti-aliasing defect
([flutter/flutter#191171](https://github.com/flutter/flutter/issues/191171)),
while its Vulkan desktop backend is still tracked as design and implementation
work
([flutter/flutter#183495](https://github.com/flutter/flutter/issues/183495)).
The profile run used for the lifetime gate identified its backend as
`Impeller (OpenGLESSDF)` and emitted a startup framebuffer-size timeout. Keep
those presentation/backend symptoms out of Lualike VM throughput conclusions.

`tool/capture_renderer_parity.sh --canvas-only` now enforces the second lane:
it rejects a process unless diagnostics report
`gpuInitializationDisabled=true`, `gpuAvailable=false`, and `mode=canvas`.
It runs the same parity-freeze source through native LOVE and the selected
Flutter Canvas process, captures both at exact 800x600, and writes `null` GPU
metrics instead of inventing a comparison. The named-region scorer accepts an
optional GPU image, so the same manifest works for both two- and three-lane
captures.

The verified non-Impeller frozen Neon Relay capture measured `0.0199939`
native-to-Canvas full-frame RMSE. Named regions measured `0.00727115` for the
HUD, `0.00806046` for the bottom HUD, `0.00627032` for the unobstructed arena,
`0.028679` for the sentinel, and `0.0343163` for the player. The amplified
difference is concentrated on filtered sprite edges. This is worse than the
matched Canvas-under-Impeller full-frame value (`0.0128832`) and direct GPU
value (`0.00892302`), so the non-Impeller lane is an attribution and support
control—not evidence that changing host renderer improves native parity.

After the command-level fixes above, the exact 800x600 frozen Neon Relay frame
measured `0.00892302` native-versus-GPU RMSE. An amplified residual map made
small periodic differences around the enemy readout circles visible, but the
source-identical static curve probe measured only `0.000441128` full-frame
native-versus-GPU RMSE. Its six width-specific circle and arc crops ranged from
`0.000330961` through `0.000621886`. The earlier source-identical texture and
composition controls likewise put isolated GPU paths close to native LOVE.

That evidence does not reproduce the full-game residual as a command encoding,
tessellation, texture, or blend-state defect under our control. Treat the
remaining Linux result as an Impeller/OpenGL raster-compositing boundary unless
a reduced source-identical probe reproduces a larger mismatch. Do not retain
full-scene GPU tweaks that merely move this residual: require an isolated probe
that attributes the error, improves native parity, and preserves the paired
frame-tail gate. Canvas remains useful as an independent semantic control, not
as proof that Linux Impeller can produce byte-identical native LOVE pixels.

## Renderer Switching and Asset Lifetime

Renderer mode must not be encoded in the `LoveFlameHarness` widget key. Doing
so recreates the complete LOVE runtime whenever automation switches between
Canvas, GPU, and comparison modes. In the Neon Relay demo, the singleton GPU
texture cache then retained identities from each discarded runtime: after
several comparisons a forced Dart GC still found 96 `LoveImage` objects and
621,154,352 bytes of `_Uint8List` data in a 646,968,208-byte Dart heap.

The demo now keeps one harness and calls `LoveFlameHarnessGame.setRenderBackend`
when presentation mode changes. Input coordinate transforms are updated on the
existing adapters at the same boundary. After eight Canvas/GPU/comparison
cycles, a forced Dart GC retained 25 `LoveImage` objects and 161,599,936 bytes
of `_Uint8List` data in a 189,956,880-byte heap. That is a 70.6% heap reduction
and a 74.0% reduction in retained image bytes and image objects. A fresh native,
Canvas, and GPU capture remained at the established `0.0128832` native-Canvas
and `0.00892302` native-GPU RMSE, so the ownership change did not alter output.

A five-window lua-bytecode GPU walking gate at exact 800x600 presentation then
measured median p95/p99 CPU-frame times of 2,158/2,441 microseconds and a median
maximum of 2,958 microseconds. Lua update p95 was 53 microseconds, and no frame
exceeded the 120 Hz or 60 Hz CPU budget. These timings are a non-regression
gate, not evidence of a throughput gain: they were not paired against the old
lifetime model in one process, and Linux Impeller timing varies between runs.

The single-runtime demo fix exposed a deeper production lifetime problem when
the old recreate-on-switch behavior was restored diagnostically. VM retaining
paths identified two independent process-global owners. The GPU texture cache
used strong identity maps for `LoveImage`, `LoveImageData`, and `ui.Image`.
Separately, the default-font support used strong maps keyed by
`LoveRuntimeContext`. The latter retained each discarded host and game; those
contexts retained their draw surfaces and image mip chains. After 25 runtime
generations, forced Dart GC still reported 25 contexts, 25 hosts, 25 games, 553
`LoveImage` objects, and 3,635,312,976 bytes of `_Uint8List` data in a
3,667,533,776-byte heap.

Both caches now use weak identity associations. Live source objects still find
their uploaded GPU texture, and live runtime contexts still find their default
font prototypes and in-flight loaders, but neither cache makes its key a
process root. With the diagnostic recreation mode enabled, 13 complete runtime
generations followed by forced GC retained exactly one runtime context, host,
game, and bytecode runtime: 25 `LoveImage` objects and 161,598,672 bytes of
`_Uint8List` data in a 184,834,096-byte heap. Use
`LOVE2D_DEMO_RECREATE_HARNESS_ON_MODE_SWITCH=true` to reproduce this ownership
stress test; ordinary comparison still keeps one harness and avoids the reload
cost entirely.

The checked-in `tool/profile_renderer_lifetime.sh` was then replayed end to end
against the profile bytecode app. Four complete Canvas/GPU/comparison runtime
generations rendered 93 commands each. After two forced Dart collections, the
gate retained one `LuaBytecodeRuntime`, context, host, and game, 25
`LoveImage` objects, and 185,473,376 heap bytes. It passed explicit ceilings of
250,000,000 heap bytes and 32 images. This is the automated regression proof;
the longer 13-generation capture above remains the stress-test evidence.

The weak-owner build preserved every frozen Neon Relay score: full-frame
native-GPU RMSE remained `0.00892302`, native-Canvas remained `0.0128832`, and
all named region scores were unchanged. A five-window lua-bytecode GPU walking
gate measured median p95/p99/max CPU-frame times of 1,227/1,391/1,484
microseconds and update p95 of 45 microseconds, with no 120 Hz or 60 Hz CPU
budget misses. This rejects a weak-lookup regression; because it was not an
interleaved strong-map/weak-map A/B in one process, do not present the lower
absolute times as an isolated throughput gain.
