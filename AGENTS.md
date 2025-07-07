Lualike is a lua interpreter written in Dart. It is designed to be a drop-in replacement for Lua, allowing you to run Lua scripts with minimal changes.

1. **Always run the full Dart test suite**
   Before submitting or merging any code changes, ensure that the entire Dart test suite passes. This helps catch regressions and unintended side effects.

2. **Verify nothing is broken**
   After making changes, confirm that all existing functionality works as expected. Do not assume that passing a subset of tests is sufficient.

3. **Address test failures individually**
   If any test fails, address each failure one at a time.
   Add useful debug output to make it easier to understand what's happening.
   Logger class has a Logger.setEnabled(false);
   - which works with --debug flag when using the interpreter (dart run bin/main.dart) Note it can be very noisy.
   - you can  use the LOGGING_ENABED  environment to the vm example: "dart --define=LOGGING_ENABLED=true run test test/stdlib/base_test.dart" will show the debug output.

   Compare results with the reference lua interpreter when uncertain. our interpreter supports the same cli arguments as the reference lua interpreter.

4. **Prefer targeted test cases**
   When fixing bugs or investigating issues, write dedicated test cases that isolate the failing expression or behavior.
   - Avoid repeatedly running the full test suite/complete lua script just to reproduce a single error.
   - Construct minimal test cases that include all necessary functions, variables, and context to trigger the issue.
   - When testing lua scripts,  write test cases for hard bugs so we do not regress on them in the future.

5. **General best practices**
   - Keep code changes minimal and focused.
   - Document any non-obvious decisions or workarounds in code comments.
   - Communicate clearly in pull requests or code reviews about the changes made and why.
   - there is a docs directory, update it where necessary.

6. **Use the dartfmt tool**
   - Use the dartfmt tool to format your code according to the Dart style guide.
   - run dart fix --apply to apply any fixes suggested by the tool.
7. **Follow Dart's style guide**
   Adhere to the Dart style guide for code formatting and organization. This ensures consistency and readability across the codebase.

## Commands
- `dart test` - Run all tests
- `dart test test/path/specific_test.dart` - Run single test file
- `dart test --name "test name"` - Run specific test by name
- `dart --define=LOGGING_ENABLED=true run test test/path/test.dart` - Run test with debug logging
- `dart format .` - Format all code
- `dart fix --apply` - Apply automated fixes
- `dart analyze` - Static analysis (uses package:lints/recommended.yaml)
- `just integrate` - Run integration tests (see justfile for variants) (not currently working)
- `dart run bin/main.dart --debug` - Run interpreter with debug logging

## Architecture
**Core:** Lua interpreter written in Dart. Grammar in `lib/src/parsers/lua.dart`, AST in `lib/src/ast.dart`, interpreter engine in `lib/src/interpreter/`.
**Key modules:** `lib/src/value.dart` (Lua values), `lib/src/stdlib/` (standard library), `lib/src/environment.dart` (scoping).
**Tests:** Organized by category (stdlib, interop, interpreter) with tags in dart_test.yaml.

## Code Style (Cursor Rules Applied)
- Follow Dart style guide: lowerCamelCase variables/methods, UpperCamelCase classes
- dart: imports first, then package: imports, then relative imports
- Lines ≤80 chars, use dart format
- Use curly braces for all flow control
- Constants in lowerCamelCase (not SCREAMING_CAPS)
- File/package names: lowercase_with_underscores

## Lualike Documentation
- Focus on user perspective, not implementation details
- Never mention Dart internals, class names, or file structure
- Use small Lua code examples to illustrate features
- Refer to language as "lualike", not "Lua"

## Command-Line Interface (CLI)

The lualike CLI is a drop-in replacement for the Lua CLI, supporting similar arguments and additional features for debugging and logging.

### Common Flags
- `--ast`         : Run using AST interpreter (default)
- `--bytecode`    : Run using bytecode VM
- `-e code`       : Execute string 'code' inline
- `--debug`       : Enable debug mode (and set logging to FINE level for all categories)
- `--level LEVEL` : Set log level (FINE, INFO, WARNING, SEVERE, etc)
- `--category CAT`: Set log category to filter (only logs for this category)
- `--help`        : Show help message

If no script or code is provided, starts REPL mode.

### Logging and Filtering
- Use `--debug` for verbose logging (all categories, FINE level) and to activate general debug features.
- Use `--level` to set the minimum log level (e.g., `--level WARNING`).
- Use `--category` to filter logs to a specific category (e.g., `--category Value`).
- You can combine `--level` and `--category` for fine-grained log control.
- Environment variables:
  - `LOGGING_ENABLED=true` enables logging in all modes (including tests).
  - `LOGGING_LEVEL=FINE` sets the default log level.

### Examples
- Run a script with debug logging:
  ```sh
  lualike --debug myscript.lua
  ```
- Run inline code and show only Value logs at FINE level:
  ```sh
  lualike --category Value --level FINE -e "1+1 >> 100"
  ```
- Run in REPL mode with warnings only:
  ```sh
  lualike --level WARNING
  ```
- Run with environment variable logging:
  ```sh
  LOGGING_ENABLED=true LOGGING_LEVEL=INFO lualike myscript.lua
  ```

See the CLI documentation in `docs/cli.md` for more details and advanced usage.
