import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('default true type font bytes', () {
    test(
      'newTrueTypeRasterizer uses injected default font bytes for coverage and glyph count',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(defaultTrueTypeFontDataLoader: _loadVeraBytes),
        );

        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );

        expect(await luaCallMethod(rasterizer, 'getGlyphCount'), 268);
        expect(await luaCallMethod(rasterizer, 'getHeight'), 14);
        expect(await luaCallMethod(rasterizer, 'getAscent'), 11);
        expect(await luaCallMethod(rasterizer, 'getDescent'), 3);
        expect(await luaCallMethod(rasterizer, 'getLineHeight'), 18);
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
      },
    );

    test(
      'graphics.newFont uses injected default font bytes when no host-backed font is available',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(defaultTrueTypeFontDataLoader: _loadVeraBytes),
        );

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        expect(await luaCallMethod(font, 'getHeight'), 14.0);
        expect(await luaCallMethod(font, 'getAscent'), 11.0);
        expect(await luaCallMethod(font, 'getDescent'), 3.0);
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
      },
    );
  });
}

Future<Uint8List> _loadVeraBytes() async {
  final bytes = await (await love2dVeraFontFile()).readAsBytes();
  return Uint8List.fromList(bytes);
}
