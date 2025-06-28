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