## ADDED Requirements

### Requirement: Source Is Lowered Directly To Lua Bytecode
The system SHALL provide a source compilation path that lowers AST through
shared semantic analysis directly to `lua_bytecode`, without routing
through `lualike_ir`.

#### Scenario: The emitter foundation avoids the IR backend
- **WHEN** the system compiles a source program through the
  `lua_bytecode` emitter path
- **THEN** the emitted chunk is produced directly from AST analysis and
  `lua_bytecode` builders
- **AND** the path does not depend on `lualike_ir` instruction classes or
  IR lowering as an intermediate representation

### Requirement: The Emitter Foundation Produces Real Executable Chunks
The system SHALL emit real `lua_bytecode` chunks for the supported
foundation subset.

#### Scenario: Minimal emitted programs execute through the runtime
- **WHEN** the emitter compiles a program in the supported foundation
  subset
- **THEN** the output is a real `lua_bytecode` chunk that can be parsed,
  disassembled, and executed by the `lua_bytecode` runtime
- **AND** the observed behavior matches the expected source semantics for
  that subset
