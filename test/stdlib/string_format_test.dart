@Tags(['stdlib'])
library;

import 'dart:convert';

import 'package:lualike/testing.dart';

void main() {
  group('String Library string.format', () {
    test('complex %q and %s interaction from strings.lua', () async {
      final bridge = LuaLike();
      // This is the failing test case from .lua-tests/strings.lua
      // Note: The character � in the original file is byte 225.
      final script = r'''
        local x = '"\225lo"\n\\'
        result = string.format('%q%s', x, x)
      ''';
      print('Script being executed:');
      print(script);
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).raw.toString();
      final expected = '"\\"\\225lo\\"\\\n\\\\""�lo"\n\\';

      // For debugging in the test output
      print('Failing test case from strings.lua');
      print('Result:   $result');
      print('Expected: $expected');

      expect(result, equals(expected));
    });

    test('simple %q escaping for quotes', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format('%q', 'a "b" c')
      ''';
      await bridge.runCode(script);
      final result = latin1.decode(
        (bridge.getGlobal('result') as Value).raw.bytes,
      );
      final expected = r'"a \"b\" c"';

      expect(result, equals(expected));
    });

    test('simple %q escaping for backslash', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format('%q', 'a\\b')
      ''';
      await bridge.runCode(script);
      final result = latin1.decode(
        (bridge.getGlobal('result') as Value).raw.bytes,
      );
      final expected = r'"a\\b"';

      expect(result, equals(expected));
    });

    test('simple %q escaping for newline', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format('%q', 'a\nb')
      ''';
      await bridge.runCode(script);
      final result = latin1.decode(
        (bridge.getGlobal('result') as Value).raw.bytes,
      );
      final expected = '"a\\\nb"';

      expect(result, equals(expected));
    });
  });
}
