import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font colored text table parity', () {
    test(
      'Font:getWrap ignores entries after the first hole in colored text tables',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final sparseColoredText = <Object?, Object?>{
          1: <Object?, Object?>{1: 1.0, 2: 0.25, 3: 0.5, 4: 1.0},
          2: 'A',
          4: 'B',
        };

        expect(
          await luaCallMethod(font, 'getWrap', <Object?>[
            sparseColoredText,
            100.0,
          ]),
          await luaCallMethod(font, 'getWrap', const <Object?>['A', 100.0]),
        );
      },
    );

    test(
      'Font:getWrap treats colored text tables without index 1 as empty text',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final missingFirstIndex = <Object?, Object?>{2: 'A'};

        expect(
          await luaCallMethod(font, 'getWrap', <Object?>[
            missingFirstIndex,
            100.0,
          ]),
          await luaCallMethod(font, 'getWrap', const <Object?>['', 100.0]),
        );
      },
    );

    test('Font:getWidth rejects colored text tables like LOVE', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      await expectLater(
        () => luaCallMethod(font, 'getWidth', <Object?>[
          <Object?, Object?>{
            1: <Object?, Object?>{1: 1.0, 2: 0.25, 3: 0.5, 4: 1.0},
            2: 'A',
          },
        ]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Font:getWidth expected a string at argument 2'),
          ),
        ),
      );
    });
  });
}
