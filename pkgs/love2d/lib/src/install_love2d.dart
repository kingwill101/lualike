library;

import 'package:lualike/lualike.dart' show EngineMode, LuaRuntime;

import 'runtime/filesystem/love_filesystem_runtime.dart';
import 'runtime/filesystem/love_filesystem_bindings.dart'
    show ensureLoveFilesystemRuntimeBindingsLoaded;
import 'runtime/love_api_bindings.dart';
import 'runtime/love_runtime.dart';
import 'runtime/love_runtime_bootstrap.dart';

/// Attaches a [LoveHost] and filesystem state to an existing [runtime].
///
/// This is useful when the generated LOVE bindings are already installed and a
/// host needs to be replaced or configured separately.
///
/// Automatic Lualike GC safe points are disabled unless [automaticGc] is true.
void attachLoveHost({
  required LuaRuntime runtime,
  required LoveHost host,
  LoveFilesystemAdapter? filesystemAdapter,
  EngineMode? engineMode,
  bool automaticGc = false,
}) {
  final context = LoveRuntimeContext.attach(
    runtime,
    host: host,
    engineMode: engineMode,
    automaticGc: automaticGc,
  );
  context.applyGcPolicy(runtime);
  LoveFilesystemState.attach(runtime, adapter: filesystemAdapter);
}

/// Installs the LOVE API surface into [runtime].
///
/// This wires up the generated API tables, runtime-specific compatibility
/// bindings, host integration, and filesystem state expected by the LOVE 11.5
/// compatibility layer.
///
/// Automatic Lualike GC safe points are disabled unless [automaticGc] is true.
void installLove2d({
  required LuaRuntime runtime,
  LoveHost? host,
  LoveFilesystemAdapter? filesystemAdapter,
  EngineMode? engineMode,
  bool automaticGc = false,
}) {
  ensureLoveApiRuntimeBindingsLoaded();
  ensureLoveFilesystemRuntimeBindingsLoaded();
  bootstrapLoveRuntime(
    runtime: runtime,
    host: host,
    filesystemAdapter: filesystemAdapter,
    engineMode: engineMode,
    automaticGc: automaticGc,
  );
}
