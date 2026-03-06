## MODIFIED Requirements

### Requirement: Lua Binary Chunks Are Parsed And Executed According To Upstream Semantics
The system SHALL parse, disassemble, and execute real upstream Lua binary
chunks according to the semantics defined by the vendored Lua release
line.

#### Scenario: Upstream `luac` chunks are accepted
- **WHEN** a binary chunk produced by upstream `luac` for the tracked
  release line is loaded
- **THEN** the system parses the chunk as `lua_bytecode`
- **AND** execution follows upstream opcode, vararg, call/return, loop,
  upvalue, table, and close semantics for the supported instruction set of
  that release line

#### Scenario: Newly supported opcode families are validated with real chunks
- **WHEN** the runtime adds support for an additional upstream opcode
  family
- **THEN** the behavior is validated with targeted chunks produced by the
  tracked upstream `luac`
- **AND** the tests assert real execution results, not only parser or
  disassembler output

### Requirement: Lua Bytecode Compatibility Claims Are Backed By Real Chunk Behavior
The system SHALL only claim upstream Lua bytecode compatibility for
artifacts and loaders that operate on real chunk structures for the
tracked release line.

#### Scenario: Compatibility messaging matches actual support
- **WHEN** a runtime path, tool, or API advertises Lua bytecode
  compatibility
- **THEN** it accepts real upstream Lua chunks as produced by tooling for
  the tracked release line
- **AND** it does not rely on synthetic headers or AST payload transport
  to satisfy that claim

#### Scenario: Unsupported upstream instructions fail explicitly
- **WHEN** a real upstream chunk reaches an opcode or semantic path the
  current `lua_bytecode` runtime does not yet implement
- **THEN** the runtime fails with an explicit `lua_bytecode` diagnostic
  naming the unsupported instruction or path
- **AND** it does not silently reinterpret the chunk through `lualike_ir`
  or legacy AST transport
