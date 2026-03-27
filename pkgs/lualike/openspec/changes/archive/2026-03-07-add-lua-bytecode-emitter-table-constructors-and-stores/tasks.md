## 1. Extend Table Lowering

- [x] 1.1 Lower the supported table-constructor subset through `NEWTABLE` and the supported `SET*` families.
- [x] 1.2 Generalize assignment-target lowering to support field and index stores.
- [x] 1.3 Keep unsupported constructor and assignment-target forms explicitly diagnostic.

## 2. Validate End To End

- [x] 2.1 Add emitted-chunk tests for supported constructors and table stores.
- [x] 2.2 Add source-engine coverage for constructor and table-store source programs.
- [x] 2.3 Re-run the `test/lua_bytecode` suite after constructor/store lowering lands.

## 3. Refresh The Roadmap

- [x] 3.1 Update the roadmap and contributor docs to reflect constructor/store support and name the next emitter gap.
