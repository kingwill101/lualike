## 1. Expand Expression Lowering

- [x] 1.1 Implement literal, local, and global expression emission for the
      supported subset.
- [x] 1.2 Implement supported unary, binary, and concatenation expression
      emission.
- [x] 1.3 Implement supported table access, method-selection, and call
      expression emission.

## 2. Tighten Register Discipline

- [x] 2.1 Ensure emitted expression chunks respect the runtime's proven
      register and open-result contracts.
- [x] 2.2 Fail explicitly for unsupported expression families instead of
      emitting speculative bytecode.

## 3. Validate End To End

- [x] 3.1 Add parse/disassembly/execution tests for emitted expression
      chunks.
- [x] 3.2 Compare emitted behavior against source execution and `luac55`
      behavior where meaningful.

## 4. Update The Roadmap

- [x] 4.1 Refresh `openspec/lua_bytecode_roadmap.md` and contributor docs
      to show the expanded emitter subset.

## Next Change

- After completing this change, continue with
  `add-lua-bytecode-emitter-control-flow`.
