# Module Loading Tests

This directory contains tests for module loading and interaction in LuaLike.

## Test Files

### `module_loading_test.dart`

Tests for module loading and interaction, including:
- Basic module loading with require
- Module caching behavior
- Module functionality with alternative syntax
- Module with method chaining

## Known Limitations

Some tests are skipped due to current limitations:

1. **Package.loaded Access**: There are issues with accessing `package.loaded` for tracking module instances.
2. **Method Chaining**: The implementation doesn't support method chaining with colon syntax (e.g., `module:method1():method2()`).

These limitations are documented in the tests with SKIP annotations and explanatory comments.