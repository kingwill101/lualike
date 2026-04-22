import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font image constructor dpi parity', () {
    test(
      'graphics.newImageFont forwards dpiscale like the rasterizer path',
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
        final rasterizerFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        final directFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[imageData, 'ABC', 1, 2.0],
        );

        expect(
          await luaCallMethod(directFont, 'getDPIScale'),
          await luaCallMethod(rasterizerFont, 'getDPIScale'),
        );
        expect(
          await luaCallMethod(directFont, 'getHeight'),
          await luaCallMethod(rasterizerFont, 'getHeight'),
        );
        expect(
          await luaCallMethod(directFont, 'getAscent'),
          await luaCallMethod(rasterizerFont, 'getAscent'),
        );
        expect(
          await luaCallMethod(directFont, 'getBaseline'),
          await luaCallMethod(rasterizerFont, 'getBaseline'),
        );
        expect(
          await luaCallMethod(directFont, 'getWidth', const <Object?>['ABC']),
          await luaCallMethod(rasterizerFont, 'getWidth', const <Object?>[
            'ABC',
          ]),
        );
      },
    );
  });
}
