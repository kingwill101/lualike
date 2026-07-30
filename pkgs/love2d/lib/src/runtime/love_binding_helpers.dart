import 'package:lualike/library_builder.dart';

import 'love_module_table_helpers.dart';

/// Shared context for LOVE module bindings.
LibraryContext loveBindingContext(LuaRuntime runtime) {
  return LibraryContext(
    environment: runtime.getCurrentEnv(),
    interpreter: runtime,
  );
}

/// Shared builder for LOVE module bindings.
BuiltinFunctionBuilder loveBindingBuilder(LuaRuntime runtime) {
  return BuiltinFunctionBuilder(loveBindingContext(runtime));
}

/// Installs LOVE bindings for [moduleName] once per [runtime].
///
/// Returns `true` when [install] ran and the module was available.
bool loveInstallModuleBindings({
  required LuaRuntime runtime,
  required Expando<bool> installed,
  required String moduleName,
  required void Function(LuaRuntime runtime, Map<dynamic, dynamic> moduleTable)
      install,
}) {
  if (installed[runtime] == true) {
    return false;
  }

  final moduleTable = loveModuleTable(runtime, moduleName);
  if (moduleTable == null) {
    return false;
  }

  install(runtime, moduleTable);
  installed[runtime] = true;
  return true;
}
