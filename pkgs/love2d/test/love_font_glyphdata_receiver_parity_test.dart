import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font glyph data receiver parity', () {
    test(
      'GlyphData:type and GlyphData:typeOf require a GlyphData receiver',
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
        final glyphData = await luaCallMethod(rasterizer, 'getGlyphData', [
          'B',
        ]);

        final typeMethod = luaRawMethod(glyphData, 'type');
        final typeOfMethod = luaRawMethod(glyphData, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[glyphData])),
          'GlyphData',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[glyphData, 'GlyphData']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (GlyphData expected, got nil)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>['oops'])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (GlyphData expected, got string)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'GlyphData']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (GlyphData expected, got string)",
            ),
          ),
        );
      },
    );

    test(
      'GlyphData release invalidates methods but preserves type metadata',
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
        final glyphData = await luaCallMethod(rasterizer, 'getGlyphData', [
          'B',
        ]);

        expect(await luaCallMethod(glyphData, 'release'), isTrue);
        expect(await luaCallMethod(glyphData, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(glyphData, 'getWidth'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(glyphData, 'type'), 'GlyphData');
        expect(
          await luaCallMethod(glyphData, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}
