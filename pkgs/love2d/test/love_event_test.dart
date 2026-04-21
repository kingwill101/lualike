import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.event bindings', () {
    test('push, poll, clear, and quit manage the event queue', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      expect(
        await _call(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['custom', 123, 'two', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['focus', false],
        ),
        isTrue,
      );

      final iterator = await _call(runtime, const ['love', 'event', 'poll']);
      expect(iterator, isA<BuiltinFunction>());
      final poll = iterator! as BuiltinFunction;

      expect(await _callCallable(poll), <Object?>['custom', 123, 'two', true]);
      expect(await _callCallable(poll), <Object?>['focus', false]);
      expect(await _callCallable(poll), isNull);

      expect(await _call(runtime, const ['love', 'event', 'quit']), isTrue);
      expect(await _callCallable(poll), <Object?>['quit', 0]);

      await _call(
        runtime,
        const ['love', 'event', 'push'],
        const <Object?>['resize', 800, 600],
      );
      await _call(runtime, const ['love', 'event', 'clear']);
      expect(await _callCallable(poll), isNull);
    });

    test(
      'wait resolves queued and future events and pump is harmless',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await _call(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['visible', true],
        );
        expect(await _call(runtime, const ['love', 'event', 'wait']), <Object?>[
          'visible',
          true,
        ]);

        final pendingWait = _rawFunction(runtime, const [
          'love',
          'event',
          'wait',
        ]).call(const <Object?>[]);
        await _call(runtime, const ['love', 'event', 'pump']);
        await _call(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['resize', 1280, 720],
        );

        expect(await _resolveCallResult(pendingWait), <Object?>[
          'resize',
          1280,
          720,
        ]);
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

Future<Object?> _callCallable(
  BuiltinFunction function, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(function.call(args));
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
