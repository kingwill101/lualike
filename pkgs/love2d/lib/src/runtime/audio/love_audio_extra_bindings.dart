library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../love_binding_helpers.dart';
import '../../generated/love_api_reference.g.dart' show loveApiEnums;

/// Whether the extra audio bindings have already been installed for a runtime.
final Expando<bool> _loveAudioExtrasInstalled = Expando<bool>(
  'love2dAudioExtrasInstalled',
);

/// Cached LOVE audio enum tables keyed by exported symbol name.
final Map<String, Map<String, Object?>> _loveAudioEnumMaps =
    _buildLoveAudioEnumMaps();

/// Builds Lua-ready enum tables for the `love.audio` module.
Map<String, Map<String, Object?>> _buildLoveAudioEnumMaps() {
  final result = <String, Map<String, Object?>>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.module != 'love.audio') {
      continue;
    }

    result[enumDoc.symbol] = <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return result;
}

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
  for (final entry in _loveAudioEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    audioTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }

  final activeSourceCount = audioTable['getActiveSourceCount'];
  if (activeSourceCount != null) {
    audioTable['getSourceCount'] = activeSourceCount;
  }
}
