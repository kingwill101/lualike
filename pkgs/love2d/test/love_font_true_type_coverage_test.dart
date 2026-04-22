import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('source-backed true type glyph coverage', () {
    test('rasterizers use cmap coverage for hasGlyphs', () async {
      final runtime = Interpreter();
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
        <Object?>[fileData, 16],
      );

      expect(
        await luaCallMethod(rasterizer, 'hasGlyphs', const <Object?>[
          'LuaLike',
        ]),
        isTrue,
      );
      expect(
        await luaCallMethod(rasterizer, 'hasGlyphs', const <Object?>['中']),
        isFalse,
      );
      expect(
        await luaCallMethod(rasterizer, 'hasGlyphs', const <Object?>['🙂']),
        isFalse,
      );
      expect(
        await luaCallMethod(rasterizer, 'hasGlyphs', const <Object?>[0x1f642]),
        isFalse,
      );

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[rasterizer],
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>['LuaLike']),
        isTrue,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>['中']),
        isFalse,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>['🙂']),
        isFalse,
      );
      final wideWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['W']) as num;
      final narrowWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['i']) as num;
      expect(wideWidth, greaterThan(narrowWidth));
      final aWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['A']) as num;
      final vWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['V']) as num;
      final avWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['AV']) as num;
      final avKerning =
          await luaCallMethod(font, 'getKerning', const <Object?>['A', 'V'])
              as num;
      expect(avKerning, lessThan(0));
      expect(avWidth, lessThan(aWidth + vWidth));
    });

    test('graphics.newFont keeps source-backed true type coverage', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final sourceDir = await love2dResourceDirectory();
      expect(LoveFilesystemState.of(runtime).setSource(sourceDir.path), isTrue);

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>['Vera.ttf', 16],
      );

      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>['LuaLike']),
        isTrue,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>['中']),
        isFalse,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>['🙂']),
        isFalse,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>[0x1f642]),
        isFalse,
      );
      final wideWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['W']) as num;
      final narrowWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['i']) as num;
      expect(wideWidth, greaterThan(narrowWidth));
      final aWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['A']) as num;
      final vWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['V']) as num;
      final avWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['AV']) as num;
      final avKerning =
          await luaCallMethod(font, 'getKerning', const <Object?>['A', 'V'])
              as num;
      expect(avKerning, lessThan(0));
      expect(avWidth, lessThan(aWidth + vWidth));
    });

    test(
      'source-backed rasterizers use parsed outline metrics for glyph data',
      () async {
        final runtime = Interpreter();
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
          <Object?>[fileData, 12, 'normal', 2.0],
        );

        final wideGlyph = await luaCallMethod(
          rasterizer,
          'getGlyphData',
          const <Object?>['W'],
        );
        final narrowGlyph = await luaCallMethod(
          rasterizer,
          'getGlyphData',
          const <Object?>['i'],
        );
        final spaceGlyph = await luaCallMethod(
          rasterizer,
          'getGlyphData',
          const <Object?>[' '],
        );

        expect(await luaCallMethod(wideGlyph, 'getFormat'), 'la8');
        expect(
          await luaCallMethod(wideGlyph, 'getWidth'),
          greaterThan(await luaCallMethod(narrowGlyph, 'getWidth') as num),
        );
        expect(
          await luaCallMethod(wideGlyph, 'getAdvance'),
          greaterThan(await luaCallMethod(narrowGlyph, 'getAdvance') as num),
        );
        expect(await luaCallMethod(spaceGlyph, 'getDimensions'), <Object?>[
          0,
          0,
        ]);
        expect(await luaCallMethod(spaceGlyph, 'getAdvance'), greaterThan(0));
        expect(await luaCallMethod(spaceGlyph, 'getSize'), 0);
      },
    );

    test(
      'source-backed rasterizers and rasterizer-backed fonts use parsed vertical metrics',
      () async {
        final runtime = Interpreter();
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
          <Object?>[fileData, 16],
        );

        expect(await luaCallMethod(rasterizer, 'getHeight'), 19);
        expect(await luaCallMethod(rasterizer, 'getAscent'), 15);
        expect(await luaCallMethod(rasterizer, 'getDescent'), 4);
        expect(await luaCallMethod(rasterizer, 'getLineHeight'), 24);

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        expect(await luaCallMethod(font, 'getHeight'), 19.0);
        expect(await luaCallMethod(font, 'getAscent'), 15.0);
        expect(await luaCallMethod(font, 'getDescent'), 4.0);
        expect(await luaCallMethod(font, 'getLineHeight'), 1.0);
      },
    );
  });
}
