# Lualike Tools

This directory contains various tools for building, testing, and working with the Lualike interpreter.

## Test Runner (`test.dart`)

The main test runner for executing Lua test suites against the Lualike interpreter. Features intelligent compilation caching, Dart executable path injection, and comprehensive test management.

### Basic Usage

```bash
# Run all tests
dart run tool/test.dart

# Run with verbose output
dart run tool/test.dart --verbose

# Run specific tests
dart run tool/test.dart --test=literals.lua,math.lua

# Skip compilation if binary exists
dart run tool/test.dart --skip-compile

# Force recompilation
dart run tool/test.dart --force-compile

# Use custom Dart executable
dart run tool/test.dart --dart-path /path/to/dart
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
dart run tool/test.dart --compile-runner

# Compile with custom dart path
dart run tool/test.dart --compile-runner --dart-path /path/to/dart

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

The Artisanal command suite for inspecting optimization output. It replaces the
former shell wrappers and routes output through a shared `Console`.

### Usage

```console
# Compare luac55 and lualike disassembly for one file.
dart run tool/compare.dart disasm luascripts/compare/01_arith.lua

# Compare a bundled entrypoint with each separate luac55 module chunk.
dart run tool/compare.dart disasm --bundle \
  luascripts/folding/21_bundle_main.lua

# Compare optimized and unoptimized IR for a file or directory.
dart run tool/compare.dart ir luascripts/folding

# Validate every folding fixture; optionally include full disassembly.
dart run tool/compare.dart folding
dart run tool/compare.dart folding --disassemble
```

Directory disassembly automatically enables bundling for entrypoints with a
static `require("module")`. `LUAC55` overrides the reference compiler path;
lualike output is compiled in-process from the current checkout so a stale
native executable cannot affect comparisons.

## Parser Profile Tool (`parser_profile.dart`)

Focused harness for profiling the PetitParser Lua grammar against small Lua
source files in `luascripts/parser_profiles`.

PetitParser's README recommends small reproducible grammar inputs, the
reflection linter for common inefficient or invalid parser graphs, `trace()`
for parser entry/exit flow, `profile()` for activation counts and inclusive
time, and `progress()` for spotting parser movement and backtracking. This tool
wraps those hooks around Lualike's real `LuaGrammarDefinition`.

### Basic Usage

```bash
# Time the whole parser-profile corpus
dart run tool/parser_profile.dart

# Add PetitParser profile rows for every corpus script
dart run tool/parser_profile.dart --profile --top=20

# Inspect one small case with trace output
dart run tool/parser_profile.dart --case table_shapes --trace --trace-limit=80

# Summarize parser movement and backtracking for one case
dart run tool/parser_profile.dart --case branches_and_loops --progress

# Run the PetitParser grammar linter before timing the corpus
dart run tool/parser_profile.dart --lint

# Include extra Lua files or directories
dart run tool/parser_profile.dart --path luascripts/test/math.lua

# Save a timing snapshot as JSON
dart run tool/parser_profile.dart --label current --json-out benchmarks/parser_profiles/current-small.json

# Compare two saved snapshots and generate Markdown
dart run tool/parser_profile_compare.dart \
  --baseline benchmarks/parser_profiles/baseline-small.json \
  --latest benchmarks/parser_profiles/current-small.json \
  --markdown-out benchmarks/parser_profiles/current-small-summary.md

# Generate baseline/current snapshots and comparison reports automatically
dart run tool/parser_profile_snapshot.dart --baseline-ref origin/ir
```

The default corpus is intentionally small and grammar-shaped rather than a
runtime benchmark. Add new `.lua` files under `luascripts/parser_profiles`
whenever a parser change needs a targeted repro.

`parser_profile_snapshot.dart` creates a temporary detached worktree for the
baseline ref, copies the profiling harness into it, runs the small parser corpus
and hot Lua suite in both trees, then writes JSON and Markdown reports under
`benchmarks/parser_profiles`. That directory is ignored by git, so these
snapshots stay local unless explicitly moved or unignored.


## Examples

### Running Tests

```bash
# Quick test run
dart run tool/test.dart --test=literals.lua --skip-compile

# Full test suite with verbose output
dart run tool/test.dart --verbose

# Run specific test category
dart run tool/test.dart --test=math.lua,bitwise.lua --verbose

# Use custom Dart executable
dart run tool/test.dart --dart-path /usr/local/dart/bin/dart --verbose
```

### Development Workflow

```bash
# 1. Compile lualike
dart run tool/test.dart --force-compile

# 2. Run tests
dart run tool/test.dart --test=your_test.lua

# 3. Compare with reference Lua
dart run tool/compare.dart "your_lua_code_here"
```

### CI/CD Usage

```bash
# Use specific Dart version
dart run tool/test.dart --dart-path /usr/local/dart/bin/dart --force-compile

# Compile test runner for faster execution
dart run tool/test.dart --compile-runner --dart-path /usr/local/dart/bin/dart

# Run with compiled runner
./test_runner --verbose

# Override Dart path in compiled runner
./test_runner --dart-path /different/dart --verbose
```

### Dart Path Injection Examples

```bash
# Compile test runner (captures current Dart path)
dart run tool/test.dart --compile-runner
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
dart run tool/test.dart --verbose --test=problematic_test.lua

# Use debug logging in the interpreter
dart run tool/test.dart --test=test.lua
# Then in the test, use: LOGGING_ENABLED=true
```
