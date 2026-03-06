## MODIFIED Requirements

### Requirement: Source Is Lowered Directly To Lua Bytecode
The system SHALL provide a source compilation path that lowers AST through
shared semantic analysis directly to `lua_bytecode`, without routing
through `lualike_ir`.

#### Scenario: Source execution can select the bytecode emitter path
- **WHEN** a caller selects the `lua_bytecode` source engine for a program
  inside the supported emitted subset
- **THEN** the system compiles the source through the `lua_bytecode`
  emitter path and executes the emitted chunk through the `lua_bytecode`
  runtime
- **AND** it does not reinterpret the source through `lualike_ir` or the
  AST interpreter for that execution path
