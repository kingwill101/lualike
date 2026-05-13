import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.errorhandler binding', () {
    test(
      'returns an error loop that draws the message, copies to the clipboard, and exits on quit',
      () async {
        final clock = TestLoveClock(nowSeconds: 0);
        final system = LoveSystemState();
        final host = LoveHeadlessHost(clock: clock, system: system);
        final runtime = LoveScriptRuntime(host: host);

        final loop = await luaCall(
          runtime,
          const ['love', 'errorhandler'],
          const <Object?>['boom'],
        );
        expect(loop, isA<BuiltinFunction>());

        runtime.context.beginDrawFrame();
        runtime.context.graphics.origin();
        expect(await luaCallCallable(loop as BuiltinFunction), isNull);

        var text = host.graphics.commands.single as LoveTextCommand;
        expect(text.text, contains('Error'));
        expect(text.text, contains('boom'));
        expect(text.text, contains('Press Escape to quit'));
        expect(clock.sleeps, <double>[0.1]);

        runtime.context.keyboard.setKeyDown('lctrl', down: true);
        runtime.context.events.pushMessage('keypressed', <Object?>[
          'c',
          null,
          false,
        ]);
        runtime.context.beginDrawFrame();
        runtime.context.graphics.origin();
        expect(await luaCallCallable(loop), isNull);

        text = host.graphics.commands.single as LoveTextCommand;
        expect(text.text, contains('Copied to clipboard!'));
        expect(await system.getClipboardText(), contains('boom'));
        runtime.context.keyboard.setKeyDown('lctrl', down: false);

        runtime.context.events.pushMessage('quit', const <Object?>[1]);
        runtime.context.beginDrawFrame();
        runtime.context.graphics.origin();
        expect(await luaCallCallable(loop), 1);
      },
    );

    test(
      'LoveScriptRuntime falls back to love.errhand when errorhandler is nil',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}
love.errorhandler = nil

function love.errhand(msg)
  testbed.msg = msg
  return function()
    return 7
  end
end
''');

        final loop = await runtime.createErrorHandlerLoop('boom');
        expect(loop, isNotNull);
        expect(runtime.unwrapGlobalTable('testbed')!['msg'], 'boom');
        expect(
          await luaResolveCallResult(runtime.callErrorHandlerLoop(loop!)),
          7,
        );
      },
    );
  });
}
