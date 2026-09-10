import 'package:lualike/lualike.dart' show EngineMode, LuaRuntime;

import 'filesystem/love_filesystem_package_loader.dart';
import 'filesystem/love_filesystem_runtime.dart';
import 'love_binding_helpers.dart' show installLoveRuntimeBindings;
import 'love_runtime.dart';

/// Attaches runtime state, installs LOVE bindings, and synchronizes filesystem
/// package interop in the required order.
LoveRuntimeContext bootstrapLoveRuntime({
  required LuaRuntime runtime,
  LoveHost? host,
  LoveFilesystemAdapter? filesystemAdapter,
  EngineMode? engineMode,
  required bool automaticGc,
}) {
  final context = LoveRuntimeContext.attach(
    runtime,
    host: host,
    engineMode: engineMode,
    automaticGc: automaticGc,
  );
  context.applyGcPolicy(runtime);
  LoveFilesystemState.attach(runtime, adapter: filesystemAdapter);
  installLoveRuntimeBindings(runtime);
  syncLoveFilesystemPackageInterop(runtime);
  return context;
}
