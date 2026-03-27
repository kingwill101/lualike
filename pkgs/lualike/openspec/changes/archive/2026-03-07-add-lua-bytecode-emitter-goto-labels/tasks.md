## 1. Add Label And Goto Lowering

- [x] 1.1 Track emitted labels and pending goto fixups inside the structured compiler.
- [x] 1.2 Lower supported `Label` and `Goto` nodes to patched `JMP` instructions.
- [x] 1.3 Keep unresolved or unsupported goto visibility cases explicitly diagnostic.

## 2. Validate End To End

- [x] 2.1 Add emitted-chunk tests for supported label/goto control flow.
- [x] 2.2 Add diagnostic tests for unresolved or unsupported goto targets.
- [x] 2.3 Re-run the `test/lua_bytecode` suite after label/goto lowering lands.

## 3. Refresh The Roadmap

- [x] 3.1 Update the roadmap and contributor docs to reflect label/goto support and name the next emitter gap.
