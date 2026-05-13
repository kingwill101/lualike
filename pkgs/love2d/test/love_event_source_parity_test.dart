import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE event source parity', () {
    test(
      'poll_i is installed directly and mirrors upstream event iteration',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await luaCallList(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['custom', 42, true],
        );
        await luaCallList(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['focus', false],
        );

        expect(
          await luaCallList(runtime, const ['love', 'event', 'poll_i']),
          <Object?>['custom', 42, true],
        );
        expect(
          await luaCallList(runtime, const ['love', 'event', 'poll_i']),
          <Object?>['focus', false],
        );
        expect(
          await luaCallList(runtime, const ['love', 'event', 'poll_i']),
          isNull,
        );

        await luaCallList(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['resize', 800, 600],
        );
        final iterator = await luaCallList(runtime, const [
          'love',
          'event',
          'poll',
        ]);
        expect(iterator, isA<BuiltinFunction>());
        expect(await luaCallCallable(iterator! as BuiltinFunction), <Object?>[
          'resize',
          800,
          600,
        ]);
      },
    );

    test('poll_i is available inside thread child runtimes', () async {
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
love.event.push('visible', true)
local name, arg = love.event.poll_i()
output:push(name)
output:push(arg)
''',
        ],
      );

      expect(
        await luaCallMethodList(thread!, 'start', <Object?>[output]),
        isTrue,
      );
      await luaCallMethodList(thread, 'wait');
      expect(await luaCallMethodList(thread, 'getError'), isNull);
      expect(await luaCallMethodList(output!, 'pop'), 'visible');
      expect(await luaCallMethodList(output, 'pop'), isTrue);
    });
  });
}
