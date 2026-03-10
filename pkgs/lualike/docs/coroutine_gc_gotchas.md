# Coroutine And GC Gotchas

This note is for maintainers working on the AST interpreter, coroutine
runtime, protected calls, and garbage collector. The recent regressions in
`gc.lua`, `coroutine.lua`, `goto.lua`, and `calls.lua` all came from a small
set of state handoff mistakes, so the important part is preserving the
invariants below.

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

### 4. `coroutine.close` Must Unwind, Not Synthetically Resume

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

### 5. Debug Hooks Need A Synthetic Final Return For Resumed Coroutines

Relevant code:
- [coroutine.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/lib/src/coroutine.dart)

If a coroutine yielded earlier, the original `_executeCoroutine` activation may
already be gone by the time the coroutine finally dies. The root Lua frame
still needs a matching `return` hook and stack cleanup.

If this is missing, traces look almost right but lose the terminal `return`
event, which is exactly the sort of bug that tends to regress later because the
call stack still "mostly works".

### 6. Stack Overflow Checks Need Both Local And Global Depth

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
./run_bytecode_tests.sh --test=coroutine.lua -v
./run_bytecode_tests.sh --test=gc.lua -v
```

If the change affects closure capture or dumped functions, also rerun:

```bash
cd pkgs/lualike
dart test test/interpreter/goto_upvalue_identity_test.dart -r compact
dart test test/interpreter/dump_load_upvalue_order_test.dart -r compact
```
