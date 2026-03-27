<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Lualike Project Instructions

Lualike is a Lua interpreter written in Dart, designed as a drop-in replacement for Lua with minimal script changes.

## Development Workflow

### Testing
- **Always run full test suite** before submitting/merging changes to catch regressions.
- **Verify functionality** after changes; don't assume subset testing is sufficient.
- **Address failures individually** with debug output.
  - Enable logging: `Logger.setEnabled(false)` (verbose with `--debug` flag).
  - Environment: `LOGGING_ENABLED=true dart test test/path/test.dart`.
- **Compare with reference Lua** when uncertain; supports same CLI arguments.
- **Use targeted tests** for bugs: create minimal test cases instead of full suite runs.
- **Write regression tests** for complex bugs.

### Best Practices
- Keep changes minimal and focused.
- Document non-obvious decisions in comments.
- Update `doc/` directory as needed.
- Use `dart format .` and `dart fix --apply` for code formatting.
- Follow Dart style guide for consistency.

## Commands
- `dart test` - Run all tests
- `dart test test/path/specific_test.dart` - Run single test file
- `dart test --name "test name"` - Run specific test by name
- `LOGGING_ENABLED=true dart test test/path/test.dart` - Run test with debug logging
- `dart tool/test.dart --compile_runner && ./test_runner` - Run integration tests
- `dart format .` - Format all code
- `dart fix --apply` - Apply automated fixes
- `dart analyze` - Static analysis (uses package:lints/recommended.yaml)
- `just integrate` - Run integration tests (see justfile; currently not working)
- `dart run bin/main.dart --debug` - Run interpreter with debug logging

## Architecture
- **Core**: Lua interpreter in Dart.
  - Grammar: `lib/src/parsers/lua.dart`
  - AST: `lib/src/ast.dart`
  - Interpreter: `lib/src/interpreter/`
- **Key Modules**:
  - `lib/src/value.dart` - Lua values
  - `lib/src/stdlib/` - Standard library
  - `lib/src/environment.dart` - Scoping
- **Tests**: Categorized (stdlib, interop, interpreter) with tags in `dart_test.yaml`.

## Code Style
- Follow Dart style: `lowerCamelCase` variables/methods, `UpperCamelCase` classes.
- Import order: `dart:`, then `package:`, then relative.
- Lines ≤80 chars; use `dart format`.
- Use curly braces for all control flow.
- Constants: `lowerCamelCase` (not `SCREAMING_CAPS`).
- File/package names: `lowercase_with_underscores`.

## Documentation Guidelines
- Focus on user perspective, not implementation.
- Never mention Dart internals, class names, or file structure.
- Use small Lua code examples.
- Refer to language as "lualike", not "Lua".

## Command-Line Interface (CLI)

Lualike CLI is a drop-in replacement for Lua CLI with additional debugging features.

### Common Flags
- `--ast` - Run using AST interpreter (default)
- `--ir` - Run using the lualike IR runtime
- `-e code` - Execute string 'code' inline
- `--debug` - Enable debug mode (FINE level logging)
- `--level LEVEL` - Set log level (ALL, FINEST, FINER, FINE, CONFIG, INFO, WARNING, SEVERE, SHOUT, OFF)
- `--category CAT` - Filter logs by category
- `--help` - Show help message

Starts REPL mode if no script/code provided.

### Logging and Filtering
- `--debug`: Verbose logging and debug features.
- `--level`: Set minimum log level (e.g., `--level WARNING`).
- `--category`: Filter by category (e.g., `--category Value`).
- Combine `--level` and `--category` for fine control.
- Environment variables:
  - `LOGGING_ENABLED=true` - Enable logging everywhere
  - `LOGGING_LEVEL=FINE` - Set default log level

### Examples
```sh
lualike --debug myscript.lua                    # Debug script
lualike --category Value --level FINE -e "1+1"  # Filtered inline code
lualike --level WARNING                        # REPL with warnings
LOGGING_ENABLED=true lualike myscript.lua       # Env logging
```

See `doc/cli.md` for advanced usage.
