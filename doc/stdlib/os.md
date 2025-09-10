# `os` Library

The `os` library provides functions for interacting with the operating system. This includes functions for getting the time, executing commands, and working with environment variables.

## `os.clock()`

Returns an approximation of the amount of CPU time used by the program in seconds.

-   **Returns**: The number of seconds of CPU time.

## `os.date([format [, time]])`

Returns a string or a table containing date and time information.

-   `format` (optional): A string specifying the format of the returned value.
    -   If `format` starts with `!`, the time is formatted in UTC.
    -   If `format` is `*t`, a table with the fields `year`, `month`, `day`, `hour`, `min`, `sec`, `wday`, `yday`, and `isdst` is returned.
    -   Otherwise, `format` is a string that follows the same rules as the C `strftime` function.
-   `time` (optional): A timestamp (number of seconds since the epoch) to format. Defaults to the current time.
-   **Returns**: A formatted date string or a table of time components.

## `os.difftime(t2, t1)`

Returns the difference in seconds between two timestamps `t2` and `t1`.

-   `t2`: The first timestamp.
-   `t1`: The second timestamp.
-   **Returns**: The difference in seconds (`t2` - `t1`).

## `os.execute([command])`

Executes a command using the operating system's shell.

-   `command` (optional): The command to execute. If omitted, it returns `true` if a shell is available.
-   **Returns**: `true` on success, or `nil` plus an error message and code.

## `os.exit([code])`

Exits the program with an optional exit `code`.

-   `code` (optional): The exit code.

## `os.getenv(varname)`

Returns the value of an environment variable.

-   `varname`: The name of the environment variable.
-   **Returns**: The value of the variable, or `nil` if it is not defined.

## `os.remove(filename)`

Deletes a file.

-   `filename`: The name of the file to delete.
-   **Returns**: `true` on success, or `nil` plus an error message.

## `os.rename(oldname, newname)`

Renames a file.

-   `oldname`: The current name of the file.
-   `newname`: The new name for the file.
-   **Returns**: `true` on success, or `nil` plus an error message.

## `os.setlocale(locale, [category])`

Sets the current locale for the program. This function is not fully supported in the current environment but will track the requested locale.

-   `locale`: The locale string.
-   `category` (optional): The category to set.
-   **Returns**: The name of the new locale, or `nil` on failure.

## `os.time([table])`

Returns the current time as a timestamp (number of seconds since the epoch).

-   `table` (optional): A table with `year`, `month`, `day`, etc., to convert to a timestamp.
-   **Returns**: The timestamp.

## `os.tmpname()`

Returns a string with a file name that can be used for a temporary file.

-   **Returns**: A temporary file name.