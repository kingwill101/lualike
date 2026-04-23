import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Text font bindings', () {
    test('newText uses the provided font and setFont replaces it', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final largeFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[20],
      );
      final text = await luaCall(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[largeFont, 'Lua'],
      );

      final initialFont = await luaCallMethod(text, 'getFont');
      expect(await luaCallMethod(initialFont, 'getHeight'), 20.0);
      expect(await luaCallMethod(text, 'getWidth'), 36.0);

      final smallFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[10],
      );

      expect(
        await luaCallMethod(text, 'setFont', <Object?>[smallFont]),
        isNull,
      );

      final currentFont = await luaCallMethod(text, 'getFont');
      expect(await luaCallMethod(currentFont, 'getHeight'), 10.0);
      expect(await luaCallMethod(text, 'getWidth'), 18.0);
    });

    test('Text font methods enforce Text and Font receivers', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );
      final text = await luaCall(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font, 'Lua'],
      );

      expect(
        () => luaRawMethod(text, 'getFont').call(const <Object?>['oops']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Text:getFont expected a Text at argument 1',
          ),
        ),
      );

      expect(
        () => luaRawMethod(text, 'setFont').call(const <Object?>['oops', null]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Text:setFont expected a Text at argument 1',
          ),
        ),
      );

      expect(
        () => luaRawMethod(text, 'setFont').call(<Object?>[text, 'oops']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Text:setFont expected a Font at argument 2',
          ),
        ),
      );
    });
  });
}
