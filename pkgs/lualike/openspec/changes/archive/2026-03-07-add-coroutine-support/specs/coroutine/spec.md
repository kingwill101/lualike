## ADDED Requirements
### Requirement: Coroutine Creation And Resumption
The coroutine library SHALL expose `create` and `resume` so that:
- `coroutine.create(fn)` returns a resumable thread value tied to `fn`'s closure.
- The first `coroutine.resume(thread, ...)` call starts `fn` with the provided arguments and returns `true` followed by any values produced by `fn` until it yields or returns.
- Subsequent resumes deliver arguments into `coroutine.yield(...)` calls and return `true` followed by the yielded values, or `false` plus an error message if the coroutine errors or is dead.

#### Scenario: Resuming A Coroutine Returns Values
- **GIVEN** `fn = function(a, b) return a + b end`
- **AND** `co = coroutine.create(fn)`
- **WHEN** `coroutine.resume(co, 2, 3)` is executed
- **THEN** it returns `true` and `5`

#### Scenario: Resuming Dead Coroutine Fails
- **GIVEN** `co = coroutine.create(function() return 1 end)`
- **AND** `coroutine.resume(co)` has been called once
- **WHEN** `coroutine.resume(co)` is called again
- **THEN** it returns `false` and "cannot resume dead coroutine"

### Requirement: Coroutine Yielding And Introspection
The coroutine library SHALL support cooperative yielding and state inspection so that:
- `coroutine.yield(...)` suspends the running coroutine and produces its values to the resumer.
- `coroutine.running()` returns the currently running thread and a boolean that is `true` when it is the main thread.
- `coroutine.status(thread)` returns `"running"`, `"suspended"`, `"normal"`, or `"dead"` according to Lua 5.4 semantics.
- `coroutine.isyieldable()` reflects whether the current thread may yield (false for the main thread).

#### Scenario: Yield Passes Values Between Resume Calls
- **GIVEN** `co = coroutine.create(function() local x = coroutine.yield(10); return x * 2 end)`
- **WHEN** `coroutine.resume(co)` is called
- **AND** the result `true, 10` is observed
- **AND** `coroutine.resume(co, 21)` is called
- **THEN** it returns `true` and `42`

#### Scenario: Status Reflects Coroutine Lifecycle
- **GIVEN** `co = coroutine.create(function() coroutine.yield(); end)`
- **WHEN** no resume has happened yet
- **THEN** `coroutine.status(co)` returns `"suspended"`
- **WHEN** `coroutine.resume(co)` is running inside `co`
- **THEN** `coroutine.status(co)` returns `"running"`
- **WHEN** `coroutine.resume(co)` returns after the yield
- **THEN** `coroutine.status(co)` returns `"suspended"`
- **WHEN** `coroutine.resume(co)` is called again and `co` terminates
- **THEN** `coroutine.status(co)` returns `"dead"`

### Requirement: Coroutine Wrap And Close
The coroutine library SHALL provide helpers for wrapping and closing coroutines so that:
- `coroutine.wrap(fn)` returns a callable value that resumes `fn` automatically and raises Lua errors on failure.
- `coroutine.close(thread[, err])` transitions a live coroutine to `dead`, returning `true` for a clean close or `false` plus an error message if it is closed with an error object.
- Wrapped coroutines respect `coroutine.yield` semantics, relaying yielded values sequentially.

#### Scenario: Wrap Propagates Errors As Lua Errors
- **GIVEN** `wrapped = coroutine.wrap(function() error("boom") end)`
- **WHEN** `wrapped()` is invoked
- **THEN** it raises a Lua error with message "boom"

#### Scenario: Close Returns Status Tuple
- **GIVEN** `co = coroutine.create(function() coroutine.yield() end)`
- **AND** `coroutine.resume(co)` has been called once
- **WHEN** `coroutine.close(co)` is invoked
- **THEN** it returns `true`
- **WHEN** `coroutine.close(co, "fatal")` is invoked on a fresh live coroutine
- **THEN** it returns `false` and "fatal"
