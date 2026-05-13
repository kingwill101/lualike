import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';
import 'test_support/physics_test_support.dart';

void main() {
  group('love.physics query and raycast bindings', () {
    late LuaRuntime runtime;
    late LuaLike lua;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'fixture and shape rayCast return LOVE-style normals and fractions',
      () async {
        final world = await luaCallList(runtime, const [
          'love',
          'physics',
          'newWorld',
        ]);
        final body = await luaCallList(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 100, 50, 'static'],
        );
        final fixture = await luaCallList(
          runtime,
          const ['love', 'physics', 'newFixture'],
          <Object?>[
            body,
            await luaCallList(
              runtime,
              const ['love', 'physics', 'newCircleShape'],
              const <Object?>[20],
            ),
            1,
          ],
        );

        expectDoubleListClose(
          await luaCallMethodList(fixture, 'rayCast', const <Object?>[
            60,
            50,
            140,
            50,
            1,
          ]),
          const <double>[-1, 0, 0.25],
        );
        expect(
          await luaCallMethodList(fixture, 'rayCast', const <Object?>[
            60,
            0,
            140,
            0,
            1,
          ]),
          <Object?>[],
        );

        final shape = await luaCallMethodList(fixture, 'getShape');
        expectDoubleListClose(
          await luaCallMethodList(shape, 'rayCast', const <Object?>[
            60,
            50,
            140,
            50,
            1,
            100,
            50,
            0,
          ]),
          const <double>[-1, 0, 0.25],
        );

        await expectLater(
          luaCallMethodList(shape, 'rayCast', const <Object?>[
            60,
            50,
            140,
            50,
            1,
            100,
            50,
            0,
            2,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Physics error: index out of bounds'),
            ),
          ),
        );
      },
    );

    test(
      'world queryBoundingBox and rayCast honor LOVE callback semantics',
      () async {
        final result = await luaExecuteList(lua, '''
local world = love.physics.newWorld()

local bodyA = love.physics.newBody(world, 30, 50, 'static')
local bodyB = love.physics.newBody(world, 60, 50, 'static')
local bodyC = love.physics.newBody(world, 90, 50, 'static')

love.physics.newFixture(bodyA, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyC, love.physics.newCircleShape(10), 1)

local queryHits = {}
world:queryBoundingBox(0, 0, 100, 100, function(fixture)
  queryHits[#queryHits + 1] = fixture:getBody():getX()
  return #queryHits < 2
end)

local rayHits = {}
world:rayCast(0, 50, 120, 50, function(fixture, x, y, xn, yn, fraction)
  rayHits[#rayHits + 1] = {fixture:getBody():getX(), x, y, xn, yn, fraction}
  if #rayHits == 1 then
    return 1
  end
  return 0
end)

local clippedHits = {}
world:rayCast(0, 50, 120, 50, function(fixture, x, y, xn, yn, fraction)
  clippedHits[#clippedHits + 1] = fixture:getBody():getX()
  return fraction
end)

return queryHits, rayHits, clippedHits
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(doubleTable(values[0] as Map), <double>[30, 60]);

        final rayRows = indexedValues(values[1] as Map);
        expect(rayRows, hasLength(2));
        expectDoubleListClose(rayRows[0], <double>[30, 20, 50, -1, 0, 1 / 6]);
        expectDoubleListClose(rayRows[1], <double>[60, 50, 50, -1, 0, 5 / 12]);

        expect(doubleTable(values[2] as Map), <double>[30]);
      },
    );

    test('world rayCast rejects non-numeric callback returns', () async {
      await expectLater(
        luaExecuteList(lua, '''
local world = love.physics.newWorld()
local body = love.physics.newBody(world, 30, 50, 'static')
love.physics.newFixture(body, love.physics.newCircleShape(10), 1)

world:rayCast(0, 50, 120, 50, function()
  return false
end)
'''),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains("Raycast callback didn't return a number!"),
          ),
        ),
      );
    });
  });
}
