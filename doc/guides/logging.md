# Logging

lualike provides flexible, structured logging you can tune for development and production. You can:

- Tag a log with multiple categories (e.g., Interp, Value, GC)
- Attach key/value context to each log
- Defer building log messages so expensive work only happens when logs are enabled and not filtered out
- Dispatch logging off the hot path to reduce performance impact

## Quick Examples

```lua
-- Run with debug logs for specific categories
lualike --category Interp --category Value myscript.lua

-- Or via environment variable
LOGGING_ENABLED=true LOGGING_LEVEL=FINE LOGGING_CATEGORY=Interp,GC lualike myscript.lua
```

Inside lualike, logs carry categories and context and can be filtered without changing your code. Context shows as key=value pairs in the default output.

Example output:

```
[2025-10-09T12:34:56.789Z] [FINE] [Interp|Value] evaluating node=42 phase=parse
```

## Categories (Tags)

- Assign one or more categories to a log.
- Filtering uses any-match semantics: if any category matches your filter list, the log is shown.
- With no filter categories, all categories can appear (subject to level).

## Context

- Provide a context map of key/value pairs.
- The default sink prints `key=value` pairs after the message.
- Structured sinks (e.g., JSON) can be added later if you need them.

## Deferred (Zero-Cost) Logging

- Logging APIs support deferred message construction, so expensive work is only executed when logs will be emitted.
- This ensures minimal overhead when logging is disabled or filtered out.

## Backend and Dispatch

- By default, lualike uses the `contextual` backend for flexible formatting and channels.
- You can switch to the basic text backend by setting `LOGGING_BACKEND=basic`.
- Pretty formatting can be toggled with `LOGGING_PRETTY=true|false`.

- By default, logs dispatch on the event loop to avoid blocking your hot path.
- You can opt into direct (synchronous) dispatch or explore isolate-based dispatch if your workload requires it.

## Levels

- Supported levels: `debug`, `notice`, `info`, `warning`, `error`, `critical`, `alert`, `emergency`.
- Legacy synonyms are accepted via CLI/env: `FINE`→`debug`, `SEVERE`→`error`, `SHOUT`→`alert`, `CONFIG`→`notice`.
