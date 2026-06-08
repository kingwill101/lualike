## 0.2.0

- Improve runtime performance with centralized raw slot access, primitive wrapper
  optimization, reduced value wrapper churn, and eliminated BigInt round-trips in
  hot arithmetic paths.
- Improve parser throughput with scanner-backed Lua fast paths, direct dispatch for
  statements and calls, binary format parsing without BigInt, and token/span caching.
- Optimize bytecode VM with cached register writes, local metadata, dead-local
  cleanup, and reduced coroutine/wrapper overhead.
- Add web-compatible 64-bit byte_data compatibility layer and overhaul web REPL UI.
- Add DevTools profiler with bytecode mode and parser profiling snapshot tooling.
- Add `--all-engines` test flag to cycle AST, IR, and lua-bytecode engines.
- Fix IO file tracking to scope per interpreter instead of static global.
- Fix value key hash canonicalization and vararg string key distinctness.
- Fix bytecode coroutine frame resolution for IR and protected call result expansion.
- Fix IR varargs and high arithmetic operand lowering, loop local preservation.
- Fix Lua chunk names with Windows-illegal characters in Uri.file().
- Fix non-finite numeric handling in web platform.
- Fix to-be-closed error messages in pcall context.
- Replace dart_console dependency with artisanal.
- Resolve 20+ pre-existing test failures across AST, bytecode, and browser modes.
- Add stdlib documentation and compiled artifact support docs.

## 0.1.0
 - Add a production-ready Lua bytecode engine, including source execution, direct chunk loading, coroutine support, and full stock-suite coverage.
 - Expand Lua 5.5 language and runtime compatibility across the parser, interpreter, standard library, and vendored suite coverage.
 - Improve parser throughput with scanner-backed Lua fast paths, direct dispatch for statement/call/suffix parsing, faster literal and format-string parsing, and committed profiling snapshots/tooling.
 - Improve runtime correctness and performance with substantial GC, coroutine, debug, load, table, and string-path fixes.
 - Refresh the web REPL and browser support, including a fallback editor path and browser-safe numeric helper behavior.
 - Export and document more of the public embedding surface, including parser utilities, library registration helpers, and refreshed guides/reference docs.
 - Run the Lua compatibility suite in both AST and bytecode modes in CI.

## 0.0.1-alpha.2
 - refactor BuiltinFunctions to accept intepreter instance
 - Introduce Library registry
 - No longer depend on a static environment

## 0.0.1-alpha.1

- Initial version.
