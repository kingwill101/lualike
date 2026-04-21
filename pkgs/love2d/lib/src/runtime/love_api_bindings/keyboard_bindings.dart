part of '../love_api_bindings.dart';

LoveApiImplementation _bindKeyboardGetKeyFromScancode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.getKeyFromScancode(
    _requireKeyboardScancode(args, 0, 'love.keyboard.getKeyFromScancode'),
  );
}

LoveApiImplementation _bindKeyboardGetScancodeFromKey(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.getScancodeFromKey(
    _requireKeyboardKeyConstant(args, 0, 'love.keyboard.getScancodeFromKey'),
  );
}

LoveApiImplementation _bindKeyboardHasKeyRepeat(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.keyRepeat;
}

LoveApiImplementation _bindKeyboardHasScreenKeyboard(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.screenKeyboardSupported;
}

LoveApiImplementation _bindKeyboardHasTextInput(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.textInputEnabled;
}

LoveApiImplementation _bindKeyboardIsDown(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.isDown(
    _keyboardKeySequence(args, 'love.keyboard.isDown'),
  );
}

LoveApiImplementation _bindKeyboardIsScancodeDown(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.isScancodeDown(
    _keyboardScancodeSequence(args, 'love.keyboard.isScancodeDown'),
  );
}

LoveApiImplementation _bindKeyboardSetKeyRepeat(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.keyboard.keyRepeat = _requireBoolean(
      args,
      0,
      'love.keyboard.setKeyRepeat',
    );
    return null;
  };
}

LoveApiImplementation _bindKeyboardSetTextInput(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final enable = _requireBoolean(args, 0, 'love.keyboard.setTextInput');
    final area = args.length <= 1
        ? null
        : LoveTextInputArea(
            x: _requireNumber(args, 1, 'love.keyboard.setTextInput'),
            y: _requireNumber(args, 2, 'love.keyboard.setTextInput'),
            width: _requireNumber(args, 3, 'love.keyboard.setTextInput'),
            height: _requireNumber(args, 4, 'love.keyboard.setTextInput'),
          );
    runtime.keyboard.setTextInput(enable, area: area);
    return null;
  };
}

String _requireKeyboardKeyConstant(
  List<Object?> args,
  int index,
  String symbol,
) {
  final key = _requireString(args, index, symbol);
  if (!loveIsValidKeyConstant(key)) {
    throw LuaError('$symbol invalid key constant "$key"');
  }

  return key;
}

String _requireKeyboardScancode(List<Object?> args, int index, String symbol) {
  final scancode = _requireString(args, index, symbol);
  if (!loveIsValidScancode(scancode)) {
    throw LuaError('$symbol invalid scancode "$scancode"');
  }

  return scancode;
}

List<String> _keyboardKeySequence(List<Object?> args, String symbol) {
  final values = _stringSequence(args, symbol: symbol);
  return values
      .map((value) {
        if (!loveIsValidKeyConstant(value)) {
          throw LuaError('$symbol invalid key constant "$value"');
        }
        return value;
      })
      .toList(growable: false);
}

List<String> _keyboardScancodeSequence(List<Object?> args, String symbol) {
  final values = _stringSequence(args, symbol: symbol);
  return values
      .map((value) {
        if (!loveIsValidScancode(value)) {
          throw LuaError('$symbol invalid scancode "$value"');
        }
        return value;
      })
      .toList(growable: false);
}

List<String> _stringSequence(List<Object?> args, {required String symbol}) {
  if (args.isEmpty) {
    return const <String>[];
  }

  final table = args.length == 1 ? _tableIfPresent(args.first) : null;
  if (table != null) {
    final values = <String>[];
    for (var index = 1; ; index++) {
      final entry = _tableIndexedEntry(table, index);
      if (entry == null) {
        break;
      }
      final stringValue = _stringLike(entry);
      if (stringValue == null) {
        throw LuaError('$symbol expected strings in table argument');
      }
      values.add(stringValue);
    }
    return values;
  }

  return List<String>.generate(
    args.length,
    (index) => _requireString(args, index, symbol),
    growable: false,
  );
}
