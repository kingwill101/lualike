# Lualike Tools

This directory contains various tools for building, testing, and working with the Lualike interpreter.

## Test Runner (`test.dart`)

The main test runner for executing Lua test suites against the Lualike interpreter.

### Basic Usage

```bash
# Run all tests
dart run tools/test.dart

# Run with verbose output
dart run tools/test.dart --verbose

# Run specific tests
dart run tools/test.dart --test=literals.lua,math.lua

# Skip compilation if binary exists
dart run tools/test.dart --skip-compile

# Force recompilation
dart run tools/test.dart --force-compile
```

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--skip-compile` | `-s` | Skip compile if lualike binary exists |
| `--force-compile` | `-f` | Force recompilation ignoring cache |
| `--verbose` | `-v` | Show verbose output for each test |
| `--soft` | | Enable soft mode (sets `_soft = true`). Enabled by default |
| `--port` | | Enable portability mode (sets `_port = true`). Enabled by default |
| `--skip-heavy` | | Skip heavy tests (sets `_skip_heavy = true`). Enabled by default |
| `--test` | `-t` | Run specific test(s) by name (e.g., `--test=bitwise.lua,math.lua`) |
| `--tests` | | Alias for `--test`; accepts comma-separated names |
| `--compile-runner` | | Compile the test runner itself into a standalone executable |
| `--dart-path` | | Path to the Dart executable (defaults to "dart" in PATH) |

### Compiling the Test Runner

You can compile the test runner into a standalone executable for faster execution:

```bash
# Compile test runner
dart run tools/test.dart --compile-runner

# Compile with custom dart path
dart run tools/test.dart --compile-runner --dart-path /path/to/dart

# Use the compiled runner
./test_runner --test=literals.lua
```

The compiled executable will be created as `test_runner` (or `test_runner.exe` on Windows) in the project root.

### Environment Variables

The test runner supports several environment variables that can be set in the Lua test environment:

- `_soft` - Soft mode (enabled by default)
- `_port` - Portability mode (enabled by default)  
- `_skip_heavy` - Skip heavy tests (enabled by default)


## Compare Tool (`compare.dart`)

Utility for comparing Lualike output with reference Lua interpreter.

### Usage

```bash
# Compare a Lua command
dart run tools/compare.dart "print('hello world')"

# Compare a Lua file
dart run tools/compare.dart script.lua
```

This tool runs the same code in both Lualike and reference Lua, showing any differences in output.


## Examples

### Running Tests

```bash
# Quick test run
dart run tools/test.dart --test=literals.lua --skip-compile

# Full test suite with verbose output
dart run tools/test.dart --verbose

# Run specific test category
dart run tools/test.dart --test=math.lua,bitwise.lua --verbose
```
