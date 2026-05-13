import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font numeric truncation parity', () {
    test(
      'fractional numeric glyph lookups truncate toward zero like LOVE',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[veraBytes, 'Vera.ttf'],
        );
        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          <Object?>[fileData, 12],
        );
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fileData, 12],
        );

        final constructorGlyph = await luaCall(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, 65.9],
        );
        final methodGlyph = await luaCallMethod(
          rasterizer,
          'getGlyphData',
          const <Object?>[65.9],
        );

        expect(await luaCallMethod(constructorGlyph, 'getGlyph'), 65);
        expect(await luaCallMethod(constructorGlyph, 'getGlyphString'), 'A');
        expect(await luaCallMethod(methodGlyph, 'getGlyph'), 65);
        expect(await luaCallMethod(methodGlyph, 'getGlyphString'), 'A');

        final exactKerning =
            (await luaCallMethod(font, 'getKerning', const <Object?>[65, 86])
                    as num)
                .toDouble();
        final fractionalKerning =
            (await luaCallMethod(font, 'getKerning', const <Object?>[
                      65.9,
                      86.9,
                    ])
                    as num)
                .toDouble();

        expect(exactKerning, isNonZero);
        expect(fractionalKerning, exactKerning);
      },
    );

    test(
      'fractional numeric hasGlyphs inputs truncate before unicode validation',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        expect(
          await luaCallMethod(rasterizer, 'hasGlyphs', const <Object?>[
            0xd7ff + 0.9,
          ]),
          isTrue,
        );
        expect(
          await luaCallMethod(font, 'hasGlyphs', const <Object?>[0xd7ff + 0.9]),
          isTrue,
        );
      },
    );

    test(
      'fractional image font extra spacing truncates toward zero like LOVE',
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
          <Object?>[imageData, 'ABC', 1.9],
        );
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[imageData, 'ABC', 1.9],
        );

        expect(await luaCallMethod(rasterizer, 'getAdvance'), 4);
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['ABC']),
          9.0,
        );
      },
    );
  });
}
