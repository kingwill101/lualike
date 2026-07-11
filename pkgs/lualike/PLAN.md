# Plan: Reduce TAILCALL interpreter overhead without compiler passes

## Context

Profile of `calls.lua --lua-bytecode` shows TAILCALL at **675 ms / 71,123 executions = ~9.5 µs per tail call**.  The goal is to shrink that without enabling compiler passes — purely interpreter-side fast paths.

The current TAILCALL handler in `vm.dart` (line ~1610) does the following on every execution:

1. `_resolveCall` — extracts callee + args from the frame (cheap)
2. `_callSiteTargetLabel` — walks bytecode backwards to find the call name (debug-only, but **always runs**)
3. `_decodeTailCallNameInfo` — regex-parses the name string (**always runs**)
4. `_flattenTailCallable` — walks metatable `__call` chains (short-circuits for closures, but still checks `rawLuaSlot` + type)
5. `_closeFrameForCoroutine` — **always async**, even when there are no to-be-closed variables
6. `throw TailCallException` — exception throw + catch overhead (71k times)
7. In `_runFrameWithTailCalls`/`invoke`: `_flattenTailCallable` **again**, `_decodeTailCallNameInfo` **again**, then `invoke()` which allocates a new frame

That's **two flattens, two name resolutions, one exception throw/catch, and one async frame close** per tail call — most of which are unnecessary for the hot path (LuaBytecodeClosure → LuaBytecodeClosure with no debug hooks).

## Approach

Add a **fast path at the top of the `Opcode.tailCall` handler** that handles the common case (LuaBytecodeClosure callee, no debug hooks, no closeable variables) without exception throw/catch, without name resolution, and with a synchronous frame close.

### Optimization 1: Synchronous frame close (matches RETURN opcode)

Replace:
```dart
await _closeFrameForCoroutine(frame, error: null);
```
with:
```dart
if (!_closeFrameForCoroutineSync(frame)) {
  await _closeFrameForCoroutine(frame, error: null);
}
```

This is the same pattern already used by `return_`, `return0`, and `return1`. Most frames have no closeable variables, so the sync path will succeed and avoid an async hop.

### Optimization 2: Skip name resolution when no debug hooks

`_callSiteTargetLabel` and `_decodeTailCallNameInfo` are only used for debug traces and error messages.  When `_debugInterpreter?.debugHookFunction == null`, skip both entirely and pass `callName: null` to the downstream paths.

### Optimization 3: Fast-path LuaBytecodeClosure without exception

When the callee is already a `LuaBytecodeClosure` (the hot path — tail calls between Lua functions), skip the `TailCallException` throw/catch cycle. Instead, directly:

1. Close the frame (sync-first, per Optimization 1)
2. Release the current frame back to the pool
3. Call `invoke()` directly — which already has the tail-call loop

Concretely, modify the `Opcode.tailCall` case to:

```dart
case Opcode.tailCall:
  {
    try {
      // ... existing top/openTop setup ...
      final call = _resolveCall(frame, word);
      final callee = call.callee;
      final rawCallee = rawLuaSlot(callee);

      // Fast path: LuaBytecodeClosure with no debug hooks
      if (rawCallee is LuaBytecodeClosure &&
          _debugInterpreter?.debugHookFunction == null) {
        if (!_closeFrameForCoroutineSync(frame)) {
          await _closeFrameForCoroutine(frame, error: null);
        }
        _releaseBytecodeFrameIfReusable(frame);
        return invoke(
          rawCallee,
          call.args,
          functionValue: callee,
          isTailCall: true,
        );
      }

      // Slow path: metatables, debug hooks, non-closure callees
      // (existing code, unchanged)
      ...
    } on YieldException catch (error) {
      _suspendTailCall(frame, error);
    }
  }
```

The `invoke()` method already handles the tail-call loop internally (vm_call.dart:40-81). When a TailCallException is caught inside `invoke`, it does `continue` to loop back and reuse the same closure+args. The key win here is:
- **No exception throw/catch** in the opcode handler
- **No double `_flattenTailCallable`** — we resolve once and pass the raw closure directly
- **No double name resolution** — skip `_callSiteTargetLabel` and `_decodeTailCallNameInfo`
- **Synchronous frame close** — avoid async hop for the common case

## Files to modify

| File | Change |
|------|--------|
| `lib/src/lua_bytecode/vm.dart` | Rewrite `Opcode.tailCall` case with sync frame close + skip name resolution when no debug hooks + inline LuaBytecodeClosure fast path |

## Reuse

- `_closeFrameForCoroutineSync` — already exists in `vm_continuation.dart:39`, used by `return_`, `return0`, `return1`
- `_releaseBytecodeFrameIfReusable` — already exists in `vm_call.dart:100`
- `invoke` — already handles the tail-call loop in `vm_call.dart:40-81`
- `rawLuaSlot` — already used throughout

## Steps

- [ ] Rewrite `Opcode.tailCall` handler in `vm.dart` with three optimizations
- [ ] Run `dart analyze` on `pkgs/lualike`
- [ ] Run `./test_runner --all-engines --test=calls.lua,closure.lua` to verify correctness
- [ ] Run `./test_runner --all-engines` for full regression
- [ ] Run `LUALIKE_PROFILE_BYTECODE=1 ./test_runner --lua-bytecode --test=calls.lua -v` to measure TAILCALL improvement

## Results

Profile comparison (`calls.lua --lua-bytecode`):

| Metric | Before | After | Delta |
|---|---|---|---|
| TAILCALL total | 675,238 µs | 575,843 µs | **−14.8%** |
| Per-call (71,123 calls) | ~9.5 µs | ~8.1 µs | **−1.4 µs** |
| % of wall time | 2.0% | 1.6% | −0.4 pp |

Savings come from:
- Skipping `_callSiteTargetLabel` (bytecode walk) when no debug hooks
- Skipping `_decodeTailCallNameInfo` (regex parse) when no debug hooks  
- Skipping `_flattenTailCallable` (metatable walk) when callee is already a LuaBytecodeClosure
- Synchronous frame close (avoids async hop)
