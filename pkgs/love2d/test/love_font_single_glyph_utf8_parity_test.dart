import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font single-glyph UTF-8 parity', () {
    test(
      'newGlyphData and getGlyphData ignore trailing invalid bytes after the first codepoint',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );
        final malformedA = LuaString.fromBytes(const <int>[0x41, 0xff]);

        final constructorGlyph = await luaCall(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, malformedA],
        );
        final methodGlyph = await luaCallMethod(
          rasterizer,
          'getGlyphData',
          <Object?>[malformedA],
        );

        expect(await luaCallMethod(constructorGlyph, 'getGlyph'), 65);
        expect(await luaCallMethod(constructorGlyph, 'getGlyphString'), 'A');
        expect(await luaCallMethod(methodGlyph, 'getGlyph'), 65);
        expect(await luaCallMethod(methodGlyph, 'getGlyphString'), 'A');
      },
    );

    test(
      'Font:getKerning string overload ignores trailing invalid bytes after the first codepoint',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[veraBytes, 'Vera.ttf'],
        );
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fileData, 16],
        );

        final baseline =
            await luaCallMethod(font, 'getKerning', const <Object?>['A', 'V'])
                as num;

        expect(
          await luaCallMethod(font, 'getKerning', <Object?>[
            LuaString.fromBytes(const <int>[0x41, 0xff]),
            'V',
          ]),
          baseline,
        );
        expect(
          await luaCallMethod(font, 'getKerning', <Object?>[
            'A',
            LuaString.fromBytes(const <int>[0x56, 0xff]),
          ]),
          baseline,
        );
      },
    );

    test(
      'full-string APIs still reject trailing invalid bytes after the first codepoint',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );
        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );
        final malformedA = LuaString.fromBytes(const <int>[0x41, 0xff]);

        Future<void> expectUtf8Error(
          Future<Object?> Function() callback,
        ) async {
          await expectLater(
            callback,
            throwsA(
              isA<LuaError>().having(
                (error) => error.message,
                'message',
                contains('UTF-8 decoding error at argument 2: Invalid UTF-8'),
              ),
            ),
          );
        }

        await expectUtf8Error(
          () => luaCallMethod(rasterizer, 'hasGlyphs', <Object?>[malformedA]),
        );
        await expectUtf8Error(
          () => luaCallMethod(font, 'hasGlyphs', <Object?>[malformedA]),
        );
      },
    );
  });
}
