# `dart.string` Library

The `dart.string` library provides a set of utility functions to manipulate strings, leveraging Dart's powerful string-handling capabilities.

## `dart.string.split(s, separator)`

Splits a string `s` by a `separator` and returns a table containing the substrings.

-   `s`: The string to be split.
-   `separator`: The string to split by.
-   **Returns**: A table of substrings.

## `dart.string.trim(s)`

Removes leading and trailing whitespace from a string `s`.

-   `s`: The string to be trimmed.
-   **Returns**: The trimmed string.

## `dart.string.toUpperCase(s)`

Converts a string `s` to uppercase.

-   `s`: The string to convert.
-   **Returns**: The uppercase string.

## `dart.string.toLowerCase(s)`

Converts a string `s` to lowercase.

-   `s`: The string to convert.
-   **Returns**: The lowercase string.

## `dart.string.contains(s, other, [startIndex])`

Checks if a string `s` contains another string `other`. An optional `startIndex` can be provided.

-   `s`: The string to check.
-   `other`: The string to search for.
-   `startIndex` (optional): The index to start searching from.
-   **Returns**: `true` if `s` contains `other`, `false` otherwise.

## `dart.string.replaceAll(s, from, to)`

Replaces all occurrences of a substring `from` with another substring `to` in a string `s`.

-   `s`: The string to perform replacements on.
-   `from`: The substring to be replaced.
-   `to`: The substring to replace with.
-   **Returns**: The new string with replacements.

## `dart.string.substring(s, startIndex, [endIndex])`

Returns a substring of `s` from `startIndex` to an optional `endIndex`.

-   `s`: The string to get a substring from.
-   `startIndex`: The starting index (inclusive).
-   `endIndex` (optional): The ending index (exclusive).
-   **Returns**: The substring.

## `dart.string.trimLeft(s)`

Removes leading whitespace from a string `s`.

-   `s`: The string to be trimmed.
-   **Returns**: The trimmed string.

## `dart.string.trimRight(s)`

Removes trailing whitespace from a string `s`.

-   `s`: The string to be trimmed.
-   **Returns**: The trimmed string.

## `dart.string.padLeft(s, width, [padding])`

Pads a string `s` on the left to a certain `width` with an optional `padding` string.

-   `s`: The string to pad.
-   `width`: The minimum width of the padded string.
-   `padding` (optional): The string to use for padding. Defaults to a space.
-   **Returns**: The padded string.

## `dart.string.padRight(s, width, [padding])`

Pads a string `s` on the right to a certain `width` with an optional `padding` string.

-   `s`: The string to pad.
-   `width`: The minimum width of the padded string.
-   `padding` (optional): The string to use for padding. Defaults to a space.
-   **Returns**: The padded string.

## `dart.string.startsWith(s, pattern, [index])`

Checks if a string `s` starts with `pattern`. An optional `index` can be provided to start searching from.

-   `s`: The string to check.
-   `pattern`: The pattern to check for.
-   `index` (optional): The index to start searching from.
-   **Returns**: `true` if `s` starts with `pattern`, `false` otherwise.

## `dart.string.endsWith(s, other)`

Checks if a string `s` ends with another string `other`.

-   `s`: The string to check.
-   `other`: The string to check for.
-   **Returns**: `true` if `s` ends with `other`, `false` otherwise.

## `dart.string.indexOf(s, pattern, [start])`

Returns the index of the first occurrence of `pattern` in a string `s`. An optional `start` index can be provided.

-   `s`: The string to search in.
-   `pattern`: The pattern to search for.
-   `start` (optional): The index to start searching from.
-   **Returns**: The index of the first occurrence, or -1 if not found.

## `dart.string.lastIndexOf(s, pattern, [start])`

Returns the index of the last occurrence of `pattern` in a string `s`. An optional `start` index can be provided to search backwards from.

-   `s`: The string to search in.
-   `pattern`: The pattern to search for.
-   `start` (optional): The index to start searching backwards from.
-   **Returns**: The index of the last occurrence, or -1 if not found.

## `dart.string.replaceFirst(s, from, to, [startIndex])`

Replaces the first occurrence of `from` with `to` in a string `s`. An optional `startIndex` can be provided.

-   `s`: The string to perform the replacement on.
-   `from`: The substring to be replaced.
-   `to`: The substring to replace with.
-   `startIndex` (optional): The index to start searching from.
-   **Returns**: The new string with the replacement.

## `dart.string.isEmpty(s)`

Checks if a string `s` is empty.

-   `s`: The string to check.
-   **Returns**: `true` if the string is empty, `false` otherwise.

## `dart.string.isNotEmpty(s)`

Checks if a string `s` is not empty.

-   `s`: The string to check.
-   **Returns**: `true` if the string is not empty, `false` otherwise.

## `dart.string.rep(s, times)`

Repeats a string `s` a number of `times`.

-   `s`: The string to repeat.
-   `times`: The number of times to repeat the string.
-   **Returns**: The repeated string.

## `dart.string.replaceRange(s, start, end, replacement)`

Replaces a range in a string `s` with a `replacement` string.

-   `s`: The string to perform the replacement on.
-   `start`: The starting index of the range (inclusive).
-   `end`: The ending index of the range (exclusive).
-   `replacement`: The string to replace the range with.
-   **Returns**: The new string with the replacement.

## `dart.string.length(s)`

Returns the length of a string `s`.

-   `s`: The string to get the length of.
-   **Returns**: The length of the string.

## `dart.string.codeUnitAt(s, index)`

Returns the 16-bit UTF-16 code unit at the given `index` of a string `s`.

-   `s`: The string to get the code unit from.
-   `index`: The index of the code unit.
-   **Returns**: The code unit at the given index.

## `dart.string.fromCharCodes(table)`

Creates a string from a table of character codes.

-   `table`: A table of character codes.
-   **Returns**: The new string.

---

## Sub-Libraries

### `dart.string.bytes`

The `dart.string` library contains a sub-library, `bytes`, for low-level byte manipulation. See the [`dart.string.bytes` documentation](./dart_string_bytes.md) for more details.