import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font true type size validation', () {
    test(
      'newTrueTypeRasterizer rejects dpi-scaled pixel sizes that round to zero',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'font', 'newTrueTypeRasterizer'],
            const <Object?>[12, 'normal', 0.01],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid TrueType font size: 0',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects source-backed dpi-scaled pixel sizes that round to zero',
      () async {
        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/Vera.ttf': veraBytes,
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
            const <Object?>['assets/fonts/Vera.ttf', 12, 'normal', 0.01],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid TrueType font size: 0',
            ),
          ),
        );
      },
    );
  });
}
