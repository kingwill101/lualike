import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font BMFont File overloads', () {
    test(
      'newBMFontRasterizer accepts mounted File objects for definition and page images',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/bmfont/test.fnt': utf8.encode(_bmFontDefinition),
              'assets/fonts/bmfont/page.png': LoveImageData(
                width: 8,
                height: 6,
              ).encode('png'),
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        final definitionFile = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/bmfont/test.fnt'],
        );
        final pageFile = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/bmfont/page.png'],
        );

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newBMFontRasterizer'],
          <Object?>[definitionFile, pageFile, 1.0],
        );

        expect(await luaCallMethodList(rasterizer, 'getGlyphCount'), 2);
        expect(await luaCallMethodList(rasterizer, 'getAdvance'), 4);
        expect(await luaCallMethodList(rasterizer, 'getHeight'), 6);
        expect(await luaCallMethodList(rasterizer, 'getAscent'), 5);
        expect(await luaCallMethodList(rasterizer, 'getDescent'), 1);
      },
    );

    test(
      'graphics.newFont accepts mounted File objects for BMFont definitions and page images',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/bmfont/test.fnt': utf8.encode(_bmFontDefinition),
              'assets/fonts/bmfont/page.png': LoveImageData(
                width: 8,
                height: 6,
              ).encode('png'),
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        final definitionFile = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/bmfont/test.fnt'],
        );
        final pageFile = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/bmfont/page.png'],
        );

        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[definitionFile, pageFile],
        );

        expect(await luaCallMethodList(font, 'getHeight'), 6.0);
        expect(await luaCallMethodList(font, 'getAscent'), 5.0);
        expect(await luaCallMethodList(font, 'getDescent'), 1.0);
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
      'auto-detected BMFont constructors accept mounted File objects and relative pages',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/bmfont/test.fnt': utf8.encode(_bmFontDefinition),
              'assets/fonts/bmfont/page.png': LoveImageData(
                width: 8,
                height: 6,
              ).encode('png'),
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        final rasterizerFile = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/bmfont/test.fnt'],
        );
        final fontFile = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/bmfont/test.fnt'],
        );

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          <Object?>[rasterizerFile],
        );
        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fontFile],
        );

        expect(await luaCallMethodList(rasterizer, 'getGlyphCount'), 2);
        expect(await luaCallMethodList(rasterizer, 'getAdvance'), 4);
        expect(await luaCallMethodList(font, 'getHeight'), 6.0);
        expect(
          await luaCallMethodList(font, 'getWidth', const <Object?>['AB']),
          6.0,
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
