## 1. Extend Constructor Lowering

- [x] 1.1 Add builder support for `SETLIST` / `EXTRAARG` constructor emission.
- [x] 1.2 Lower contiguous array constructor batches through buffered `SETLIST` flushing.
- [x] 1.3 Lower supported trailing open-result constructor entries such as `{f()}` and keep unsupported constructor mixes explicitly diagnostic.

## 2. Validate End To End

- [x] 2.1 Add emitted-chunk tests for large array constructors and trailing open-result constructor entries.
- [x] 2.2 Add source-engine coverage for supported `SETLIST`-backed constructor programs.
- [x] 2.3 Re-run the `test/lua_bytecode` suite after `SETLIST` constructor lowering lands.

## 3. Refresh The Roadmap

- [x] 3.1 Update the roadmap and contributor docs to reflect `SETLIST` constructor support and name the next emitter gap.
