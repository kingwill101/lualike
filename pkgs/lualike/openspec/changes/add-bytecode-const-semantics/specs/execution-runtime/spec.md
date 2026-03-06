## ADDED Requirements
### Requirement: Bytecode Const Locals
The bytecode compiler and VM MUST honour Lua `<const>` local semantics so that scripts using const locals behave identically under bytecode and AST execution.

#### Scenario: Const Local Initialisation
- **GIVEN** the script `local <const> x = math.mininteger; return x`
- **WHEN** executed in bytecode mode
- **THEN** the compiler emits metadata marking `x` as const and seals its register after initialisation
- **AND** the VM returns `math.mininteger` without raising an error.

#### Scenario: Const Reassignment Error
- **GIVEN** the script `local <const> x = 1; x = 2`
- **WHEN** executed in bytecode mode
- **THEN** the VM raises `attempt to assign to const variable`
- **AND** the stack trace points at the reassignment line.

#### Scenario: Const Multi-Value Binding
- **GIVEN** the script `local <const> a, b = 1, 2; return a, b`
- **WHEN** executed in bytecode mode
- **THEN** both locals are initialised correctly, sealed after assignment, and returned as `1, 2`.
