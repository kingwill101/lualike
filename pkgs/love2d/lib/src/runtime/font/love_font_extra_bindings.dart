library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../love_module_table_helpers.dart';
import '../../generated/love_api_reference.g.dart' show loveApiEnums;

/// Tracks which runtimes already have font extra bindings installed.
final Expando<bool> _loveFontExtrasInstalled = Expando<bool>(
  'love2dFontExtrasInstalled',
);

/// The generated hinting-mode enum table exposed through the LOVE font module.
final Map<String, Object?> _loveHintingModeEnumMap = _buildHintingModeEnumMap();

/// Builds the Lua-facing `HintingMode` enum table for `love.font`.
Map<String, Object?> _buildHintingModeEnumMap() {
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.symbol != 'HintingMode') {
      continue;
    }

    return <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }

  return const <String, Object?>{
    'normal': 'normal',
    'light': 'light',
    'mono': 'mono',
    'none': 'none',
  };
}

/// Installs font-specific extra bindings into [runtime].
void installLoveFontExtraBindings(LuaRuntime runtime) {
  if (_loveFontExtrasInstalled[runtime] == true) {
    return;
  }
  _loveFontExtrasInstalled[runtime] = true;

  final enumValue = Value(Map<String, Object?>.from(_loveHintingModeEnumMap));
  runtime.globals.define('HintingMode', enumValue);

  final fontTable = loveModuleTable(runtime, 'font');
  if (fontTable == null) {
    return;
  }

  fontTable['HintingMode'] = enumValue;
}
