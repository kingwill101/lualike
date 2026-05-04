@Tags(['ir'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/logging/logging.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

Object? _unwrapResult(Object? value) {
  if (value is Value) {
    return _unwrapResult(value.raw);
  }
  if (value is LuaString) {
    return value.toString();
  }
  if (value is List) {
    return value.map(_unwrapResult).toList();
  }
  return value;
}

void main() {
  Logger.setEnabled(false);

  group('Lualike IR lowered literals', () {
    test('executes numeric return', () async {
      final result = await executeCode('return 123', mode: EngineMode.ir);
      expect(result, equals(123));
    });

    test('executes boolean return', () async {
      final result = await executeCode('return false', mode: EngineMode.ir);
      expect(result, isFalse);
    });

    test('executes nil return', () async {
      final result = await executeCode('return nil', mode: EngineMode.ir);
      expect(result, isNull);
    });

    test('implicit return yields null', () async {
      final result = await executeCode('', mode: EngineMode.ir);
      expect(result, isNull);
    });

    test(
      'preserves byte-valued string constants after bytecode lowering',
      () async {
        final result = await executeCode(r'''
local s = "\0\255\0"
local a, b, c = string.byte(s, 1, 3)
return a, b, c, string.char(0, 255, 0) == s
''', mode: EngineMode.ir);

        expect(_unwrapResult(result), equals(<Object?>[0, 255, 0, true]));
      },
    );

    test(
      'does not collide Dart text strings with Lua byte constants',
      () async {
        final result = await executeCode(
          r'''
local text = dart_text
local literal = "\228"
local text1, text2 = string.byte(text, 1, 2)
local literal1 = string.byte(literal, 1)
return text1, text2, literal1
''',
          mode: EngineMode.ir,
          onRuntimeSetup: (runtime) {
            runtime.globals.define('dart_text', 'ä');
          },
        );

        expect(_unwrapResult(result), equals(<Object?>[195, 164, 228]));
      },
    );
  });
}
