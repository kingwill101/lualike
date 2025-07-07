@Tags(['expressions'])
library;

import 'package:lualike/testing.dart';

void main() {
  group('Table assignments with undefined identifier keys', () {
    test('dot syntax uses field name when identifier is undefined', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        t = {}
        t.undef = 42
      ''');
      final t = bridge.getGlobal('t') as Value;
      final map = t.raw as Map<dynamic, dynamic>;
      expect(map['undef'], equals(Value(42)));
    });

    test(
      'bracket syntax uses identifier name when variable is undefined',
      () async {
        final bridge = LuaLike();
        await bridge.runCode('''
        t = {}
        t[undef] = 99
      ''');
        final t = bridge.getGlobal('t') as Value;
        final map = t.raw as Map<dynamic, dynamic>;
        expect(map['undef'], equals(Value(99)));
      },
    );
  });
}
