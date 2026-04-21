import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.physics contact object bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test(
      'Body:getContacts and World:getContacts expose active Contact objects',
      () async {
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

        final bodyContacts = _indexedValues(
          await _callMethod(bodyA, 'getContacts') as Map,
        );
        final worldContacts = _indexedValues(
          await _callMethod(world, 'getContacts') as Map,
        );

        expect(bodyContacts, hasLength(1));
        expect(worldContacts, hasLength(1));

        final contact = bodyContacts.single;
        expect(await _callMethod(contact, 'type'), 'Contact');
        expect(
          await _callMethod(contact, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
        expect(await _callMethod(contact, 'isDestroyed'), isFalse);
        expect(await _callMethod(contact, 'isTouching'), isTrue);
        expect(await _callMethod(contact, 'isEnabled'), isTrue);

        _expectDoubleListClose(
          await _callMethod(contact, 'getChildren'),
          const <double>[1, 1],
        );

        final contactFixtures = _doubleTableFixtures(
          await _callMethod(contact, 'getFixtures') as List<Object?>,
        );
        expect(await _callMethod(contactFixtures[0], 'getType'), 'circle');
        expect(await _callMethod(contactFixtures[1], 'getType'), 'circle');
        final currentBodyAPosition = _doubleResults(
          await _callMethod(bodyA, 'getPosition'),
        );
        final currentBodyBPosition = _doubleResults(
          await _callMethod(bodyB, 'getPosition'),
        );
        _expectDoubleListClose(
          await _callMethod(
            await _callMethod(contactFixtures[0], 'getBody'),
            'getPosition',
          ),
          currentBodyAPosition,
        );
        _expectDoubleListClose(
          await _callMethod(
            await _callMethod(contactFixtures[1], 'getBody'),
            'getPosition',
          ),
          currentBodyBPosition,
        );

        final normal = _doubleResults(await _callMethod(contact, 'getNormal'));
        expect(normal[0], closeTo(1.0, 1e-6));
        expect(normal[1], closeTo(0.0, 1e-6));

        final positions = _doubleResults(
          await _callMethod(contact, 'getPositions'),
        );
        expect(positions, hasLength(2));
        expect(positions[0], closeTo(7.5, 1e-6));
        expect(positions[1], closeTo(0.0, 1e-6));
      },
    );

    test(
      'Contact setters and resetters roundtrip through LOVE bindings',
      () async {
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

        final fixtureA = await _call(
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
        final fixtureB = await _call(
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

        await _callMethod(fixtureA, 'setFriction', const <Object?>[0.2]);
        await _callMethod(fixtureB, 'setFriction', const <Object?>[0.8]);
        await _callMethod(fixtureA, 'setRestitution', const <Object?>[0.2]);
        await _callMethod(fixtureB, 'setRestitution', const <Object?>[0.6]);

        await _callMethod(world, 'update', const <Object?>[1 / 60]);
        final contact = _indexedValues(
          await _callMethod(world, 'getContacts') as Map,
        ).single;

        expect(await _callMethod(contact, 'getFriction'), closeTo(0.4, 1e-6));
        expect(
          await _callMethod(contact, 'getRestitution'),
          closeTo(0.6, 1e-6),
        );

        await _callMethod(contact, 'setFriction', const <Object?>[1.25]);
        await _callMethod(contact, 'setRestitution', const <Object?>[0.15]);
        await _callMethod(contact, 'setEnabled', const <Object?>[false]);

        expect(await _callMethod(contact, 'getFriction'), closeTo(1.25, 1e-6));
        expect(
          await _callMethod(contact, 'getRestitution'),
          closeTo(0.15, 1e-6),
        );
        expect(await _callMethod(contact, 'isEnabled'), isFalse);

        await _callMethod(contact, 'resetFriction');
        await _callMethod(contact, 'resetRestitution');
        await _callMethod(contact, 'setEnabled', const <Object?>[true]);

        expect(await _callMethod(contact, 'getFriction'), closeTo(0.4, 1e-6));
        expect(
          await _callMethod(contact, 'getRestitution'),
          closeTo(0.6, 1e-6),
        );
        expect(await _callMethod(contact, 'isEnabled'), isTrue);
      },
    );

    test(
      'Contact:setFriction affects later solver steps, not just getters',
      () async {
        final controlVelocity = await _runSlidingContactScenario(
          runtime,
          overrideContactFriction: false,
        );
        final overrideVelocity = await _runSlidingContactScenario(
          runtime,
          overrideContactFriction: true,
        );

        expect(controlVelocity.dx, lessThan(overrideVelocity.dx));
        expect(controlVelocity.dx, lessThan(50));
        expect(overrideVelocity.dx, greaterThan(controlVelocity.dx * 1.5));
        expect(overrideVelocity.dx, greaterThan(45));
      },
    );

    test(
      'Contact:setRestitution affects later solver steps, not just getters',
      () async {
        final controlVelocity = await _runRestitutionContactScenario(
          runtime,
          overrideContactRestitution: false,
        );
        final overrideVelocity = await _runRestitutionContactScenario(
          runtime,
          overrideContactRestitution: true,
        );

        expect(controlVelocity.dy, greaterThan(-1));
        expect(overrideVelocity.dy, lessThan(controlVelocity.dy - 100));
        expect(overrideVelocity.dy, lessThan(-50));
      },
    );

    test('destroyed contacts reject further use after separation', () async {
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
      final contact = _indexedValues(
        await _callMethod(world, 'getContacts') as Map,
      ).single;

      await _callMethod(bodyB, 'setPosition', const <Object?>[100, 0]);
      await _callMethod(world, 'update', const <Object?>[1 / 60]);

      expect(await _callMethod(contact, 'isDestroyed'), isTrue);
      await expectLater(
        _callMethod(contact, 'getNormal'),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Attempt to use destroyed contact.'),
          ),
        ),
      );
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

List<Object?> _indexedValues(Map table) {
  final keys = table.keys.whereType<num>().map((key) => key.toInt()).toList()
    ..sort();
  return keys.map((key) => table[key]).toList(growable: false);
}

List<Object?> _doubleTableFixtures(List<Object?> values) => values;

List<double> _doubleResults(Object? value) {
  return (value as List<Object?>)
      .map((entry) => (entry as num).toDouble())
      .toList(growable: false);
}

void _expectDoubleListClose(Object? value, List<double> expected) {
  expect(_doubleResults(value), hasLength(expected.length));
  final actual = _doubleResults(value);
  for (var index = 0; index < expected.length; index++) {
    expect(actual[index], closeTo(expected[index], 1e-6));
  }
}

Future<({double dx, double dy})> _runSlidingContactScenario(
  Interpreter runtime, {
  required bool overrideContactFriction,
}) async {
  final world = await _call(
    runtime,
    const ['love', 'physics', 'newWorld'],
    const <Object?>[0, 1000, false],
  );
  final floor = await _call(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 100, 'static'],
  );
  final box = await _call(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 80, 'dynamic'],
  );

  final floorShape = await _call(
    runtime,
    const ['love', 'physics', 'newRectangleShape'],
    const <Object?>[400, 20],
  );
  final boxShape = await _call(
    runtime,
    const ['love', 'physics', 'newRectangleShape'],
    const <Object?>[20, 20],
  );

  final floorFixture = await _call(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[floor, floorShape, 1],
  );
  final boxFixture = await _call(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[box, boxShape, 1],
  );

  await _callMethod(floorFixture, 'setFriction', const <Object?>[4]);
  await _callMethod(boxFixture, 'setFriction', const <Object?>[4]);
  await _callMethod(floorFixture, 'setRestitution', const <Object?>[0]);
  await _callMethod(boxFixture, 'setRestitution', const <Object?>[0]);
  await _callMethod(box, 'setFixedRotation', const <Object?>[true]);
  await _callMethod(box, 'setLinearVelocity', const <Object?>[120, 0]);

  await _callMethod(world, 'update', const <Object?>[1 / 60]);
  final contact = _indexedValues(
    await _callMethod(world, 'getContacts') as Map,
  ).single;

  if (overrideContactFriction) {
    await _callMethod(contact, 'setFriction', const <Object?>[0]);
  }

  for (var index = 0; index < 20; index++) {
    await _callMethod(world, 'update', const <Object?>[1 / 60]);
  }

  final velocity = _doubleResults(await _callMethod(box, 'getLinearVelocity'));
  return (dx: velocity[0], dy: velocity[1]);
}

Future<({double dx, double dy})> _runRestitutionContactScenario(
  Interpreter runtime, {
  required bool overrideContactRestitution,
}) async {
  final world = await _call(
    runtime,
    const ['love', 'physics', 'newWorld'],
    const <Object?>[0, 0, false],
  );
  final floor = await _call(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 100, 'static'],
  );
  final ball = await _call(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 80, 'dynamic'],
  );

  final floorShape = await _call(
    runtime,
    const ['love', 'physics', 'newRectangleShape'],
    const <Object?>[400, 20],
  );
  final ballShape = await _call(
    runtime,
    const ['love', 'physics', 'newCircleShape'],
    const <Object?>[10],
  );

  final floorFixture = await _call(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[floor, floorShape, 1],
  );
  final ballFixture = await _call(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[ball, ballShape, 1],
  );

  await _callMethod(floorFixture, 'setRestitution', const <Object?>[0]);
  await _callMethod(ballFixture, 'setRestitution', const <Object?>[0]);

  await _callMethod(world, 'update', const <Object?>[1 / 60]);
  final contact = _indexedValues(
    await _callMethod(world, 'getContacts') as Map,
  ).single;

  if (overrideContactRestitution) {
    await _callMethod(contact, 'setRestitution', const <Object?>[1]);
  }

  await _callMethod(ball, 'setLinearVelocity', const <Object?>[0, 240]);
  await _callMethod(world, 'update', const <Object?>[1 / 60]);

  final velocity = _doubleResults(await _callMethod(ball, 'getLinearVelocity'));
  return (dx: velocity[0], dy: velocity[1]);
}
