## ADDED Requirements
### Requirement: Bytecode Branching Support
The bytecode compiler and VM SHALL execute conditional and loop constructs using Lua 5.4 branching opcodes with behaviour matching the AST interpreter (including truthiness and short-circuit semantics).

#### Scenario: If/Else Bytecode
- **GIVEN** a script `if cond then a = 1 else a = 2 end`
- **WHEN** it runs in bytecode mode
- **THEN** the compiler emits the necessary `TEST`/`JMP` sequence
- **AND** the VM follows the same branch the AST interpreter would for all truthy/falsy inputs.

#### Scenario: While Loop Bytecode
- **GIVEN** a script `while i < 3 do i = i + 1 end`
- **WHEN** executed under bytecode mode
- **THEN** the loop iterates exactly as under the AST interpreter, honoring truthiness each iteration.

#### Scenario: Short-Circuit Boolean Bytecode
- **GIVEN** an expression `return cond and compute()`
- **WHEN** the script runs in bytecode mode
- **THEN** the compiler emits branching opcodes to skip the function call when `cond` is falsy
- **AND** the VM matches the AST interpreter behaviour, including side effects only when expected.
