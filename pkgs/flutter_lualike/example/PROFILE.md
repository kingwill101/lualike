# Reproducible LuaLike allocation profiling

This app has a dedicated profile-mode entry point. It compiles one fixed Lua
program at startup, warms the VM, then measures identical steady-state calls.
The capture resets Dart VM allocation accumulators immediately before every
sample and subtracts an immediate pre-run snapshot from the post-run snapshot.
The subtraction matters because the VM includes already-live objects in reset
totals. Compilation, Flutter startup, warm-up, and retained objects from prior
runs are therefore excluded.

## Automated capture

From this directory, run:

```sh
flutter pub get
dart run tool/capture_allocations.dart \
  --flutter=/absolute/path/to/flutter \
  --app-dir=. \
  --target=lib/profile_main.dart \
  --device=macos \
  --warmup-runs=2 \
  --samples=5 \
  --iterations=10000 \
  --scenarios=steady-bytecode,fresh-ast \
  --output=benchmark/flutter_allocations/latest.json
```

Use the same Flutter revision, device, run counts, and iteration count for
before/after comparisons. Do not compare debug-mode captures with profile-mode
captures. Each JSON report contains the inputs, every class allocation row,
and a median summary for `Value` and `Environment`. `steady-bytecode` measures
calls through one compiled runtime; `fresh-ast` measures a fresh AST execution
and exercises scope/environment creation as well as value churn.

## Inspect in Dart DevTools

Run the visual harness with:

```sh
flutter run --profile -d macos -t lib/profile_main.dart
```

Open the printed DevTools link, select **Memory**, force GC, reset accumulated
allocations, click **Run 10,000 iterations**, and take an allocation snapshot.
Filter the class table for `Value` and `Environment`. Repeat at least five
times after two warm-up runs; compare medians, not a single run.

The harness is profiling-only. It does not alter the LuaLike runtime.
