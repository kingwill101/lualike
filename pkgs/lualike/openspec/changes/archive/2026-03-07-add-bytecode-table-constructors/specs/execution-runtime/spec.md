## ADDED Requirements
### Requirement: Bytecode Table Constructors
The bytecode compiler and VM SHALL support Lua table constructor expressions so that array and hash fields initialised via `{...}` literals behave identically in bytecode and AST modes.

#### Scenario: Empty Table Literal
- **GIVEN** the script `return {}` executed in bytecode mode
- **THEN** the compiler emits a `NEWTABLE` instruction with zero array/hash slots
- **AND** the VM returns a new table value exactly as the AST interpreter does.

#### Scenario: Sequential Elements
- **GIVEN** `return {1, 2, 3}`
- **WHEN** the script executes in bytecode mode
- **THEN** the compiler emits bytecode that inserts the three values in order
- **AND** the VM produces a table identical to the AST interpreter result.

#### Scenario: Vararg Expansion In Constructor
- **GIVEN** `local function build(...) return {1, 2, ...} end`
- **WHEN** `build(3, 4, 5)` runs in bytecode mode
- **THEN** the compiler lowers the constructor so every argument populates sequential array slots
- **AND** the VM yields `{1, 2, 3, 4, 5}` exactly like the AST interpreter.

#### Scenario: Large Sequential Constructor
- **GIVEN** `return {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51 }`
- **WHEN** the script executes in bytecode mode
- **THEN** the compiler emits multiple `SETLIST` batches to cover every sequential element
- **AND** the VM produces the same table layout as the AST interpreter.

#### Scenario: Mixed Keyed And Sequential Fields
- **GIVEN** `return { foo = 1, [bar()] = 2, 5, six = 6 }`
- **WHEN** the script runs in bytecode mode
- **THEN** keyed fields are applied in order using table store opcodes after `NEWTABLE`
- **AND** the VM yields a table matching AST semantics, including the sequential `5` inserted after keyed assignments.
