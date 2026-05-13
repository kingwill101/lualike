import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font BMFont constructor validation', () {
    test(
      'newBMFontRasterizer uses LOVE BMFont error text for invalid FileData definitions',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>[_notABmFontDefinition, 'assets/fonts/invalid.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
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
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont uses LOVE BMFont error text for invalid FileData definitions',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>[_notABmFontDefinition, 'assets/fonts/invalid.fnt'],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
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
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont uses LOVE BMFont error text for invalid mounted definitions',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/invalid.fnt': utf8.encode(_notABmFontDefinition),
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>['assets/fonts/invalid.fnt', imageData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );

    test(
      'newBMFontRasterizer rejects whitespace-prefixed valid definitions like upstream',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>[
            _whitespacePrefixedValidBmFontDefinition,
            'assets/fonts/invalid.fnt',
          ],
        );
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
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
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects whitespace-prefixed valid definitions like upstream',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/invalid.fnt': utf8.encode(
                _whitespacePrefixedValidBmFontDefinition,
              ),
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>['assets/fonts/invalid.fnt', imageData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );
  });
}

const String _notABmFontDefinition = 'this is not a bmfont definition';

const String _whitespacePrefixedValidBmFontDefinition = '''
 info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
 common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
 page id=0 file="page.png"
 chars count=1
 char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 xadvance=1 page=0 chnl=15
''';
