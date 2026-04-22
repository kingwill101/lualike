import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font tab parity', () {
    test(
      'LoveFont layout uses synthetic tab advances without reporting tab glyphs',
      () {
        final font = LoveFont(
          size: 16.0,
          fontType: LoveFont.trueTypeFontType,
          dataType: LoveFont.trueTypeFontType,
          glyphAdvances: const <int, double>{0x20: 2.0, 0x41: 4.0, 0x42: 4.0},
          supportsCodepointCallback: (codepoint) {
            return codepoint == 0x20 || codepoint == 0x41 || codepoint == 0x42;
          },
          syntheticTabAdvance: 8.0,
        );

        expect(font.hasGlyphValues(const <Object?>['\t']), isFalse);
        expect(font.measureWidth('\t'), 8.0);
        expect(font.measureWidth('A\tB'), 16.0);
        expect(font.measureWidth('A    B'), 16.0);
      },
    );

    test(
      'bmfont fonts measure tabs like four spaces without reporting tab glyphs',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontWithSpaceDefinition, 'assets/fonts/bmfont/tab.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[1, 1],
        );
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fileData, imageData],
        );

        expect(
          await luaCallMethod(font, 'hasGlyphs', const <Object?>['\t']),
          isFalse,
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['\t']),
          8.0,
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['A\tA']),
          16.0,
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['A    A']),
          16.0,
        );
      },
    );
  });
}

const String _bmFontWithSpaceDefinition = '''
info face="TabParity" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=1 scaleH=1 pages=1 packed=0
page id=0 file="page.png"
chars count=2
char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=2 page=0 chnl=15
char id=65 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=4 page=0 chnl=15
''';
