# `package` Library

The `package` library controls module loading state for `require()` and related
helpers.

## Table of Contents

- [Overview](#overview)
- [Core fields](#core-fields)
- [Functions](#functions)
- [How `require()` fits in](#how-require-fits-in)
- [Compatibility notes](#compatibility-notes)

## Overview

LuaLike installs `package` as a global table and also wires `require()` into
the base library so scripts can load modules in the usual Lua style.

The runtime keeps `package.loaded` synchronized with both built-in libraries
and loaded script modules.

## Core fields

### `package.preload`

A table of loader functions checked before filesystem searchers.

### `package.loaded`

A table used to track modules and libraries that have already been initialized.

### `package.path`

The search template string used for Lua-style module loading.

### `package.cpath`

The compatibility search template string for native modules.

LuaLike does not implement real C extension loading, but the field is present
because Lua programs often inspect it.

### `package.config`

A newline-delimited configuration string describing path separators and related
loader conventions.

### `package.searchers`

The ordered list of searcher functions consulted by `require()`.

LuaLike includes preload and Lua-file searchers, plus compatibility stubs for
the unsupported native-loading entries.

## Functions

### `package.searchpath(name, path, [sep, [rep]])`

Resolves a module-like name against a search path template string.

On success it returns the first matching path. On failure it returns `nil`
plus an error string listing the attempted filenames.

### `package.loadlib(libname, funcname)`

Compatibility entrypoint for native library loading.

LuaLike does not dynamically load C modules. The function reports success only
for the limited compatibility cases it can model and otherwise returns
Lua-style failure tuples.

## How `require()` fits in

`require()` is exposed globally, but it relies on `package` internals:

- `package.loaded` tracks already-loaded modules
- `package.searchers` defines lookup order
- `package.path` and `package.searchpath()` drive Lua-file resolution

If you are embedding LuaLike and want custom module loading, `package.preload`
is often the simplest insertion point.

## Compatibility notes

- Native dynamic library loading is not implemented.
- Search behavior is still file-manager-dependent because LuaLike can run in
  embedded host environments, not just from the local filesystem.
- The `package` table is a runtime object, so host code can override or extend
  its fields if needed.
