import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.physics contact and inertia bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test('Body:setInertia updates inertia-dependent getters', () async {
      final world = await _call(
        runtime,
        const ['love', 'physics', 'newWorld'],
      );
      final body = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );
      await _call(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          body,
          await _call(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[10],
          ),
          2,
        ],
      );

      final initialMassData = _doubleResults(await _callMethod(body, 'getMassData'));
      await _callMethod(body, 'setInertia', const <Object?>[540]);

      expect(await _callMethod(body, 'getInertia'), closeTo(540, 1e-6));
      final updatedMassData = _doubleResults(await _callMethod(body, 'getMassData'));
      expect(updatedMassData[0], closeTo(initialMassData[0], 1e-6));
      expect(updatedMassData[1], closeTo(initialMassData[1], 1e-6));
      expect(updatedMassData[2], closeTo(initialMassData[2], 1e-6));
      expect(updatedMassData[3], closeTo(540, 1e-6));
    });

    test('World:getContactCount and Body:isTouching reflect stepped contacts', () async {
      final world = await _call(
        runtime,
        const ['love', 'physics', 'newWorld'],
        const <Object?>[0, 0, false],
      );
      final bodyA = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );
      final bodyB = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 15, 0, 'dynamic'],
      );

      await _call(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          bodyA,
          await _call(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[10],
          ),
          1,
        ],
      );
      await _call(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          bodyB,
          await _call(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[10],
          ),
          1,
        ],
      );

      await _callMethod(world, 'update', const <Object?>[1 / 60]);
      expect(await _callMethod(world, 'getContactCount'), 1);
      expect(await _callMethod(bodyA, 'isTouching', <Object?>[bodyB]), isTrue);
      expect(await _callMethod(bodyB, 'isTouching', <Object?>[bodyA]), isTrue);

      await _callMethod(bodyB, 'setPosition', const <Object?>[100, 0]);
      await _callMethod(world, 'update', const <Object?>[1 / 60]);
      expect(await _callMethod(world, 'getContactCount'), 0);
      expect(await _callMethod(bodyA, 'isTouching', <Object?>[bodyB]), isFalse);
      expect(await _callMethod(bodyB, 'isTouching', <Object?>[bodyA]), isFalse);
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

Future<Object?> _callMethod(
  Object? receiver,
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

BuiltinFunction _rawMethod(Object? receiver, String method) {
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

List<double> _doubleResults(Object? value) {
  return (value as List<Object?>)
      .map((entry) => (entry as num).toDouble())
      .toList(growable: false);
}
