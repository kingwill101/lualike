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

## Establish A Repeatable Repro

Pick one action that clearly reproduces the slowdown:

- idle render
- mouse movement over the window
- resize
- text-heavy interaction
- scene change

For this project, cursor motion is currently a useful repro because it pushes
the frame rate down hard enough to show up in both the app and the profiler.

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
