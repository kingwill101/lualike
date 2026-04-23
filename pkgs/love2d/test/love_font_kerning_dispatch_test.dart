import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font kerning overload dispatch', () {
    test('source-backed fonts accept both documented overloads', () async {
      final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
      final runtime = createLuaLikeTestRuntime();
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
        const <Object?>['assets/fonts/Body.ttf', 16],
      );

      final stringKerning =
          await luaCallMethod(font, 'getKerning', const <Object?>['A', 'V'])
              as num;
      final glyphKerning =
          await luaCallMethod(font, 'getKerning', const <Object?>[65, 86])
              as num;

      expect(stringKerning, lessThan(0));
      expect(glyphKerning, stringKerning);
    });

    test(
      'mixed kerning arguments follow LOVE left-argument dispatch',
      () async {
        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final runtime = createLuaLikeTestRuntime();
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
          const <Object?>['assets/fonts/Body.ttf', 16],
        );

        expect(
          await luaCallMethod(font, 'getKerning', const <Object?>['A', 86]),
          await luaCallMethod(font, 'getKerning', const <Object?>['A', '86']),
        );
        expect(
          await luaCallMethod(font, 'getKerning', const <Object?>[65, '86']),
          await luaCallMethod(font, 'getKerning', const <Object?>[65, 86]),
        );
      },
    );
  });
}
