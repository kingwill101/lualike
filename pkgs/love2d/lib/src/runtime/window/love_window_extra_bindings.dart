library;

import 'package:lualike/lualike.dart' show LuaRuntime;

import '../love_binding_helpers.dart';

/// Tracks which runtimes already have window extra bindings installed.
final Expando<bool> _loveWindowExtrasInstalled = Expando<bool>(
  'love2dWindowExtrasInstalled',
);

/// The generated enum tables exposed through the LOVE window module.
final Map<String, Map<String, Object?>> _loveWindowEnumMaps =
    loveEnumMapsForModule('love.window');

/// Installs generated window enum tables and aliases into [runtime].
void installLoveWindowExtraBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveWindowExtrasInstalled,
    moduleName: 'window',
    install: _installLoveWindowExtraBindings,
  );
}

void _installLoveWindowExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> windowTable,
) {
  loveInstallEnumTables(runtime, windowTable, _loveWindowEnumMaps);

  final dpiScale = windowTable['getDPIScale'];
  if (dpiScale != null) {
    windowTable['getNativeDPIScale'] = dpiScale;
  }
}
