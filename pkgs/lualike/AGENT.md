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
    - You can use the `LOGGING_ENABLED` environment variable when running tests, e.g., `LOGGING_ENABLED=true dart test test/stdlib/base_test.dart`.

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
- `LOGGING_ENABLED=true dart test test/path/test.dart` - Run test with debug logging
- `dart format .` - Format all code
- `dart fix --apply` - Apply automated fixes
- `dart analyze` - Static analysis (uses package:lints/recommended.yaml)
- `just integrate` - Run integration tests (see justfile for variants) (not currently working)
- `dart run bin/main.dart --debug` - Run interpreter with debug logging

## Architecture
**Core:** Lua interpreter written in Dart. Grammar in `lib/src/parsers/lua.dart`, AST in `lib/src/ast.dart`, interpreter engine in `lib/src/interpreter/`.
**Key modules:** `lib/src/value.dart` (Lua values), `lib/src/stdlib/` (standard library), `lib/src/environment.dart` (scoping).
**Artifact families:**
- `AST / interpreter`: source parsing and AST execution.
- `lualike_ir`: internal compiled/runtime path under `lib/src/ir/`.
- `lua_bytecode`: real upstream chunk parsing and execution under `lib/src/lua_bytecode/`.
- `legacy AST chunk transport`: compatibility path for AST-backed `string.dump` / `load`, implemented in `lib/src/legacy_ast_chunk_transport.dart`.
**Rule:** Do not describe `lualike_ir` or legacy AST chunks as upstream Lua bytecode. Any real bytecode claim must be backed by `lib/src/lua_bytecode/` plus upstream-generated chunk tests.
**Current `lua_bytecode` subset:** real-chunk parsing, disassembly, routing,
closures/upvalues, loops, varargs, arithmetic/bitwise/unary/concat families,
open-result `CALL`/`RETURN`/`TAILCALL` flow, raw comparison semantics plus the
supported `__eq`/`__lt`/`__le` comparison subset, supported table access/store,
constructor, and length semantics, supported `CLOSE`/`TBC` semantics, and
`SELF`/method-call execution are in scope. Remaining
unsupported areas should stay explicitly diagnostic until implemented.
**Current `lua_bytecode` emitter subset:** direct AST ->
`lib/src/lua_bytecode/` lowering now covers the foundation, expression
slice, and the first structured source subset: literal/local/global
expressions, unary/binary/concat, table access, method selection/calls,
supported call expressions, call expression statements, open-result return
lowering, identifier assignments, `if`, `while`, numeric `for`, generic
`for`, `repeat ... until`, `break`, labels/goto, simple and qualified
`function` / `local function` lowering, nested function literals, captured
local upvalues, supported table constructors, `SETLIST`-backed constructor
batches, trailing open-result constructor entries, and field/index
assignment targets. The supported subset is now wired into an opt-in
source engine via `EngineMode.luaBytecode` and `--lua-bytecode`, and
supported emitted functions dump to real `lua_bytecode` chunks through the
runtime boundary. It remains a real chunk emitter backed by the same
binary serializer/parser/runtime stack and must not lower through
`lualike_ir`. Unsupported control-flow forms and unsupported goto
visibility cases should stay explicitly diagnostic until their runtime and
oracle coverage exists.
**Tests:** Organized by artifact family and category with tags in `dart_test.yaml`; see `test/README.md`.
**Coroutine runtime:** The coroutine stdlib path is exercised from
`test/stdlib/coroutine_library_test.dart`. Lifecycle regressions should
prefer focused coroutine tests, especially around weak-table reachability,
`collectgarbage`, and resume/close edge cases.
**Bytecode coroutines:** `lua_bytecode` coroutine coverage lives in
`test/lua_bytecode/execution_test.dart` and
`test/lua_bytecode/source_engine_test.dart`. Validate both upstream-chunk
and source-engine paths before claiming new bytecode coroutine support.
**Logging in hot paths:** In GC and coroutine internals, use
`Logger.debugLazy` / `Logger.infoLazy` or guard eager logs with
`Logger.enabled`. Do not add interpolated `Logger.debug(...)` calls inside
allocation, mark/sweep, or resume/yield loops.

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
- `--ir`          : Run using the lualike IR runtime
- `--lua-bytecode`: Run supported source through the opt-in `lua_bytecode` engine
- `-e code`       : Execute string 'code' inline
- `--debug`       : Enable debug mode (and set logging to FINE level for all categories)
- `--level LEVEL` : Set log level. Valid levels: `ALL`, `FINEST`, `FINER`, `FINE`, `CONFIG`, `INFO`, `WARNING`, `SEVERE`, `SHOUT`, `OFF`. Invalid levels default to `WARNING`.
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
