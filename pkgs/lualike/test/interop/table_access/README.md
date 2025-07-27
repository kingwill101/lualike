# Table Access Tests

This directory contains tests for table access and property manipulation in LuaLike.

## Test Files

### `table_indexing_test.dart`

Tests for table indexing operations, including:
- Direct table indexing assignment (`table[key] = value`)
- For loop table indexing (currently failing due to bounds checking issues)
- Deeply nested table indexing (`table.subtable.value[key] = value`)

### `table_property_test.dart`

Tests for table property access using different notations:
- Dot notation (`table.property`)
- Bracket notation (`table["property"]`)
- Mixed notation (`table.subtable["property"]`)
- Property access with computed keys (`table[variable]`)
- Table property function call syntax (`table.property("arg")` and `table.property"arg"`)

## Known Limitations

Some tests are skipped due to current limitations:

1. **Function Calls on Bracket Notation**: The parser doesn't support function calls on table elements accessed with bracket notation (e.g., `table["method"]()`).
2. **Mixed Notation**: The parser doesn't support bracket notation after dot notation (e.g., `table.subtable["key"]`).
3. **Computed Keys**: There are issues with table access using computed keys.

These limitations are documented in the tests with SKIP annotations and explanatory comments.