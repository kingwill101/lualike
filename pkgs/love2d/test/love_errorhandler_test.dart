import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.errorhandler binding', () {
    test(
      'returns an error loop that draws the message, copies to the clipboard, and exits on quit',
      () async {
        final clock = _TestLoveClock(nowSeconds: 0);
        final system = LoveSystemState();
        final host = LoveHeadlessHost(clock: clock, system: system);
        final runtime = LoveScriptRuntime(host: host);

        final loop = await _call(
          runtime,
          const ['love', 'errorhandler'],
          const <Object?>['boom'],
        );
        expect(loop, isA<BuiltinFunction>());

        runtime.context.beginDrawFrame();
        runtime.context.graphics.origin();
        expect(await _callCallable(loop as BuiltinFunction), isNull);

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
        expect(await _callCallable(loop), isNull);

        text = host.graphics.commands.single as LoveTextCommand;
        expect(text.text, contains('Copied to clipboard!'));
        expect(await system.getClipboardText(), contains('boom'));
        runtime.context.keyboard.setKeyDown('lctrl', down: false);

        runtime.context.events.pushMessage('quit', const <Object?>[1]);
        runtime.context.beginDrawFrame();
        runtime.context.graphics.origin();
        expect(await _callCallable(loop), 1);
      },
    );
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

  final double _nowSeconds;

  @override
  double nowSeconds() => _nowSeconds;

  final List<double> sleeps = <double>[];

  @override
  Future<void> sleepSeconds(double seconds) async {
    sleeps.add(seconds);
  }
}
