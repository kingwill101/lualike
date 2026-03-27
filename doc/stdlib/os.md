# `os` Library

The `os` library provides time, filesystem, environment, and shell-adjacent
helpers.

## Table of Contents

- [Overview](#overview)
- [Time and date helpers](#time-and-date-helpers)
- [Filesystem and process helpers](#filesystem-and-process-helpers)
- [Locale and environment helpers](#locale-and-environment-helpers)
- [Portability notes](#portability-notes)

## Overview

LuaLike registers `os` as a module-style table with the familiar Lua entry
points:

- `os.clock()`
- `os.date([format [, time]])`
- `os.difftime(t2, t1)`
- `os.execute([command])`
- `os.exit([code])`
- `os.getenv(varname)`
- `os.remove(filename)`
- `os.rename(oldname, newname)`
- `os.setlocale(locale, [category])`
- `os.time([table])`
- `os.tmpname()`

## Time and date helpers

### `os.clock()`

Returns an approximation of CPU time used by the process.

### `os.date([format [, time]])`

Formats a timestamp or returns a date table.

Important forms include:

- `os.date()` for a formatted local-time string
- `os.date("!*t")` for a UTC date table
- `os.date("*t")` for a local-time date table

### `os.difftime(t2, t1)`

Returns the difference between two timestamps.

### `os.time([table])`

Returns the current timestamp or converts a date table into one.

## Filesystem and process helpers

### `os.execute([command])`

Runs a shell command when supported by the host environment.

With no argument, it reports whether a shell is available.

### `os.remove(filename)`

Deletes a file and returns `true` on success or `nil, error` on failure.

### `os.rename(oldname, newname)`

Renames or moves a file and returns `true` on success or `nil, error` on
failure.

### `os.tmpname()`

Returns a temporary file name string.

### `os.exit([code])`

Requests process termination.

This is a strong side effect and is primarily relevant when you intentionally
let LuaLike control process exit behavior.

## Locale and environment helpers

### `os.getenv(varname)`

Returns the value of an environment variable or `nil` if it is unset.

### `os.setlocale(locale, [category])`

Tracks locale requests in a Lua-compatible shape.

The function exists for compatibility, but locale behavior still depends on
what the host Dart environment can meaningfully represent.

## Portability notes

- `os.execute()` and `os.exit()` are inherently host-dependent.
- `os.setlocale()` is compatibility-oriented rather than a full locale system.
- File and shell behavior will vary across operating systems and CI
  environments.
