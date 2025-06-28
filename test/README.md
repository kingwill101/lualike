# Test Organization

The tests for the LuaLike project are organized into the following directories:

## Directory Structure

- `test/` - Root directory for general tests
- `test/bytecode/` - Tests for bytecode compilation and execution
- `test/stdlib/` - Tests for standard library functions
- `test/interop/` - Tests for interoperability between Dart and LuaLike
- `test/interpreter/` - Tests for the interpreter
  - `test/interpreter/core/` - Tests for core interpreter components
  - `test/interpreter/statements/` - Tests for statement-related functionality
  - `test/interpreter/expressions/` - Tests for expression-related functionality
  - `test/interpreter/functions/` - Tests for function-related functionality
  - `test/interpreter/misc/` - Miscellaneous interpreter tests

## Running Tests

You can run tests for specific categories by specifying the directory path:

```bash
# Run all tests
dart test

# Run bytecode tests
dart test test/bytecode

# Run stdlib tests
dart test test/stdlib

# Run interop tests
dart test test/interop

# Run interpreter tests
dart test test/interpreter

# Run specific interpreter test categories
dart test test/interpreter/core
dart test test/interpreter/statements
dart test test/interpreter/expressions
dart test test/interpreter/functions
dart test test/interpreter/misc
```

## Using Tags in Tests

You can also use tags to categorize tests. To add a tag to a test, use the `@Tags()` annotation:

```dart
import 'package:test/test.dart';

@Tags(['bytecode'])
void main() {
  test('Bytecode test', () {
    // Test code here
  });
}
```

You can add multiple tags to a test:

```dart
@Tags(['bytecode', 'compiler'])
void main() {
  // Test code here
}
```

### Hierarchical Tags

The project uses a hierarchical tagging system. For example, tests tagged with `core`, `statements`, `expressions`, `functions`, or `misc` automatically get the `interpreter` tag as well.

This means:
- You can run all interpreter tests with `dart test --tags interpreter`
- You can run just the core interpreter tests with `dart test --tags core`

To run tests with a specific tag:

```bash
# Run all tests with the 'bytecode' tag
dart test --tags bytecode

# Run all tests with the 'stdlib' tag
dart test --tags stdlib

# Run all interpreter tests (includes core, statements, expressions, functions, misc)
dart test --tags interpreter

# Run only the core interpreter tests
dart test --tags core
```

You can also exclude tests with specific tags:

```bash
# Run all tests except those with the 'slow' tag
dart test --exclude-tags slow
```

## Combining Filters

You can combine directory paths with name filters:

```bash
# Run tests in the interpreter/core directory with "VM" in their name
dart test test/interpreter/core --name "VM"

# Run tests in the stdlib directory with "string" in their name
dart test test/stdlib --name "string"
```

## Running Tests with Specific Platforms

By default, tests run on the Dart VM. You can specify other platforms:

```bash
# Run tests on Chrome
dart test -p chrome

# Run tests on both VM and Chrome
dart test -p vm,chrome
```

## Test Configuration

The test configuration is defined in `dart_test.yaml` in the project root. It includes:

- Path configuration for all test directories
- Tag definitions with hierarchical relationships
- Concurrency settings (4 concurrent test suites)
- Default timeout (30 seconds)
- Reporter configuration (expanded output)

## Additional Options

```bash
# Run tests with verbose output
dart test --reporter expanded

# Run tests with a specific timeout
dart test --timeout 60s

# Run tests with a specific concurrency
dart test -j 2

# Run tests and generate coverage report
dart test --coverage=coverage
```