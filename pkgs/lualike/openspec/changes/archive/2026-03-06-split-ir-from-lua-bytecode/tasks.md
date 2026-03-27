## 1. Rename And Reclassify The Current Bytecode Stack

- [x] 1.1 Rename the current `lib/src/bytecode` modules, public entry points, tools, and test references to `ir` / `lualike_ir` terminology.
- [x] 1.2 Update comments, docs, and user-facing messages so the current compiled path is described as `lualike_ir` instead of upstream Lua bytecode.
- [x] 1.3 Reclassify the existing chunk serializer and related load/dump paths as legacy AST/internal transport rather than the serialization contract for compiled execution.

## 2. Extract The Shared Engine Boundary

- [x] 2.1 Define the engine-facing runtime contract for loading, dumping, executing compiled artifacts, and looking up engine-specific debug metadata.
- [x] 2.2 Refactor shared stdlib entry points such as `load` and `string.dump` to call the active engine through the shared boundary instead of AST-specific or IR-specific internals.
- [x] 2.3 Wire the existing AST interpreter and `lualike_ir` runtime through the new engine boundary without changing shared stdlib semantics.

## 3. Give Lualike IR Its Own Serialization And Tooling Path

- [x] 3.1 Add an IR-specific serialization format and loader for cached execution that does not depend on legacy AST chunk transport.
- [x] 3.2 Update the current compiler, VM, and developer tools to use the `lualike_ir` artifact path end-to-end.
- [x] 3.3 Add or update tests proving cached `lualike_ir` execution works without reconstructing programs through AST transport.

## 4. Split Tests And Correct Mixed Contracts

- [x] 4.1 Reorganize tests and tooling so AST transport, `lualike_ir`, and `lua_bytecode` targets are declared and validated independently.
- [x] 4.2 Rewrite or remove tests and docs that encode IR-specific opcode behavior as if it were real upstream Lua bytecode behavior.
- [x] 4.3 Correct known incorrect Lua expectations, including the generic `for` contract and any other cases verified to disagree with the vendored upstream Lua release line.

## 5. Introduce The Lua Bytecode Chunk Model

- [x] 5.1 Create a new `lua_bytecode` module with exact chunk/header structures, constants, upvalue metadata, and packed instruction decoding for the vendored upstream Lua release line.
- [x] 5.2 Implement a `lua_bytecode` chunk parser and disassembler that accept real upstream `luac` output for the tracked release line.
- [x] 5.3 Add oracle tests that compare parser and disassembler behavior against upstream `lua` / `luac` fixtures for the tracked release line.

## 6. Implement The Lua Bytecode Runtime Path

- [x] 6.1 Add runtime selection and loading so real upstream Lua binary chunks are routed to the new `lua_bytecode` path instead of AST transport or `lualike_ir`.
- [x] 6.2 Implement the initial `lua_bytecode` VM with correct upstream semantics for comparisons/tests, call and return flow, varargs, loops, upvalues, `CLOSE`, and `EXTRAARG`-driven instructions.
- [x] 6.3 Add execution tests using upstream-generated chunks to verify the new runtime matches tracked upstream Lua behavior for the implemented instruction set.

## 7. Finish Migration Guardrails

- [x] 7.1 Add compatibility checks and error messages that prevent legacy AST chunks or `lualike_ir` artifacts from being misidentified as upstream Lua bytecode.
- [x] 7.2 Update contributor documentation so future work distinguishes AST transport, `lualike_ir`, and `lua_bytecode` responsibilities and test suites.
- [x] 7.3 Verify the renamed IR path, shared engine boundary, and new `lua_bytecode` runtime can coexist without regressions in existing shared semantic tests.
