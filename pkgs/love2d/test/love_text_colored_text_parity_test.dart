import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Text colored text parity', () {
    test('constructor and addf accept numeric text inputs', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      final numericText = await luaCall(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font, 12345],
      );
      final stringText = await luaCall(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font, '12345'],
      );

      expect(
        await luaCallMethod(numericText, 'getWidth'),
        await luaCallMethod(stringText, 'getWidth'),
      );

      final text = await luaCall(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font],
      );
      final numericIndex = await luaCallMethod(text, 'addf', const <Object?>[
        67890,
        100.0,
        'left',
      ]);
      final stringIndex = await luaCallMethod(text, 'addf', const <Object?>[
        '67890',
        100.0,
        'left',
      ]);

      expect(
        await luaCallMethod(text, 'getWidth', <Object?>[numericIndex]),
        36.0,
      );
      expect(
        await luaCallMethod(text, 'getWidth', <Object?>[numericIndex]),
        await luaCallMethod(text, 'getWidth', <Object?>[stringIndex]),
      );
    });

    test(
      'constructor accepts numeric segments in colored text tables',
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

        final colored = await luaCall(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, coloredText],
        );
        final plain = await luaCall(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, '1234'],
        );

        expect(
          await luaCallMethod(colored, 'getWidth'),
          await luaCallMethod(plain, 'getWidth'),
        );
      },
    );

    test(
      'constructor and methods validate partial color tables like LOVE',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );
        final text = await luaCall(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'seed'],
        );

        final partialColorText = <Object?, Object?>{
          1: <Object?, Object?>{1: 1.0},
          2: 'A',
        };
        final invalidColorText = <Object?, Object?>{
          1: <Object?, Object?>{1: 'bad', 2: 'color', 3: 'table'},
          2: 'A',
        };

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newText'],
            <Object?>[font, partialColorText],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('color component at index 2'),
            ),
          ),
        );

        await expectLater(
          () => luaCallMethod(text, 'set', <Object?>[invalidColorText]),
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
  });
}
