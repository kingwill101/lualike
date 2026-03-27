## Why
Bytecode mode still rejects core Lua patterns that rely on multiple return values or multi-target assignments. Statements like `return a, b` currently throw `UnsupportedError`, and assignments such as `local x, y = f()` cannot be lowered because the compiler only handles a single target/expression. Until multi-value semantics are supported, large parts of the standard library and user scripts must fall back to the AST interpreter.

## What Changes
- Extend the bytecode compiler so `return` statements, assignments, and local declarations propagate multiple results, including tail expressions that are function calls or `...`.
- Ensure the VM respects the `RETURN`/`CALL` operands for variable result counts so bytecode execution matches AST behaviour.
- Add regression coverage exercising multi-value returns, chained assignments, and vararg propagation in bytecode mode.

## Impact
- Affected capability: `execution-runtime`
- Key modules: `lib/src/bytecode/compiler.dart`, `lib/src/bytecode/vm.dart`, executor parity tests.
