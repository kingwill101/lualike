import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font true type validation', () {
    test('newTrueTypeRasterizer rejects non-font FileData inputs', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final fileData = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_notAFontBytes, 'fake.ttf'],
      );

      await expectLater(
        () => luaCall(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          <Object?>[fileData, 16],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Invalid font file: fake.ttf',
          ),
        ),
      );
    });

    test('newTrueTypeRasterizer rejects non-font filenames', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'assets/fonts/not_a_font.ttf': _notAFontBytes,
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
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>['assets/fonts/not_a_font.ttf', 16],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Invalid font file: assets/fonts/not_a_font.ttf',
          ),
        ),
      );
    });

    test(
      'newRasterizer rejects invalid loaded font data with LOVE text',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_notAFontBytes, 'fake.ttf'],
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
              'Invalid font file: fake.ttf',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects invalid loaded font data with LOVE text',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_notAFontBytes, 'fake.ttf'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>[fileData, 16],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid font file: fake.ttf',
            ),
          ),
        );
      },
    );
  });
}

final List<int> _notAFontBytes = utf8.encode('not a true type font');
