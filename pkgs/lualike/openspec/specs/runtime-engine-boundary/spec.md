## Purpose

Define the shared engine-facing runtime boundary used by the AST
interpreter, `lualike_ir`, and `lua_bytecode`.

## Requirements

### Requirement: Shared Runtime Services Are Exposed Through An Engine Boundary
The system SHALL expose shared runtime services used by the AST
interpreter, `lualike_ir`, and `lua_bytecode` through explicit
engine-facing contracts instead of direct engine-specific coupling.

#### Scenario: Shared runtime behavior is consumed through interfaces
- **WHEN** an execution engine needs shared services such as values,
  environments, tables, metamethod behavior, or stdlib integration
- **THEN** it uses the shared engine boundary
- **AND** it does not depend directly on another engine's internal
  representations

### Requirement: Stdlib Behavior Is Reused Across Engines Without Engine Leakage
The system SHALL allow stdlib behavior to be reused across AST,
`lualike_ir`, and `lua_bytecode` execution paths without requiring the
stdlib layer to depend directly on AST-only or IR-only implementation
details.

#### Scenario: Stdlib load and dump operations use engine capabilities
- **WHEN** stdlib functionality needs engine-specific behavior such as
  loading, dumping, or executing compiled artifacts
- **THEN** the stdlib calls the active engine through the shared boundary
- **AND** engine-specific loading and serialization logic remains outside
  the stdlib implementation

### Requirement: Engine-Specific Artifacts Remain Isolated
The system SHALL keep AST transport artifacts, `lualike_ir` artifacts, and
upstream Lua bytecode artifacts isolated so tests, tooling, and
implementation work can target each contract independently.

#### Scenario: Tests and tools target the correct artifact family
- **WHEN** tests, debuggers, serializers, or disassemblers are run
- **THEN** they declare whether they target AST transport, `lualike_ir`,
  or `lua_bytecode`
- **AND** success in one artifact family does not imply compatibility with
  the others
