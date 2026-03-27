# `coroutine` Library

The `coroutine` library exposes Lua-style cooperative coroutines.

## Table of Contents

- [Overview](#overview)
- [`coroutine.create(f)`](#coroutinecreatef)
- [`coroutine.resume(thread, ...)`](#coroutineresumethread-)
- [`coroutine.yield(...)`](#coroutineyield)
- [`coroutine.status(thread)`](#coroutinestatusthread)
- [`coroutine.running()`](#coroutinerunning)
- [`coroutine.wrap(f)`](#coroutinewrapf)
- [`coroutine.close(thread)`](#coroutineclosethread)
- [`coroutine.isyieldable()`](#coroutineisyieldable)
- [Notes](#notes)

## Overview

LuaLike registers `coroutine` as a standard module-style table and supports the
core lifecycle expected by the Lua test suite.

The exported entrypoints are:

- `coroutine.create`
- `coroutine.resume`
- `coroutine.yield`
- `coroutine.status`
- `coroutine.running`
- `coroutine.wrap`
- `coroutine.close`
- `coroutine.isyieldable`

## `coroutine.create(f)`

Creates a suspended coroutine from a LuaLike function and returns the thread
object.

The argument must be callable. For true Lua coroutine behavior, the most
portable input is a Lua-defined function.

## `coroutine.resume(thread, ...)`

Resumes a suspended coroutine and passes any extra arguments into its body.

The return shape follows Lua conventions:

- `true, ...results` on success
- `false, error` on failure

## `coroutine.yield(...)`

Suspends the currently running coroutine and returns control to the resumer.

The yielded values become the extra return values from `coroutine.resume()`.

## `coroutine.status(thread)`

Returns the coroutine status string:

- `"running"`
- `"normal"`
- `"suspended"`
- `"dead"`

## `coroutine.running()`

Returns the current thread plus a boolean flag indicating whether it is the
main thread.

## `coroutine.wrap(f)`

Creates a callable wrapper around a coroutine.

Calling the wrapper resumes the coroutine directly and either returns yielded
or final results or raises the coroutine error in the wrapped style.

## `coroutine.close(thread)`

Closes a suspended or dead coroutine and releases its resumable state.

This is especially useful for test cases and host integrations that want
explicit coroutine cleanup rather than waiting for GC.

## `coroutine.isyieldable()`

Returns whether the current execution context can yield.

## Notes

- LuaLike's coroutine support is fully exercised by the Lua compatibility
  suite.
- Coroutine behavior interacts with debug hooks, closures, and GC-visible
  suspended state, so those subsystems are intentionally wired together in the
  runtime.
- For the exact edge behavior, cross-check the tests under
  `pkgs/lualike/test/` and `pkgs/lualike/luascripts/test/`.
