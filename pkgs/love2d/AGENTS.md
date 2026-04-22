# love2d Package Instructions

These instructions apply to work under `pkgs/love2d`.

## Priorities

- Preserve `LÖVE 11.5` behavior first.
- Prefer small, focused changes over broad rewrites.
- Keep compatibility tests authoritative.
- Treat performance regressions, frame-time spikes, and first-use hitches as real regressions, not follow-up work.

## Before Larger Changes

Open these docs before making architectural or performance-heavy changes:

- `doc/flame_feature_adoption_plan.md`
- `doc/love_11_5_compatibility_matrix.md`
- `doc/love_11_5_api_audit.md`

If the change affects Flame integration, viewport ownership, batching, overlays, or input routing, align the work with `doc/flame_feature_adoption_plan.md` instead of inventing a parallel direction.

## Test Helper Rules

Do not copy local Lua-call helper blocks into new tests.

Specifically, do not reintroduce file-local versions of:

- `_call`
- `_callMethod`
- `_rawFunction`
- `_rawMethod`
- `_resolveCallResult`
- `_resolveRawCallResult`
- `_unwrap`

Use the shared helpers in `test/test_support/lua_api_test_helpers.dart`.

### Helper selection

- Use `luaCall` / `luaCallMethod` for the normal case that should unwrap `Value` via `Value.unwrap()`.
- Use `luaCallList` / `luaCallMethodList` when plain `List<Object?>` results should also be treated like multi-return values.
- Use `luaCallRaw` / `luaCallMethodRaw` when the test must preserve `Value.raw` instead of `Value.unwrap()`.
- Use `luaCallRawList` / `luaCallMethodRawList` when both conditions apply:
  - preserve `Value.raw`
  - treat plain `List<Object?>` as multi-return output
- Use `luaResolveRawCallResult` only when the test genuinely needs the raw multi-return shape before unwrapping.

### Extending helper behavior

- If a new test needs behavior not covered by the shared helpers, extend `test/test_support/lua_api_test_helpers.dart`.
- Do not create another one-off local helper set unless the behavior is truly file-specific and cannot be expressed cleanly as a shared option.
- If a test needs a custom unwrapping strategy, prefer adding a named shared helper rather than embedding another private `_unwrap` block in the file.

### Error semantics

- Keep the helper wrappers `async`.
- Synchronous Lua argument/type errors must still surface as failed `Future`s so existing `throwsA(...)` expectations keep working.
- Do not "simplify" the shared helpers into direct returns that change this behavior.

## Testing Expectations

- Run targeted tests for the files and helper variants you touched.
- If shared test infrastructure changes, run a representative matrix that covers:
  - normal unwrap behavior
  - plain-list multi-return behavior
  - raw-value behavior
  - synchronous error-path expectations
- If the change is broad, follow up with a wider `pkgs/love2d` test run before considering it complete.

## Flame And Performance Rules

- Prefer using Flame as the owner of camera, viewport, widget, batching, and input infrastructure when that reduces duplicated logic without weakening parity.
- Do not trade away correctness for "more Flame-native" code.
- Separate first-use hitch reduction from steady-state frame-cost reduction.
- Prefer preload, warmup, event-driven sync, and conservative batching over doing more work during interactive frames.
- Keep fallback paths for unsupported shader, blend, scissor, or texture cases.

## Editing Guidelines

- Keep docs and tests in sync with behavior changes.
- When you remove duplicated infrastructure, leave one clear shared home for the replacement.
- Avoid hidden behavior changes in bulk cleanup passes; verify a representative sample after refactors.
