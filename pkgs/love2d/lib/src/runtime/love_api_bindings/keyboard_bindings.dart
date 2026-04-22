part of '../love_api_bindings.dart';

/// Whether verbose keyboard trace logging is enabled for debugging.
const bool _loveTraceKeyboardLeak = bool.fromEnvironment(
  'LOVE2D_TRACE_TOUCH_LEAK',
  defaultValue: true,
);

/// Emits a structured keyboard-binding trace when tracing is enabled.
void _loveTraceKeyboard(
  String stage, {
  Map<String, Object?> details = const {},
}) {
  if (!_loveTraceKeyboardLeak) {
    return;
  }

  final message = details.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join(' ');
  if (stage.isEmpty && message.isEmpty) {
    return;
  }
  // print('[love2d-keyboard] $stage${message.isEmpty ? '' : ' $message'}');
}

/// Returns a printable representation of keyboard binding [args].
String _loveDescribeKeyboardArgs(List<Object?> args) {
  if (args.isEmpty) {
    return '[]';
  }

  return '[${args.map(_loveDescribeKeyboardValue).join(', ')}]';
}

/// Returns a printable representation of a single keyboard binding argument.
String _loveDescribeKeyboardValue(Object? value) {
  final raw = _rawValue(value);
  return '${value.runtimeType}(${raw.runtimeType}:$raw)';
}

/// Binds `love.keyboard.getKeyFromScancode`.
LoveApiImplementation _bindKeyboardGetKeyFromScancode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.getKeyFromScancode(
    _requireKeyboardScancode(args, 0, 'love.keyboard.getKeyFromScancode'),
  );
}

/// Binds `love.keyboard.getScancodeFromKey`.
LoveApiImplementation _bindKeyboardGetScancodeFromKey(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.getScancodeFromKey(
    _requireKeyboardKeyConstant(args, 0, 'love.keyboard.getScancodeFromKey'),
  );
}

/// Binds `love.keyboard.hasKeyRepeat`.
LoveApiImplementation _bindKeyboardHasKeyRepeat(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.keyRepeat;
}

/// Binds `love.keyboard.hasScreenKeyboard`.
LoveApiImplementation _bindKeyboardHasScreenKeyboard(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.screenKeyboardSupported;
}

/// Binds `love.keyboard.hasTextInput`.
LoveApiImplementation _bindKeyboardHasTextInput(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.textInputEnabled;
}

/// Binds `love.keyboard.isDown`.
///
/// This binding accepts LOVE's flexible argument shapes and filters leaked
/// touch IDs before delegating to the runtime keyboard state.
LoveApiImplementation _bindKeyboardIsDown(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final rawArgs = _loveDescribeKeyboardArgs(args);
    try {
      final keys = _keyboardKeySequence(
        args,
        'love.keyboard.isDown',
        touch: runtime.touch,
      );
      final result = runtime.keyboard.isDown(keys);
      _loveTraceKeyboard(
        'isDown',
        details: <String, Object?>{
          'rawArgs': rawArgs,
          'keys': keys,
          'touches': runtime.touch.getTouches(),
          'scancodes': runtime.keyboard.pressedScancodes.toList(
            growable: false,
          ),
          'result': result,
        },
      );
      return result;
    } catch (error) {
      _loveTraceKeyboard(
        'isDown.error',
        details: <String, Object?>{
          'rawArgs': rawArgs,
          'touches': runtime.touch.getTouches(),
          'scancodes': runtime.keyboard.pressedScancodes.toList(
            growable: false,
          ),
          'error': error,
        },
      );
      rethrow;
    }
  };
}

/// Binds `love.keyboard.isScancodeDown`.
LoveApiImplementation _bindKeyboardIsScancodeDown(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.keyboard.isScancodeDown(
    _keyboardScancodeSequence(args, 'love.keyboard.isScancodeDown'),
  );
}

/// Binds `love.keyboard.setKeyRepeat`.
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

/// Binds `love.keyboard.setTextInput`.
///
/// LOVE optionally accepts a text-input rectangle describing the soft-keyboard
/// editing region, so this binding only constructs the area object when the
/// extra coordinates are present.
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

/// Returns the validated LOVE key constant at [index].
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

/// Returns the validated LOVE scancode at [index].
String _requireKeyboardScancode(List<Object?> args, int index, String symbol) {
  final scancode = _requireString(args, index, symbol);
  if (!loveIsValidScancode(scancode)) {
    throw LuaError('$symbol invalid scancode "$scancode"');
  }

  return scancode;
}

/// Normalizes keyboard key arguments into validated LOVE key constants.
List<String> _keyboardKeySequence(
  List<Object?> args,
  String symbol, {
  LoveTouchState? touch,
}) {
  return _keyboardKeySequenceWithTouchState(args, symbol, touch: touch);
}

/// Normalizes scancode arguments into validated LOVE scancode strings.
List<String> _keyboardScancodeSequence(List<Object?> args, String symbol) {
  final values = _stringSequence(args, symbol: symbol, coerceNumbers: true);
  return values
      .map((value) {
        if (!loveIsValidScancode(value)) {
          throw LuaError('$symbol invalid scancode "$value"');
        }
        return value;
      })
      .toList(growable: false);
}

/// Normalizes keyboard key arguments while filtering leaked active touch IDs.
///
/// Some input paths may accidentally surface touch identifiers as string-like
/// keyboard arguments, so this helper drops those values instead of treating
/// them as invalid keys.
List<String> _keyboardKeySequenceWithTouchState(
  List<Object?> args,
  String symbol, {
  LoveTouchState? touch,
}) {
  final values = _stringSequence(args, symbol: symbol, coerceNumbers: true);
  _loveTraceKeyboard(
    'keySequence.begin',
    details: <String, Object?>{
      'symbol': symbol,
      'rawArgs': _loveDescribeKeyboardArgs(args),
      'values': values,
      'touches': touch?.getTouches(),
    },
  );
  final keys = <String>[];
  for (final value in values) {
    if (loveIsValidKeyConstant(value)) {
      keys.add(value);
      continue;
    }
    if (_isLeakedActiveTouchId(value, touch: touch)) {
      _loveTraceKeyboard(
        'keySequence.dropTouchId',
        details: <String, Object?>{
          'symbol': symbol,
          'value': value,
          'touches': touch?.getTouches(),
        },
      );
      continue;
    }
    _loveTraceKeyboard(
      'keySequence.invalid',
      details: <String, Object?>{
        'symbol': symbol,
        'value': value,
        'rawArgs': _loveDescribeKeyboardArgs(args),
        'touches': touch?.getTouches(),
      },
    );
    throw LuaError('$symbol invalid key constant "$value"');
  }
  _loveTraceKeyboard(
    'keySequence.end',
    details: <String, Object?>{'symbol': symbol, 'keys': keys},
  );
  return keys;
}

/// Returns whether [value] names an active touch that leaked into key args.
bool _isLeakedActiveTouchId(String value, {LoveTouchState? touch}) {
  if (touch == null) {
    return false;
  }

  final touchId = int.tryParse(value);
  if (touchId == null) {
    return false;
  }

  return touch.activeTouch(touchId) != null;
}

/// Converts positional or table-based string arguments into a sequence.
List<String> _stringSequence(
  List<Object?> args, {
  required String symbol,
  bool coerceNumbers = false,
}) {
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
      final stringValue = _sequenceStringLike(
        entry,
        coerceNumbers: coerceNumbers,
      );
      if (stringValue == null) {
        throw LuaError('$symbol expected strings in table argument');
      }
      values.add(stringValue);
    }
    return values;
  }

  return List<String>.generate(args.length, (index) {
    final stringValue = _sequenceStringLike(
      _valueAt(args, index),
      coerceNumbers: coerceNumbers,
    );
    if (stringValue != null) {
      return stringValue;
    }
    throw LuaError('$symbol expected a string at argument ${index + 1}');
  }, growable: false);
}

/// Returns a string-like representation of [value] when allowed.
///
/// Numeric coercion is optional so callers can match the specific LOVE API they
/// are validating.
String? _sequenceStringLike(Object? value, {required bool coerceNumbers}) {
  final stringValue = _stringLike(value);
  if (stringValue != null) {
    return stringValue;
  }

  if (!coerceNumbers) {
    return null;
  }

  final raw = _rawValue(value);
  return raw is num ? raw.toString() : null;
}
