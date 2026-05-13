import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('true type glyph pixels', () {
    test(
      'source-backed rasterizers generate non-empty alpha coverage for simple glyphs',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[veraBytes, 'Vera.ttf'],
        );

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          <Object?>[fileData, 12, 'normal', 2.0],
        );
        final glyphData = await luaCallMethodList(
          rasterizer,
          'getGlyphData',
          const <Object?>['A'],
        );

        final payload = requireLuaStringBytes(
          await luaCallMethodRaw(glyphData, 'getString'),
        );
        final alphaBytes = <int>[
          for (var index = 1; index < payload.length; index += 2)
            payload[index],
        ];

        expect(await luaCallMethodList(glyphData, 'getFormat'), 'la8');
        expect(await luaCallMethodList(glyphData, 'getSize'), payload.length);
        expect(alphaBytes, isNotEmpty);
        expect(alphaBytes.any((value) => value > 0), isTrue);
        expect(alphaBytes.any((value) => value == 0), isTrue);
      },
    );
  });
}
