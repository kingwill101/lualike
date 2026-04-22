import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font limitations', () {
    test(
      'default true type rasterizers without source data still reject glyph count enumeration',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );

        const message =
            'true type rasterizer glyph count is not supported yet without source font data';

        await expectLater(
          () => luaCallMethodList(rasterizer, 'getGlyphCount'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(message),
            ),
          ),
        );
      },
    );

    test(
      'font fallbacks reject different underlying font data types',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final bmFontDefinition = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final bmFontPage = await luaCallList(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );
        final bmFont = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[bmFontDefinition, bmFontPage],
        );

        final imageFontStrip = await luaCallList(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        final imageFont = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[imageFontStrip, 'ABC', 1],
        );

        await expectLater(
          () => luaCallMethodList(bmFont, 'setFallbacks', <Object?>[imageFont]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('same font type'),
            ),
          ),
        );
      },
    );
  });
}

const String _bmFontDefinition = '''
info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=2
char id=65 x=0 y=0 width=3 height=6 xoffset=0 yoffset=0 xadvance=4 page=0 chnl=15
char id=66 x=3 y=0 width=2 height=6 xoffset=0 yoffset=0 xadvance=3 page=0 chnl=15
kernings count=1
kerning first=65 second=66 amount=-1
''';
