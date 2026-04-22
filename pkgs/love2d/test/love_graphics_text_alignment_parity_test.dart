import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics text alignment parity', () {
    test(
      'printf treats nil alignment like an omitted left alignment',
      () async {
        final host = LoveHeadlessHost();
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        host.graphics.beginFrame();
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'printf'],
            <Object?>['Lua', font, 4.0, 8.0, 96.0, null],
          ),
          isNull,
        );

        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveTextCommand;
        expect(command.text, 'Lua');
        expect(command.limit, 96.0);
        expect(command.align, 'left');
      },
    );

    test(
      'printf and Text formatted methods use LOVE alignment error text',
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
          <Object?>[font, 'Lua'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'printf'],
            <Object?>['Lua', font, 0.0, 0.0, 96.0, 'bogus'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "Invalid alignment 'bogus', expected one of: "
                  "'left', 'right', 'center', 'justify'",
            ),
          ),
        );

        await expectLater(
          () => luaCallMethod(text, 'addf', <Object?>['Lua', 96.0, 'bogus']),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "Invalid align mode 'bogus', expected one of: "
                  "'left', 'right', 'center', 'justify'",
            ),
          ),
        );

        await expectLater(
          () => luaCallMethod(text, 'setf', <Object?>['Lua', 96.0, 'bogus']),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "Invalid align mode 'bogus', expected one of: "
                  "'left', 'right', 'center', 'justify'",
            ),
          ),
        );
      },
    );
  });
}
