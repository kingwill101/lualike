import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font BMFont bounding box parity', () {
    test(
      'bmfont glyph offsets map to LOVE bearings and bounding boxes',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_offsetBmFontDefinition, 'assets/fonts/bmfont/offsets.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );
        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newBMFontRasterizer'],
          <Object?>[fileData, imageData, 1.0],
        );

        final glyphData = await luaCallMethod(rasterizer, 'getGlyphData', [
          'B',
        ]);

        expect(await luaCallMethod(glyphData, 'getDimensions'), <Object?>[
          2,
          4,
        ]);
        expect(await luaCallMethod(glyphData, 'getBearing'), <Object?>[2, -1]);
        expect(await luaCallMethod(glyphData, 'getBoundingBox'), <Object?>[
          2,
          5,
          2,
          -6,
        ]);
        expect(await luaCallMethod(glyphData, 'getAdvance'), 5);
      },
    );
  });
}

const String _offsetBmFontDefinition = '''
info face="OffsetTest" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=1
char id=66 x=0 y=0 width=2 height=4 xoffset=2 yoffset=1 xadvance=5 page=0 chnl=15
''';
