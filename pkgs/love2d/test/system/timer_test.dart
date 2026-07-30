import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.timer bindings', () {
    test(
      'use the attached host clock for time, delta, fps, and sleep',
      () async {
        final clock = _TestLoveClock(nowSeconds: 0);
        final host = LoveHeadlessHost(clock: clock);
        final lualike = LuaLike();
        final runtime = lualike.vm;

        installLove2d(runtime: runtime, host: host);

        expect(
          ((await lualike.execute('return love.timer.getTime()')) as Value)
              .unwrap(),
          0.0,
        );
        expect(
          ((await lualike.execute('return love.timer.getDelta()')) as Value)
              .unwrap(),
          0.0,
        );

        clock.currentTime = 0.25;
        expect(
          ((await lualike.execute('return love.timer.step()')) as Value)
              .unwrap(),
          0.25,
        );
        expect(
          ((await lualike.execute('return love.timer.getDelta()')) as Value)
              .unwrap(),
          0.25,
        );

        clock.currentTime = 0.5;
        expect(
          ((await lualike.execute('return love.timer.step()')) as Value)
              .unwrap(),
          0.25,
        );

        clock.currentTime = 1.25;
        expect(
          ((await lualike.execute('return love.timer.step()')) as Value)
              .unwrap(),
          0.75,
        );
        expect(
          ((await lualike.execute('return love.timer.getFPS()')) as Value)
              .unwrap(),
          2,
        );
        expect(
          ((await lualike.execute('return love.timer.getAverageDelta()'))
                  as Value)
              .unwrap(),
          closeTo(1.25 / 3, 1e-9),
        );

        await lualike.execute('love.timer.sleep(0.125)');
        expect(clock.sleeps, <double>[0.125]);
      },
    );

    test(
      'stepExternal keeps LOVE timer state aligned with an external loop',
      () {
        final clock = _TestLoveClock(nowSeconds: 0);
        final lualike = LuaLike();
        final runtime = lualike.vm;

        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(clock: clock),
        );

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

final class _TestLoveClock implements LoveClock {
  _TestLoveClock({required double nowSeconds}) : _nowSeconds = nowSeconds;

  double _nowSeconds;
  final List<double> sleeps = <double>[];

  set currentTime(double value) => _nowSeconds = value;

  @override
  double nowSeconds() => _nowSeconds;

  @override
  Future<void> sleepSeconds(double seconds) async {
    sleeps.add(seconds);
  }
}
