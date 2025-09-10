# `io` Library

The `io` library provides functions for file manipulation and input/output operations.

## `io.close([file])`

Closes a `file`. If `file` is omitted, the default output file is closed.

-   `file` (optional): The file handle to close.
-   **Returns**: `true` on success, or `nil` plus an error message.

## `io.flush()`

Flushes the default output buffer.

-   **Returns**: `true` on success, or `nil` plus an error message.

## `io.input([file])`

Sets the default input file or returns the current default input file.

-   `file` (optional): A file name or a file handle to set as the default input.
-   **Returns**: The current default input file.

## `io.lines([filename, ...])`

Returns an iterator function that, each time it is called, reads the file according to the given formats.

-   `filename` (optional): The name of the file to read from. If omitted, it reads from the default input file.
-   `...` (optional): A sequence of format strings.
-   **Returns**: An iterator function.

## `io.open(filename, [mode])`

Opens a file with the given `mode`.

-   `filename`: The name of the file to open.
-   `mode` (optional): A string specifying the file mode (e.g., "r", "w", "a").
-   **Returns**: A new file handle, or `nil` plus an error message.

## `io.output([file])`

Sets the default output file or returns the current default output file.

-   `file` (optional): A file name or a file handle to set as the default output.
-   **Returns**: The current default output file.

## `io.popen(prog, [mode])`

Starts a program `prog` in a separate process. This function is not supported.

-   `prog`: The program to start.
-   `mode` (optional): The mode to open the program with.
-   **Returns**: `nil` and an error message.

## `io.read(...)`

Reads from the default input file, according to the given formats.

-   `...`: A sequence of format strings.
-   **Returns**: The read values, or `nil` on failure.

## `io.tmpfile()`

Returns a handle for a temporary file.

-   **Returns**: A file handle for a temporary file.

## `io.type(obj)`

Checks if an `obj` is a file handle.

-   `obj`: The object to check.
--  **Returns**: The string "file" if `obj` is an open file handle, "closed file" if it is a closed file handle, or `nil` otherwise.

## `io.write(...)`

Writes values to the default output file.

-   `...`: A sequence of values to write.
-   **Returns**: `true` on success, or `nil` plus an error message.