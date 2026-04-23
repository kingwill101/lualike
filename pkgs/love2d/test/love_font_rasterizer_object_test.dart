import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('Rasterizer and GlyphData object semantics', () {
    test(
      'image rasterizers expose LOVE Object type, typeOf, and release behavior',
      () async {
        final runtime = createLuaLikeTestRuntime();
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

        expect(await luaCallMethod(rasterizer, 'type'), 'Rasterizer');
        expect(
          await luaCallMethod(rasterizer, 'typeOf', const <Object?>[
            'Rasterizer',
          ]),
          isTrue,
        );
        expect(
          await luaCallMethod(rasterizer, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
        expect(
          await luaCallMethod(rasterizer, 'typeOf', const <Object?>[
            'GlyphData',
          ]),
          isFalse,
        );
        expect(await luaCallMethod(rasterizer, 'release'), isTrue);
        expect(await luaCallMethod(rasterizer, 'release'), isFalse);
      },
    );

    test(
      'glyph data objects expose LOVE Data/Object semantics and clone independently',
      () async {
        final runtime = createLuaLikeTestRuntime();
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

        expect(await luaCallMethod(glyphData, 'type'), 'GlyphData');
        expect(
          await luaCallMethod(glyphData, 'typeOf', const <Object?>[
            'GlyphData',
          ]),
          isTrue,
        );
        expect(
          await luaCallMethod(glyphData, 'typeOf', const <Object?>['Data']),
          isTrue,
        );
        expect(
          await luaCallMethod(glyphData, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
        expect(
          await luaCallMethod(glyphData, 'typeOf', const <Object?>[
            'Rasterizer',
          ]),
          isFalse,
        );

        final clone = await luaCallMethod(glyphData, 'clone');
        expect(await luaCallMethod(clone, 'type'), 'GlyphData');
        expect(await luaCallMethod(clone, 'getGlyphString'), 'B');
        expect(await luaCallMethod(clone, 'getDimensions'), <Object?>[1, 6]);
        expect(
          await luaCallMethod(clone, 'getString'),
          await luaCallMethod(glyphData, 'getString'),
        );
        expect(await luaCallMethod(glyphData, 'release'), isTrue);
        expect(await luaCallMethod(glyphData, 'release'), isFalse);
        expect(await luaCallMethod(clone, 'release'), isTrue);
      },
    );
  });
}
