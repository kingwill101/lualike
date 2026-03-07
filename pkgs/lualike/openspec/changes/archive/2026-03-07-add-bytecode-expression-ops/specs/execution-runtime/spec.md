## ADDED Requirements
### Requirement: Bytecode Expression Opcode Support
The bytecode compiler/VM SHALL execute bitwise, comparison, and unary expressions with the same observable behaviour as the AST interpreter.

#### Scenario: Bitwise Expression Bytecode
- **GIVEN** a script `return (a & 3) | 1`
- **AND** `a` is defined in the global environment
- **WHEN** the script runs in bytecode mode
- **THEN** the compiler emits bitwise opcodes
- **AND** the VM evaluates the result identical to the AST interpreter.

#### Scenario: Comparison Expression Bytecode
- **GIVEN** a script `return x < y`
- **WHEN** it executes in bytecode mode
- **THEN** the VM returns the same boolean value produced by the AST interpreter for all numeric inputs.

#### Scenario: Unary Expression Bytecode
- **GIVEN** a script `return not flag`
- **WHEN** it runs in bytecode mode
- **THEN** truthiness semantics match the AST interpreter output.
