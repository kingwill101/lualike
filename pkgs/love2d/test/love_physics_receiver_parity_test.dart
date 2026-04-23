import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';
import 'test_support/physics_test_support.dart';

void main() {
  group('love.physics object receiver parity', () {
    test(
      'World type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime);

        final world = await luaCall(
          runtime,
          const ['love', 'physics', 'newWorld'],
          const <Object?>[0, 0, false],
        );

        await _expectReleasedObjectParity(
          object: world,
          typeName: 'World',
          queryType: 'Object',
          failingMethod: 'getBodyCount',
        );
      },
    );

    test(
      'Body type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime);

        final world = await luaCall(
          runtime,
          const ['love', 'physics', 'newWorld'],
          const <Object?>[0, 0, false],
        );
        final body = await luaCall(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 10, 20, 'dynamic'],
        );

        await _expectReleasedObjectParity(
          object: body,
          typeName: 'Body',
          queryType: 'Object',
          failingMethod: 'getPosition',
        );
      },
    );

    test(
      'Fixture type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime);

        final world = await luaCall(
          runtime,
          const ['love', 'physics', 'newWorld'],
          const <Object?>[0, 0, false],
        );
        final body = await luaCall(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 10, 20, 'dynamic'],
        );
        final shape = await luaCall(
          runtime,
          const ['love', 'physics', 'newCircleShape'],
          const <Object?>[8],
        );
        final fixture = await luaCall(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[body, shape, 1],
        );

        await _expectReleasedObjectParity(
          object: fixture,
          typeName: 'Fixture',
          queryType: 'Object',
          failingMethod: 'getDensity',
        );
      },
    );

    test(
      'CircleShape type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime);

        final shape = await luaCall(
          runtime,
          const ['love', 'physics', 'newCircleShape'],
          const <Object?>[8],
        );

        await _expectReleasedObjectParity(
          object: shape,
          typeName: 'CircleShape',
          queryType: 'Shape',
          failingMethod: 'getRadius',
        );
      },
    );

    test(
      'DistanceJoint type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime);

        final world = await luaCall(
          runtime,
          const ['love', 'physics', 'newWorld'],
          const <Object?>[0, 0, false],
        );
        final bodyA = await luaCall(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 0, 0, 'dynamic'],
        );
        final bodyB = await luaCall(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 20, 0, 'dynamic'],
        );
        final joint = await luaCall(
          runtime,
          const ['love', 'physics', 'newDistanceJoint'],
          <Object?>[bodyA, bodyB, 0, 0, 20, 0, false],
        );

        await _expectReleasedObjectParity(
          object: joint,
          typeName: 'DistanceJoint',
          queryType: 'Joint',
          failingMethod: 'getLength',
        );
      },
    );

    test(
      'Contact type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime);

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

        await _expectReleasedObjectParity(
          object: contact,
          typeName: 'Contact',
          queryType: 'Object',
          failingMethod: 'getNormal',
        );
      },
    );
  });
}

Future<void> _expectReleasedObjectParity({
  required Object? object,
  required String typeName,
  required String queryType,
  required String failingMethod,
  List<Object?> failingArgs = const <Object?>[],
}) async {
  final typeMethod = luaRawMethod(object, 'type');
  final typeOfMethod = luaRawMethod(object, 'typeOf');

  expect(
    await luaResolveCallResult(typeMethod.call(<Object?>[object])),
    typeName,
  );
  expect(
    await luaResolveCallResult(typeOfMethod.call(<Object?>[object, queryType])),
    isTrue,
  );

  await expectLater(
    () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
    throwsA(
      isA<LuaError>().having(
        (error) => error.message,
        'message',
        "bad argument #1 to 'type' ($typeName expected, got nil)",
      ),
    ),
  );

  await expectLater(
    () => luaResolveCallResult(
      typeOfMethod.call(const <Object?>['oops', 'Object']),
    ),
    throwsA(
      isA<LuaError>().having(
        (error) => error.message,
        'message',
        "bad argument #1 to 'typeOf' ($typeName expected, got string)",
      ),
    ),
  );

  expect(await luaCallMethod(object, 'release'), isTrue);
  expect(await luaCallMethod(object, 'release'), isFalse);

  await expectLater(
    () => luaCallMethod(object, failingMethod, failingArgs),
    throwsA(
      isA<LuaError>().having(
        (error) => error.message,
        'message',
        'Cannot use object after it has been released.',
      ),
    ),
  );

  expect(await luaCallMethod(object, 'type'), typeName);
  expect(await luaCallMethod(object, 'typeOf', <Object?>[queryType]), isTrue);
}
