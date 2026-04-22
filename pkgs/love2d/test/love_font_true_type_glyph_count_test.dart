import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font true type glyph count', () {
    test(
      'source-backed true type rasterizers expose maxp glyph count',
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
        expect(await luaCallMethod(rasterizer, 'getGlyphCount'), 268);

        final autoRasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          <Object?>[fileData],
        );
        expect(await luaCallMethod(autoRasterizer, 'getGlyphCount'), 268);
      },
    );
  });
}
