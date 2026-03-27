## 0.1.0
 - Add a production-ready Lua bytecode engine, including source execution, direct chunk loading, coroutine support, and full stock-suite coverage.
 - Expand Lua 5.5 language and runtime compatibility across the parser, interpreter, standard library, and vendored suite coverage.
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
