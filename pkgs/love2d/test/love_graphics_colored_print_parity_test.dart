import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics colored print parity', () {
    test('print and printf accept numeric and colored text inputs', () async {
      final host = LoveHeadlessHost();
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: host);

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

      host.graphics.beginFrame();
      await luaCall(
        runtime,
        const ['love', 'graphics', 'print'],
        <Object?>[12345, font, 4.0, 8.0],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'printf'],
        <Object?>[coloredText, font, 4.0, 8.0, 96.0, 'center'],
      );

      expect(host.graphics.commands, hasLength(2));

      final printCommand = host.graphics.commands[0] as LoveTextCommand;
      final printfCommand = host.graphics.commands[1] as LoveTextCommand;

      expect(printCommand.text, '12345');
      expect(printCommand.spans, hasLength(1));
      expect(printCommand.spans.single.text, '12345');
      expect(printCommand.spans.single.color, isNull);

      expect(printfCommand.text, '1234');
      expect(printfCommand.spans, hasLength(2));
      expect(printfCommand.spans[0].text, '12');
      expect(
        printfCommand.spans[0].color,
        const LoveColor(1.0, 0.25, 0.5, 1.0),
      );
      expect(printfCommand.spans[1].text, '34');
      expect(
        printfCommand.spans[1].color,
        const LoveColor(1.0, 0.25, 0.5, 1.0),
      );
      expect(printfCommand.limit, 96.0);
      expect(printfCommand.align, 'center');
    });

    test('print and printf validate partial color tables like LOVE', () async {
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
      final invalidColorText = <Object?, Object?>{
        1: <Object?, Object?>{1: 'bad', 2: 'color', 3: 'table'},
        2: 'A',
      };

      await expectLater(
        () => luaCall(
          runtime,
          const ['love', 'graphics', 'print'],
          <Object?>[partialColorText, font, 0.0, 0.0],
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
        () => luaCall(
          runtime,
          const ['love', 'graphics', 'printf'],
          <Object?>[invalidColorText, font, 0.0, 0.0, 100.0, 'left'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('numeric color component'),
          ),
        ),
      );
    });
  });
}
