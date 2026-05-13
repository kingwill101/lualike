import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.event bindings', () {
    test('push, poll, clear, and quit manage the event queue', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      expect(
        await luaCall(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['custom', 123, 'two', true],
        ),
        isTrue,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['focus', false],
        ),
        isTrue,
      );

      final iterator = await luaCall(runtime, const ['love', 'event', 'poll']);
      expect(iterator, isA<BuiltinFunction>());
      final poll = iterator! as BuiltinFunction;

      expect(await luaCallCallable(poll), <Object?>[
        'custom',
        123,
        'two',
        true,
      ]);
      expect(await luaCallCallable(poll), <Object?>['focus', false]);
      expect(await luaCallCallable(poll), isNull);

      expect(await luaCall(runtime, const ['love', 'event', 'quit']), isTrue);
      expect(await luaCallCallable(poll), <Object?>['quit', 0]);

      await luaCall(
        runtime,
        const ['love', 'event', 'push'],
        const <Object?>['resize', 800, 600],
      );
      await luaCall(runtime, const ['love', 'event', 'clear']);
      expect(await luaCallCallable(poll), isNull);
    });

    test(
      'wait resolves queued and future events and pump is harmless',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await luaCall(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['visible', true],
        );
        expect(
          await luaCall(runtime, const ['love', 'event', 'wait']),
          <Object?>['visible', true],
        );

        final pendingWait = luaRawFunction(runtime, const [
          'love',
          'event',
          'wait',
        ]).call(const <Object?>[]);
        await luaCall(runtime, const ['love', 'event', 'pump']);
        await luaCall(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['resize', 1280, 720],
        );

        expect(await luaResolveCallResult(pendingWait), <Object?>[
          'resize',
          1280,
          720,
        ]);
      },
    );
  });
}
