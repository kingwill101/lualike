## Unreleased

- Bytecode density (Lua **5.5** / `luac55` baseline): peephole folds
  `ARITH tmp; MMBIN*; MOVE dest,tmp` into in-place `ARITH dest` and
  `LOAD* tmp; MOVE dest,tmp` into `LOAD* dest`. Integer `FORLOOP` and
  binary arithmetic fast paths use `storeRegisterRaw` for private
  transients. Soft suite remains the Lua 5.5 port tests.
- Loop unrolling still available via
  `CompilePipelineConfig.enableLoopUnrolling` (default off; IR
  constant-bounded `for` up to 64 iters).
- Bytecode VM hot-path tweaks: cheaper opcode decode, coarser GC loop
  safepoints, and `MOVE` via `storeRegisterRaw` (avoids re-cloning values
  that are already frame-safe). Keeps load/store isolation for
  `debug.setlocal`.
- Default `--lua-bytecode` source path: IR + SSA + mechanical lower
  (`CompilePipelineConfig.luaBytecodeOptimized`), with suite-hardening for
  jump compact, TEST/EQI use-def, folded tables, fold inlining isolation,
  and signed immediate compares.
- Precompiled binary chunks are detected by official Lua header only (no
  reserved extension). They load and run on the bytecode VM without
  re-entering the IR/SSA pipeline. `--compile` requires explicit `--output`.

## 0.3.0

- Add `ValueDoc`, `DocDescriptor`, `AccessScope`, `GenericParam`, `OverloadDoc`,
  `OperatorDoc`, `AliasDoc`, `EnumDoc` to core doc model for rich library metadata.
- `LibraryRegistrationContext.define()` now accepts `DocDescriptor` objects
  (`FunctionDescriptor`, `ConstantDescriptor`, `AliasDescriptor`, `EnumDescriptor`,
  `TableDescriptor`) for structured library registration.
- Add full LuaLS annotation support across all three renderers: deprecated, async,
  nodiscard, scope, generic, overload, alias, enum, operator, see, source, version,
  and type annotations for ValueDoc constants.
- Add `CompositeFileSystemBackend` to core lualike for layered filesystem backends.
- Consolidate extension dispatch: `unwrap()` on `Object?`, `Value.rawObject` getter,
  and `Map.unwrap(key)` that properly handles `LuaString` conversion.
- Add `DerivedDocumentedLibrary` mixin for composing library metadata.
- Expose new doc model types in public API (`package:lualike/lualike.dart`).
- Document math constants (`pi`, `huge`, `maxinteger`, `mininteger`) and `_VERSION`
  via `ValueDoc`.

## 0.2.4

- Add public `setFileSystemProvider()` API to bridge `package:lualike`'s
  `FileSystemProvider` into the built-in `IOLib.fileSystemProvider`.
- Fix `file_lualike` `io.open()` routing: `useFileSystem()` now assigns the
  configured `FileSystemProvider` to `IOLib.fileSystemProvider` so `io.open()` /
  `io.lines()` / `io.input()` / `io.output()` / `io.tmpfile()` all delegate to
  the remote/backend filesystem instead of falling through to local `dart:io`.

## 0.2.3

- Add `FileSystemBackend` abstract class with `setFileSystemBackend`/`currentFileSystemBackend` injection point for pluggable filesystem metadata backends.
- Export `IODevice`, `FileSystemProvider`, `FileSystemBackend`, `file_system_utils.dart` from `package:lualike/lualike.dart` (web-safe; no `dart:io` in public signatures).

## 0.2.2

- Add `@TableSchema()` / `@SchemaField()` annotations and `table_schema` build_runner builder
  for auto-generating `TableDoc` constants from Dart classes.
- Add `FieldDoc` and `TableDoc` types to `lib/src/stdlib/doc.dart`.
- Extract `MetadataFormat` into `metadata_format.dart` for web-safe exports from `docs.dart`.
- Add CSS styles for section toggles in `web/docs.html`.
- Rewrite `example/table_doc_example.dart` to use only built-in types.
- Add `example/builder_demo/` demonstrating all registration mechanisms (annotations,
  BuiltinFunction, ValueClass, constants, table schemas).
- Update README with annotations/builder documentation and example links.

## 0.2.1

- Fix bytecode coroutine yield-through-pcall regression caused by premature
  `exitProtectedCall` in `_ProtectedCallSuspension.resume()`.
- Add `LuaLike.register(Library)` convenience shorthand.
- Add `LuaLike.fileManager` getter for easy access to virtual file/module API.
- Re-export `Library` base class from `package:lualike/lualike.dart`.
- Update README with feature demonstrations, inline docs pattern, and
  custom I/O backend documentation.

## 0.2.0

- Improve runtime performance with centralized raw slot access, primitive wrapper
  optimization, reduced value wrapper churn, and eliminated BigInt round-trips in
  hot arithmetic paths.
- Improve parser throughput with scanner-backed Lua fast paths, direct dispatch for
  statements and calls, binary format parsing without BigInt, and token/span caching.
- Optimize bytecode VM with cached register writes, local metadata, dead-local
  cleanup, and reduced coroutine/wrapper overhead.
- Add web-compatible 64-bit byte_data compatibility layer and overhaul web REPL UI.
- Add DevTools profiler with bytecode mode and parser profiling snapshot tooling.
- Add `--all-engines` test flag to cycle AST, IR, and lua-bytecode engines.
- Fix IO file tracking to scope per interpreter instead of static global.
- Fix value key hash canonicalization and vararg string key distinctness.
- Fix bytecode coroutine frame resolution for IR and protected call result expansion.
- Fix IR varargs and high arithmetic operand lowering, loop local preservation.
- Fix Lua chunk names with Windows-illegal characters in Uri.file().
- Fix non-finite numeric handling in web platform.
- Fix to-be-closed error messages in pcall context.
- Replace dart_console dependency with artisanal.
- Resolve 20+ pre-existing test failures across AST, bytecode, and browser modes.
- Add stdlib documentation and compiled artifact support docs.

## 0.1.0
 - Add a production-ready Lua bytecode engine, including source execution, direct chunk loading, coroutine support, and full stock-suite coverage.
 - Expand Lua 5.5 language and runtime compatibility across the parser, interpreter, standard library, and vendored suite coverage.
 - Improve parser throughput with scanner-backed Lua fast paths, direct dispatch for statement/call/suffix parsing, faster literal and format-string parsing, and committed profiling snapshots/tooling.
 - Improve runtime correctness and performance with substantial GC, coroutine, debug, load, table, and string-path fixes.
 - Refresh the web REPL and browser support, including a fallback editor path and browser-safe numeric helper behavior.
 - Export and document more of the public embedding surface, including parser utilities, library registration helpers, and refreshed guides/reference docs.
 - Run the Lua compatibility suite in both AST and bytecode modes in CI.

## 0.0.1-alpha.2
 - refactor BuiltinFunctions to accept intepreter instance
 - Introduce Library registry
 - No longer depend on a static environment

## 0.0.1-alpha.1

- Initial version.
