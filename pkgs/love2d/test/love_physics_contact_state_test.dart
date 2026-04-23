import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';
import 'test_support/physics_test_support.dart';

void main() {
  group('love.physics contact and inertia bindings', () {
    late LuaRuntime runtime;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime);
    });

    test('Body:setInertia updates inertia-dependent getters', () async {
      final world = await luaCallList(runtime, const [
        'love',
        'physics',
        'newWorld',
      ]);
      final body = await luaCallList(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 0, 0, 'dynamic'],
      );
      await luaCallList(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          body,
          await luaCallList(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[10],
          ),
          2,
        ],
      );

      final initialMassData = doubleResults(
        await luaCallMethodList(body, 'getMassData'),
      );
      await luaCallMethodList(body, 'setInertia', const <Object?>[540]);

      expect(await luaCallMethodList(body, 'getInertia'), closeTo(540, 1e-6));
      final updatedMassData = doubleResults(
        await luaCallMethodList(body, 'getMassData'),
      );
      expect(updatedMassData[0], closeTo(initialMassData[0], 1e-6));
      expect(updatedMassData[1], closeTo(initialMassData[1], 1e-6));
      expect(updatedMassData[2], closeTo(initialMassData[2], 1e-6));
      expect(updatedMassData[3], closeTo(540, 1e-6));
    });

    test(
      'World:getContactCount and Body:isTouching reflect stepped contacts',
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
        expect(await luaCallMethodList(world, 'getContactCount'), 1);
        expect(
          await luaCallMethodList(bodyA, 'isTouching', <Object?>[bodyB]),
          isTrue,
        );
        expect(
          await luaCallMethodList(bodyB, 'isTouching', <Object?>[bodyA]),
          isTrue,
        );

        await luaCallMethodList(bodyB, 'setPosition', const <Object?>[100, 0]);
        await luaCallMethodList(world, 'update', const <Object?>[1 / 60]);
        expect(await luaCallMethodList(world, 'getContactCount'), 0);
        expect(
          await luaCallMethodList(bodyA, 'isTouching', <Object?>[bodyB]),
          isFalse,
        );
        expect(
          await luaCallMethodList(bodyB, 'isTouching', <Object?>[bodyA]),
          isFalse,
        );
      },
    );
  });
}
