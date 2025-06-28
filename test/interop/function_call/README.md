# Function Call Syntax Tests

This directory contains tests for different ways to call functions in LuaLike.

## Test Files

### `function_call_syntax_test.dart`

Tests for function call syntax variations, including:
- Standard function call with parentheses (`func("arg")`)
- Function call without parentheses for string literals (`func"arg"`)
- Table method call with parentheses (`table.method("arg")`)
- Table method call without parentheses (`table.method"arg"`)
- Standard library function call without parentheses (`string.upper"hello"`)
- Require function call with and without parentheses (`require("module")` and `require"module"`)
- Method chaining syntax (`obj:method1():method2()`)
- Method chaining on function results (`require("module").method()`)
- Combined alternative syntax (`require"module".method"arg"`)

## Known Limitations

Some tests are skipped due to current limitations:

1. **Method Chaining**: The implementation doesn't support method chaining with colon syntax (e.g., `obj:method1():method2()`).
2. **Method Chaining on Function Results**: The parser doesn't support method chaining on function results (e.g., `require("module").method()`).

These limitations are documented in the tests with SKIP annotations and explanatory comments.