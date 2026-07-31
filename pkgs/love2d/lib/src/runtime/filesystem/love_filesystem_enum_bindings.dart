library;

import 'package:lualike/lualike.dart' show LuaRuntime;

import '../love_binding_helpers.dart';

/// Tracks which runtimes already have filesystem enum bindings installed.
final Expando<bool> _loveFilesystemEnumsInstalled = Expando<bool>(
  'love2dFilesystemEnumsInstalled',
);

/// The generated filesystem enum tables exposed through the LOVE globals.
final Map<String, Map<String, Object?>> _loveFilesystemEnumMaps =
    loveEnumMapsForModule('love.filesystem');

/// Installs generated filesystem enum tables into [runtime].
void installLoveFilesystemEnumBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveFilesystemEnumsInstalled,
    moduleName: 'filesystem',
    install: _installLoveFilesystemEnumBindings,
  );
}

void _installLoveFilesystemEnumBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> filesystemTable,
) {
  loveInstallEnumTables(runtime, filesystemTable, _loveFilesystemEnumMaps);
}
