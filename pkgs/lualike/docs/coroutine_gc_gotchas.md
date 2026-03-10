# Coroutine And GC Gotchas

This note is for maintainers working on the AST interpreter, coroutine
runtime, protected calls, and garbage collector. The recent regressions in
`gc.lua`, `coroutine.lua`, `goto.lua`, and `calls.lua` all came from a small
set of state handoff mistakes, so the important part is preserving the
invariants below.

The later interpreter failures in `literals.lua`, `files.lua`, and
`nextvar.lua` turned out to be the same category of bug. The loop or condition
still looked live from Lua, but the relevant runtime state existed only in Dart
temporaries, so the collector and condition evaluator had to be taught about
those cases explicitly.

## Why This Exists

Several runtime subsystems share mutable execution state:

- the active interpreter scope (`currentEnv`, `currentFunction`,
  `currentFastLocals`)
- the explicit call stack
- temporary GC roots owned by active calls
- suspended coroutine state and saved call stacks
- debug hook bookkeeping

When one of those handoffs is even slightly wrong, the failures are usually far
away from the actual bug:

- a closure suddenly loses an upvalue after `collectgarbage()`
- a coroutine resume returns into the wrong local scope
- `debug.sethook` misses the last `return`
- `coroutine.close` or `<close>` handling resumes a coroutine "normally" when
  it should still be unwinding
- recursive `coroutine.wrap(a)(a)` hangs instead of failing with stack overflow

## Invariants

### 1. Yield Must Restore The Caller Context

Relevant code:
- [function.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/interpreter/function.dart)
- [coroutine.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/coroutine.dart)

The caller's `currentEnv`, `currentFunction`, and `currentFastLocals` must be
captured before entering a call frame and restored after a yielded nested call
resumes.

If this is broken, code after the yield resolves locals against the wrong
closure or helper frame. The regression that exposed this was the
`pcall`/iterator path from `coroutine.lua`, where `s` became effectively lost
after the wrapped iterator resumed.

Guard tests:
- [coroutine_library_test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/test/stdlib/coroutine_library_test.dart)

### 2. Active Call Roots Must Move Off The Interpreter When A Coroutine Yields

Relevant code:
- [function.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/interpreter/function.dart)
- [coroutine.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/coroutine.dart)

Active calls temporarily root the current callable and its captured upvalue
boxes. That is correct while the call is running, but wrong while a coroutine is
paused.

On yield:
- detach interpreter-owned external GC root providers
- snapshot their exposed objects onto the coroutine

On resume:
- restore those providers back to the interpreter

If this is broken in either direction:
- suspended coroutines can become immortal because the main interpreter still
  roots them
- or active closures can be collected while they are still executing

This was the core of the self-referenced-thread GC bug.

Guard tests:
- [self_referenced_thread_collection_test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/test/gc/self_referenced_thread_collection_test.dart)
- [coroutine_library_test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/test/stdlib/coroutine_library_test.dart)
- [upvalue_assignment_fix_test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/test/upvalue_assignment_fix_test.dart)

### 3. Call Frames Must Root Their Callable

Relevant code:
- [generational_gc.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/gc/generational_gc.dart)

The GC root set must include `frame.callable`, not only the frame environment.
Some active closures remain reachable only through the executing frame, and
explicit collection can otherwise strip their upvalues or reclaimed wrappers.

The practical symptom is "returned closure still exists, but captured state is
gone or nil".

### 4. Active `for-in` State Must Be Published As Temporary GC Roots

Relevant code:
- [control_flow.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/interpreter/control_flow.dart)

The AST interpreter keeps several loop internals in Dart locals:

- the direct-table fast path stores the source table outside the Lua environment
- generic `for` stores the iterator callable, state, control variable, and
  optional to-be-closed value in async locals
- the optimized `pairs(next, t, nil)` path bypasses a Lua-visible iterator
  object entirely

That state is still live across `coroutine.yield()` even though it is not
reachable from ordinary Lua objects. If the loop body yields and the script
calls `collectgarbage()` before resuming, the GC must still see:

- the loop environment
- the source table for direct iteration
- the iterator callable/state/control tuple for generic `for`
- any synthetic to-be-closed helper value used by the loop

The fix is to publish those objects through `pushExternalGcRoots(...)` for the
entire lifetime of the active loop and pop them in a `finally` block.

If this invariant breaks, the failures are indirect:

- wrapped recursive generators stop early
- `for value in coroutine.wrap(...) do` dies mid-stream
- later tests such as `files.lua` fail even though the real bug is loop-state
  liveness

Guard tests:
- [coroutine_library_test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/test/stdlib/coroutine_library_test.dart)

### 5. Statement Truthiness Must Collapse Empty Multi-Results

Relevant code:
- [control_flow.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/interpreter/control_flow.dart)
- [value.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/value.dart)

Lua expressions can return multiple values, but statement conditions only test
the first result. When there are zero results, that behaves like `nil`, not
like a truthy wrapper object.

This matters most for wrapped coroutines:

- `co()` can yield one value on one iteration
- then finish with zero final values on the next call
- `while co() do` must stop immediately

If condition evaluation tests the raw multi container instead of collapsing it
first, the loop performs one extra iteration and attempts to resume a dead
coroutine.

The implementation rule is:

- collapse multi-results to their first element before condition coercion
- treat an empty multi-result as `nil`
- then apply normal Lua truthiness (`nil` and `false` are falsey; everything
  else is truthy)

Guard tests:
- [coroutine_library_test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/test/stdlib/coroutine_library_test.dart)

### 6. `coroutine.close` Must Unwind, Not Synthetically Resume

Relevant code:
- [coroutine.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/coroutine.dart)
- [environment.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/environment.dart)

Closing a suspended coroutine cannot complete its stored yield completer with a
fake "normal" result just to make the waiting future continue. That causes AST
frames to believe the coroutine resumed normally while `<close>` handlers are
still unwinding.

The correct behavior is:
- mark the coroutine dead
- unwind to-be-closed variables directly
- propagate any unwind error
- reject yields across the close boundary with the C-call-boundary error

The self-resume / `<close>` cases in `coroutine.lua` exercise this directly.

### 7. Debug Hooks Need A Synthetic Final Return For Resumed Coroutines

Relevant code:
- [coroutine.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/coroutine.dart)

If a coroutine yielded earlier, the original `_executeCoroutine` activation may
already be gone by the time the coroutine finally dies. The root Lua frame
still needs a matching `return` hook and stack cleanup.

If this is missing, traces look almost right but lose the terminal `return`
event, which is exactly the sort of bug that tends to regress later because the
call stack still "mostly works".

### 8. Suspended Coroutine Tracebacks Must Stop At Real Lua Frames

Relevant code:
- [coroutine.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/coroutine.dart)
- [lib_debug.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/stdlib/lib_debug.dart)

`debug.traceback(co, ...)` for a suspended coroutine should reflect the saved
Lua call chain and nothing more. A synthetic root frame is still useful when a
coroutine has no saved Lua frames at all, but once `_savedCallStack` already
contains real Lua frames, appending an extra synthetic function frame creates a
subtle off-by-one traceback:

- `db.lua` sees one extra source line at the end of the stack
- higher `level` values stop on the wrong frame
- frame names degrade from "function </path.lua:line>" to a repeated named
  function frame

The rule is:

- if saved or live Lua frames exist, return only those frames for debug-level
  lookup
- only synthesize a root frame when the coroutine is suspended/running without
  any visible Lua frames

Guard tests:
- [debug_getinfo_test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/test/interpreter/debug_getinfo_test.dart)
- [db.lua](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/luascripts/test/db.lua)

### 9. Stack Overflow Checks Need Both Local And Global Depth

Relevant code:
- [function.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/interpreter/function.dart)

Per-coroutine depth is not enough. `coroutine.wrap(a)(a)` creates a fresh
coroutine at each step, so a local-only guard never trips even though the host
stack is still growing.

Always check:
- the coroutine-local slice depth
- the global interpreter call stack depth

The expected failure mode is a prompt `C stack overflow`, not a hang.

## Upvalue Ordering Notes

Recent regressions in `goto.lua` and `calls.lua` came from upvalue ordering,
not from coroutine mechanics directly.

Relevant code:
- [upvalue_analyzer.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/interpreter/upvalue_analyzer.dart)

Important rules:
- preserve first-reference order for captured names
- do not let environment walk order reshuffle upvalue slots
- respect source-order semantics in assignment traversal

If that ordering changes, the main symptom is not a crash. It is debug API or
dump/load behavior returning the "wrong" upvalue in slot 1, which then breaks
`debug.upvalueid`, `debug.setupvalue`, and some binary chunk reload checks.

Guard tests:
- [goto_upvalue_identity_test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/test/interpreter/goto_upvalue_identity_test.dart)
- [dump_load_upvalue_order_test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/test/interpreter/dump_load_upvalue_order_test.dart)

## When Touching This Area

At minimum, rerun:

```bash
cd pkgs/lualike
dart test test/stdlib/coroutine_library_test.dart -r compact
dart test test/gc/self_referenced_thread_collection_test.dart -r compact
./test_runner --test=literals.lua -v
./test_runner --test=nextvar.lua -v
./run_bytecode_tests.sh --test=coroutine.lua -v
./run_bytecode_tests.sh --test=gc.lua -v
```

If the change affects closure capture or dumped functions, also rerun:

```bash
cd pkgs/lualike
dart test test/interpreter/goto_upvalue_identity_test.dart -r compact
dart test test/interpreter/dump_load_upvalue_order_test.dart -r compact
```
