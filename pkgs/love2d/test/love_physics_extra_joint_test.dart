import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics friction and rope joints', () {
    late LuaRuntime runtime;
    late LuaLike lua;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'love.physics.newFrictionJoint supports both constructor overloads and force accessors',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 90, 0, 'dynamic')

local jointA = love.physics.newFrictionJoint(bodyA, bodyB, 10, 0, true)
jointA:setMaxForce(120)
jointA:setMaxTorque(900)

local ax1, ay1, bx1, by1 = jointA:getAnchors()

local jointB = love.physics.newFrictionJoint(bodyA, bodyB, 0, 0, 90, 0, false)
local ax2, ay2, bx2, by2 = jointB:getAnchors()

        return
  jointA:type(),
  jointA:typeOf('FrictionJoint'),
  jointA:typeOf('Joint'),
  jointA:getType(),
  jointA:getCollideConnected(),
  jointA:getMaxForce(),
  jointA:getMaxTorque(),
  ax1, ay1, bx1, by1,
  jointB:getCollideConnected(),
  ax2, ay2, bx2, by2,
  world:getJointCount(),
  #world:getJoints(),
  #bodyB:getJoints()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], 'FrictionJoint');
        expect(values[1], true);
        expect(values[2], true);
        expect(values[3], 'friction');
        expect(values[4], true);
        expect((values[5] as num).toDouble(), closeTo(120, 1e-6));
        expect((values[6] as num).toDouble(), closeTo(900, 1e-6));
        expect((values[7] as num).toDouble(), closeTo(10, 1e-5));
        expect((values[8] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[9] as num).toDouble(), closeTo(10, 1e-5));
        expect((values[10] as num).toDouble(), closeTo(0, 1e-5));
        expect(values[11], false);
        expect((values[12] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[13] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[14] as num).toDouble(), closeTo(90, 1e-5));
        expect((values[15] as num).toDouble(), closeTo(0, 1e-5));
        expect(values[16], 2);
        expect(values[17], 2);
        expect(values[18], 2);
      },
    );

    test(
      'love.physics.newRopeJoint exposes max length mutation and inventories',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 60, 0, 'dynamic')

local joint = love.physics.newRopeJoint(bodyA, bodyB, 0, 0, 60, 0, 70, true)
local ax1, ay1, bx1, by1 = joint:getAnchors()
local typeName = joint:type()
local typeOfRope = joint:typeOf('RopeJoint')
local typeOfJoint = joint:typeOf('Joint')
local jointType = joint:getType()
local collideConnected = joint:getCollideConnected()
joint:setMaxLength(80)
local maxLength = joint:getMaxLength()

joint:destroy()

local ok, err = pcall(function()
  return joint:getMaxLength()
end)

return
  typeName,
  typeOfRope,
  typeOfJoint,
  jointType,
  collideConnected,
  ax1, ay1, bx1, by1,
  maxLength,
  joint:isDestroyed(),
  ok,
  string.find(err, 'destroyed joint') ~= nil,
  world:getJointCount(),
  #bodyA:getJoints(),
  #world:getJointList()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], 'RopeJoint');
        expect(values[1], true);
        expect(values[2], true);
        expect(values[3], 'rope');
        expect(values[4], true);
        expect((values[5] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[6] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[7] as num).toDouble(), closeTo(60, 1e-5));
        expect((values[8] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[9] as num).toDouble(), closeTo(80, 1e-5));
        expect(values[10], true);
        expect(values[11], false);
        expect(values[12], true);
        expect(values[13], 0);
        expect(values[14], 0);
        expect(values[15], 0);
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
