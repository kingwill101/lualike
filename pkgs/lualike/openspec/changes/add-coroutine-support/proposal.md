## Why
lualike's coroutine standard library is stubbed out, so scripts that depend on `coroutine.create`, `resume`, and related APIs fail (e.g., `gc.lua`, `calls.lua`). The recent incremental GC work also introduced heavy debug logging on hot paths, which is dragging execution time into minutes for Lua test suite cases.

## What Changes
- Implement the coroutine standard library against the existing interpreter `Coroutine` runtime (create/resume/yield/status/running/wrap/close/isyieldable).
- Wire coroutine lifecycle into the interpreter and garbage collector so GC tests can exercise coroutines safely.
- Replace hot-path debug logging with lazy/guarded logging to remove the current performance cliff while keeping diagnostics available when logging is enabled.

## Impact
- Affected specs: coroutine
- Affected code: `lib/src/stdlib/lib_coroutine.dart`, `lib/src/coroutine.dart`, interpreter coroutine integration, hot-path logging (GC, interpreter loops), GC tests & docs.
