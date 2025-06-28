@Tags(['interop'])
import 'package:lualike/testing.dart';

void main() {
  Logger.setEnabled(true);

  group('Local Attributes', () {
    test('valid attribute', () async {
      final bridge = LuaLikeBridge();

      await bridge.runCode('''
       local s <const> = 1;
      ''');
      bridge.asserts.global("s", 1);
    });

    test('multiple valid attributes', () async {
      final bridge = LuaLikeBridge();

      await bridge.runCode('''
        local s <const>, t <const> = 1, 2;
      ''');
      bridge.asserts.global("s", 1);
      bridge.asserts.global("t", 2);
    });

    test('invalid attribute', () async {
      final bridge = LuaLikeBridge();

      // expect(() async {
      await bridge.runCode('''
              local s <const>, t <invalidAttribute> = 1, 2; print(s, t);
            ''');
      // }, throwsA(isA<Exception>()));
    });
  });
}
