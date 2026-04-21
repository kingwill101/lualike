library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../../generated/love_api_reference.g.dart' show loveApiEnums;

final Expando<bool> _loveFontExtrasInstalled = Expando<bool>(
  'love2dFontExtrasInstalled',
);

final Map<String, Object?> _loveHintingModeEnumMap = _buildHintingModeEnumMap();

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

void installLoveFontExtraBindings(LuaRuntime runtime) {
  if (_loveFontExtrasInstalled[runtime] == true) {
    return;
  }
  _loveFontExtrasInstalled[runtime] = true;

  final enumValue = Value(Map<String, Object?>.from(_loveHintingModeEnumMap));
  runtime.globals.define('HintingMode', enumValue);

  final fontTable = _fontModuleTable(runtime);
  if (fontTable == null) {
    return;
  }

  fontTable['HintingMode'] = enumValue;
}

Map<dynamic, dynamic>? _fontModuleTable(LuaRuntime runtime) {
  final love = runtime.globals.get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final font = loveTable['font'];
  final fontTable = font is Value ? font.raw : font;
  if (fontTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return fontTable;
}
