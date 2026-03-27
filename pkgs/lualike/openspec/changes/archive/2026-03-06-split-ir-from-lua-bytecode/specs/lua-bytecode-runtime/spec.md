## ADDED Requirements

### Requirement: Lua Bytecode Is Implemented As A Separate Runtime
The system SHALL provide a `lua_bytecode` runtime path that is separate from `lualike_ir` and from the AST interpreter.

#### Scenario: Runtime path selection distinguishes Lua bytecode from IR
- **WHEN** a caller requests execution of a real upstream Lua binary chunk for the vendored release line
- **THEN** the system routes execution through the `lua_bytecode` path
- **AND** it does not reinterpret the artifact as `lualike_ir` or legacy AST chunk transport

### Requirement: Lua Binary Chunks Are Parsed And Executed According To Upstream Semantics
The system SHALL parse, disassemble, and execute real upstream Lua binary chunks according to the semantics defined by the vendored Lua release line.

#### Scenario: Upstream `luac` chunks are accepted
- **WHEN** a binary chunk produced by upstream `luac` for the tracked release line is loaded
- **THEN** the system parses the chunk as `lua_bytecode`
- **AND** execution follows upstream opcode, vararg, call/return, loop, and upvalue semantics for that release line

### Requirement: Lua Bytecode Compatibility Claims Are Backed By Real Chunk Behavior
The system SHALL only claim upstream Lua bytecode compatibility for artifacts and loaders that operate on real chunk structures for the tracked release line.

#### Scenario: Compatibility messaging matches actual support
- **WHEN** a runtime path, tool, or API advertises Lua bytecode compatibility
- **THEN** it accepts real upstream Lua chunks as produced by tooling for the tracked release line
- **AND** it does not rely on synthetic headers or AST payload transport to satisfy that claim
