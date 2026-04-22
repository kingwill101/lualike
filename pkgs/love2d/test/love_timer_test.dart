import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.timer bindings', () {
    test(
      'use the attached host clock for time, delta, fps, and sleep',
      () async {
        final clock = TestLoveClock(nowSeconds: 0);
        final host = LoveHeadlessHost(clock: clock);
        final runtime = Interpreter();

        installLove2d(runtime: runtime, host: host);

        expect(await luaCall(runtime, const ['love', 'timer', 'getTime']), 0.0);
        expect(
          await luaCall(runtime, const ['love', 'timer', 'getDelta']),
          0.0,
        );

        clock.currentTime = 0.25;
        expect(await luaCall(runtime, const ['love', 'timer', 'step']), 0.25);
        expect(
          await luaCall(runtime, const ['love', 'timer', 'getDelta']),
          0.25,
        );

        clock.currentTime = 0.5;
        expect(await luaCall(runtime, const ['love', 'timer', 'step']), 0.25);

        clock.currentTime = 1.25;
        expect(await luaCall(runtime, const ['love', 'timer', 'step']), 0.75);
        expect(await luaCall(runtime, const ['love', 'timer', 'getFPS']), 2);
        expect(
          await luaCall(runtime, const ['love', 'timer', 'getAverageDelta']),
          closeTo(1.25 / 3, 1e-9),
        );

        await luaCall(
          runtime,
          const ['love', 'timer', 'sleep'],
          const <Object?>[0.125],
        );
        expect(clock.sleeps, <double>[0.125]);
      },
    );

    test(
      'stepExternal keeps LOVE timer state aligned with an external loop',
      () {
        final runtime = Interpreter();

        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final context = LoveRuntimeContext.of(runtime);
        expect(context.delta, 0);
        expect(context.fps, 0);

        expect(context.stepExternal(0.5), 0.5);
        expect(context.delta, 0.5);
        expect(context.fps, 0);

        expect(context.stepExternal(0.5), 0.5);
        expect(context.delta, 0.5);
        expect(context.fps, 0);

        expect(context.stepExternal(0.5), 0.5);
        expect(context.delta, 0.5);
        expect(context.fps, 2);
        expect(context.averageDelta, closeTo(0.5, 1e-9));

        expect(context.stepExternal(-1), 0);
        expect(context.delta, 0);
      },
    );
  });
}
