## 1. Add Control-Flow Lowering

- [x] 1.1 Implement label and fixup support for jumps, branches, and loops.
- [x] 1.2 Emit supported statement/control-flow forms for the current
      source subset.

## 2. Add Function And Closure Lowering

- [x] 2.1 Emit supported function bodies, returns, and call/result shaping.
- [x] 2.2 Emit supported closure and upvalue metadata using the shared
      semantic analysis facts.

## 3. Validate End To End

- [x] 3.1 Add emitted-chunk tests for branches, loops, and supported
      nested-function cases.
- [x] 3.2 Compare emitted behavior against source execution and `luac55`
      behavior where meaningful.

## 4. Refresh Documentation

- [x] 4.1 Update the roadmap and contributor docs to reflect the expanded
      emitted source subset.

## Next Change

- After completing this change, continue with
  `integrate-lua-bytecode-source-engine`.
