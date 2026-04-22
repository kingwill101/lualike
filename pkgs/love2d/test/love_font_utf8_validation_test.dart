import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font UTF-8 validation', () {
    test(
      'image font constructors reject malformed UTF-8 glyph lists',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        final malformed = LuaString.fromBytes(const <int>[0xc3, 0x28]);

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'font', 'newImageRasterizer'],
            <Object?>[imageData, malformed, 1, 1.0],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('UTF-8 decoding error at argument 2: Invalid UTF-8'),
            ),
          ),
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newImageFont'],
            <Object?>[imageData, malformed, 1],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('UTF-8 decoding error at argument 2: Invalid UTF-8'),
            ),
          ),
        );
      },
    );

    test(
      'glyph lookup and measurement APIs reject malformed UTF-8 LuaString inputs',
      () async {
        final runtime = Interpreter();
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
        final malformed = LuaString.fromBytes(const <int>[0xc3, 0x28]);

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
          () => luaCall(
            runtime,
            const ['love', 'font', 'newGlyphData'],
            <Object?>[rasterizer, malformed],
          ),
        );
        await expectUtf8Error(
          () => luaCallMethod(rasterizer, 'getGlyphData', <Object?>[malformed]),
        );
        await expectUtf8Error(
          () => luaCallMethod(rasterizer, 'hasGlyphs', <Object?>[malformed]),
        );
        await expectUtf8Error(
          () => luaCallMethod(font, 'hasGlyphs', <Object?>[malformed]),
        );
        await expectUtf8Error(
          () => luaCallMethod(font, 'getKerning', <Object?>[malformed, 'A']),
        );
        await expectUtf8Error(
          () => luaCallMethod(font, 'getWidth', <Object?>[malformed]),
        );
        await expectUtf8Error(
          () => luaCallMethod(font, 'getWrap', <Object?>[malformed, 10.0]),
        );
      },
    );

    test(
      'glyph data rejects invalid codepoints when re-encoding glyph strings',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );
        final glyphData = await luaCall(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, 0x110000],
        );

        await expectLater(
          () => luaCallMethod(glyphData, 'getGlyphString'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('UTF-8 decoding error: Invalid code point'),
            ),
          ),
        );
      },
    );
  });
}
