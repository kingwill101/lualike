## 1. Extend Loop Lowering

- [x] 1.1 Add generic `for` lowering through the supported `TFOR*` bytecode family.
- [x] 1.2 Add `repeat ... until` lowering with the correct body-first order and repeat-scope visibility.
- [x] 1.3 Keep labels / `goto` and other unsupported control-flow families explicitly diagnostic.

## 2. Validate End To End

- [x] 2.1 Add emitted-chunk tests for generic `for` and `repeat ... until`.
- [x] 2.2 Compare emitted opcode families against `luac55` where the loop shape is stable enough to be meaningful.
- [x] 2.3 Re-run the `test/lua_bytecode` suite after the new loop families land.

## 3. Refresh The Roadmap

- [x] 3.1 Update the roadmap and contributor docs to reflect the expanded iterative-control-flow subset and name the next emitter gap.
