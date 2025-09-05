@Tags(['stdlib'])
library;

import 'dart:convert';

import 'package:lualike_test/test.dart';

void main() {
  group('String Library string.format', () {
    test('complex %q and %s interaction from strings.lua', () async {
      final bridge = LuaLike();
      // This is the failing test case from .lua-tests/strings.lua
      // Note: The character � in the original file is byte 225.
      final script = r'''
        x = '"\225lo"\n\\'
        result = string.format('%q%s', x, x)
      ''';
      print('Script being executed:');
      print(script);
      await bridge.execute(script);
      final result = (bridge.getGlobal('result') as Value).raw.toLatin1String();

      // Build expected result using actual byte sequences
      // Input: x = '"\225lo"\n\\'
      // %q part: "\"\225lo\"\n\\" -> escape quotes, backslashes, and byte 225
      // Expected %q: "\"\225lo\"\n\\"
      final qBytes = [
        34,
        92,
        34,
        92,
        50,
        50,
        53,
        108,
        111,
        92,
        34,
        92,
        10,
        92,
        92,
        34,
      ];
      final qPart = String.fromCharCodes(qBytes);

      // %s part: raw string with byte 225
      final sBytes = [34, 225, 108, 111, 34, 10, 92];
      final sPart = String.fromCharCodes(sBytes);

      final expected = qPart + sPart;

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
      await bridge.execute(script);
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
      await bridge.execute(script);
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
      await bridge.execute(script);
      final result = latin1.decode(
        (bridge.getGlobal('result') as Value).raw.bytes,
      );
      final expected = '"a\\\nb"';

      expect(result, equals(expected));
    });
  });
}
