import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font File overloads', () {
    test(
      'auto-detected true type constructors accept mounted File objects',
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
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        final rasterizerFile = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/Body.ttf'],
        );
        final fontFile = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/Body.ttf'],
        );

        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          <Object?>[rasterizerFile],
        );
        final baselineRasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          const <Object?>['assets/fonts/Body.ttf'],
        );
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fontFile],
        );
        final baselineFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['assets/fonts/Body.ttf'],
        );

        expect(
          await luaCallMethod(rasterizer, 'getHeight'),
          await luaCallMethod(baselineRasterizer, 'getHeight'),
        );
        expect(
          await luaCallMethod(rasterizer, 'getGlyphCount'),
          await luaCallMethod(baselineRasterizer, 'getGlyphCount'),
        );
        expect(
          await luaCallMethod(font, 'getHeight'),
          await luaCallMethod(baselineFont, 'getHeight'),
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['LuaLike']),
          await luaCallMethod(baselineFont, 'getWidth', const <Object?>[
            'LuaLike',
          ]),
        );
      },
    );

    test('true type constructors accept mounted File objects', () async {
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
      expect(
        LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
        isTrue,
      );

      final rasterizerFile = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['assets/fonts/Body.ttf'],
      );
      final fontFile = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['assets/fonts/Body.ttf'],
      );

      final rasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[rasterizerFile, 16, 'mono', 2.0],
      );
      final baselineRasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
      );
      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[fontFile, 16, 'mono', 2.0],
      );
      final baselineFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
      );

      expect(
        await luaCallMethod(rasterizer, 'getHeight'),
        await luaCallMethod(baselineRasterizer, 'getHeight'),
      );
      expect(
        await luaCallMethod(rasterizer, 'getGlyphCount'),
        await luaCallMethod(baselineRasterizer, 'getGlyphCount'),
      );
      expect(
        await luaCallMethod(font, 'getDPIScale'),
        await luaCallMethod(baselineFont, 'getDPIScale'),
      );
      expect(
        await luaCallMethod(font, 'getHeight'),
        await luaCallMethod(baselineFont, 'getHeight'),
      );
      expect(
        await luaCallMethod(font, 'getWidth', const <Object?>['W']),
        await luaCallMethod(baselineFont, 'getWidth', const <Object?>['W']),
      );
    });

    test('image font constructors accept mounted File objects', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'assets/fonts/imagefont.png': LoveImageData.fromRgbaBytes(
              width: 9,
              height: 6,
              bytes: imageFontStripBytes(),
            ).encode('png'),
          }),
        ),
      );
      expect(
        LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
        isTrue,
      );

      final rasterizerFile = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['assets/fonts/imagefont.png'],
      );
      final fontFile = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['assets/fonts/imagefont.png'],
      );

      final rasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newImageRasterizer'],
        <Object?>[rasterizerFile, 'ABC', 1, 1.0],
      );
      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[fontFile, 'ABC', 1],
      );
      final baselineFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        const <Object?>['assets/fonts/imagefont.png', 'ABC', 1],
      );

      expect(await luaCallMethod(rasterizer, 'getGlyphCount'), 3);
      expect(await luaCallMethod(rasterizer, 'getAdvance'), 4);
      expect(await luaCallMethod(rasterizer, 'getHeight'), 6);
      expect(
        await luaCallMethod(font, 'getDPIScale'),
        await luaCallMethod(baselineFont, 'getDPIScale'),
      );
      expect(
        await luaCallMethod(font, 'getWidth', const <Object?>['AB']),
        await luaCallMethod(baselineFont, 'getWidth', const <Object?>['AB']),
      );
    });
  });
}
