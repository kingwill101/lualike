import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';
import 'test_support/physics_test_support.dart';

void main() {
  group('love.physics contact object bindings', () {
    late LuaRuntime runtime;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime);
    });

    test(
      'Body:getContacts and World:getContacts expose active Contact objects',
      () async {
        final world = await luaCallList(
          runtime,
          const ['love', 'physics', 'newWorld'],
          const <Object?>[0, 0, false],
        );
        final bodyA = await luaCallList(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 0, 0, 'dynamic'],
        );
        final bodyB = await luaCallList(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 15, 0, 'dynamic'],
        );

        await luaCallList(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[
            bodyA,
            await luaCallList(
              runtime,
              const ['love', 'physics', 'newCircleShape'],
              const <Object?>[10],
            ),
            1,
          ],
        );
        await luaCallList(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[
            bodyB,
            await luaCallList(
              runtime,
              const ['love', 'physics', 'newCircleShape'],
              const <Object?>[10],
            ),
            1,
          ],
        );

        await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);

        final bodyContacts = indexedValues(
          await luaCallMethodList(bodyA, 'getContacts') as Map,
        );
        final worldContacts = indexedValues(
          await luaCallMethodList(world, 'getContacts') as Map,
        );

        expect(bodyContacts, hasLength(1));
        expect(worldContacts, hasLength(1));

        final contact = bodyContacts.single;
        expect(await luaCallMethodList(contact, 'type'), 'Contact');
        expect(
          await luaCallMethodList(contact, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
        expect(await luaCallMethodList(contact, 'isDestroyed'), isFalse);
        expect(await luaCallMethodList(contact, 'isTouching'), isTrue);
        expect(await luaCallMethodList(contact, 'isEnabled'), isTrue);

        expectDoubleListClose(
          await luaCallMethodList(contact, 'getChildren'),
          const <double>[1, 1],
        );

        final contactFixtures = _doubleTableFixtures(
          await luaCallMethodList(contact, 'getFixtures') as List<Object?>,
        );
        expect(
          await luaCallMethodList(contactFixtures[0], 'getType'),
          'circle',
        );
        expect(
          await luaCallMethodList(contactFixtures[1], 'getType'),
          'circle',
        );
        final currentBodyAPosition = doubleResults(
          await luaCallMethodList(bodyA, 'getPosition'),
        );
        final currentBodyBPosition = doubleResults(
          await luaCallMethodList(bodyB, 'getPosition'),
        );
        expectDoubleListClose(
          await luaCallMethodList(
            await luaCallMethodList(contactFixtures[0], 'getBody'),
            'getPosition',
          ),
          currentBodyAPosition,
        );
        expectDoubleListClose(
          await luaCallMethodList(
            await luaCallMethodList(contactFixtures[1], 'getBody'),
            'getPosition',
          ),
          currentBodyBPosition,
        );

        final normal = doubleResults(
          await luaCallMethodList(contact, 'getNormal'),
        );
        expect(normal[0], closeTo(1.0, 1e-6));
        expect(normal[1], closeTo(0.0, 1e-6));

        final positions = doubleResults(
          await luaCallMethodList(contact, 'getPositions'),
        );
        expect(positions, hasLength(2));
        expect(positions[0], closeTo(7.5, 1e-6));
        expect(positions[1], closeTo(0.0, 1e-6));
      },
    );

    test(
      'Contact setters and resetters roundtrip through LOVE bindings',
      () async {
        final world = await luaCallList(
          runtime,
          const ['love', 'physics', 'newWorld'],
          const <Object?>[0, 0, false],
        );
        final bodyA = await luaCallList(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 0, 0, 'dynamic'],
        );
        final bodyB = await luaCallList(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 15, 0, 'dynamic'],
        );

        final fixtureA = await luaCallList(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[
            bodyA,
            await luaCallList(
              runtime,
              const ['love', 'physics', 'newCircleShape'],
              const <Object?>[10],
            ),
            1,
          ],
        );
        final fixtureB = await luaCallList(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[
            bodyB,
            await luaCallList(
              runtime,
              const ['love', 'physics', 'newCircleShape'],
              const <Object?>[10],
            ),
            1,
          ],
        );

        await luaCallMethodList(fixtureA, 'setFriction', const <Object?>[0.2]);
        await luaCallMethodList(fixtureB, 'setFriction', const <Object?>[0.8]);
        await luaCallMethodList(fixtureA, 'setRestitution', const <Object?>[
          0.2,
        ]);
        await luaCallMethodList(fixtureB, 'setRestitution', const <Object?>[
          0.6,
        ]);

        await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);
        final contact = indexedValues(
          await luaCallMethodList(world, 'getContacts') as Map,
        ).single;

        expect(
          await luaCallMethodList(contact, 'getFriction'),
          closeTo(0.4, 1e-6),
        );
        expect(
          await luaCallMethodList(contact, 'getRestitution'),
          closeTo(0.6, 1e-6),
        );
        expect(
          await luaCallMethodList(contact, 'getTangentSpeed'),
          closeTo(0, 1e-6),
        );

        await luaCallMethodList(contact, 'setFriction', const <Object?>[1.25]);
        await luaCallMethodList(contact, 'setRestitution', const <Object?>[
          0.15,
        ]);
        await luaCallMethodList(contact, 'setTangentSpeed', const <Object?>[
          5.5,
        ]);
        await luaCallMethodList(contact, 'setEnabled', const <Object?>[false]);

        expect(
          await luaCallMethodList(contact, 'getFriction'),
          closeTo(1.25, 1e-6),
        );
        expect(
          await luaCallMethodList(contact, 'getRestitution'),
          closeTo(0.15, 1e-6),
        );
        expect(
          await luaCallMethodList(contact, 'getTangentSpeed'),
          closeTo(5.5, 1e-6),
        );
        expect(await luaCallMethodList(contact, 'isEnabled'), isFalse);

        await luaCallMethodList(contact, 'resetFriction');
        await luaCallMethodList(contact, 'resetRestitution');
        await luaCallMethodList(contact, 'setEnabled', const <Object?>[true]);

        expect(
          await luaCallMethodList(contact, 'getFriction'),
          closeTo(0.4, 1e-6),
        );
        expect(
          await luaCallMethodList(contact, 'getRestitution'),
          closeTo(0.6, 1e-6),
        );
        expect(
          await luaCallMethodList(contact, 'getTangentSpeed'),
          closeTo(5.5, 1e-6),
        );
        expect(await luaCallMethodList(contact, 'isEnabled'), isTrue);
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

    test(
      'Contact:setTangentSpeed affects later solver steps, not just getters',
      () async {
        final controlVelocity = await _runTangentSpeedContactScenario(
          runtime,
          overrideContactTangentSpeed: false,
        );
        final overrideVelocity = await _runTangentSpeedContactScenario(
          runtime,
          overrideContactTangentSpeed: true,
        );

        expect(controlVelocity.dx.abs(), lessThan(10));
        expect(
          overrideVelocity.dx.abs(),
          greaterThan(controlVelocity.dx.abs() + 40),
        );
        expect(overrideVelocity.dx.abs(), greaterThan(60));
      },
    );

    test('destroyed contacts reject further use after separation', () async {
      final world = await luaCallList(
        runtime,
        const ['love', 'physics', 'newWorld'],
        const <Object?>[0, 0, false],
      );
      final bodyA = await luaCallList(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );
      final bodyB = await luaCallList(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 15, 0, 'dynamic'],
      );

      await luaCallList(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          bodyA,
          await luaCallList(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[10],
          ),
          1,
        ],
      );
      await luaCallList(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          bodyB,
          await luaCallList(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[10],
          ),
          1,
        ],
      );

      await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);
      final contact = indexedValues(
        await luaCallMethodList(world, 'getContacts') as Map,
      ).single;

      await luaCallMethodList(bodyB, 'setPosition', const <Object?>[100, 0]);
      await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);

      expect(await luaCallMethodList(contact, 'isDestroyed'), isTrue);
      await expectLater(
        luaCallMethodList(contact, 'getNormal'),
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

List<Object?> _doubleTableFixtures(List<Object?> values) => values;

Future<({double dx, double dy})> _runSlidingContactScenario(
  LuaRuntime runtime, {
  required bool overrideContactFriction,
}) async {
  final world = await luaCallList(
    runtime,
    const ['love', 'physics', 'newWorld'],
    const <Object?>[0, 1000, false],
  );
  final floor = await luaCallList(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 100, 'static'],
  );
  final box = await luaCallList(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 80, 'dynamic'],
  );

  final floorShape = await luaCallList(
    runtime,
    const ['love', 'physics', 'newRectangleShape'],
    const <Object?>[400, 20],
  );
  final boxShape = await luaCallList(
    runtime,
    const ['love', 'physics', 'newRectangleShape'],
    const <Object?>[20, 20],
  );

  final floorFixture = await luaCallList(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[floor, floorShape, 1],
  );
  final boxFixture = await luaCallList(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[box, boxShape, 1],
  );

  await luaCallMethodList(floorFixture, 'setFriction', const <Object?>[4]);
  await luaCallMethodList(boxFixture, 'setFriction', const <Object?>[4]);
  await luaCallMethodList(floorFixture, 'setRestitution', const <Object?>[0]);
  await luaCallMethodList(boxFixture, 'setRestitution', const <Object?>[0]);
  await luaCallMethodList(box, 'setFixedRotation', const <Object?>[true]);
  await luaCallMethodList(box, 'setLinearVelocity', const <Object?>[120, 0]);

  await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);
  final contact = indexedValues(
    await luaCallMethodList(world, 'getContacts') as Map,
  ).single;

  if (overrideContactFriction) {
    await luaCallMethodList(contact, 'setFriction', const <Object?>[0]);
  }

  for (var index = 0; index < 20; index++) {
    await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);
  }

  final velocity = doubleResults(
    await luaCallMethodList(box, 'getLinearVelocity'),
  );
  return (dx: velocity[0], dy: velocity[1]);
}

Future<({double dx, double dy})> _runRestitutionContactScenario(
  LuaRuntime runtime, {
  required bool overrideContactRestitution,
}) async {
  final world = await luaCallList(
    runtime,
    const ['love', 'physics', 'newWorld'],
    const <Object?>[0, 0, false],
  );
  final floor = await luaCallList(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 100, 'static'],
  );
  final ball = await luaCallList(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 80, 'dynamic'],
  );

  final floorShape = await luaCallList(
    runtime,
    const ['love', 'physics', 'newRectangleShape'],
    const <Object?>[400, 20],
  );
  final ballShape = await luaCallList(
    runtime,
    const ['love', 'physics', 'newCircleShape'],
    const <Object?>[10],
  );

  final floorFixture = await luaCallList(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[floor, floorShape, 1],
  );
  final ballFixture = await luaCallList(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[ball, ballShape, 1],
  );

  await luaCallMethodList(floorFixture, 'setRestitution', const <Object?>[0]);
  await luaCallMethodList(ballFixture, 'setRestitution', const <Object?>[0]);

  await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);
  final contact = indexedValues(
    await luaCallMethodList(world, 'getContacts') as Map,
  ).single;

  if (overrideContactRestitution) {
    await luaCallMethodList(contact, 'setRestitution', const <Object?>[1]);
  }

  await luaCallMethodList(ball, 'setLinearVelocity', const <Object?>[0, 240]);
  await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);

  final velocity = doubleResults(
    await luaCallMethodList(ball, 'getLinearVelocity'),
  );
  return (dx: velocity[0], dy: velocity[1]);
}

Future<({double dx, double dy})> _runTangentSpeedContactScenario(
  LuaRuntime runtime, {
  required bool overrideContactTangentSpeed,
}) async {
  final world = await luaCallList(
    runtime,
    const ['love', 'physics', 'newWorld'],
    const <Object?>[0, 1000, false],
  );
  final floor = await luaCallList(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 100, 'static'],
  );
  final box = await luaCallList(
    runtime,
    const ['love', 'physics', 'newBody'],
    <Object?>[world, 0, 80, 'dynamic'],
  );

  final floorShape = await luaCallList(
    runtime,
    const ['love', 'physics', 'newRectangleShape'],
    const <Object?>[400, 20],
  );
  final boxShape = await luaCallList(
    runtime,
    const ['love', 'physics', 'newRectangleShape'],
    const <Object?>[20, 20],
  );

  final floorFixture = await luaCallList(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[floor, floorShape, 1],
  );
  final boxFixture = await luaCallList(
    runtime,
    const ['love', 'physics', 'newFixture'],
    <Object?>[box, boxShape, 1],
  );

  await luaCallMethodList(floorFixture, 'setFriction', const <Object?>[8]);
  await luaCallMethodList(boxFixture, 'setFriction', const <Object?>[8]);
  await luaCallMethodList(floorFixture, 'setRestitution', const <Object?>[0]);
  await luaCallMethodList(boxFixture, 'setRestitution', const <Object?>[0]);
  await luaCallMethodList(box, 'setFixedRotation', const <Object?>[true]);

  await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);
  final contact = indexedValues(
    await luaCallMethodList(world, 'getContacts') as Map,
  ).single;

  if (overrideContactTangentSpeed) {
    await luaCallMethodList(contact, 'setTangentSpeed', const <Object?>[5]);
  }

  for (var index = 0; index < 20; index++) {
    await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);
  }

  final velocity = doubleResults(
    await luaCallMethodList(box, 'getLinearVelocity'),
  );
  return (dx: velocity[0], dy: velocity[1]);
}
