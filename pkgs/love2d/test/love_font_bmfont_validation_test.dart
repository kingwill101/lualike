import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font BMFont validation', () {
    test(
      'newBMFontRasterizer uses LOVE error text for invalid page ids',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_invalidPageDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
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
              'Invalid BMFont character page id: 1',
            ),
          ),
        );
      },
    );

    test(
      'newBMFontRasterizer uses LOVE error text for invalid character coordinates',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _invalidCoordinatesDefinition,
            'assets/fonts/bmfont/test.fnt',
          ],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
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
              'Invalid coordinates for BMFont character 65.',
            ),
          ),
        );
      },
    );

    test(
      'newBMFontRasterizer uses LOVE error text for invalid widths',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_invalidWidthDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
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
              'Invalid width 2 for BMFont character 65.',
            ),
          ),
        );
      },
    );

    test(
      'newBMFontRasterizer uses LOVE error text for invalid heights',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_invalidHeightDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
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
              'Invalid height 2 for BMFont character 65.',
            ),
          ),
        );
      },
    );
  });
}

const String _invalidPageDefinition = '''
info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=1
char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 xadvance=1 page=1 chnl=15
''';

const String _invalidCoordinatesDefinition = '''
info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=1
char id=65 x=8 y=0 width=1 height=1 xoffset=0 yoffset=0 xadvance=1 page=0 chnl=15
''';

const String _invalidWidthDefinition = '''
info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=1
char id=65 x=7 y=0 width=2 height=1 xoffset=0 yoffset=0 xadvance=2 page=0 chnl=15
''';

const String _invalidHeightDefinition = '''
info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=1
char id=65 x=0 y=5 width=1 height=2 xoffset=0 yoffset=0 xadvance=1 page=0 chnl=15
''';
