## ADDED Requirements
### Requirement: Bytecode Multiple Return Values
The bytecode compiler and VM SHALL support Lua `return` statements with multiple expressions so that the last expression forwards all results when it is a function call or `...`, matching AST interpreter semantics.

#### Scenario: Returning Multiple Named Values
- **GIVEN** `function pair() local a, b = 1, 2; return a, b end`
- **WHEN** `return pair()` executes in bytecode mode
- **THEN** the compiler emits a `RETURN` instruction that yields both values
- **AND** the VM produces `1, 2` exactly as the AST interpreter does.

#### Scenario: Trailing Call In Return Forwards All Results
- **GIVEN** `function collect(...) return helper(...) end`
- **AND** `helper` itself returns three numbers
- **WHEN** `collect(1, 2, 3)` runs in bytecode mode
- **THEN** the compiler lowers the final call so all helper results are forwarded
- **AND** the VM returns `1, 2, 3`.

### Requirement: Bytecode Multi-Target Assignment
The bytecode compiler SHALL lower assignments and local declarations with multiple targets so that trailing calls or `...` provide additional values, unused results are discarded, and missing values become `nil`, matching Lua rules.

#### Scenario: Local Declaration With Vararg Source
- **GIVEN** `local function source(...) return ... end`
- **AND** `local x, y, z = source(4, 5)`
- **WHEN** the script executes in bytecode mode
- **THEN** `x == 4`, `y == 5`, and `z == nil`
- **AND** the compiler emits bytecode that mirrors the AST interpreter.

#### Scenario: Assignment Uses Trailing Call Results
- **GIVEN** `local a, b; function pair() return 7, 8 end`
- **WHEN** `a, b = pair()` executes in bytecode mode
- **THEN** the compiler emits bytecode that stores both results into `a` and `b`
- **AND** the VM updates the locals exactly as in AST mode.
