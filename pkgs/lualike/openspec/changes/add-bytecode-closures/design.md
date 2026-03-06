# Design: Bytecode Closures, Upvalues, and Varargs

## Goals
- Produce nested bytecode prototypes for every Lua function definition/literal.
- Execute bytecode closures (with captured upvalues) inside the VM’s call stack.
- Handle Lua varargs (`...`) via `VARARGPREP` and `VARARG` so bytecode mode mirrors the AST interpreter.

## Breaking the Work into Two Stages
1. **Stage A – Closures & Upvalues (no varargs yet)**
   - Emit child prototypes and `CLOSURE` instructions.
   - Track lexical locals to populate `BytecodeUpvalueDescriptor`s.
   - Extend the VM with a stack of frames (register array, PC, prototype ref, upvalues).
   - Execute `CLOSURE` to instantiate closure values, capture required registers, and extend `CALL`/`TAILCALL` to run bytecode closures.
   - Add tests covering nested closures, recursion, and upvalue reads.
2. **Stage B – Vararg Support**
   - During prototype creation, mark `isVararg` from `FunctionBody.isVararg`.
   - Emit `VARARGPREP` at function entry when `isVararg == true`.
   - Lower `VarArg` expressions to `VARARG` instructions, respecting Lua’s last-argument multi-value semantics.
   - Extend VM frames with `varargs` storage, implement opcodes, and test forwarding (`function f(...) return ... end`).

## Stage A Details (Closures & Upvalues)
### Compiler Changes
- **Prototype Context Updates**: pass parameter names, vararg flag, and parent scope to new `_PrototypeContext` instances. Ensure parameter registers are allocated and stored in `_localScopes` so closures can capture them.
- **Child Prototype Emission**: for each `FunctionBody`, call a new `builder.createChild()`, build the nested context, and record its index for the eventual `CLOSURE` instruction.
- **Function Definitions**:
  - `FunctionDef` / `LocalFunctionDef` emit `CLOSURE` followed by `SETTABUP`/`SETTABLE`/assignments depending on target (global, table field, local register).
  - Function literals emit `CLOSURE` and return the destination register.
- **Upvalues**: when encountering identifiers not found in the current scope, treat them as upvalues. Record `inStack/index` in the child builder’s `upvalueDescriptors`.

### VM Changes
- **Frame Structure**: create a `BytecodeFrame` class with registers, prototype pointer, PC, varargs placeholder, and captured upvalues.
- **Call Stack**: `BytecodeVm.execute` pushes an initial frame (instead of using a flat register list). `CALL` creates new frames when callee is a `BytecodeClosure`; `TAILCALL` replaces the current frame.
- **BytecodeClosure**: new value type storing prototype and upvalues. `CLOSURE` constructs it using the current frame’s registers per descriptor.
- **Return Handling**: adapt existing `RETURN0/RETURN1` logic to pop frames and propagate values to the caller.

### Tests (Stage A)
- Compiler snapshots for a simple nested function verifying the child prototype and opcodes.
- VM test building a chunk with `function outer(x) return function() return x end end` and ensuring closure returns `x`.
- Executor test invoking nested closures and recursion to confirm parity with AST interpreter.

## Stage B Details (Varargs)
### Compiler
- If `FunctionBody.isVararg`, emit `VARARGPREP` at the start of the prototype.
- Lower `VarArg` nodes to `VARARG` instructions; for tail positions (`return ...`) set `B = 0` to request all remaining args.
- Ensure vararg functions capture their fixed parameters and continue to use upvalue logic from Stage A.

### VM
- Extend `BytecodeFrame` with `varargs` list; `VARARGPREP` copies arguments beyond the fixed parameter count into that list.
- Implement `VARARG`: if `B == 0`, return all; otherwise return the requested count padded with nil.
- Ensure `CALL` passes arguments to the new frame while respecting vararg semantics and that `RETURN` pushes multi-values back to the caller.

### Tests (Stage B)
- Compiler tests verifying `VARARGPREP` and `VARARG` emission.
- VM tests: `function collect(...) return ... end`, `return (...), select(2, ...)`, and nested vararg forwarding.
- Executor integration verifying bytecode mode handles vararg recursion and tail vararg returns the same as AST.

## Dependencies & Risks
- Requires updating `BytecodePrototype` to serialize nested prototypes and upvalue descriptors.
- Call stack mistakes could lead to leaks or infinite loops—unit tests and instrumentation will help catch this early.
- Upvalues: start with simple lexical capture; avoid cross-function assignment until base behaviour is stable.

## Next Steps
- Implement Stage A (closures/upvalues) with targeted tests.
- Verify bytecode parity on representative scripts.
- Proceed to Stage B (varargs), expanding test coverage accordingly.
