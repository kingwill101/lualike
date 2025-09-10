# `debug` Library

The `debug` library provides functions for debugging `lualike` scripts. Note that many of these functions are not fully implemented and may have limited functionality.

## `debug.debug()`

Enters an interactive mode, running each string the user enters.

## `debug.gethook()`

Returns the current hook function, mask, and count. (Not implemented)

## `debug.getinfo(function, [what])`

Returns a table with information about a function.

-   `function`: The function to get information about.
-   `what` (optional): A string specifying what information to return.
-   **Returns**: A table of information.

## `debug.getlocal(thread, level, local)`

Returns the name and value of the local variable with index `local` at `level` of the stack. (Not implemented)

## `debug.getmetatable(value)`

Returns the metatable of the given `value`.

-   `value`: The value to get the metatable of.
-   **Returns**: The metatable.

## `debug.getregistry()`

Returns the registry table. (Not implemented)

## `debug.getupvalue(f, up)`

Returns the name and value of the upvalue with index `up` of the function `f`. (Not implemented)

## `debug.getuservalue(u, n)`

Returns the `n`-th user value of the userdata `u`. (Not implemented)

## `debug.sethook([hook, mask, count])`

Sets the given function as a hook. (Not implemented)

## `debug.setlocal(thread, level, local, value)`

Assigns the `value` to the local variable with index `local` at `level` of the stack. (Not implemented)

## `debug.setmetatable(value, table)`

Sets the metatable for the given `value`.

-   `value`: The value to set the metatable for.
-   `table`: The metatable to set.
-   **Returns**: The original `value`.

## `debug.setupvalue(f, up, value)`

Assigns the `value` to the upvalue with index `up` of the function `f`. (Not implemented)

## `debug.setuservalue(u, value, n)`

Sets the `value` as the `n`-th user value for the given userdata `u`. (Not implemented)

## `debug.traceback([message, [level]])`

Returns a string with a traceback of the call stack.

-   `message` (optional): A message to be appended to the traceback.
-   `level` (optional): The stack level to start the traceback from.
-   **Returns**: The traceback string.

## `debug.upvalueid(f, n)`

Returns a unique identifier for the upvalue with index `n` from the given function `f`. (Not implemented)

## `debug.upvaluejoin(f1, n1, f2, n2)`

Makes the `n1`-th upvalue of the Lua closure `f1` refer to the `n2`-th upvalue of the Lua closure `f2`. (Not implemented)