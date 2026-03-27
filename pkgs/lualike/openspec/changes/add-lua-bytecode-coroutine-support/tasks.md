## 1. Coroutine Model

- [x] 1.1 Generalize the shared coroutine state model so it can own a bytecode continuation as well as the existing AST-oriented execution path.
- [x] 1.2 Define the bytecode continuation snapshot structure needed to preserve frames, registers, resume payloads, and supported close-state across yields.
- [x] 1.3 Update shared coroutine lifecycle bookkeeping so current coroutine, current environment, and close behavior remain consistent for bytecode-backed threads.

## 2. Bytecode VM Support

- [x] 2.1 Teach the `lua_bytecode` VM to treat supported yield paths as suspension boundaries instead of terminal errors.
- [x] 2.2 Implement resume-from-suspension for the saved bytecode continuation state and deliver resume arguments back into the yielded call boundary.
- [x] 2.3 Preserve or explicitly reject closeable-resource and unsupported coroutine bytecode paths with clear diagnostics.

## 3. Validation

- [x] 3.1 Add targeted `lua_bytecode` runtime tests for create/resume/yield/status/wrap/close over supported bytecode-backed functions.
- [x] 3.2 Add oracle-backed upstream chunk fixtures for supported coroutine bytecode paths.
- [x] 3.3 Add source-engine tests proving supported coroutine programs run through emitted `lua_bytecode` without AST or `lualike_ir` fallback.
- [x] 3.4 Update roadmap/spec sync notes after the implementation is green.
