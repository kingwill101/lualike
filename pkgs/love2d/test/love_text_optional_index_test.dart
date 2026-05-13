import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Text optional index parity', () {
    test(
      'getWidth/getHeight/getDimensions treat nil like an omitted index',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[20],
        );
        final text = await luaCall(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'Lua'],
        );

        await luaCallMethod(text, 'addf', const <Object?>[
          'ab cd',
          24.0,
          'center',
        ]);

        expect(
          await luaCallMethod(text, 'getWidth'),
          await luaCallMethod(text, 'getWidth', const <Object?>[null]),
        );
        expect(
          await luaCallMethod(text, 'getHeight'),
          await luaCallMethod(text, 'getHeight', const <Object?>[null]),
        );
        expect(
          await luaCallMethod(text, 'getDimensions'),
          await luaCallMethod(text, 'getDimensions', const <Object?>[null]),
        );

        expect(
          await luaCallMethod(text, 'getWidth', const <Object?>[0]),
          await luaCallMethod(text, 'getWidth', const <Object?>[null]),
        );
        expect(
          await luaCallMethod(text, 'getHeight', const <Object?>[0]),
          await luaCallMethod(text, 'getHeight', const <Object?>[null]),
        );
        expect(
          await luaCallMethod(text, 'getDimensions', const <Object?>[0]),
          await luaCallMethod(text, 'getDimensions', const <Object?>[null]),
        );
      },
    );
  });
}
