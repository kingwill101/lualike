# LuaLike Documentation

This directory contains documentation for the LuaLike library, a Lua implementation in Dart.

## Contents

- [Guides](./guides/): Detailed guides on specific topics
  - [Writing Builtin Functions](./guides/writing_builtin_functions.md): How to implement builtin functions in LuaLike
  - [Value Handling](./guides/value_handling.md): Working with the Value class and type conversions
  - [Metatables and Metamethods](./guides/metatables.md): Working with metatables and implementing metamethods
  - [Standard Library Implementation](./guides/standard_library.md): Guidelines for implementing standard library functions
  - [Error Handling](./guides/error_handling.md): Understanding error handling and protected calls in LuaLike

## Purpose

This documentation aims to help developers understand the internals of the LuaLike library and contribute to its development. It provides insights into the design decisions, implementation details, and best practices for extending the library.

## Numeric Types and Semantics

LuaLike follows the Lua 5.4 numeric model, which distinguishes between integers and floating-point numbers (doubles). Lua integers are always 64-bit signed values, while floats are IEEE 754 double-precision values (with a 53-bit mantissa).

- **Integers**: Range from -9223372036854775808 to 9223372036854775807 (64-bit signed).
- **Floats**: IEEE 754 double-precision, can exactly represent integers up to 2^53.
- **Automatic Coercion**: Lua automatically converts between strings and numbers in arithmetic and comparison operations when possible. See [Value Handling](./guides/value_handling.md) for details.

### Dart Implementation Details

- LuaLike uses Dart's `int`, `double`, and `BigInt` to represent Lua numbers.
- Arithmetic and comparison operations are designed to match Lua's semantics:
  - If either operand is a float, both are promoted to double for the operation.
  - For equality, an int and a float are only equal if the float is finite and exactly represents the int.
  - For ordering (`<`, `>`, etc.), mathematical ordering is always used (e.g., `int.toDouble() < double`).
- All correctness is checked against the Lua CLI (`lua -e "..."`) and compared with the LuaLike REPL (`dart run bin/main.dart -e "..."`).

### Float/Int Boundary and Rounding Caveats

- Due to Dart's double implementation, some large integer/float conversions may differ in the least significant bits from C/Lua, especially near the 64-bit integer boundary (e.g., `-9223372036854775808 * -1.0` may yield `9223372036854776000.0` instead of `9223372036854775808.0`).
- However, ordering and equality semantics are spec-compliant and match Lua's behavior for all practical purposes.
- If you encounter a discrepancy, always check the result against the Lua CLI to determine the correct behavior.

For more on type coercion and value wrapping, see [Value Handling](./guides/value_handling.md).

## Contributing

When adding new features or modifying existing ones, please update the relevant documentation to keep it in sync with the codebase.

## String Formatting

The `string.format` function in LuaLike supports various format specifiers, allowing you to format numbers, strings, and other data types. Here are the supported specifiers:

- `%d`, `%i`: Integer numbers
- `%f`: Floating-point numbers
- `%s`: Strings
- `%#o`: Prefixed octal numbers
- `%x`, `%X`: Lowercase and uppercase hexadecimal numbers
- `%#x`, `%#X`: Prefixed lowercase and uppercase hexadecimal numbers
- `%c`: Characters

### Examples

```lua
-- Integer formatting
print(string.format("%d", 42))  -- Output: 42

-- Floating-point formatting
print(string.format("%.2f", 3.14159))  -- Output: 3.14

-- String formatting
print(string.format("%s", "hello"))  -- Output: hello

-- Octal formatting
print(string.format("%#o", 63))  -- Output: 077

-- Hexadecimal formatting
print(string.format("%x", 255))  -- Output: ff
print(string.format("%#X", 255))  -- Output: 0XFF

-- Character formatting
print(string.format("%c", 65))  -- Output: A
```

These examples demonstrate how to use the `string.format` function with different specifiers to achieve the desired output.