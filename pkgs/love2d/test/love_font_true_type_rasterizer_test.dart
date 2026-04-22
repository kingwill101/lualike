import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font true type rasterizers', () {
    test('expose estimated glyph data for individual glyph queries', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final rasterizer = await luaCallList(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        const <Object?>[12, 'light', 2.0],
      );

      final glyphData = await luaCallList(
        runtime,
        const ['love', 'font', 'newGlyphData'],
        <Object?>[rasterizer, 'A'],
      );

      expect(await luaCallMethodList(glyphData, 'type'), 'GlyphData');
      expect(await luaCallMethodList(glyphData, 'getGlyph'), 65);
      expect(await luaCallMethodList(glyphData, 'getGlyphString'), 'A');
      expect(await luaCallMethodList(glyphData, 'getFormat'), 'la8');
      expect(await luaCallMethodList(glyphData, 'getDimensions'), <Object?>[
        14,
        24,
      ]);
      expect(await luaCallMethodList(glyphData, 'getBearing'), <Object?>[
        0,
        19,
      ]);
      expect(await luaCallMethodList(glyphData, 'getAdvance'), 14);
      expect(await luaCallMethodList(glyphData, 'getSize'), 672);

      final viaMethod = await luaCallMethodList(
        rasterizer,
        'getGlyphData',
        const <Object?>[' '],
      );
      expect(await luaCallMethodList(viaMethod, 'getFormat'), 'la8');
      expect(await luaCallMethodList(viaMethod, 'getDimensions'), <Object?>[
        8,
        24,
      ]);
      expect(await luaCallMethodList(viaMethod, 'getAdvance'), 8);
      expect(await luaCallMethodList(viaMethod, 'getSize'), 384);
    });

    test(
      'report approximate glyph availability for valid unicode scalars',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );

        expect(
          await luaCallMethodList(rasterizer, 'hasGlyphs', const <Object?>[
            'LuaLike',
          ]),
          isTrue,
        );
        expect(
          await luaCallMethodList(rasterizer, 'hasGlyphs', const <Object?>[
            0x1f642,
          ]),
          isTrue,
        );
        expect(
          await luaCallMethodList(rasterizer, 'hasGlyphs', const <Object?>[
            0x110000,
          ]),
          isFalse,
        );
        expect(
          await luaCallMethodList(rasterizer, 'hasGlyphs', const <Object?>[
            0xd800,
          ]),
          isFalse,
        );
        expect(
          await luaCallMethodList(rasterizer, 'hasGlyphs', const <Object?>['']),
          isFalse,
        );
        await expectLater(
          () => luaCallMethodList(rasterizer, 'hasGlyphs'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Rasterizer:hasGlyphs expected a number at argument 2'),
            ),
          ),
        );
      },
    );

    test(
      'estimated glyph data uses transparent-white la8 placeholder bytes',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12, 'light', 2.0],
        );
        final glyphData = await luaCallList(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, 'A'],
        );

        final payload = requireLuaStringBytes(
          await luaCallMethodRaw(glyphData, 'getString'),
        );
        expect(payload.length, 672);
        expect(payload[0], 255);
        expect(payload[1], 0);
        expect(payload[2], 255);
        expect(payload[3], 0);
        expect(payload[payload.length - 2], 255);
        expect(payload[payload.length - 1], 0);
      },
    );

    test(
      'glyph extraction distinguishes empty strings and non-string errors',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'font', 'newGlyphData'],
            <Object?>[rasterizer, ''],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'love.font.newGlyphData UTF-8 decoding error at argument 2: Not enough space',
              ),
            ),
          ),
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'font', 'newGlyphData'],
            <Object?>[rasterizer, <Object?, Object?>{}],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'love.font.newGlyphData expected a number at argument 2',
              ),
            ),
          ),
        );

        await expectLater(
          () => luaCallMethodList(rasterizer, 'getGlyphData', const <Object?>[
            '',
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Rasterizer:getGlyphData UTF-8 decoding error at argument 2: Not enough space',
              ),
            ),
          ),
        );

        await expectLater(
          () => luaCallMethodList(rasterizer, 'getGlyphData', <Object?>[
            <Object?, Object?>{},
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Rasterizer:getGlyphData expected a number at argument 2',
              ),
            ),
          ),
        );
      },
    );

    test('glyph extraction reports LOVE-style invalid UTF-8 errors', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final rasterizer = await luaCallList(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        const <Object?>[12],
      );
      final malformed = LuaString.fromBytes(const <int>[0xc3, 0x28]);

      await expectLater(
        () => luaCallList(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, malformed],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              'love.font.newGlyphData UTF-8 decoding error at argument 2: Invalid UTF-8',
            ),
          ),
        ),
      );

      await expectLater(
        () =>
            luaCallMethodList(rasterizer, 'getGlyphData', <Object?>[malformed]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              'Rasterizer:getGlyphData UTF-8 decoding error at argument 2: Invalid UTF-8',
            ),
          ),
        ),
      );
    });
  });
}
