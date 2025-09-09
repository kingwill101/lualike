# Lualike Tools

This directory contains various tools for building, testing, and working with the Lualike interpreter.

## Test Runner (`test.dart`)

The main test runner for executing Lua test suites against the Lualike interpreter. Features intelligent compilation caching, Dart executable path injection, and comprehensive test management.

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

# Use custom Dart executable
dart run tools/test.dart --dart-path /path/to/dart
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

You can compile the test runner into a standalone executable for faster execution. The compiled runner automatically uses the same Dart executable that was used to compile it:

```bash
# Compile test runner (automatically injects current Dart path)
dart run tools/test.dart --compile-runner

# Compile with custom dart path
dart run tools/test.dart --compile-runner --dart-path /path/to/dart

# Use the compiled runner (uses injected Dart path automatically)
./test_runner --test=literals.lua

# Override Dart path in compiled runner if needed
./test_runner --test=literals.lua --dart-path /different/dart
```

**Key Features:**
- **Automatic Dart Path Injection**: The compiled test runner automatically uses the same Dart executable that compiled it
- **User Override**: You can still override the Dart path with `--dart-path` if needed
- **Path Verification**: Both the test runner and lualike compiler show which Dart executable they're using
- **Cross-platform**: Works on Windows (`.exe` extension) and Unix systems

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

# Use custom Dart executable
dart run tools/test.dart --dart-path /usr/local/dart/bin/dart --verbose
```

### Development Workflow

```bash
# 1. Compile lualike
dart run tools/test.dart --force-compile

# 2. Run tests
dart run tools/test.dart --test=your_test.lua

# 3. Compare with reference Lua
dart run tools/compare.dart "your_lua_code_here"
```

### CI/CD Usage

```bash
# Use specific Dart version
dart run tools/test.dart --dart-path /usr/local/dart/bin/dart --force-compile

# Compile test runner for faster execution
dart run tools/test.dart --compile-runner --dart-path /usr/local/dart/bin/dart

# Run with compiled runner
./test_runner --verbose

# Override Dart path in compiled runner
./test_runner --dart-path /different/dart --verbose
```

### Dart Path Injection Examples

```bash
# Compile test runner (captures current Dart path)
dart run tools/test.dart --compile-runner
# Output: Using Dart executable: /home/user/fvm/versions/3.35.1/bin/cache/dart-sdk/bin/dart

# Use compiled runner (automatically uses captured Dart path)
./test_runner --test=literals.lua
# Output: Using Dart executable: /home/user/fvm/versions/3.35.1/bin/cache/dart-sdk/bin/dart

# Override Dart path in compiled runner
./test_runner --dart-path dart --test=literals.lua
# Output: Using Dart executable: dart
```

## Troubleshooting

### Common Issues

1. **Compilation fails**: Ensure Dart SDK is properly installed and in PATH
2. **Tests fail**: Check that the lualike binary exists and is executable
3. **Permission errors**: On Unix systems, ensure the lualike binary has execute permissions
4. **Custom dart path not found**: Verify the path to the Dart executable is correct

### Debug Mode

For debugging test issues, you can enable verbose logging:

```bash
# Run with verbose output
dart run tools/test.dart --verbose --test=problematic_test.lua

# Use debug logging in the interpreter
dart run tools/test.dart --test=test.lua
# Then in the test, use: LOGGING_ENABLED=true
```
