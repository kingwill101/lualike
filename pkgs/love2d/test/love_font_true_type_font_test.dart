import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics true type fonts', () {
    test('reject invalid unicode scalars in hasGlyphs', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>['LuaLike']),
        isTrue,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>[0x1f642]),
        isTrue,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>[-1]),
        isFalse,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>[0xd800]),
        isFalse,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>[0x110000]),
        isFalse,
      );
      expect(
        await luaCallMethod(font, 'hasGlyphs', const <Object?>['']),
        isFalse,
      );
    });

    test('expose LOVE object semantics', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(await luaCallMethod(font, 'type'), 'Font');
      expect(
        await luaCallMethod(font, 'typeOf', const <Object?>['Font']),
        isTrue,
      );
      expect(
        await luaCallMethod(font, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      expect(
        await luaCallMethod(font, 'typeOf', const <Object?>['Rasterizer']),
        isFalse,
      );
      expect(await luaCallMethod(font, 'release'), isTrue);
      expect(await luaCallMethod(font, 'release'), isFalse);
    });

    test('validate glyph-like arguments for kerning and hasGlyphs', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(
        await luaCallMethod(font, 'getKerning', const <Object?>['A', 'V']),
        0.0,
      );
      expect(
        await luaCallMethod(font, 'getKerning', const <Object?>[65, 86]),
        0.0,
      );

      await expectLater(
        () => luaCallMethod(font, 'hasGlyphs', <Object?>[<Object?, Object?>{}]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Font:hasGlyphs expected a number at argument 2'),
          ),
        ),
      );

      await expectLater(
        () => luaCallMethod(font, 'getKerning', <Object?>[
          <Object?, Object?>{},
          'V',
        ]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Font:getKerning expected a number at argument 2'),
          ),
        ),
      );

      await expectLater(
        () => luaCallMethod(font, 'getKerning', const <Object?>['A']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Font:getKerning expected a string at argument 3'),
          ),
        ),
      );

      await expectLater(
        () => luaCallMethod(font, 'getKerning', const <Object?>['', 'V']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              'Font:getKerning UTF-8 decoding error at argument 2: Not enough space',
            ),
          ),
        ),
      );

      await expectLater(
        () => luaCallMethod(font, 'getKerning', const <Object?>[65, 'V']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Font:getKerning expected a number at argument 3'),
          ),
        ),
      );
    });
  });
}
