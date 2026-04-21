import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.physics module', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test('exposes meter defaults and world/body/fixture metadata', () async {
      expect(await _call(runtime, const ['love', 'physics', 'getMeter']), 30);

      await expectLater(
        _call(
          runtime,
          const ['love', 'physics', 'setMeter'],
          const <Object?>[0],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Physics error: invalid meter'),
          ),
        ),
      );

      await _call(
        runtime,
        const ['love', 'physics', 'setMeter'],
        const <Object?>[60],
      );
      expect(await _call(runtime, const ['love', 'physics', 'getMeter']), 60);

      final world = await _call(runtime, const ['love', 'physics', 'newWorld']);
      expect(world, isA<Map>());
      _expectDoubleListClose(
        await _callMethod(world!, 'getGravity'),
        const <double>[0, 0],
      );
      expect(await _callMethod(world, 'isSleepingAllowed'), isTrue);
      expect(await _callMethod(world, 'isLocked'), isFalse);
      expect(await _callMethod(world, 'type'), 'World');
      expect(
        await _callMethod(world, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      expect(await _callMethod(world, 'release'), isTrue);
      expect(await _callMethod(world, 'release'), isFalse);

      final body = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 90, 120, 'dynamic'],
      );
      expect(body, isA<Map>());
      _expectDoubleListClose(
        await _callMethod(body!, 'getPosition'),
        const <double>[90, 120],
      );
      expect(await _callMethod(body, 'getType'), 'dynamic');
      expect(await _callMethod(body, 'type'), 'Body');
      expect(
        await _callMethod(body, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      final bodyWorld = await _callMethod(body, 'getWorld');
      expect(await _callMethod(bodyWorld!, 'type'), 'World');
      expect(await _callMethod(bodyWorld, 'getBodyCount'), 1);

      final circle = await _call(
        runtime,
        const ['love', 'physics', 'newCircleShape'],
        const <Object?>[15],
      );
      expect(circle, isA<Map>());
      expect(await _callMethod(circle!, 'getType'), 'circle');
      expect(await _callMethod(circle, 'type'), 'CircleShape');
      expect(
        await _callMethod(circle, 'typeOf', const <Object?>['Shape']),
        isTrue,
      );
      expect(await _callMethod(circle, 'getChildCount'), 1);
      expect(await _callMethod(circle, 'getRadius'), 15.0);
      _expectDoubleListClose(
        await _callMethod(circle, 'getPoint'),
        const <double>[0, 0],
      );

      final fixture = await _call(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[body, circle, 2.5],
      );
      expect(fixture, isA<Map>());
      expect(await _callMethod(world, 'getBodyCount'), 1);
      final worldBodies = _indexedValues(
        await _callMethod(world, 'getBodies') as Map,
      );
      expect(worldBodies, hasLength(1));
      _expectDoubleListClose(
        await _callMethod(worldBodies.single as Object, 'getPosition'),
        const <double>[90, 120],
      );
      final bodyFixtures = _indexedValues(
        await _callMethod(body, 'getFixtures') as Map,
      );
      expect(bodyFixtures, hasLength(1));
      expect(
        await _callMethod(bodyFixtures.single as Object, 'getDensity'),
        2.5,
      );
      expect(await _callMethod(fixture!, 'getType'), 'circle');
      expect(await _callMethod(fixture, 'getDensity'), 2.5);
      expect(await _callMethod(fixture, 'type'), 'Fixture');
      expect(
        await _callMethod(fixture, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      final fixtureBody = await _callMethod(fixture, 'getBody');
      _expectDoubleListClose(
        await _callMethod(fixtureBody!, 'getPosition'),
        const <double>[90, 120],
      );

      final fixtureShape = await _callMethod(fixture, 'getShape');
      expect(fixtureShape, isA<Map>());
      expect(fixtureShape, isNot(same(circle)));
      expect(await _callMethod(fixtureShape!, 'getRadius'), 15.0);
    });

    test('updates worlds and bodies using LOVE units', () async {
      final world = await _call(
        runtime,
        const ['love', 'physics', 'newWorld'],
        const <Object?>[0, 0, false],
      );
      final body = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );

      await _callMethod(body!, 'setLinearVelocity', const <Object?>[60, 0]);
      await _callMethod(body, 'setAngularVelocity', const <Object?>[1.25]);
      await _callMethod(world!, 'update', const <Object?>[0.5, 8, 3]);

      expect(
        _doubleResults(await _callMethod(body, 'getPosition')).first,
        closeTo(30.0, 1e-6),
      );
      _expectDoubleListClose(
        await _callMethod(body, 'getLinearVelocity'),
        const <double>[60, 0],
      );
      expect(await _callMethod(body, 'getAngularVelocity'), 1.25);

      await _callMethod(body, 'setTransform', const <Object?>[40, 50, 0.75]);
      _expectDoubleListClose(
        await _callMethod(body, 'getTransform'),
        const <double>[40, 50, 0.75],
      );

      await _callMethod(body, 'setX', const <Object?>[10]);
      await _callMethod(body, 'setY', const <Object?>[25]);
      await _callMethod(body, 'setAngle', const <Object?>[0.5]);
      _expectDoubleListClose(
        await _callMethod(body, 'getTransform'),
        const <double>[10, 25, 0.5],
      );

      await _callMethod(world, 'setGravity', const <Object?>[0, 120]);
      await _callMethod(body, 'setGravityScale', const <Object?>[0.25]);
      await _callMethod(body, 'setBullet', const <Object?>[true]);
      await _callMethod(body, 'setSleepingAllowed', const <Object?>[false]);
      await _callMethod(body, 'setFixedRotation', const <Object?>[true]);
      await _callMethod(body, 'setActive', const <Object?>[false]);

      _expectDoubleListClose(
        await _callMethod(world, 'getGravity'),
        const <double>[0, 120],
      );
      expect(await _callMethod(body, 'getGravityScale'), 0.25);
      expect(await _callMethod(body, 'isBullet'), isTrue);
      expect(await _callMethod(body, 'isSleepingAllowed'), isFalse);
      expect(await _callMethod(body, 'isFixedRotation'), isTrue);
      expect(await _callMethod(body, 'isActive'), isFalse);

      await _callMethod(body, 'setActive', const <Object?>[true]);
      await _callMethod(world, 'translateOrigin', const <Object?>[10, -5]);
      _expectDoubleListClose(
        await _callMethod(body, 'getPosition'),
        const <double>[0, 30],
      );
    });

    test('transforms body coordinates and roundtrips user data', () async {
      final world = await _call(runtime, const ['love', 'physics', 'newWorld']);
      final body = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 100, 50, 'dynamic'],
      );

      await _callMethod(body!, 'setAngle', <Object?>[math.pi / 2]);
      await _callMethod(body, 'setAngularVelocity', const <Object?>[1]);
      await _callMethod(body, 'setUserData', const <Object?>['player']);
      expect(await _callMethod(body, 'getUserData'), 'player');

      _expectDoubleListClose(
        await _callMethod(body, 'getWorldPoint', const <Object?>[10, 0]),
        const <double>[100, 60],
      );
      _expectDoubleListClose(
        await _callMethod(body, 'getLocalPoint', const <Object?>[100, 60]),
        const <double>[10, 0],
      );
      _expectDoubleListClose(
        await _callMethod(body, 'getWorldPoints', const <Object?>[
          10,
          0,
          0,
          10,
        ]),
        const <double>[100, 60, 90, 50],
      );
      _expectDoubleListClose(
        await _callMethod(body, 'getLocalPoints', const <Object?>[
          100,
          60,
          90,
          50,
        ]),
        const <double>[10, 0, 0, 10],
      );
      _expectDoubleListClose(
        await _callMethod(body, 'getWorldVector', const <Object?>[0, 10]),
        const <double>[-10, 0],
      );
      _expectDoubleListClose(
        await _callMethod(body, 'getLocalVector', const <Object?>[-10, 0]),
        const <double>[0, 10],
      );
      _expectDoubleListClose(
        await _callMethod(
          body,
          'getLinearVelocityFromWorldPoint',
          const <Object?>[100, 80],
        ),
        const <double>[-30, 0],
      );
      _expectDoubleListClose(
        await _callMethod(
          body,
          'getLinearVelocityFromLocalPoint',
          const <Object?>[30, 0],
        ),
        const <double>[-30, 0],
      );

      final fixture = await _call(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          body,
          await _call(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[20],
          ),
          1,
        ],
      );
      await _callMethod(fixture!, 'setUserData', const <Object?>[123]);
      expect(await _callMethod(fixture, 'getUserData'), 123);
      expect(
        await _callMethod(fixture, 'testPoint', const <Object?>[100, 69]),
        isTrue,
      );
      expect(
        await _callMethod(fixture, 'testPoint', const <Object?>[100, 71]),
        isFalse,
      );
    });

    test('exposes fixture filter, bounds, and mass helpers', () async {
      final world = await _call(runtime, const ['love', 'physics', 'newWorld']);
      final body = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 100, 50, 'dynamic'],
      );
      final fixture = await _call(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          body,
          await _call(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[20],
          ),
          2.5,
        ],
      );

      expect(await _callMethod(fixture!, 'getCategory'), <Object?>[1]);
      expect(await _callMethod(fixture, 'getMask'), <Object?>[]);
      expect(await _callMethod(fixture, 'getFilterData'), <Object?>[
        1,
        65535,
        0,
      ]);

      await _callMethod(fixture, 'setCategory', <Object?>[
        Value(<Object?, Object?>{1: 1, 2: 4}),
      ]);
      expect(await _callMethod(fixture, 'getCategory'), <Object?>[1, 4]);

      await _callMethod(fixture, 'setMask', const <Object?>[2, 3]);
      expect(await _callMethod(fixture, 'getMask'), <Object?>[2, 3]);

      await _callMethod(fixture, 'setGroupIndex', const <Object?>[-7]);
      expect(await _callMethod(fixture, 'getGroupIndex'), -7);

      await _callMethod(fixture, 'setFilterData', const <Object?>[
        3,
        65534,
        -2,
      ]);
      expect(await _callMethod(fixture, 'getFilterData'), <Object?>[
        3,
        65534,
        -2,
      ]);
      expect(await _callMethod(fixture, 'getCategory'), <Object?>[1, 2]);
      expect(await _callMethod(fixture, 'getMask'), <Object?>[1]);

      _expectDoubleListClose(
        await _callMethod(fixture, 'getBoundingBox'),
        const <double>[80, 30, 120, 70],
      );

      final radiusInMeters = 20 / 30;
      final expectedMass = 2.5 * math.pi * radiusInMeters * radiusInMeters;
      final expectedInertia =
          expectedMass * (0.5 * radiusInMeters * radiusInMeters);
      _expectDoubleListClose(
        await _callMethod(fixture, 'getMassData'),
        <double>[0, 0, expectedMass, expectedInertia],
      );

      await expectLater(
        _callMethod(fixture, 'getBoundingBox', const <Object?>[2]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Physics error: index out of bounds'),
          ),
        ),
      );

      await expectLater(
        _callMethod(fixture, 'setCategory', const <Object?>[17]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Values must be in range 1-16.'),
          ),
        ),
      );
    });

    test(
      'exposes geometry helpers for circles, polygons, edges, and chains',
      () async {
        final circle = await _call(
          runtime,
          const ['love', 'physics', 'newCircleShape'],
          const <Object?>[5, -2, 10],
        );

        _expectDoubleListClose(
          await _callMethod(circle!, 'computeAABB', const <Object?>[20, 30, 0]),
          const <double>[15, 18, 35, 38],
        );
        expect(
          await _callMethod(circle, 'testPoint', const <Object?>[
            20,
            30,
            0,
            25,
            28,
          ]),
          isTrue,
        );
        expect(
          await _callMethod(circle, 'testPoint', const <Object?>[
            20,
            30,
            0,
            40,
            40,
          ]),
          isFalse,
        );

        final circleMass = _doubleResults(
          await _callMethod(circle, 'computeMass', const <Object?>[2]),
        );
        final radiusInMeters = 10 / 30;
        final expectedMass = 2 * math.pi * radiusInMeters * radiusInMeters;
        final expectedInertia =
            expectedMass *
            ((0.5 * radiusInMeters * radiusInMeters) +
                math.pow(5 / 30, 2) +
                math.pow(2 / 30, 2)) *
            30 *
            30;
        expect(circleMass[0], closeTo(5.0, 1e-6));
        expect(circleMass[1], closeTo(-2.0, 1e-6));
        expect(circleMass[2], closeTo(expectedMass, 1e-6));
        expect(circleMass[3], closeTo(expectedInertia, 1e-5));

        final polygon = await _call(
          runtime,
          const ['love', 'physics', 'newPolygonShape'],
          <Object?>[
            Value(<Object?, Object?>{
              1: 0,
              2: 0,
              3: 30,
              4: 0,
              5: 30,
              6: 20,
              7: 0,
              8: 20,
            }),
          ],
        );
        expect(await _callMethod(polygon!, 'validate'), isTrue);
        _expectPointSetClose(
          await _callMethod(polygon, 'getPoints'),
          const <({double x, double y})>[
            (x: 0, y: 0),
            (x: 30, y: 0),
            (x: 30, y: 20),
            (x: 0, y: 20),
          ],
        );

        final edge = await _call(
          runtime,
          const ['love', 'physics', 'newEdgeShape'],
          const <Object?>[0, 0, 30, 10],
        );
        _expectDoubleListClose(
          await _callMethod(edge!, 'getPoints'),
          const <double>[0, 0, 30, 10],
        );
        expect(await _callMethod(edge, 'getNextVertex'), <Object?>[]);
        expect(await _callMethod(edge, 'getPreviousVertex'), <Object?>[]);
        await _callMethod(edge, 'setNextVertex', const <Object?>[60, 15]);
        await _callMethod(edge, 'setPreviousVertex', const <Object?>[-5, -5]);
        _expectDoubleListClose(
          await _callMethod(edge, 'getNextVertex'),
          const <double>[60, 15],
        );
        _expectDoubleListClose(
          await _callMethod(edge, 'getPreviousVertex'),
          const <double>[-5, -5],
        );

        final chain = await _call(
          runtime,
          const ['love', 'physics', 'newChainShape'],
          <Object?>[
            false,
            Value(<Object?, Object?>{1: 0, 2: 0, 3: 30, 4: 0, 5: 30, 6: 20}),
          ],
        );
        expect(await _callMethod(chain!, 'getVertexCount'), 3);
        expect(await _callMethod(chain, 'getChildCount'), 2);
        _expectDoubleListClose(
          await _callMethod(chain, 'getPoint', const <Object?>[3]),
          const <double>[30, 20],
        );
        _expectDoubleListClose(
          await _callMethod(chain, 'getPoints'),
          const <double>[0, 0, 30, 0, 30, 20],
        );
        expect(await _callMethod(chain, 'getNextVertex'), <Object?>[]);
        expect(await _callMethod(chain, 'getPreviousVertex'), <Object?>[]);

        final childEdge = await _callMethod(
          chain,
          'getChildEdge',
          const <Object?>[1],
        );
        expect(await _callMethod(childEdge!, 'getType'), 'edge');
        _expectDoubleListClose(
          await _callMethod(childEdge, 'getPoints'),
          const <double>[0, 0, 30, 0],
        );

        await _callMethod(chain, 'setNextVertex', const <Object?>[40, 25]);
        await _callMethod(chain, 'setPreviousVertex', const <Object?>[-5, 0]);
        _expectDoubleListClose(
          await _callMethod(chain, 'getNextVertex'),
          const <double>[40, 25],
        );
        _expectDoubleListClose(
          await _callMethod(chain, 'getPreviousVertex'),
          const <double>[-5, 0],
        );
      },
    );

    test(
      'clones fixture shapes and rebuilds fixture geometry when mutated',
      () async {
        final world = await _call(runtime, const [
          'love',
          'physics',
          'newWorld',
        ]);
        final bodyA = await _call(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 0, 0, 'static'],
        );
        final bodyB = await _call(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 120, 0, 'static'],
        );

        final sourceShape = await _call(
          runtime,
          const ['love', 'physics', 'newCircleShape'],
          const <Object?>[15],
        );
        final fixtureA = await _call(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[bodyA, sourceShape, 1],
        );
        final fixtureB = await _call(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[
            bodyB,
            await _call(
              runtime,
              const ['love', 'physics', 'newCircleShape'],
              const <Object?>[15],
            ),
            1,
          ],
        );

        await _callMethod(sourceShape!, 'setRadius', const <Object?>[30]);
        final fixtureShape = await _callMethod(fixtureA!, 'getShape');
        expect(await _callMethod(sourceShape, 'getRadius'), 30.0);
        expect(await _callMethod(fixtureShape!, 'getRadius'), 15.0);

        expect(
          _doubleResults(
            await _call(
              runtime,
              const ['love', 'physics', 'getDistance'],
              <Object?>[fixtureA, fixtureB],
            ),
          ).first,
          closeTo(90.0, 1e-6),
        );

        await _callMethod(fixtureShape, 'setRadius', const <Object?>[20]);
        expect(await _callMethod(fixtureShape, 'getRadius'), 20.0);
        expect(
          _doubleResults(
            await _call(
              runtime,
              const ['love', 'physics', 'getDistance'],
              <Object?>[fixtureA, fixtureB],
            ),
          ).first,
          closeTo(85.0, 1e-6),
        );
      },
    );

    test('reports LOVE-style destroyed object errors', () async {
      final world = await _call(runtime, const ['love', 'physics', 'newWorld']);
      final body = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );
      final fixture = await _call(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          body,
          await _call(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[10],
          ),
          1,
        ],
      );

      await _callMethod(fixture!, 'destroy');
      await expectLater(
        _callMethod(fixture, 'getDensity'),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Attempt to use destroyed fixture.'),
          ),
        ),
      );

      final secondBody = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );
      await _callMethod(secondBody!, 'destroy');
      await expectLater(
        _callMethod(secondBody, 'getX'),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Attempt to use destroyed body.'),
          ),
        ),
      );

      final secondWorld = await _call(runtime, const [
        'love',
        'physics',
        'newWorld',
      ]);
      await _callMethod(secondWorld!, 'destroy');
      await expectLater(
        _callMethod(secondWorld, 'getBodyCount'),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Attempt to use destroyed world.'),
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
  Object object,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  final table = object is Value ? object.raw : object;
  expect(table, isA<Map>());

  final methodValue = (table as Map)[method];
  final callable = switch (methodValue) {
    final Value value => value.raw,
    final BuiltinFunction function => function,
    _ => methodValue,
  };
  expect(callable, isA<BuiltinFunction>());
  return _resolveCallResult(
    (callable as BuiltinFunction).call(<Object?>[object, ...args]),
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

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;

  if (resolved case final Value wrapped when wrapped.isMulti) {
    return (wrapped.raw as List<Object?>).map(_unwrap).toList(growable: false);
  }

  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;

List<Object?> _indexedValues(Map table) {
  final keys = table.keys.whereType<num>().map((key) => key.toInt()).toList()
    ..sort();
  return keys.map((key) => table[key]).toList(growable: false);
}

List<double> _doubleResults(Object? value) {
  return (value as List<Object?>)
      .map((entry) => (entry as num).toDouble())
      .toList(growable: false);
}

void _expectDoubleListClose(
  Object? value,
  List<double> expected, [
  double epsilon = 1e-5,
]) {
  final actual = _doubleResults(value);
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(
      actual[i],
      closeTo(expected[i], epsilon),
      reason: 'Unexpected value at index $i',
    );
  }
}

void _expectPointSetClose(
  Object? value,
  List<({double x, double y})> expected, [
  double epsilon = 1e-5,
]) {
  final actualValues = _doubleResults(value);
  expect(actualValues.length, expected.length * 2);

  final actualPoints = <({double x, double y})>[];
  for (var i = 0; i < actualValues.length; i += 2) {
    actualPoints.add((x: actualValues[i], y: actualValues[i + 1]));
  }

  for (final expectedPoint in expected) {
    expect(
      actualPoints.any(
        (actualPoint) =>
            (actualPoint.x - expectedPoint.x).abs() <= epsilon &&
            (actualPoint.y - expectedPoint.y).abs() <= epsilon,
      ),
      isTrue,
      reason: 'Missing point (${expectedPoint.x}, ${expectedPoint.y})',
    );
  }
}
