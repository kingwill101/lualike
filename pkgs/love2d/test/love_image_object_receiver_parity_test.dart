import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Image receiver parity', () {
    test(
      'Image type metadata survives release while other methods fail',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[2, 2],
        );
        final image = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[imageData],
        );

        final typeMethod = luaRawMethod(image, 'type');
        final typeOfMethod = luaRawMethod(image, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[image])),
          'Image',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[image, 'Texture']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (Image expected, got nil)",
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
              "bad argument #1 to 'typeOf' (Image expected, got string)",
            ),
          ),
        );

        expect(await luaCallMethod(image, 'release'), isTrue);
        expect(await luaCallMethod(image, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(image, 'getWidth'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(image, 'type'), 'Image');
        expect(
          await luaCallMethod(image, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}
