import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font BMFont auto-detection parity', () {
    test(
      'newRasterizer rejects BOM-prefixed BMFont file data like upstream',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bomPrefixedDefinition, 'assets/fonts/bom-prefixed.fnt'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'font', 'newRasterizer'],
            <Object?>[fileData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid font file: assets/fonts/bom-prefixed.fnt',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects BOM-prefixed BMFont file data like upstream',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bomPrefixedDefinition, 'assets/fonts/bom-prefixed.fnt'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>[fileData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid font file: assets/fonts/bom-prefixed.fnt',
            ),
          ),
        );
      },
    );

    test(
      'newRasterizer rejects whitespace-prefixed mounted BMFont definitions like upstream',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/space-prefixed.fnt': _whitespacePrefixedDefinition,
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'font', 'newRasterizer'],
            const <Object?>['assets/fonts/space-prefixed.fnt'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid font file: assets/fonts/space-prefixed.fnt',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects whitespace-prefixed mounted BMFont definitions like upstream',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/space-prefixed.fnt': _whitespacePrefixedDefinition,
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newFont'],
            const <Object?>['assets/fonts/space-prefixed.fnt'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid font file: assets/fonts/space-prefixed.fnt',
            ),
          ),
        );
      },
    );
  });
}

final List<int> _bomPrefixedDefinition = <int>[
  0xef,
  0xbb,
  0xbf,
  ...utf8.encode(_bmFontDefinition),
];
final List<int> _whitespacePrefixedDefinition = utf8.encode(
  '  $_bmFontDefinition',
);

const String _bmFontDefinition = '''
info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=1
char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 xadvance=1 page=0 chnl=15
''';
