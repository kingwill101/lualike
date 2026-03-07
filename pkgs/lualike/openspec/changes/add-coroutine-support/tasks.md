## 1. Specification
- [x] 1.1 Author coroutine capability deltas (requirements + scenarios)

## 2. Implementation
- [x] 2.1 Implement coroutine.create/resume/yield/status/wrap/close/isyieldable using interpreter Coroutine runtime
- [x] 2.2 Ensure interpreter + GC properly track coroutine lifecycle (register, status, weak refs)
- [x] 2.3 Gate hot-path debug logging with lazy builders or `Logger.enabled` checks
- [x] 2.4 Add focused Lua/Dart tests covering coroutine library, GC coroutine interactions, and performance regression harness if possible
- [x] 2.5 Update docs for coroutine support and logging guidance (if applicable)
- [x] 2.6 Run `dart test` and lua suite spot checks (`./test_runner --test=gc.lua`, `calls.lua`, `bitwise.lua`)

## Next Change
- After completing this change, continue with
  `build-lua-bytecode-emitter-foundation`.
