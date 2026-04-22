import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font rasterizer receiver parity', () {
    test(
      'Rasterizer:type and Rasterizer:typeOf require a Rasterizer receiver',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[imageData, 'ABC', 1, 1.0],
        );

        final typeMethod = luaRawMethod(rasterizer, 'type');
        final typeOfMethod = luaRawMethod(rasterizer, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[rasterizer])),
          'Rasterizer',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[rasterizer, 'Rasterizer']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (Rasterizer expected, got nil)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>['oops'])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (Rasterizer expected, got string)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'Rasterizer']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (Rasterizer expected, got string)",
            ),
          ),
        );
      },
    );

    test(
      'Rasterizer release invalidates methods but preserves type metadata',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[imageData, 'ABC', 1, 1.0],
        );

        expect(await luaCallMethod(rasterizer, 'release'), isTrue);
        expect(await luaCallMethod(rasterizer, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(rasterizer, 'getHeight'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(rasterizer, 'type'), 'Rasterizer');
        expect(
          await luaCallMethod(rasterizer, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}
