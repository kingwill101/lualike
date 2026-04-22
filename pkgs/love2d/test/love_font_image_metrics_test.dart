import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font image metrics parity', () {
    test('graphics.newImageFont preserves LOVE image font metrics', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final imageData = await luaCall(
        runtime,
        const ['love', 'image', 'newImageData'],
        <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
      );
      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'ABC', 1],
      );

      expect(await luaCallMethod(font, 'getHeight'), 6.0);
      expect(await luaCallMethod(font, 'getAscent'), 6.0);
      expect(await luaCallMethod(font, 'getDescent'), 0.0);
      expect(await luaCallMethod(font, 'getBaseline'), 6.0);
    });

    test(
      'rasterizer-backed image fonts preserve dpi-scaled LOVE metrics',
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
          <Object?>[imageData, 'ABC', 1, 2.0],
        );
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );

        expect(await luaCallMethod(font, 'getDPIScale'), 2.0);
        expect(await luaCallMethod(font, 'getHeight'), 3.0);
        expect(await luaCallMethod(font, 'getAscent'), 3.0);
        expect(await luaCallMethod(font, 'getDescent'), 0.0);
        expect(await luaCallMethod(font, 'getBaseline'), 3.0);
      },
    );
  });
}
