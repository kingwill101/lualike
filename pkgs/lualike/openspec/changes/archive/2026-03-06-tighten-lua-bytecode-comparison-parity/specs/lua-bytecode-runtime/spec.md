## MODIFIED Requirements

### Requirement: Lua Binary Chunks Are Parsed And Executed According To Upstream Semantics

#### Scenario: Equality and ordering comparisons follow upstream semantics
- **WHEN** a real upstream chunk executes supported comparison opcodes
- **THEN** the `lua_bytecode` runtime follows the tracked upstream equality
  and ordering semantics for the supported instruction set
- **AND** the behavior is validated with targeted upstream-generated
  fixtures

#### Scenario: Supported comparison metamethods are honored
- **WHEN** a supported upstream chunk compares values that require
  `__eq`, `__lt`, or `__le` behavior inside the current runtime envelope
- **THEN** the `lua_bytecode` runtime follows the tracked upstream
  metamethod semantics for those comparisons
- **AND** the result matches upstream execution

### Requirement: Lua Bytecode Compatibility Claims Are Backed By Real Chunk Behavior

#### Scenario: Unsupported comparison paths fail explicitly
- **WHEN** a real upstream chunk reaches a comparison or ordering path that
  is still outside the current `lua_bytecode` runtime subset
- **THEN** the runtime fails with an explicit `lua_bytecode` diagnostic
- **AND** it does not silently fall back to host-language comparison rules
