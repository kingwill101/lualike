@Tags(['interop'])
library;

import 'package:lualike_test/test.dart';

void main() {
  group('Local Attributes', () {
    test('valid attribute', () async {
      final bridge = LuaLike();

      await bridge.execute('''
       local s <const> = 1;
      ''');
      bridge.asserts.global("s", 1);
    });

    test('multiple valid attributes', () async {
      final bridge = LuaLike();

      await bridge.execute('''
        local s <const>, t <const> = 1, 2;
      ''');
      bridge.asserts.global("s", 1);
      bridge.asserts.global("t", 2);
    });

    test('invalid attribute', () async {
      final bridge = LuaLike();

      // expect(() async {
      await bridge.execute('''
              local s <const>, t <invalidAttribute> = 1, 2; print(s, t);
            ''');
      // }, throwsA(isA<Exception>()));
    });
  });
}
