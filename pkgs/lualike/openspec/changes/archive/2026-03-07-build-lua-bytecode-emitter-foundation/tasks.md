## 1. Define The Compiler Boundary

- [x] 1.1 Add or document the emitter module boundary and the shared
      semantic-analysis facts needed for the foundation subset.
- [x] 1.2 Ensure the design explicitly rejects AST -> `lualike_ir` ->
      `lua_bytecode` lowering.

## 2. Build The Foundation

- [x] 2.1 Implement chunk/prototype/instruction builder scaffolding for
      emitted `lua_bytecode`.
- [x] 2.2 Implement a minimal compile entrypoint for the supported
      foundation subset.
- [x] 2.3 Add any debug or disassembly hooks needed to inspect emitted
      chunks during tests.

## 3. Validate End To End

- [x] 3.1 Add tests that parse, disassemble, and execute emitted foundation
      chunks.
- [x] 3.2 Compare the emitted subset against upstream behavior or `luac55`
      output where the shape is stable enough to be meaningful.

## 4. Document The Boundary

- [x] 4.1 Update the roadmap and contributor docs to describe the new
      emitter foundation and its current limits.

## Next Change

- After completing this change, continue with
  `add-lua-bytecode-emitter-expressions`.
