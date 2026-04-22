import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font kerning rounding', () {
    test(
      'source-backed true type kerning follows LOVE dpi-normalized rounding',
      () async {
        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/Body.ttf': veraBytes,
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
        );

        final kerning =
            await luaCallMethod(font, 'getKerning', const <Object?>['L', 'O'])
                as num;
        final widthL =
            await luaCallMethod(font, 'getWidth', const <Object?>['L']) as num;
        final widthO =
            await luaCallMethod(font, 'getWidth', const <Object?>['O']) as num;
        final widthLO =
            await luaCallMethod(font, 'getWidth', const <Object?>['LO']) as num;

        expect(kerning, 0.0);
        expect(widthLO, widthL + widthO);
      },
    );
  });
}
