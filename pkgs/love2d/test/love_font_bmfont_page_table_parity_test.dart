import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font BMFont page table parity', () {
    test(
      'newBMFontRasterizer maps contiguous image tables to zero-based page ids',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _bmFontSecondPageDefinition,
            'assets/fonts/bmfont/test.fnt',
          ],
        );
        final pageImage = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );

        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newBMFontRasterizer'],
          <Object?>[
            definition,
            <Object?, Object?>{1: pageImage, 2: pageImage},
          ],
        );

        expect(await luaCallMethod(rasterizer, 'getGlyphCount'), 1);
        final glyphData = await luaCallMethod(rasterizer, 'getGlyphData', [
          'B',
        ]);
        expect(await luaCallMethod(glyphData, 'getGlyphString'), 'B');
        expect(await luaCallMethod(glyphData, 'getDimensions'), <Object?>[
          2,
          6,
        ]);
      },
    );

    test(
      'graphics.newFont ignores sparse BMFont page tables after the first hole',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _bmFontSecondPageDefinition,
            'assets/fonts/bmfont/test.fnt',
          ],
        );
        final pageImage = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>[
              definition,
              <Object?, Object?>{2: pageImage},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('missing image for BMFont page 1'),
            ),
          ),
        );
      },
    );
  });
}

const String _bmFontSecondPageDefinition = '''
info face="SecondPage" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=2 packed=0
page id=1 file=""
chars count=1
char id=66 x=3 y=0 width=2 height=6 xoffset=0 yoffset=0 xadvance=3 page=1 chnl=15
''';
