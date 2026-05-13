import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics SpriteBatch receiver parity', () {
    test(
      'SpriteBatch type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[1, 1],
        );
        final image = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[imageData],
        );
        final spriteBatch = await luaCall(
          runtime,
          const ['love', 'graphics', 'newSpriteBatch'],
          <Object?>[image, 4],
        );

        final typeMethod = luaRawMethod(spriteBatch, 'type');
        final typeOfMethod = luaRawMethod(spriteBatch, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[spriteBatch])),
          'SpriteBatch',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[spriteBatch, 'Drawable']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (SpriteBatch expected, got nil)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'Object']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (SpriteBatch expected, got string)",
            ),
          ),
        );

        expect(await luaCallMethod(spriteBatch, 'release'), isTrue);
        expect(await luaCallMethod(spriteBatch, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(spriteBatch, 'getCount'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(spriteBatch, 'type'), 'SpriteBatch');
        expect(
          await luaCallMethod(spriteBatch, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}
