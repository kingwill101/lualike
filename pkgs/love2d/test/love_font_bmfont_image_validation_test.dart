import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font BMFont image validation', () {
    test(
      'newBMFontRasterizer rejects non-rgba page images with LOVE error text',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6, 'la8'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'font', 'newBMFontRasterizer'],
            <Object?>[definition, imageData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Only 32-bit RGBA images are supported in BMFonts.',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects non-rgba BMFont page images with LOVE error text',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6, 'la8'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>[definition, imageData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Only 32-bit RGBA images are supported in BMFonts.',
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
