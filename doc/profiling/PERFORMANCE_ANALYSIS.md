# LuaLike Bytecode VM Performance Analysis

## Overview

The bytecode VM dispatch loop has been optimized for hot paths.
`loop_stress` bench: **3.48s → 2.60s (25% faster)**.
All 30/30 tests pass on AST, IR, and lua-bytecode engines.

## Recent optimizations (this session)

1. **Profile state caching**: Cache `_activeProfile` outside the dispatch loop
   (immutable during frame execution). Saves a field read + null check per
   instruction on the non-profiled path.
2. **FORLOOP closure safety**: Verified that in-place mutation of loop variable
   registers breaks closures that capture the loop variable. The allocation
   path (`transientPrimitiveValue`) is necessary for correctness.
3. **Bytecode-to-bytecode fast path**: Early detection of `LuaBytecodeClosure`
   in `_invokeValueWithName` skips tail-call flattening, builtin checks,
   debug-local handling, and `args.cast<Value>()` for direct calls.
4. **Skip state restoration**: Skip env/scriptPath/callStack restoration in
   `_runFrame` finally block on the happy path when no debug hook is active.
5. **Cache env var checks**: Cache `LUALIKE_DEBUG_BYTECODE_HOOKS` as top-level
   final instead of calling `getEnvironmentVariable()` per frame.

## Key profiling results

### loop_stress bench (1M iterations × 6 nested loops)

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Total wall | 3.48s | 2.60s | 25% |
| FORLOOP/iter | 478us | 332us | 31% |
| MOVE/op | 7.1us | 4.7us | 34% |
| ADD/op | 27us | 20us | 26% |

### call_stress bench (20K calls × 3 functions)

| Metric | Value |
|--------|-------|
| Total wall | 2.31s |
| CALL overhead | 35.7us/call (75% of time) |
| RETURN overhead | 3.4us/return |

### Per-instruction dispatch overhead

The VM dispatch loop adds ~4-5us per instruction from:
- `frame.expireDeadLocals()` — fast path (flag check)
- `_syncCurrentCoroutine()` — coroutine active check
- GC safe point counter increment
- Debug hook check (null when no hook set)
- Line number lookup (null when no debug info)

## GC status

GC is NOT the bottleneck. All 62 major collections in gc.lua take <1ms each.
Total GC time <5ms across the full 5.7s test.

## How to profile

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

## Recent bytecode profiles

### `calls.lua` / call-stress
Latest profile sessions:
- `0710040345-6e8d1`
- `0710040600-4c1f3`
- `0710040818-38cf3`
- `0710040944-fb516`

What still shows up in the call tree:
- `LuaBytecodeVm._executeFrame`
- `LuaBytecodeVmCallEntry.invoke`
- `LuaBytecodeVm._runFrame`
- `LuaBytecodeFrame.setRegister`
- `LuaBytecodeFrame._initializeCallState`
- `bindBytecodeCallFrame`
- `Interpreter.getMainThread` / `getCurrentCoroutine`

What improved:
- call-site naming work is no longer dominating
- frame setup is less alloc-heavy than before
- `LuaBytecodeClosure.callableValue` is cached
- frame result materialization is now a simple fill/copy path

### `sort.lua`
Still a comparator-heavy stress test, but the direct bytecode path is much less noisy now.
It remains a good regression check for call overhead and GC pressure.

### GC churn / `gc.lua` proxy
Latest useful profile used an aged-table churn loop derived from `gc.lua`.
The hot spots were:
- `_runGcLoopSafePoint` / `runLoopGcAtSafePoint`
- `GenerationalGCManager.noteRootWrite`
- `GenerationalGCManager._enqueueForMarking`
- `LuaBytecodeFrame.setRegister`
- `Value.Value`
- `MemoryCredits.onAllocate`
- `TableStorage.[]=`

Before the latest GC queue tweak, `Value.hashCode` and `Value.==` also showed up
inside GC marking because the mark/finalizer membership checks were keyed off
full `Value` equality instead of the underlying raw payload.

## Changes made recently

### Cached closure call wrappers
- `LuaBytecodeClosure.callableValue` now reuses the same wrapper
- avoids rebuilding bytecode-entry `Value` objects on repeat calls

### Cached prototype-level frame metadata
- `_localExpiryFlags` is cached per prototype
- `_expiredRegisterCandidatesByPc`, `_trackedRegisterWriteFlags`,
  `_visibleNamedLocalsByPc`, and related local caches are prototype-scoped
- `LuaBytecodeFrame._initializeCallState` now normalizes args with a tight loop
- `LuaBytecodeFrame.resultsFrom()` now fills/copies directly instead of
  building multiple intermediate lists

### Raw-payload-keyed GC queues
- `_queuedToMark`, `_toBeFinalized`, and `_alreadyFinalized` now key off the
  underlying raw payload, while the queues still store the actual GC objects
- this preserves dedupe across shared wrappers without paying `Value.==`/
  `hashCode` on every churn cycle

### Hot-path guardrails
- debug-only work stays behind `debugHookFunction != null`
- call setup keeps staying as lean as possible in non-debug runs
- GC bookkeeping keys queues by raw payload so mark/finalizer membership
  checks don't pay `Value.hashCode` / `Value.==` on every churn cycle

## What the latest profile suggests

The current hot spots are less about raw call dispatch and more about:

1. **GC/root management**
   - `GenerationalGCManager.noteRootWrite`
   - `GenerationalGCManager._enqueueForMarking`
   - `LuaBytecodeFrame.setRegister`
   - `LuaBytecodeRuntime.runLoopGcAtSafePoint`
   - `MemoryCredits.onAllocate`

2. **Frame lifecycle**
   - `_initializeCallState`
   - `setRegister`
   - `bindBytecodeCallFrame`

3. **Residual VM overhead**
   - `_executeFrame`
   - `invoke`
   - `_runFrame`

## Next step

Profile `gc.lua` next and focus on:
- `noteRootWrite`
- `popExternalGcRoots`
- `runGcLoopSafePoint`
- to-be-closed / root churn in `setRegister`

If `gc.lua`/the churn proxy keeps pointing here, the next ticket is more GC queue/root
cleanup and maybe `popExternalGcRoots` reuse.
