## ADDED Requirements
### Requirement: Bytecode Arithmetic Operators
The bytecode compiler and VM SHALL support modulo (`%`), floor division (`//`), and exponent (`^`) binary expressions with behaviour identical to the AST interpreter.

#### Scenario: Bytecode Modulo Execution
- **GIVEN** a script `return a % b`
- **AND** both operands are provided via globals or literals
- **WHEN** the script runs in bytecode mode
- **THEN** the compiler emits `MOD`
- **AND** the VM produces the same result as the AST interpreter, including string-to-number coercion.

#### Scenario: Bytecode Floor Division Execution
- **GIVEN** a script `return a // b`
- **WHEN** it executes under bytecode mode
- **THEN** the VM yields the floor-division result matching the interpreter, raising the same errors for invalid operands.

#### Scenario: Bytecode Exponent Execution
- **GIVEN** a script `return a ^ b`
- **WHEN** it runs under bytecode mode
- **THEN** the emitted bytecode uses `POW`
- **AND** the VM delivers identical results (including coercion) as the AST interpreter.
