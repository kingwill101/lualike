## ADDED Requirements
### Requirement: Bytecode Closures and Varargs
The bytecode compiler and VM SHALL support Lua function definitions (including nested closures and varargs) using the `CLOSURE`, `CALL`, `TAILCALL`, `VARARGPREP`, and `VARARG` opcodes so bytecode mode matches the AST interpreter for function-heavy scripts.

#### Scenario: Nested Closure Captures Outer Local
- **GIVEN** `function outer(x) return function() return x end end`
- **WHEN** the script runs in bytecode mode
- **THEN** the compiler emits a child prototype and `CLOSURE`
- **AND** the VM returns a callable closure that produces the captured `x` value, matching the AST interpreter.

#### Scenario: Vararg Function Returns All Arguments
- **GIVEN** `function collect(...) return ... end`
- **WHEN** `return collect(1, 2, 3)` executes in bytecode mode
- **THEN** the compiler inserts `VARARGPREP`/`VARARG`
- **AND** the VM returns `1, 2, 3`, identical to the AST interpreter.

#### Scenario: Tail-Recursive Bytecode Function
- **GIVEN** `function fact(n, acc) if n == 0 then return acc else return fact(n - 1, acc * n) end end`
- **WHEN** called in bytecode mode
- **THEN** the compiler emits `TAILCALL` for the recursive branch
- **AND** the VM reuses the frame (no unbounded growth) while computing factorial correctly.
