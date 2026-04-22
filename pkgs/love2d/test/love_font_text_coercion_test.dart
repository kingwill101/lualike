import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font text coercion', () {
    test('Font:getWidth and Font:getWrap accept numeric text inputs', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(
        await luaCallMethod(font, 'getWidth', const <Object?>[12345]),
        await luaCallMethod(font, 'getWidth', const <Object?>['12345']),
      );
      expect(
        await luaCallMethod(font, 'getWrap', const <Object?>[12345, 100.0]),
        await luaCallMethod(font, 'getWrap', const <Object?>['12345', 100.0]),
      );
    });

    test(
      'Font:getWrap accepts numeric segments in colored text tables',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final coloredText = <Object?, Object?>{
          1: <Object?, Object?>{1: 1.0, 2: 0.25, 3: 0.5, 4: 1.0},
          2: 12,
          3: 34,
        };

        expect(
          await luaCallMethod(font, 'getWrap', <Object?>[coloredText, 100.0]),
          await luaCallMethod(font, 'getWrap', const <Object?>['1234', 100.0]),
        );
      },
    );

    test(
      'Font:getWrap rejects invalid non-string entries in colored text tables',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final invalidColoredText = <Object?, Object?>{
          1: <Object?, Object?>{1: 'bad', 2: 'color', 3: 'table'},
          2: 'A',
        };

        await expectLater(
          () => luaCallMethod(font, 'getWrap', <Object?>[
            invalidColoredText,
            100.0,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('numeric color component'),
            ),
          ),
        );
      },
    );

    test('Font:getWrap validates partial color tables like LOVE', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      final partialColorText = <Object?, Object?>{
        1: <Object?, Object?>{1: 1.0},
        2: 'A',
      };

      await expectLater(
        () =>
            luaCallMethod(font, 'getWrap', <Object?>[partialColorText, 100.0]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('color component at index 2'),
          ),
        ),
      );
    });

    test(
      'Font:getWrap keeps strict UTF-8 validation for LuaString table segments',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final malformed = LuaString.fromBytes(const <int>[0xc3, 0x28]);
        final coloredText = <Object?, Object?>{
          1: <Object?, Object?>{1: 1.0, 2: 1.0, 3: 1.0, 4: 1.0},
          2: malformed,
        };

        await expectLater(
          () => luaCallMethod(font, 'getWrap', <Object?>[coloredText, 100.0]),
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
  });
}
