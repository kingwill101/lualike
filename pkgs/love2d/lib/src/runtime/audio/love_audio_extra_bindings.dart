library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

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
  if (_loveAudioExtrasInstalled[runtime] == true) {
    return;
  }

  final audioTable = _audioModuleTable(runtime);
  if (audioTable == null) {
    return;
  }

  for (final entry in _loveAudioEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    audioTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }

  final activeSourceCount = audioTable['getActiveSourceCount'];
  if (activeSourceCount != null) {
    audioTable['getSourceCount'] = activeSourceCount;
  }

  _loveAudioExtrasInstalled[runtime] = true;
}

/// Returns the current `love.audio` module table when it is available.
Map<dynamic, dynamic>? _audioModuleTable(LuaRuntime runtime) {
  final love = runtime.getCurrentEnv().get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final audio = loveTable['audio'];
  final audioTable = audio is Value ? audio.raw : audio;
  if (audioTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return audioTable;
}
