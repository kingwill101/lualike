import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.run binding', () {
    test(
      'returns a main loop that calls love.load, love.update, love.draw, and sleeps via the host clock',
      () async {
        final clock = _TestLoveClock(nowSeconds: 0);
        final host = LoveHeadlessHost(clock: clock);
        final runtime = LoveScriptRuntime(host: host);

        await runtime.execute('''
testbed = {
  load_calls = 0,
  update_calls = 0,
  draw_calls = 0,
}

function love.load(args, rawArgs)
  testbed.load_calls = testbed.load_calls + 1
  testbed.load_arg_count = select('#', args, rawArgs)
end

function love.update(dt)
  testbed.update_calls = testbed.update_calls + 1
  testbed.last_dt = string.format("%.3f", dt)
end

function love.draw()
  testbed.draw_calls = testbed.draw_calls + 1
end
''');

        final mainLoop = await _call(runtime, const ['love', 'run']);
        expect(mainLoop, isA<BuiltinFunction>());

        var snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['load_calls'], 1);
        expect(snapshot['load_arg_count'], 2);
        expect(snapshot['update_calls'], 0);
        expect(snapshot['draw_calls'], 0);

        clock.currentTime = 0.25;
        expect(await _callCallable(mainLoop as BuiltinFunction), isNull);

        snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['update_calls'], 1);
        expect(snapshot['draw_calls'], 1);
        expect(snapshot['last_dt'], '0.250');
        expect(clock.sleeps, <double>[0.001]);
      },
    );

    test(
      'processes queued events and respects love.quit return values',
      () async {
        final clock = _TestLoveClock(nowSeconds: 0);
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost(clock: clock));

        await runtime.execute('''
testbed = {
  keypressed = nil,
  quit_calls = 0,
  update_calls = 0,
}

abortQuit = true

function love.keypressed(key, scancode, isrepeat)
  testbed.keypressed = string.format(
    "%s|%s|%s",
    key,
    tostring(scancode),
    tostring(isrepeat)
  )
end

function love.quit()
  testbed.quit_calls = testbed.quit_calls + 1
  return abortQuit
end

function love.update(dt)
  testbed.update_calls = testbed.update_calls + 1
end
''');

        final mainLoop = await _call(runtime, const ['love', 'run']);
        expect(mainLoop, isA<BuiltinFunction>());

        runtime.context.events.pushMessage('keypressed', <Object?>[
          'space',
          null,
          false,
        ]);
        runtime.context.events.pushMessage('quit', const <Object?>[7]);
        clock.currentTime = 0.25;
        expect(await _callCallable(mainLoop as BuiltinFunction), isNull);

        var snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['keypressed'], 'space|nil|false');
        expect(snapshot['quit_calls'], 1);
        expect(snapshot['update_calls'], 1);

        await runtime.execute('abortQuit = false');
        runtime.context.events.pushMessage('quit', const <Object?>['restart']);
        clock.currentTime = 0.5;
        expect(await _callCallable(mainLoop), 'restart');

        snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['quit_calls'], 2);
        expect(snapshot['update_calls'], 1);
      },
    );

    test('resets the graphics origin before each draw frame', () async {
      final clock = _TestLoveClock(nowSeconds: 0);
      final host = LoveHeadlessHost(clock: clock);
      final runtime = LoveScriptRuntime(host: host);

      await runtime.execute('''
function love.draw()
  love.graphics.translate(5, 6)
  love.graphics.rectangle("fill", 0, 0, 10, 10)
end
''');

      final mainLoop = await _call(runtime, const ['love', 'run']);
      expect(mainLoop, isA<BuiltinFunction>());

      clock.currentTime = 0.1;
      await _callCallable(mainLoop as BuiltinFunction);
      var rectangle = host.graphics.commands.single as LoveRectangleCommand;
      expect(rectangle.transform.storage[12], closeTo(5, 1e-9));
      expect(rectangle.transform.storage[13], closeTo(6, 1e-9));

      clock.currentTime = 0.2;
      await _callCallable(mainLoop);
      rectangle = host.graphics.commands.single as LoveRectangleCommand;
      expect(rectangle.transform.storage[12], closeTo(5, 1e-9));
      expect(rectangle.transform.storage[13], closeTo(6, 1e-9));
    });
  });
}

Future<Object?> _call(
  LoveScriptRuntime runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime.runtime, path).call(args));
}

Future<Object?> _callCallable(
  BuiltinFunction function, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(function.call(args));
}

BuiltinFunction _rawFunction(LuaRuntime runtime, List<String> path) {
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
