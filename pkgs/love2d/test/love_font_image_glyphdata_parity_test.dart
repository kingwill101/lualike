import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font image glyph data parity', () {
    test(
      'image rasterizers use LOVE bearing and bounding-box semantics',
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
        expect(await luaCallMethod(glyphData, 'getDimensions'), <Object?>[
          1,
          6,
        ]);
        expect(await luaCallMethod(glyphData, 'getBearing'), <Object?>[0, 0]);
        expect(await luaCallMethod(glyphData, 'getBoundingBox'), <Object?>[
          0,
          6,
          1,
          -6,
        ]);

        final missing = await luaCallMethod(rasterizer, 'getGlyphData', ['Z']);
        expect(await luaCallMethod(missing, 'getDimensions'), <Object?>[0, 6]);
        expect(await luaCallMethod(missing, 'getBearing'), <Object?>[0, 0]);
        expect(await luaCallMethod(missing, 'getBoundingBox'), <Object?>[
          0,
          6,
          0,
          -6,
        ]);
      },
    );
  });
}
