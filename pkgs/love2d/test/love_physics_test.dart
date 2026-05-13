import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';
import 'test_support/physics_test_support.dart';

void main() {
  group('love.physics module', () {
    late LuaRuntime runtime;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime);
    });

    test('exposes meter defaults and world/body/fixture metadata', () async {
      expect(await luaCall(runtime, const ['love', 'physics', 'getMeter']), 30);

      await expectLater(
        luaCall(
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

      await luaCall(
        runtime,
        const ['love', 'physics', 'setMeter'],
        const <Object?>[60],
      );
      expect(await luaCall(runtime, const ['love', 'physics', 'getMeter']), 60);

      final world = await luaCall(runtime, const [
        'love',
        'physics',
        'newWorld',
      ]);
      expect(world, isA<Map>());
      expectDoubleListClose(
        await luaCallMethod(world!, 'getGravity'),
        const <double>[0, 0],
      );
      expect(await luaCallMethod(world, 'isSleepingAllowed'), isTrue);
      expect(await luaCallMethod(world, 'isLocked'), isFalse);
      expect(await luaCallMethod(world, 'type'), 'World');
      expect(
        await luaCallMethod(world, 'typeOf', const <Object?>['Object']),
        isTrue,
      );

      final body = await luaCall(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 90, 120, 'dynamic'],
      );
      expect(body, isA<Map>());
      expectDoubleListClose(
        await luaCallMethod(body!, 'getPosition'),
        const <double>[90, 120],
      );
      expect(await luaCallMethod(body, 'getType'), 'dynamic');
      expect(await luaCallMethod(body, 'type'), 'Body');
      expect(
        await luaCallMethod(body, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      final bodyWorld = await luaCallMethod(body, 'getWorld');
      expect(await luaCallMethod(bodyWorld!, 'type'), 'World');
      expect(await luaCallMethod(bodyWorld, 'getBodyCount'), 1);

      final circle = await luaCall(
        runtime,
        const ['love', 'physics', 'newCircleShape'],
        const <Object?>[15],
      );
      expect(circle, isA<Map>());
      expect(await luaCallMethod(circle!, 'getType'), 'circle');
      expect(await luaCallMethod(circle, 'type'), 'CircleShape');
      expect(
        await luaCallMethod(circle, 'typeOf', const <Object?>['Shape']),
        isTrue,
      );
      expect(await luaCallMethod(circle, 'getChildCount'), 1);
      expect(await luaCallMethod(circle, 'getRadius'), 15.0);
      expectDoubleListClose(
        await luaCallMethod(circle, 'getPoint'),
        const <double>[0, 0],
      );

      final fixture = await luaCall(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[body, circle, 2.5],
      );
      expect(fixture, isA<Map>());
      expect(await luaCallMethod(world, 'getBodyCount'), 1);
      final worldBodies = indexedValues(
        await luaCallMethod(world, 'getBodies') as Map,
      );
      expect(worldBodies, hasLength(1));
      expectDoubleListClose(
        await luaCallMethod(worldBodies.single as Object, 'getPosition'),
        const <double>[90, 120],
      );
      final bodyFixtures = indexedValues(
        await luaCallMethod(body, 'getFixtures') as Map,
      );
      expect(bodyFixtures, hasLength(1));
      expect(
        await luaCallMethod(bodyFixtures.single as Object, 'getDensity'),
        2.5,
      );
      expect(await luaCallMethod(fixture!, 'getType'), 'circle');
      expect(await luaCallMethod(fixture, 'getDensity'), 2.5);
      expect(await luaCallMethod(fixture, 'type'), 'Fixture');
      expect(
        await luaCallMethod(fixture, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      final fixtureBody = await luaCallMethod(fixture, 'getBody');
      expectDoubleListClose(
        await luaCallMethod(fixtureBody!, 'getPosition'),
        const <double>[90, 120],
      );

      final fixtureShape = await luaCallMethod(fixture, 'getShape');
      expect(fixtureShape, isA<Map>());
      expect(fixtureShape, isNot(same(circle)));
      expect(await luaCallMethod(fixtureShape!, 'getRadius'), 15.0);

      expect(await luaCallMethod(world, 'release'), isTrue);
      expect(await luaCallMethod(world, 'release'), isFalse);
    });

    test('updates worlds and bodies using LOVE units', () async {
      final world = await luaCall(
        runtime,
        const ['love', 'physics', 'newWorld'],
        const <Object?>[0, 0, false],
      );
      final body = await luaCall(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );

      await luaCallMethod(body!, 'setLinearVelocity', const <Object?>[60, 0]);
      await luaCallMethod(body, 'setAngularVelocity', const <Object?>[1.25]);
      await luaCallMethod(world!, 'update', const <Object?>[0.5, 8, 3]);

      expect(
        doubleResults(await luaCallMethod(body, 'getPosition')).first,
        closeTo(30.0, 1e-6),
      );
      expectDoubleListClose(
        await luaCallMethod(body, 'getLinearVelocity'),
        const <double>[60, 0],
      );
      expect(await luaCallMethod(body, 'getAngularVelocity'), 1.25);

      await luaCallMethod(body, 'setTransform', const <Object?>[40, 50, 0.75]);
      expectDoubleListClose(
        await luaCallMethod(body, 'getTransform'),
        const <double>[40, 50, 0.75],
      );

      await luaCallMethod(body, 'setX', const <Object?>[10]);
      await luaCallMethod(body, 'setY', const <Object?>[25]);
      await luaCallMethod(body, 'setAngle', const <Object?>[0.5]);
      expectDoubleListClose(
        await luaCallMethod(body, 'getTransform'),
        const <double>[10, 25, 0.5],
      );

      await luaCallMethod(world, 'setGravity', const <Object?>[0, 120]);
      await luaCallMethod(body, 'setGravityScale', const <Object?>[0.25]);
      await luaCallMethod(body, 'setBullet', const <Object?>[true]);
      await luaCallMethod(body, 'setSleepingAllowed', const <Object?>[false]);
      await luaCallMethod(body, 'setFixedRotation', const <Object?>[true]);
      await luaCallMethod(body, 'setActive', const <Object?>[false]);

      expectDoubleListClose(
        await luaCallMethod(world, 'getGravity'),
        const <double>[0, 120],
      );
      expect(await luaCallMethod(body, 'getGravityScale'), 0.25);
      expect(await luaCallMethod(body, 'isBullet'), isTrue);
      expect(await luaCallMethod(body, 'isSleepingAllowed'), isFalse);
      expect(await luaCallMethod(body, 'isFixedRotation'), isTrue);
      expect(await luaCallMethod(body, 'isActive'), isFalse);

      await luaCallMethod(body, 'setActive', const <Object?>[true]);
      await luaCallMethod(world, 'translateOrigin', const <Object?>[10, -5]);
      expectDoubleListClose(
        await luaCallMethod(body, 'getPosition'),
        const <double>[0, 30],
      );
    });

    test('transforms body coordinates and roundtrips user data', () async {
      final world = await luaCall(runtime, const [
        'love',
        'physics',
        'newWorld',
      ]);
      final body = await luaCall(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 100, 50, 'dynamic'],
      );

      await luaCallMethod(body!, 'setAngle', <Object?>[math.pi / 2]);
      await luaCallMethod(body, 'setAngularVelocity', const <Object?>[1]);
      await luaCallMethod(body, 'setUserData', const <Object?>['player']);
      expect(await luaCallMethod(body, 'getUserData'), 'player');

      expectDoubleListClose(
        await luaCallMethod(body, 'getWorldPoint', const <Object?>[10, 0]),
        const <double>[100, 60],
      );
      expectDoubleListClose(
        await luaCallMethod(body, 'getLocalPoint', const <Object?>[100, 60]),
        const <double>[10, 0],
      );
      expectDoubleListClose(
        await luaCallMethod(body, 'getWorldPoints', const <Object?>[
          10,
          0,
          0,
          10,
        ]),
        const <double>[100, 60, 90, 50],
      );
      expectDoubleListClose(
        await luaCallMethod(body, 'getLocalPoints', const <Object?>[
          100,
          60,
          90,
          50,
        ]),
        const <double>[10, 0, 0, 10],
      );
      expectDoubleListClose(
        await luaCallMethod(body, 'getWorldVector', const <Object?>[0, 10]),
        const <double>[-10, 0],
      );
      expectDoubleListClose(
        await luaCallMethod(body, 'getLocalVector', const <Object?>[-10, 0]),
        const <double>[0, 10],
      );
      expectDoubleListClose(
        await luaCallMethod(
          body,
          'getLinearVelocityFromWorldPoint',
          const <Object?>[100, 80],
        ),
        const <double>[-30, 0],
      );
      expectDoubleListClose(
        await luaCallMethod(
          body,
          'getLinearVelocityFromLocalPoint',
          const <Object?>[30, 0],
        ),
        const <double>[-30, 0],
      );

      final fixture = await luaCall(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          body,
          await luaCall(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[20],
          ),
          1,
        ],
      );
      await luaCallMethod(fixture!, 'setUserData', const <Object?>[123]);
      expect(await luaCallMethod(fixture, 'getUserData'), 123);
      expect(
        await luaCallMethod(fixture, 'testPoint', const <Object?>[100, 69]),
        isTrue,
      );
      expect(
        await luaCallMethod(fixture, 'testPoint', const <Object?>[100, 71]),
        isFalse,
      );
    });

    test('exposes fixture filter, bounds, and mass helpers', () async {
      final world = await luaCall(runtime, const [
        'love',
        'physics',
        'newWorld',
      ]);
      final body = await luaCall(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 100, 50, 'dynamic'],
      );
      final fixture = await luaCall(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          body,
          await luaCall(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[20],
          ),
          2.5,
        ],
      );

      expect(await luaCallMethod(fixture!, 'getCategory'), <Object?>[1]);
      expect(await luaCallMethod(fixture, 'getMask'), <Object?>[]);
      expect(await luaCallMethod(fixture, 'getFilterData'), <Object?>[
        1,
        65535,
        0,
      ]);

      await luaCallMethod(fixture, 'setCategory', <Object?>[
        Value(<Object?, Object?>{1: 1, 2: 4}),
      ]);
      expect(await luaCallMethod(fixture, 'getCategory'), <Object?>[1, 4]);

      await luaCallMethod(fixture, 'setMask', const <Object?>[2, 3]);
      expect(await luaCallMethod(fixture, 'getMask'), <Object?>[2, 3]);

      await luaCallMethod(fixture, 'setGroupIndex', const <Object?>[-7]);
      expect(await luaCallMethod(fixture, 'getGroupIndex'), -7);

      await luaCallMethod(fixture, 'setFilterData', const <Object?>[
        3,
        65534,
        -2,
      ]);
      expect(await luaCallMethod(fixture, 'getFilterData'), <Object?>[
        3,
        65534,
        -2,
      ]);
      expect(await luaCallMethod(fixture, 'getCategory'), <Object?>[1, 2]);
      expect(await luaCallMethod(fixture, 'getMask'), <Object?>[1]);

      expectDoubleListClose(
        await luaCallMethod(fixture, 'getBoundingBox'),
        const <double>[80, 30, 120, 70],
      );

      final radiusInMeters = 20 / 30;
      final expectedMass = 2.5 * math.pi * radiusInMeters * radiusInMeters;
      final expectedInertia =
          expectedMass * (0.5 * radiusInMeters * radiusInMeters);
      expectDoubleListClose(
        await luaCallMethod(fixture, 'getMassData'),
        <double>[0, 0, expectedMass, expectedInertia],
      );

      await expectLater(
        luaCallMethod(fixture, 'getBoundingBox', const <Object?>[2]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Physics error: index out of bounds'),
          ),
        ),
      );

      await expectLater(
        luaCallMethod(fixture, 'setCategory', const <Object?>[17]),
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
        final circle = await luaCall(
          runtime,
          const ['love', 'physics', 'newCircleShape'],
          const <Object?>[5, -2, 10],
        );

        expectDoubleListClose(
          await luaCallMethod(circle!, 'computeAABB', const <Object?>[
            20,
            30,
            0,
          ]),
          const <double>[15, 18, 35, 38],
        );
        expect(
          await luaCallMethod(circle, 'testPoint', const <Object?>[
            20,
            30,
            0,
            25,
            28,
          ]),
          isTrue,
        );
        expect(
          await luaCallMethod(circle, 'testPoint', const <Object?>[
            20,
            30,
            0,
            40,
            40,
          ]),
          isFalse,
        );

        final circleMass = doubleResults(
          await luaCallMethod(circle, 'computeMass', const <Object?>[2]),
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

        final polygon = await luaCall(
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
        expect(await luaCallMethod(polygon!, 'validate'), isTrue);
        expectPointSetClose(
          await luaCallMethod(polygon, 'getPoints'),
          const <({double x, double y})>[
            (x: 0, y: 0),
            (x: 30, y: 0),
            (x: 30, y: 20),
            (x: 0, y: 20),
          ],
        );

        final edge = await luaCall(
          runtime,
          const ['love', 'physics', 'newEdgeShape'],
          const <Object?>[0, 0, 30, 10],
        );
        expectDoubleListClose(
          await luaCallMethod(edge!, 'getPoints'),
          const <double>[0, 0, 30, 10],
        );
        expect(await luaCallMethod(edge, 'getNextVertex'), <Object?>[]);
        expect(await luaCallMethod(edge, 'getPreviousVertex'), <Object?>[]);
        await luaCallMethod(edge, 'setNextVertex', const <Object?>[60, 15]);
        await luaCallMethod(edge, 'setPreviousVertex', const <Object?>[-5, -5]);
        expectDoubleListClose(
          await luaCallMethod(edge, 'getNextVertex'),
          const <double>[60, 15],
        );
        expectDoubleListClose(
          await luaCallMethod(edge, 'getPreviousVertex'),
          const <double>[-5, -5],
        );

        final chain = await luaCall(
          runtime,
          const ['love', 'physics', 'newChainShape'],
          <Object?>[
            false,
            Value(<Object?, Object?>{1: 0, 2: 0, 3: 30, 4: 0, 5: 30, 6: 20}),
          ],
        );
        expect(await luaCallMethod(chain!, 'getVertexCount'), 3);
        expect(await luaCallMethod(chain, 'getChildCount'), 2);
        expectDoubleListClose(
          await luaCallMethod(chain, 'getPoint', const <Object?>[3]),
          const <double>[30, 20],
        );
        expectDoubleListClose(
          await luaCallMethod(chain, 'getPoints'),
          const <double>[0, 0, 30, 0, 30, 20],
        );
        expect(await luaCallMethod(chain, 'getNextVertex'), <Object?>[]);
        expect(await luaCallMethod(chain, 'getPreviousVertex'), <Object?>[]);

        final childEdge = await luaCallMethod(
          chain,
          'getChildEdge',
          const <Object?>[1],
        );
        expect(await luaCallMethod(childEdge!, 'getType'), 'edge');
        expectDoubleListClose(
          await luaCallMethod(childEdge, 'getPoints'),
          const <double>[0, 0, 30, 0],
        );

        await luaCallMethod(chain, 'setNextVertex', const <Object?>[40, 25]);
        await luaCallMethod(chain, 'setPreviousVertex', const <Object?>[-5, 0]);
        expectDoubleListClose(
          await luaCallMethod(chain, 'getNextVertex'),
          const <double>[40, 25],
        );
        expectDoubleListClose(
          await luaCallMethod(chain, 'getPreviousVertex'),
          const <double>[-5, 0],
        );
      },
    );

    test(
      'clones fixture shapes and rebuilds fixture geometry when mutated',
      () async {
        final world = await luaCall(runtime, const [
          'love',
          'physics',
          'newWorld',
        ]);
        final bodyA = await luaCall(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 0, 0, 'static'],
        );
        final bodyB = await luaCall(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 120, 0, 'static'],
        );

        final sourceShape = await luaCall(
          runtime,
          const ['love', 'physics', 'newCircleShape'],
          const <Object?>[15],
        );
        final fixtureA = await luaCall(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[bodyA, sourceShape, 1],
        );
        final fixtureB = await luaCall(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[
            bodyB,
            await luaCall(
              runtime,
              const ['love', 'physics', 'newCircleShape'],
              const <Object?>[15],
            ),
            1,
          ],
        );

        await luaCallMethod(sourceShape!, 'setRadius', const <Object?>[30]);
        final fixtureShape = await luaCallMethod(fixtureA!, 'getShape');
        expect(await luaCallMethod(sourceShape, 'getRadius'), 30.0);
        expect(await luaCallMethod(fixtureShape!, 'getRadius'), 15.0);

        expect(
          doubleResults(
            await luaCall(
              runtime,
              const ['love', 'physics', 'getDistance'],
              <Object?>[fixtureA, fixtureB],
            ),
          ).first,
          closeTo(90.0, 1e-6),
        );

        await luaCallMethod(fixtureShape, 'setRadius', const <Object?>[20]);
        expect(await luaCallMethod(fixtureShape, 'getRadius'), 20.0);
        expect(
          doubleResults(
            await luaCall(
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
      final world = await luaCall(runtime, const [
        'love',
        'physics',
        'newWorld',
      ]);
      final body = await luaCall(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );
      final fixture = await luaCall(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          body,
          await luaCall(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[10],
          ),
          1,
        ],
      );

      await luaCallMethod(fixture!, 'destroy');
      await expectLater(
        luaCallMethod(fixture, 'getDensity'),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Attempt to use destroyed fixture.'),
          ),
        ),
      );

      final secondBody = await luaCall(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );
      await luaCallMethod(secondBody!, 'destroy');
      await expectLater(
        luaCallMethod(secondBody, 'getX'),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Attempt to use destroyed body.'),
          ),
        ),
      );

      final secondWorld = await luaCall(runtime, const [
        'love',
        'physics',
        'newWorld',
      ]);
      await luaCallMethod(secondWorld!, 'destroy');
      await expectLater(
        luaCallMethod(secondWorld, 'getBodyCount'),
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
