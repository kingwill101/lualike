import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LOVE event source parity', () {
    test(
      'poll_i is installed directly and mirrors upstream event iteration',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await _call(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['custom', 42, true],
        );
        await _call(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['focus', false],
        );

        expect(
          await _call(runtime, const ['love', 'event', 'poll_i']),
          <Object?>['custom', 42, true],
        );
        expect(
          await _call(runtime, const ['love', 'event', 'poll_i']),
          <Object?>['focus', false],
        );
        expect(await _call(runtime, const ['love', 'event', 'poll_i']), isNull);

        await _call(
          runtime,
          const ['love', 'event', 'push'],
          const <Object?>['resize', 800, 600],
        );
        final iterator = await _call(runtime, const ['love', 'event', 'poll']);
        expect(iterator, isA<BuiltinFunction>());
        expect(await _callCallable(iterator! as BuiltinFunction), <Object?>[
          'resize',
          800,
          600,
        ]);
      },
    );

    test('poll_i is available inside thread child runtimes', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final output = await _call(runtime, const [
        'love',
        'thread',
        'newChannel',
      ]);
      final thread = await _call(
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

      expect(await _callMethod(thread!, 'start', <Object?>[output]), isTrue);
      await _callMethod(thread, 'wait');
      expect(await _callMethod(thread, 'getError'), isNull);
      expect(await _callMethod(output!, 'pop'), 'visible');
      expect(await _callMethod(output, 'pop'), isTrue);
    });
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

Future<Object?> _callMethod(
  Object receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(
    _rawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
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

BuiltinFunction _rawMethod(Object receiver, String method) {
  final table = receiver is Value ? receiver.raw : receiver;
  expect(table, isA<Map>());
  final entry = (table! as Map)[method];
  return switch (entry) {
    final Value wrapped when wrapped.raw is BuiltinFunction =>
      wrapped.raw as BuiltinFunction,
    final BuiltinFunction function => function,
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
