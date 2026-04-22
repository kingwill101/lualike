import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics deprecated inventory aliases', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'World and Body legacy get*List aliases mirror the modern inventory methods',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 15, 0, 'dynamic')

love.physics.newFixture(bodyA, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(10), 1)

world:update(1 / 60)

return
  #world:getBodies(), #world:getBodyList(),
  #world:getJoints(), #world:getJointList(),
  #world:getContacts(), #world:getContactList(),
  #bodyB:getFixtures(), #bodyB:getFixtureList(),
  #bodyB:getJoints(), #bodyB:getJointList(),
  #bodyB:getContacts(), #bodyB:getContactList()
''');

        expect(result, <Object?>[2, 2, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1]);
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
