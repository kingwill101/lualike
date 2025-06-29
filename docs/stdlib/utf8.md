# `utf8` Library

The `utf8` library provides functions for handling UTF-8 encoded strings.

## `utf8.char(...)`

Receives zero or more integers, converts each one to its corresponding UTF-8 byte sequence and returns a string with the concatenation of all these sequences.

-   `...`: A sequence of integers representing Unicode code points.
-   **Returns**: A string of the concatenated UTF-8 characters.

## `utf8.codes(s)`

Returns an iterator function that, each time it is called, returns the next character's code point in the string `s`.

-   `s`: The string to iterate over.
-   **Returns**: An iterator function.

## `utf8.codepoint(s, [i, [j]])`

Returns the code points (as integers) from all characters in `s` that start between byte position `i` and `j` (both inclusive).

-   `s`: The string.
-   `i` (optional): The starting byte position. Defaults to 1.
-   `j` (optional): The ending byte position. Defaults to `i`.
-   **Returns**: The code points for the characters in the specified range.

## `utf8.len(s, [i, [j]])`

Returns the number of UTF-8 characters in `s` that start between byte position `i` and `j` (both inclusive).

-   `s`: The string.
-   `i` (optional): The starting byte position. Defaults to 1.
-   `j` (optional): The ending byte position. Defaults to -1.
-   **Returns**: The number of characters, or `nil` if an invalid byte sequence is found.

## `utf8.offset(s, n, [i])`

Returns the position (in bytes) of the `n`-th character of string `s` (counting from position `i`).

-   `s`: The string.
-   `n`: The character offset.
-   `i` (optional): The byte position to start from.
-   **Returns**: The byte position of the `n`-th character.

## `utf8.charpattern`

A constant string with a pattern that matches exactly one UTF-8 byte sequence.