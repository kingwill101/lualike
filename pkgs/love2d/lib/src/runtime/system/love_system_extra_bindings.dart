library;

import 'package:lualike/lualike.dart' show LuaRuntime;

import '../love_binding_helpers.dart';

/// Tracks which runtimes already have system extra bindings installed.
final Expando<bool> _loveSystemExtrasInstalled = Expando<bool>(
  'love2dSystemExtrasInstalled',
);

/// The generated enum tables exposed through the LOVE system module.
final Map<String, Map<String, Object?>> _loveSystemEnumMaps =
    loveEnumMapsForModule('love.system');

/// Installs generated system enum tables into [runtime].
void installLoveSystemExtraBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveSystemExtrasInstalled,
    moduleName: 'system',
    install: _installLoveSystemExtraBindings,
  );
}

void _installLoveSystemExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> systemTable,
) {
  loveInstallEnumTables(runtime, systemTable, _loveSystemEnumMaps);
}
