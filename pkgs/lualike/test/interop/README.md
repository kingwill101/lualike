# Interop Tests

This directory contains tests for the interoperability features of LuaLike, focusing on how Dart code interacts with LuaLike code and vice versa.

## Directory Structure

- `table_access/` - Tests for table access and property manipulation
  - `table_indexing_test.dart` - Tests for table indexing operations
  - `table_property_test.dart` - Tests for table property access using dot notation and bracket notation

- `function_call/` - Tests for function call syntax variations
  - `function_call_syntax_test.dart` - Tests for different ways to call functions, including with and without parentheses

- `module/` - Tests for module loading and interaction
  - `module_loading_test.dart` - Tests for loading modules with require and interacting with them

- `value_test.dart` - Tests for the Value class that wraps Lua values in Dart
- `value_class_test.dart` - Tests for the ValueClass utility for creating Lua-like classes
- `interop_test.dart` - Basic interop tests for calling between Dart and LuaLike

## Features and Limitations

### Supported Features
1. **Function Call Chaining**: The parser now supports function call chaining (e.g., `a()()`)
2. **Table Method Calls**: Function calls on table fields (e.g., `table.method()`)
3. **Alternative Call Syntax**: String literals without parentheses (e.g., `print"hello"`)

### Known Limitations
Some tests are marked as skipped due to current limitations in the LuaLike implementation:

1. **Method Chaining**: The parser doesn't support method chaining with colon syntax (e.g., `obj:method1():method2()`)
2. **Function Calls on Table Elements**: Function calls on table elements accessed with bracket notation (e.g., `table["method"]()`)
3. **Mixed Notation**: Bracket notation after dot notation (e.g., `table.subtable["key"]`)
4. **Computed Keys**: Issues with table access using computed keys

These limitations are documented in the tests with SKIP annotations and explanatory comments.

## Running the Tests

To run all interop tests:

```bash
dart test test/interop
```

To run a specific category of tests:

```bash
dart test test/interop/table_access
dart test test/interop/function_call
dart test test/interop/module
```

To run a specific test file:

```bash
dart test test/interop/table_access/table_indexing_test.dart
```