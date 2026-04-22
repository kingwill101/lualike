import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font baseline parity', () {
    test(
      'source-backed true type fonts use parsed ascent as the baseline',
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
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );

        expect(await luaCallMethod(font, 'getAscent'), 15.0);
        expect(await luaCallMethod(font, 'getBaseline'), 15.0);
      },
    );

    test(
      'bmfont fonts use ascent as the baseline across direct and dpi-scaled rasterizer paths',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );

        final directFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fileData, imageData],
        );
        expect(await luaCallMethod(directFont, 'getAscent'), 5.0);
        expect(await luaCallMethod(directFont, 'getBaseline'), 5.0);

        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newBMFontRasterizer'],
          <Object?>[fileData, imageData, 2.0],
        );
        final rasterizerFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        expect(await luaCallMethod(rasterizerFont, 'getDPIScale'), 2.0);
        expect(await luaCallMethod(rasterizerFont, 'getAscent'), 2.5);
        expect(await luaCallMethod(rasterizerFont, 'getBaseline'), 2.5);
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
