## ADDED Requirements
### Requirement: Bytecode Literal Comparison Support
The bytecode compiler and VM SHALL handle comparisons against literal operands using the appropriate constant/immediate opcodes with behaviour identical to the AST interpreter.

#### Scenario: Equality Against Literal Constant
- **GIVEN** a script `return a == "foo"`
- **WHEN** it runs in bytecode mode
- **THEN** the compiler emits an equality opcode using the literal constant without loading it into a register
- **AND** the VM returns the same boolean result as the AST interpreter.

#### Scenario: Relational Comparison Against Numeric Literal
- **GIVEN** a script `return x < 10`
- **WHEN** it runs under bytecode mode
- **THEN** the compiler emits an immediate comparison opcode (`LTI`)
- **AND** the VM matches the AST interpreter's numeric coercion and truthiness semantics.
