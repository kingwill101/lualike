# LuaLike Runtime Performance Analysis

## Overview

The bytecode VM dispatch loop has been optimized through several rounds
targeting call dispatch, frame setup, GC root management, and debug-only
overhead. The AST runtime is also measured against a real LOVE update/render
loop so lower-level engines and allocation changes are retained only when they
improve the game workload.

## Relic Breach profile-mode gate (2026-08-26)

> **Historical timing correction (2026-08-28):** these update values were
> captured before the harness timed the awaited LOVE runtime frame. They
> measure synchronous dispatch into an asynchronous controller and therefore
> cannot establish Lualike VM throughput or a percentage speedup. The stable
> workload, command-count, input, and visual-parity evidence remains useful.
> New runtime decisions must use awaited update/runtime-frame timing or a pure
> standalone kernel.

The Flutter GPU demo runs the vendored Relic Breach `main.lua` and asset tree
through `LoveLualikeFilesystemAdapter`. Every trial below used:

- the same AST/IR/bytecode source and 142-command game state;
- GPU-only rendering with 4x MSAA and zero software fallbacks;
- a reset before each trial, logical pointer at `(640, 360)`, and `d` held;
- five 240-frame profile-mode windows after a one-second warmup.

The table is retained as historical experiment provenance, not as the current
Lualike performance gate.

| Runtime candidate | p95 update trials (us) | Median | Decision |
|---|---:|---:|---|
| AST baseline at `aacba341` | 34, 30, 33, 30, 27 | 30 | Reference |
| Direct private call-stack scan | 38, 38, 37, 39, 44 | 38 | Reverted |
| AST debug-hook no-op gate | 27, 27, 24, 35, 25 | 27 | Retained |
| IR engine | 29, 33, 36, 39, 42 | 36 | Experimental only |
| Lua bytecode engine | 44, 48, 51, 54, 54 | 51 | Experimental only |

The retained AST change avoids constructing call/return transfer metadata and
awaiting hook dispatch when `debug.sethook` is not installed. Focused
debug-hook, coroutine, tail-call, and ordinary-function tests still exercise
the active-hook path. The old table does not prove its frame-time effect; the
change remains because it removes inactive work and preserves correctness.

The deterministic harness also sets LOVE's logical pointer explicitly. Before
that control existed, host cursor position changed aim direction and produced
different command counts between otherwise identical trials.

### Visual parity evidence

The installed LOVE CLI and Flutter comparison mode were captured from the same
Relic Breach source. Canvas and Flutter GPU displayed the same room, player
pose, HUD, water animation phase, and lighting state. The synchronized panes
were not pixel-identical: an ImageMagick pane comparison measured normalized
RMSE `0.0345064`, concentrated on anti-aliased edges and text. That difference
is a renderer-parity target, not a reason to weaken the game workload.

## Benchmark results (AOT compiled, system normal load)

### call_stress (20K calls × 3 functions + deep(200))

| Metric | Before optimizations | Current | Improvement |
|--------|---------------------|---------|-------------|
| Total wall | ~2s (under load) | ~330ms | ~6x |
| CALL overhead | 35.7us/call | ~5.5us/call | ~6.5x |

### loop_stress (1M iterations × 6 nested loops)

| Metric | Before optimizations | Current | Improvement |
|--------|---------------------|---------|-------------|
| Total wall | ~2.4s (under load) | ~930ms | ~2.6x |

## Optimizations applied

### Session 1: Profile state + bytecode fast path + frame close

1. **Profile state caching**: Cache `_activeProfile` outside the dispatch loop
   (immutable during frame execution). Saves a field read + null check per
   instruction on the non-profiled path.
2. **Bytecode-to-bytecode fast path**: Early detection of `LuaBytecodeClosure`
   in `_invokeValueWithName` skips tail-call flattening, builtin checks,
   debug-local handling, and `args.cast<Value>()` for direct calls.
   **15% faster call_stress** (35.7us → 30.3us per call).
3. **Synchronous frame close**: Added `_closeFrameForCoroutineSync` that handles
   the common case (no to-be-closed registers, no open upvalues) synchronously
   without creating an async continuation. Used in RETURN opcodes and `_runFrame`
   finally block.
4. **Skip state restoration**: Skip env/scriptPath/callStack restoration in
   `_runFrame` finally block on the happy path when no debug hook is active.
5. **Cache env var checks**: Cache `LUALIKE_DEBUG_BYTECODE_HOOKS` as top-level
   final instead of calling `getEnvironmentVariable()` per frame.

### Session 2: GC root management + call frame state

6. **Throttle `_pruneDeadCoroutineRefs`**: Only prune dead coroutine weak
   references every 256 calls to `getMainThread()` (was called every bytecode
   instruction, iterating over all active coroutine weak refs).
7. **Fast `popExternalGcRoots`**: Use `removeLast()` when the pop matches the
   last pushed element (always true for LIFO frame lifecycle) instead of always
   calling `List.remove()` which does an O(n) linear scan.
8. **Remove redundant Expando**: `bindBytecodeCallFrame` was storing the
   bytecode frame in both an Expando (identity-hash lookup) and
   `CallFrame.engineFrameState` field. Now only sets the field — all readers
   read `engineFrameState` directly.

### Cached prototype-level metadata (earlier commits)

9. **Cached closure call wrappers**: `LuaBytecodeClosure.callableValue` reuses
   the same wrapper instead of rebuilding bytecode-entry `Value` objects.
10. **Prototype-scoped frame metadata**: `_localExpiryFlags`,
   `_expiredRegisterCandidatesByPc`, `_trackedRegisterWriteFlags`,
   `_visibleNamedLocalsByPc` are cached per prototype via `Expando`.
11. **Raw-payload-keyed GC queues**: `_queuedToMark`, `_toBeFinalized`,
    `_alreadyFinalized` key off the underlying raw payload via `_gcIdentityKey`,
    avoiding `Value.hashCode` / `Value.==` on every GC churn cycle.

## Key profiling results

### Top self frames (call_stress, current)

| Method | Self% | Notes |
|--------|-------|-------|
| Native/unknown | ~86% | IO/waiting |
| `_executeFrame` | ~3.3% | Dispatch loop itself |
| `LuaBytecodeFrame.register` | ~1.0% | Register access (inlined) |
| `Value.transientPrimitive` | ~0.9% | Primitive value creation |
| `instructionWritesRegister` | ~0.8% | Register write tracking (debug) |
| `Interpreter.setCurrentEnv` | ~0.6% | Environment setting per frame |
| `_runFrame` | ~0.4% | Frame setup overhead |
| `invoke` | ~0.3% | Call dispatch |
| `_callSiteNameInfo` | ~0.2% | Call name resolution (debug) |

### Key improvements vs earlier profiles

| Hotspot | Before (self) | After (self) | Notes |
|---------|---------------|--------------|-------|
| `Interpreter.getMainThread` | 189 | not visible | Throttled `_pruneDeadCoroutineRefs` |
| `Interpreter.popExternalGcRoots` | 193 | not visible | Fast `removeLast()` |
| `bindBytecodeCallFrame` | 68 | not visible | Removed Expando lookup |

## GC status

GC is NOT the bottleneck. All 62 major collections in gc.lua take <1ms each.
Total GC time <5ms across the full test.

## Items tried and reverted

- **CallFrame pooling**: The list manipulation overhead exceeded allocation savings.
- **`identical()` env fast path**: Environments aren't identical even for same-module calls.
- **`assignTransientRaw` for FORLOOP**: In-place mutation breaks closures capturing loop variables.
- **`CallStack popRecycled()`**: Reusing popped CallFrame entries made things worse.
- **Skipping `_callSiteNameInfo` for non-debug calls**: `debug.getinfo` needs the resolved
  call name even without active debug hooks (assertions fail otherwise).

## How to profile

Run the focused bytecode tests first:

```bash
cd pkgs/lualike
./test_runner --lua-bytecode --test=calls.lua,sort.lua
./test_runner --lua-bytecode --test=constructs.lua,locals.lua,db.lua
```

Capture a CPU profile for a stress script:

```bash
devtools-profiler run \
  --cwd <repo-root> \
  --artifact-dir <out-dir> \
  -- dart run pkgs/lualike/bin/main.dart --lua-bytecode pkgs/lualike/bench/call_stress.lua
```

Then inspect the saved session:

```bash
devtools-profiler summarize <out-dir>/overall/summary.json
devtools-profiler inspect --method LuaBytecodeVmCallEntry.invoke <session-dir>
devtools-profiler explain <session-dir>
```

For GC work, swap in `pkgs/lualike/luascripts/test/gc.lua` or another GC-heavy script.
If the full `gc.lua` harness is noisy, a short `-e` churn loop that ages tables,
mutates a field in place, and calls `collectgarbage("step")` is a useful proxy.

## How to read the results

- **Top self frames** = direct CPU cost; these are the best optimization targets.
- **Top total frames** = who is paying for a cost; useful for tracing call chains.
- If a method has **high self%**, it is usually the actual bottleneck.
- If a method has **low self% but high total%**, it is mostly orchestration.
- If `unknown` dominates, the workload is mostly outside Dart frames or is blocked in native/runtime work.
- For regression hunting, compare the newest session with the previous one and look for methods whose self% or total% jumped.

## Current bottlenecks and next steps

After the current round of optimizations, the remaining hot spots are:

1. **Dispatch loop overhead** (~3.3% self): Fundamental — each instruction reads
   opcode, dispatches to handler, advances PC.
2. **Register access** (~1% self): `slotValue()` bounds check + array load per
   register read. Already inlined.
3. **Primitive value creation** (~0.9% self): `transientPrimitiveValue` called
   on every register write. Required for FORLOOP correctness.
4. **Register write tracking** (~0.8% self): `instructionWritesRegister` used
   by `_callSiteNameInfo` for debug name resolution.
5. **Frame setup** (~0.4% self): Environment setting, call stack push, GC root
   push per frame.

The remaining overhead is spread across many small operations, each contributing
<1% of total time. Further micro-optimizations may not yield significant wins.
