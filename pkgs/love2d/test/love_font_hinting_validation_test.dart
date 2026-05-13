import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font hinting validation', () {
    test(
      'newTrueTypeRasterizer uses LOVE enum error text for invalid hinting',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'font', 'newTrueTypeRasterizer'],
            const <Object?>[12, 'bogus'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "Invalid TrueType font hinting mode 'bogus', expected one of: "
                  "'normal', 'light', 'mono', 'none'",
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont uses LOVE enum error text for invalid hinting',
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
            const <Object?>['assets/fonts/Vera.ttf', 16, 'bogus'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "Invalid TrueType font hinting mode 'bogus', expected one of: "
                  "'normal', 'light', 'mono', 'none'",
            ),
          ),
        );
      },
    );
  });
}
