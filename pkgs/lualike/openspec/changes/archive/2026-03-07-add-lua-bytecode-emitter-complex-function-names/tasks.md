## 1. Extend Function-Definition Lowering

- [x] 1.1 Lower dotted function-name paths to qualified table stores in the structured emitter.
- [x] 1.2 Lower method-style function names with the correct implicit `self` parameter.
- [x] 1.3 Keep unsupported function-definition forms explicitly diagnostic.

## 2. Validate End To End

- [x] 2.1 Add emitted-chunk tests for dotted and method-style function definitions.
- [x] 2.2 Add source-engine coverage for the supported complex function-name subset.
- [x] 2.3 Re-run the `test/lua_bytecode` suite after complex function-name lowering lands.

## 3. Refresh The Roadmap

- [x] 3.1 Update the roadmap and contributor docs to reflect complex function-name support and name the next emitter gap.
