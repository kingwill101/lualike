## Purpose

Define the contract for loading, executing, and validating real upstream
Lua binary chunks through the `lua_bytecode` runtime path.

## Requirements

### Requirement: Lua Bytecode Is Implemented As A Separate Runtime
The system SHALL provide a `lua_bytecode` runtime path that is separate
from `lualike_ir` and from the AST interpreter.

#### Scenario: Runtime path selection distinguishes Lua bytecode from IR
- **WHEN** a caller requests execution of a real upstream Lua binary chunk
  for the vendored release line
- **THEN** the system routes execution through the `lua_bytecode` path
- **AND** it does not reinterpret the artifact as `lualike_ir` or legacy
  AST chunk transport

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

#### Scenario: Table access and store follow upstream chunk semantics
- **WHEN** a real upstream chunk performs table field, integer-key, or
  generic-key access and store operations
- **THEN** the `lua_bytecode` runtime follows the tracked upstream table
  semantics for the supported instruction set
- **AND** the behavior is validated with targeted upstream-generated
  fixtures

#### Scenario: Table construction honors `NEWTABLE` / `SETLIST` / `EXTRAARG`
- **WHEN** a real upstream chunk constructs tables using list-style writes
  or constructor patterns emitted by the tracked `luac`
- **THEN** the runtime honors the register, index, and `EXTRAARG`
  semantics required by those chunk patterns
- **AND** the resulting table contents match upstream execution

#### Scenario: `LEN` follows upstream semantics for supported table cases
- **WHEN** a real upstream chunk applies `LEN` to values covered by the
  current runtime subset
- **THEN** the runtime follows the tracked upstream semantics for strings,
  supported table cases, and supported `__len` behavior
- **AND** unsupported cases fail explicitly instead of silently returning a
  container-specific shortcut

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

#### Scenario: Unsupported comparison paths fail explicitly
- **WHEN** a real upstream chunk reaches a comparison or ordering path that
  is still outside the current `lua_bytecode` runtime subset
- **THEN** the runtime fails with an explicit `lua_bytecode` diagnostic
- **AND** it does not silently fall back to host-language comparison rules
