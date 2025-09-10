# `package` Library

The `package` library provides functions for loading modules in `lualike`.

## `package.loadlib(libname, funcname)`

Dynamically links the host program with the C library `libname`. This is not supported in `lualike`.

## `package.searchpath(name, path, [sep, [rep]])`

Searches for a `name` in a `path`.

-   `name`: The name of the module to search for.
-   `path`: A string specifying the search path.
-   `sep` (optional): The separator for the path elements. Defaults to ".".
-   `rep` (optional): The replacement for the separator in the module name. Defaults to the system's directory separator.
-   **Returns**: The path where the module was found. If no file is located, it returns `nil` followed by an error string listing each file it tried.

## `package.preload`

A table to store loader functions for specific modules. When `require` is called, it will first look in this table.

## `package.loaded`

A table used by `require` to control which modules are already loaded.

## `package.path`

A string that `require` uses to search for a Lua loader.

## `package.cpath`

A string that `require` uses to search for a C loader.

## `package.config`

A string describing some compile-time configurations for `lualike`.

## `package.searchers`

A table used by `require` to search for modules. It is a sequence of searcher functions.