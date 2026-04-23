import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE thread extra binding parity', () {
    test(
      'thread child runtimes install the same enum-backed extras as the main runtime',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final output = await luaCallList(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final thread = await luaCallList(
          runtime,
          const ['love', 'thread', 'newThread'],
          <Object?>[
            '''
local output = ...
output:push(ContainerType.string)
output:push(love.data.EncodeFormat.hex)
output:push(HashFunction.sha256)
output:push(Event.focus)
output:push(love.event.Event.quit)
output:push(HintingMode.normal)
output:push(love.system.PowerState.battery)
output:push(PowerState.charging)
output:push(JoystickHat.ru)
output:push(BodyType.dynamic)
output:push(love.physics.ShapeType.circle)
''',
          ],
        );

        expect(
          await luaCallMethodList(thread!, 'start', <Object?>[output]),
          isTrue,
        );
        await luaCallMethodList(thread, 'wait');
        expect(await luaCallMethodList(thread, 'getError'), isNull);

        expect(await luaCallMethodList(output!, 'pop'), 'string');
        expect(await luaCallMethodList(output, 'pop'), 'hex');
        expect(await luaCallMethodList(output, 'pop'), 'sha256');
        expect(await luaCallMethodList(output, 'pop'), 'focus');
        expect(await luaCallMethodList(output, 'pop'), 'quit');
        expect(await luaCallMethodList(output, 'pop'), 'normal');
        expect(await luaCallMethodList(output, 'pop'), 'battery');
        expect(await luaCallMethodList(output, 'pop'), 'charging');
        expect(await luaCallMethodList(output, 'pop'), 'ru');
        expect(await luaCallMethodList(output, 'pop'), 'dynamic');
        expect(await luaCallMethodList(output, 'pop'), 'circle');
      },
    );
  });
}
