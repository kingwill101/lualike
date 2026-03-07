## ADDED Requirements
### Requirement: Bytecode Function Call Support
The bytecode compiler and VM SHALL support Lua function invocation and return semantics using the `CALL`, `TAILCALL`, and `RETURN*` opcode family so that bytecode mode matches the AST interpreter for standard function calls.

#### Scenario: Direct Function Call
- **GIVEN** a script `return inc(1)` where `inc` is a Lua function `function inc(x) return x + 1 end`
- **WHEN** it runs in bytecode mode
- **THEN** the compiler emits `CALL` and `RETURN` opcodes for both `inc` and the caller
- **AND** the VM returns `2` exactly as the AST interpreter does.

#### Scenario: Tail Call Optimisation
- **GIVEN** `function recurse(n) if n == 0 then return 0 else return recurse(n - 1) end end`
- **WHEN** the script executes in bytecode mode
- **THEN** the compiler emits `TAILCALL` for the tail position invocation
- **AND** the VM avoids growing the call stack, matching interpreter behaviour.

#### Scenario: Vararg Function Receives Arguments *(Planned)*
- **GIVEN** `function collect(...) return ... end`
- **WHEN** `return collect(1, 2, 3)` runs in bytecode mode
- **THEN** the compiler inserts the necessary `VARARGPREP`/`VARARG` handling
- **AND** the VM returns `1, 2, 3`, matching the AST interpreter once vararg lowering is implemented.
