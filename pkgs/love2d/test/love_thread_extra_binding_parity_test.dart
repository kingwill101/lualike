import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LOVE thread extra binding parity', () {
    test(
      'thread child runtimes install the same enum-backed extras as the main runtime',
      () async {
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

        expect(await _callMethod(thread!, 'start', <Object?>[output]), isTrue);
        await _callMethod(thread, 'wait');
        expect(await _callMethod(thread, 'getError'), isNull);

        expect(await _callMethod(output!, 'pop'), 'string');
        expect(await _callMethod(output, 'pop'), 'hex');
        expect(await _callMethod(output, 'pop'), 'sha256');
        expect(await _callMethod(output, 'pop'), 'focus');
        expect(await _callMethod(output, 'pop'), 'quit');
        expect(await _callMethod(output, 'pop'), 'normal');
        expect(await _callMethod(output, 'pop'), 'battery');
        expect(await _callMethod(output, 'pop'), 'charging');
        expect(await _callMethod(output, 'pop'), 'ru');
        expect(await _callMethod(output, 'pop'), 'dynamic');
        expect(await _callMethod(output, 'pop'), 'circle');
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
