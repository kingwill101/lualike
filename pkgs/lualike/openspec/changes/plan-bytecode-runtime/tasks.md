## 1. Investigation
- [x] 1.1 Catalogue every `Interpreter` API consumed by `lib/src/stdlib`, `lib/src/value.dart`, and other runtime helpers; group them by capability (environment, coroutine, GC, IO).
- [x] 1.2 Map current execution flow (`executeCode` → `Interpreter.run`) and note seams available for plugging alternative engines.

## 2. Runtime Interface Design
- [x] 2.1 Draft the proposed runtime interface/mixin exposing only the capabilities discovered in Investigation, with notes on how the AST interpreter already satisfies each surface.
- [x] 2.2 Identify adjustments needed in shared components (e.g., `LibraryRegistry`, `Environment`, `Value`) to depend on the interface instead of the concrete interpreter.

## 3. Bytecode Pipeline Planning
- [x] 3.1 Define the bytecode chunk layout (instruction format, constant pool, upvalue representation) and map Lua control-flow constructs to instructions, leveraging the txtlang register-VM lessons.
- [x] 3.2 Specify the Dart-side `CodeEmitter` abstraction and lowering path from AST to bytecode along with required compiler passes (upvalue analysis, loop lowering, constant folding hooks).
- [x] 3.3 Outline the bytecode VM execution model (call frames, coroutine handling, error reporting) and its reuse of existing runtime components.
- [x] 3.4 Catalogue Lua 5.4 opcode semantics (per `lopcodes.h`) and ensure the planned instruction set matches or intentionally documents deviations, including k-flag handling and extra-arg coordination.

## 4. Compatibility & Validation Strategy
- [x] 4.1 Produce a compatibility plan ensuring stdlib modules and user scripts can switch between AST and bytecode modes without modification (API invariants, feature coverage).
- [x] 4.2 Define benchmarking and regression test coverage comparing AST vs bytecode execution for loop-heavy workloads.
- [x] 4.3 Summarize rollout steps (feature flags, configuration, documentation updates) and identify open risks or follow-ups.
