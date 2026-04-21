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
        final runtime = Interpreter();

        installLove2d(runtime: runtime, host: host);

        expect(await _call(runtime, const ['love', 'timer', 'getTime']), 0.0);
        expect(await _call(runtime, const ['love', 'timer', 'getDelta']), 0.0);

        clock.currentTime = 0.25;
        expect(await _call(runtime, const ['love', 'timer', 'step']), 0.25);
        expect(await _call(runtime, const ['love', 'timer', 'getDelta']), 0.25);

        clock.currentTime = 0.5;
        expect(await _call(runtime, const ['love', 'timer', 'step']), 0.25);

        clock.currentTime = 1.25;
        expect(await _call(runtime, const ['love', 'timer', 'step']), 0.75);
        expect(await _call(runtime, const ['love', 'timer', 'getFPS']), 2);
        expect(
          await _call(runtime, const ['love', 'timer', 'getAverageDelta']),
          closeTo(1.25 / 3, 1e-9),
        );

        await _call(
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

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;

  if (resolved case final Value wrapped when wrapped.isMulti) {
    return (wrapped.raw as List<Object?>).map(_unwrap).toList(growable: false);
  }

  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;

class _TestLoveClock implements LoveClock {
  _TestLoveClock({required double nowSeconds}) : _nowSeconds = nowSeconds;

  double _nowSeconds;

  set currentTime(double value) => _nowSeconds = value;

  @override
  double nowSeconds() => _nowSeconds;

  final List<double> sleeps = <double>[];

  @override
  Future<void> sleepSeconds(double seconds) async {
    sleeps.add(seconds);
  }
}
