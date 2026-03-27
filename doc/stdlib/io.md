# `io` Library

The `io` library provides file and stream operations close to stock Lua's
`io` module.

## Table of Contents

- [Overview](#overview)
- [Standard streams](#standard-streams)
- [Top-level functions](#top-level-functions)
- [File handle methods](#file-handle-methods)
- [Portability notes](#portability-notes)

## Overview

LuaLike registers `io` as a namespaced library and also exposes the standard
streams as fields on that table.

The top-level functions follow the usual Lua shape:

- `io.close([file])`
- `io.flush()`
- `io.input([file])`
- `io.lines([filename, ...])`
- `io.open(filename, [mode])`
- `io.output([file])`
- `io.popen(prog, [mode])`
- `io.read(...)`
- `io.tmpfile()`
- `io.type(obj)`
- `io.write(...)`

## Standard streams

LuaLike registers these default handles:

- `io.stdin`
- `io.stdout`
- `io.stderr`

These are backed by runtime IO devices and are treated specially so normal GC
cleanup does not accidentally close the process standard streams.

## Top-level functions

### Open, select, and close files

- `io.open(filename, [mode])` opens a file and returns a file handle or
  `nil, error`.
- `io.input([file])` gets or sets the default input handle.
- `io.output([file])` gets or sets the default output handle.
- `io.close([file])` closes an explicit handle or the current default output
  handle.

### Read and write

- `io.read(...)` reads from the current default input.
- `io.write(...)` writes to the current default output.
- `io.flush()` flushes the current default output.
- `io.lines([filename, ...])` returns an iterator over line or format reads.

### Miscellaneous helpers

- `io.tmpfile()` creates a temporary file handle.
- `io.type(obj)` returns `"file"`, `"closed file"`, or `nil`.
- `io.popen(...)` is present for compatibility but currently reports that the
  feature is unsupported.

## File handle methods

Handles returned from `io.open()` and related helpers expose method-style
operations:

- `file:close()`
- `file:flush()`
- `file:read(...)`
- `file:write(...)`
- `file:seek(whence, [offset])`
- `file:lines(...)`
- `file:setvbuf(...)`

## Portability notes

- Platform-specific devices such as `/dev/full` or shell-backed behavior may
  differ across operating systems.
- `io.popen()` is intentionally a compatibility stub rather than a process
  launcher.
- File handles are runtime objects, so exact GC timing should not be relied on
  for closing resources. Prefer explicit `:close()`.
