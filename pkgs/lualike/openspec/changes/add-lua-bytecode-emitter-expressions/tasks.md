## 1. Expand Expression Lowering

- [ ] 1.1 Implement literal, local, and global expression emission for the
      supported subset.
- [ ] 1.2 Implement supported unary, binary, and concatenation expression
      emission.
- [ ] 1.3 Implement supported table access, method-selection, and call
      expression emission.

## 2. Tighten Register Discipline

- [ ] 2.1 Ensure emitted expression chunks respect the runtime's proven
      register and open-result contracts.
- [ ] 2.2 Fail explicitly for unsupported expression families instead of
      emitting speculative bytecode.

## 3. Validate End To End

- [ ] 3.1 Add parse/disassembly/execution tests for emitted expression
      chunks.
- [ ] 3.2 Compare emitted behavior against source execution and `luac55`
      behavior where meaningful.

## 4. Update The Roadmap

- [ ] 4.1 Refresh `openspec/lua_bytecode_roadmap.md` and contributor docs
      to show the expanded emitter subset.

## Next Change

- After completing this change, continue with
  `add-lua-bytecode-emitter-control-flow`.
