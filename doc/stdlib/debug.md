# `debug` Library

The `debug` library provides runtime inspection helpers for stack frames,
locals, hooks, tracebacks, and upvalues.

LuaLike implements a substantial subset of the classic Lua `debug` surface and
also exposes a couple of runtime-specific memory helpers.

## Table of Contents

- [`debug.debug()`](#debugdebug)
- [`debug.gethook()`](#debuggethook)
- [`debug.getinfo(function-or-level, [what])`](#debuggetinfofunction-or-level-what)
- [`debug.getlocal(thread-or-level, local)`](#debuggetlocalthread-or-level-local)
- [`debug.getmetatable(value)`](#debuggetmetatablevalue)
- [`debug.getregistry()`](#debuggetregistry)
- [`debug.getupvalue(f, up)`](#debuggetupvaluef-up)
- [`debug.getuservalue(u, n)`](#debuggetuservalueu-n)
- [`debug.sethook([hook, mask, count])`](#debugsethookhook-mask-count)
- [`debug.setlocal(thread-or-level, index, value)`](#debugsetlocalthread-or-level-index-value)
- [`debug.setmetatable(value, table)`](#debugsetmetatablevalue-table)
- [`debug.setupvalue(f, up, value)`](#debugsetupvaluef-up-value)
- [`debug.setuservalue(u, value, n)`](#debugsetuservalueu-value-n)
- [`debug.traceback([message, [level]])`](#debugtracebackmessage-level)
- [`debug.upvalueid(f, n)`](#debugupvalueidf-n)
- [`debug.upvaluejoin(f1, n1, f2, n2)`](#debugupvaluejoinf1-n1-f2-n2)
- [LuaLike-specific helpers](#lualike-specific-helpers)

## `debug.debug()`

Enters a simple interactive debug console and returns when the user enters
`cont`.

This is primarily intended for manual debugging sessions.

## `debug.gethook()`

Returns the current hook function, hook mask, and count.

If no hook is installed, it returns `nil`, `nil`, and `0`.

## `debug.getinfo(function-or-level, [what])`

Returns a table describing a function or stack level.

LuaLike uses runtime-specific debug information so this function can report
source names, line numbers, function shape, and other metadata across the AST
and bytecode backends.

## `debug.getlocal(thread-or-level, local)`

Returns the name and value of the local variable with the given index.

LuaLike supports stack-local inspection for active frames and uses runtime
debug metadata to map local names back to current values.

## `debug.getmetatable(value)`

Returns the metatable for `value`, honoring protected `__metatable` behavior.

## `debug.getregistry()`

Returns the runtime debug registry table.

## `debug.getupvalue(f, up)`

Returns the name and value of the upvalue with index `up` from function `f`.

## `debug.getuservalue(u, n)`

Returns the `n`th user value associated with `u`.

## `debug.sethook([hook, mask, count])`

Installs or clears the active debug hook.

- `hook`
  The function to call.
- `mask`
  A string describing which events trigger the hook.
- `count`
  The instruction-count threshold for count hooks.

## `debug.setlocal(thread-or-level, index, value)`

Assigns `value` to the local variable at the specified stack location.

## `debug.setmetatable(value, table)`

Sets the metatable for `value` and returns the original value.

## `debug.setupvalue(f, up, value)`

Assigns a new value to an upvalue and returns the upvalue name.

## `debug.setuservalue(u, value, n)`

Sets the `n`th user value associated with `u`.

## `debug.traceback([message, [level]])`

Returns a traceback string for the current stack.

This is the primary script-facing tool for debugging failures and is also used
by `xpcall`.

## `debug.upvalueid(f, n)`

Returns a stable identifier for the `n`th upvalue of `f`.

## `debug.upvaluejoin(f1, n1, f2, n2)`

Makes upvalue `n1` in `f1` refer to the same storage as upvalue `n2` in `f2`.

## LuaLike-specific helpers

LuaLike also exposes:

- `debug.memtrace()`
- `debug.memtree()`

These are runtime-specific diagnostics for memory inspection and are not part
of stock Lua.

## Notes

- The `debug` library is powerful and intentionally low-level.
- Some edge behaviors are runtime-dependent because they depend on frame and
  debug metadata.
- When exact compatibility matters, verify behavior against the relevant test
  cases under `pkgs/lualike/test/`.
