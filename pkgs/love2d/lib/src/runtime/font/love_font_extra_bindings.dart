library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../love_binding_helpers.dart';
import '../love_module_table_helpers.dart';

/// Tracks which runtimes already have font extra bindings installed.
final Expando<bool> _loveFontExtrasInstalled = Expando<bool>(
  'love2dFontExtrasInstalled',
);

/// The generated hinting-mode enum table exposed through the LOVE font module.
final Map<String, Object?> _loveHintingModeEnumMap =
    loveEnumMapForSymbol('HintingMode');

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
