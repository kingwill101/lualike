import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font LuaJIT numeric text coercion parity', () {
    test('Font:getWidth and Font:getWrap stringify 1.0 like LuaJIT', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );
      final singleWidth =
          await luaCallMethod(font, 'getWidth', const <Object?>['1']) as num;

      expect(
        await luaCallMethod(font, 'getWidth', const <Object?>[1.0]),
        await luaCallMethod(font, 'getWidth', const <Object?>['1']),
      );
      expect(
        await luaCallMethod(font, 'getWidth', const <Object?>['1.0']),
        greaterThan(singleWidth),
      );

      expect(
        await luaCallMethod(font, 'getWrap', <Object?>[1.0, singleWidth]),
        await luaCallMethod(font, 'getWrap', <Object?>['1', singleWidth]),
      );
      expect(
        await luaCallMethod(font, 'getWrap', <Object?>['1.0', singleWidth]),
        isNot(
          await luaCallMethod(font, 'getWrap', <Object?>['1', singleWidth]),
        ),
      );
    });

    test(
      'Font:getWidth and Font:getWrap preserve LuaJIT formatting for -0.0 and 1000.0',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final negativeZeroWidth =
            await luaCallMethod(font, 'getWidth', const <Object?>['-0']) as num;
        final integerThousandWidth =
            await luaCallMethod(font, 'getWidth', const <Object?>['1000'])
                as num;

        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>[-0.0]),
          await luaCallMethod(font, 'getWidth', const <Object?>['-0']),
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['-0.0']),
          greaterThan(negativeZeroWidth),
        );

        expect(
          await luaCallMethod(font, 'getWrap', <Object?>[
            -0.0,
            negativeZeroWidth,
          ]),
          await luaCallMethod(font, 'getWrap', <Object?>[
            '-0',
            negativeZeroWidth,
          ]),
        );
        expect(
          await luaCallMethod(font, 'getWrap', <Object?>[
            '-0.0',
            negativeZeroWidth,
          ]),
          isNot(
            await luaCallMethod(font, 'getWrap', <Object?>[
              '-0',
              negativeZeroWidth,
            ]),
          ),
        );

        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>[1000.0]),
          await luaCallMethod(font, 'getWidth', const <Object?>['1000']),
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['1000.0']),
          greaterThan(integerThousandWidth),
        );

        expect(
          await luaCallMethod(font, 'getWrap', <Object?>[
            1000.0,
            integerThousandWidth,
          ]),
          await luaCallMethod(font, 'getWrap', <Object?>[
            '1000',
            integerThousandWidth,
          ]),
        );
        expect(
          await luaCallMethod(font, 'getWrap', <Object?>[
            '1000.0',
            integerThousandWidth,
          ]),
          isNot(
            await luaCallMethod(font, 'getWrap', <Object?>[
              '1000',
              integerThousandWidth,
            ]),
          ),
        );
      },
    );

    test(
      'Font:getWrap colored text numeric segments stringify 1.0 like LuaJIT',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final coloredText = <Object?, Object?>{
          1: <Object?, Object?>{1: 1.0, 2: 0.25, 3: 0.5, 4: 1.0},
          2: 1.0,
        };

        expect(
          await luaCallMethod(font, 'getWrap', <Object?>[coloredText, 100.0]),
          await luaCallMethod(font, 'getWrap', const <Object?>['1', 100.0]),
        );
      },
    );
  });
}
