import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font zero-argument constructors', () {
    test('graphics.newFont() uses the LOVE default size 12 path', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final implicitFont = await luaCall(runtime, const [
        'love',
        'graphics',
        'newFont',
      ]);
      final explicitFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(
        await luaCallMethod(implicitFont, 'getHeight'),
        await luaCallMethod(explicitFont, 'getHeight'),
      );
      expect(
        await luaCallMethod(implicitFont, 'getLineHeight'),
        await luaCallMethod(explicitFont, 'getLineHeight'),
      );
      expect(
        await luaCallMethod(implicitFont, 'getWidth', const <Object?>['AV']),
        await luaCallMethod(explicitFont, 'getWidth', const <Object?>['AV']),
      );
    });

    test('graphics.setNewFont() uses the LOVE default size 12 path', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final implicitFont = await luaCall(runtime, const [
        'love',
        'graphics',
        'setNewFont',
      ]);
      final current = await luaCall(runtime, const [
        'love',
        'graphics',
        'getFont',
      ]);
      final explicitFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(
        await luaCallMethod(implicitFont, 'getHeight'),
        await luaCallMethod(explicitFont, 'getHeight'),
      );
      expect(
        await luaCallMethod(current, 'getHeight'),
        await luaCallMethod(explicitFont, 'getHeight'),
      );
      expect(
        await luaCallMethod(current, 'getWidth', const <Object?>['LuaLike']),
        await luaCallMethod(explicitFont, 'getWidth', const <Object?>[
          'LuaLike',
        ]),
      );
    });
  });
}
