import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font BMFont bindings', () {
    test(
      'newBMFontRasterizer reads BMFont definitions and preserves kerning in graphics fonts',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final imageData = await luaCallList(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newBMFontRasterizer'],
          <Object?>[fileData, imageData, 1.0],
        );

        expect(await luaCallMethodList(rasterizer, 'type'), 'Rasterizer');
        expect(await luaCallMethodList(rasterizer, 'getGlyphCount'), 2);
        expect(await luaCallMethodList(rasterizer, 'getAdvance'), 4);
        expect(await luaCallMethodList(rasterizer, 'getHeight'), 6);
        expect(await luaCallMethodList(rasterizer, 'getAscent'), 5);
        expect(await luaCallMethodList(rasterizer, 'getDescent'), 1);
        expect(await luaCallMethodList(rasterizer, 'getLineHeight'), 6);
        expect(
          await luaCallMethodList(rasterizer, 'hasGlyphs', const <Object?>[
            'AB',
          ]),
          isTrue,
        );

        final glyphData = await luaCallMethodList(rasterizer, 'getGlyphData', [
          'B',
        ]);
        expect(await luaCallMethodList(glyphData, 'getGlyphString'), 'B');
        expect(await luaCallMethodList(glyphData, 'getDimensions'), <Object?>[
          2,
          6,
        ]);
        expect(await luaCallMethodList(glyphData, 'getAdvance'), 3);

        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        expect(
          await luaCallMethodList(font, 'getKerning', const <Object?>[
            'A',
            'B',
          ]),
          -1.0,
        );
        expect(
          await luaCallMethodList(font, 'getWidth', const <Object?>['AB']),
          6.0,
        );
      },
    );

    test(
      'newRasterizer autodetects BMFont file data and loads relative page images',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/bmfont/page.png': LoveImageData(
                width: 8,
                height: 6,
              ).encode('png'),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
        );

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          <Object?>[fileData],
        );
        expect(await luaCallMethodList(rasterizer, 'getGlyphCount'), 2);
        expect(await luaCallMethodList(rasterizer, 'getAdvance'), 4);

        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        expect(
          await luaCallMethodList(font, 'getWidth', const <Object?>['AB']),
          6.0,
        );
      },
    );

    test('graphics.newFont loads BMFont definitions directly', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final fileData = await luaCallList(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
      );
      final imageData = await luaCallList(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[8, 6],
      );

      final font = await luaCallList(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[fileData, imageData],
      );

      expect(await luaCallMethodList(font, 'getHeight'), 6.0);
      expect(await luaCallMethodList(font, 'getAscent'), 5.0);
      expect(await luaCallMethodList(font, 'getDescent'), 1.0);
      expect(
        await luaCallMethodList(font, 'getKerning', const <Object?>['A', 'B']),
        -1.0,
      );
      expect(
        await luaCallMethodList(font, 'getWidth', const <Object?>['AB']),
        6.0,
      );
    });

    test(
      'bmfont fallbacks contribute missing glyph widths and kerning',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final primaryDefinition = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _bmFontPrimaryOnlyDefinition,
            'assets/fonts/bmfont/primary.fnt',
          ],
        );
        final fallbackDefinition = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final imageData = await luaCallList(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );

        final primary = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[primaryDefinition, imageData],
        );
        final fallback = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fallbackDefinition, imageData],
        );

        await luaCallMethodList(primary, 'setFallbacks', <Object?>[fallback]);

        expect(
          await luaCallMethodList(primary, 'getKerning', const <Object?>[
            'A',
            'B',
          ]),
          -1.0,
        );
        expect(
          await luaCallMethodList(primary, 'getWidth', const <Object?>['AB']),
          6.0,
        );
        expect(
          await luaCallMethodList(primary, 'hasGlyphs', const <Object?>['AB']),
          isTrue,
        );
      },
    );
  });
}

const String _bmFontPrimaryOnlyDefinition = '''
info face="PrimaryOnly" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=1
char id=88 x=0 y=0 width=3 height=6 xoffset=0 yoffset=0 xadvance=4 page=0 chnl=15
''';

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
