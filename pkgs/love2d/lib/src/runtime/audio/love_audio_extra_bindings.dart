library;

import 'package:lualike/lualike.dart' show LuaRuntime;

import '../love_binding_helpers.dart';

/// Whether the extra audio bindings have already been installed for a runtime.
final Expando<bool> _loveAudioExtrasInstalled = Expando<bool>(
  'love2dAudioExtrasInstalled',
);

/// Cached LOVE audio enum tables keyed by exported symbol name.
final Map<String, Map<String, Object?>> _loveAudioEnumMaps =
    loveEnumMapsForModule('love.audio');

/// Installs generated enum tables and compatibility aliases into `love.audio`.
void installLoveAudioExtraBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveAudioExtrasInstalled,
    moduleName: 'audio',
    install: _installLoveAudioExtraBindings,
  );
}

void _installLoveAudioExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> audioTable,
) {
  loveInstallEnumTables(runtime, audioTable, _loveAudioEnumMaps);

  final activeSourceCount = audioTable['getActiveSourceCount'];
  if (activeSourceCount != null) {
    audioTable['getSourceCount'] = activeSourceCount;
  }
}
