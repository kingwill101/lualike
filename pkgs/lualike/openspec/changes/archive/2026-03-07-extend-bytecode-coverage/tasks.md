## 1. Opcode Inventory & Infrastructure
- [x] 1.1 Produce an authoritative opcode matrix (compiler responsibility, VM handling, blockers) sourced from Lua 5.4 `lopcodes.h`.
- [x] 1.2 Identify cross-cutting infrastructure needs (register allocator upgrades, frame model, constant pools, debug info) and document dependencies.

## 2. Expression & Metamethod Support
- [x] 2.1 Plan emission/VM work for arithmetic, bitwise, comparison, unary, and concatenation opcodes, including metamethod fallback requirements.
- [x] 2.2 Document numeric coercion and string handling strategies to match AST interpreter behaviour.

## 3. Variable & Function Semantics
- [x] 3.1 Outline tasks for locals, upvalues, varargs, closures, and to-be-closed variables (`MOVE`, `GETUPVAL`, `SETUPVAL`, `CLOSURE`, `VARARG`, `TBC`, `CLOSE`).
- [x] 3.2 Plan register allocation and environment management updates needed to support the above opcodes.

## 4. Table Operations & Iteration
- [x] 4.1 Map emitter/VM tasks for table access/set opcodes and table construction (`NEWTABLE`, `SETLIST`).
- [x] 4.2 Plan iterator support (`TFORPREP`, `TFORCALL`, `TFORLOOP`) including interaction with metamethods and coroutine safety.

## 5. Control Flow & Calls
- [x] 5.1 Define tasks for jumps/tests (`JMP`, `TEST`, `TESTSET`, etc.) and numeric loops (`FORPREP`, `FORLOOP`).
- [x] 5.2 Plan call/tailcall/return opcode handling, stack frame layout, and coroutine integration.

## 6. Tooling & Validation
- [x] 6.1 Specify test coverage expansion (unit, integration, fuzz/parity) for each opcode group.
- [x] 6.2 Outline benchmarking milestones and documentation updates for bytecode parity.
