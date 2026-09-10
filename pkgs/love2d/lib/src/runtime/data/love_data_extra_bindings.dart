library;

import 'package:lualike/lualike.dart' show LuaRuntime;

import '../love_binding_helpers.dart';

/// Whether the extra data bindings have already been installed for a runtime.
final Expando<bool> _loveDataExtrasInstalled = Expando<bool>(
  'love2dDataExtrasInstalled',
);

/// Cached LOVE data enum tables keyed by exported symbol name.
final Map<String, Map<String, Object?>> _loveDataEnumMaps =
    loveEnumMapsForModule('love.data');

/// Installs generated enum tables into `love.data`.
void installLoveDataExtraBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveDataExtrasInstalled,
    moduleName: 'data',
    install: _installLoveDataExtraBindings,
  );
}

void _installLoveDataExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> dataTable,
) {
  loveInstallEnumTables(runtime, dataTable, _loveDataEnumMaps);
}
