import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font source-backed metadata fallback parity', () {
    test(
      'graphics.newFont preserves missing-glyph width and synthetic tab spacing',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final sourceDir = await love2dResourceDirectory();
        expect(
          LoveFilesystemState.of(runtime).setSource(sourceDir.path),
          isTrue,
        );

        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          <Object?>['Vera.ttf', 12, null, 2.0],
        );
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>['Vera.ttf', 12, null, 2.0],
        );

        const missingGlyph = '🙂';
        final glyphData = await luaCallMethod(
          rasterizer,
          'getGlyphData',
          const <Object?>[missingGlyph],
        );
        final expectedMissingWidth =
            (await luaCallMethod(glyphData, 'getAdvance') as num) / 2.0;

        expect(
          await luaCallMethod(rasterizer, 'hasGlyphs', const <Object?>[
            missingGlyph,
          ]),
          isFalse,
        );
        expect(
          await luaCallMethod(font, 'hasGlyphs', const <Object?>[missingGlyph]),
          isFalse,
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>[missingGlyph]),
          closeTo(expectedMissingWidth, 1e-9),
        );

        expect(
          await luaCallMethod(font, 'hasGlyphs', const <Object?>['\t']),
          isFalse,
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['\t']),
          closeTo(
            await luaCallMethod(font, 'getWidth', const <Object?>['    '])
                as num,
            1e-9,
          ),
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['A\tA']),
          closeTo(
            await luaCallMethod(font, 'getWidth', const <Object?>['A    A'])
                as num,
            1e-9,
          ),
        );
      },
    );
  });
}
