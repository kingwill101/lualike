## ADDED Requirements
### Requirement: Unified Runtime Interface
Introduce an abstract runtime surface that SHALL expose the interpreter capabilities required by stdlib modules, GC, value helpers, and coroutine support, allowing multiple execution engines to interoperate without code duplication.

#### Scenario: Stdlib Uses Shared Runtime API
- **GIVEN** the standard library initialization flow
- **WHEN** a library function needs access to globals, coroutine control, or GC registration
- **THEN** it resolves those services through the new runtime interface rather than concrete `Interpreter` methods
- **AND** both the existing AST interpreter and the planned bytecode VM implement the interface.

### Requirement: Bytecode Compilation Pipeline
Provide a compilation path from parsed AST to bytecode chunk using a `CodeEmitter` abstraction that MUST produce function prototypes, instruction streams, and constant pools compatible with Lua semantics.

#### Scenario: AST Lowered to Bytecode Chunk
- **GIVEN** a Lua-like script with loops, closures, and table operations
- **WHEN** the compiler is invoked in bytecode mode
- **THEN** it traverses the AST with the emitter, emits bytecode instructions covering control flow, upvalues, and metamethod hooks
- **AND** assembles a chunk containing function prototypes and constant pools ready for VM execution.

#### Scenario: Instruction Set Mirrors Lua Opcodes
- **GIVEN** the reference opcode table defined in Lua 5.4 `lopcodes.h`
- **WHEN** the bytecode pipeline defines its opcode inventory
- **THEN** each opcode SHALL correspond to a Lua 5.4 instruction (same mnemonic and operand mode) unless a deliberate deviation is documented in the design tasks
- **AND** flags such as the k-bit, extra-argument usage, and test/jump semantics are preserved so runtime behaviour remains Lua-compatible.

### Requirement: Bytecode VM Compatibility
Design the bytecode VM so it MUST execute the emitted chunks while reusing existing runtime components (values, stdlib, GC, coroutines) and maintaining observable behaviour parity with AST interpretation.

#### Scenario: Script Runs Identically Under Bytecode VM
- **GIVEN** a script that exercises stdlib modules, coroutines, and metamethods
- **WHEN** the script runs under the bytecode VM via the unified runtime interface
- **THEN** it produces the same outputs and side effects as the AST interpreter
- **AND** stdlib code remains unchanged.

### Requirement: Execution Mode Selection & Testing
The runtime MUST allow callers to pick AST or bytecode execution and define validation to ensure parity and performance measurement for loop-heavy workloads.

#### Scenario: Bytecode Mode Enabled
- **GIVEN** the CLI or embedding API opts into bytecode mode
- **WHEN** the program executes
- **THEN** the runtime selects the bytecode pipeline and VM
- **AND** automated regression and performance tests compare results and timing against AST execution before rollout.
