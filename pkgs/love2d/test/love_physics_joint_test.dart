import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics joints', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'love.physics.newDistanceJoint exposes joint inventory and base APIs',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 60, 0, 'dynamic')
local joint = love.physics.newDistanceJoint(bodyA, bodyB, 0, 0, 60, 0, true)

joint:setUserData({ tag = 'bridge' })
bodyB:setPosition(90, 0)
joint:setFrequency(4.5)
joint:setDampingRatio(0.25)
joint:setLength(75)

local body1, body2 = joint:getBodies()
local ax, ay, bx, by = joint:getAnchors()
local fx, fy = joint:getReactionForce(60)
local torque = joint:getReactionTorque(60)
local worldJoints = world:getJoints()
local bodyAJoints = bodyA:getJoints()
local bodyBJointList = bodyB:getJointList()

return
  joint:type(),
  joint:typeOf('DistanceJoint'),
  joint:typeOf('Joint'),
  joint:typeOf('Object'),
  joint:getType(),
  body1 == bodyA,
  body2 == bodyB,
  joint:getCollideConnected(),
  joint:getUserData().tag,
  world:getJointCount(),
  #worldJoints,
  #bodyAJoints,
  #bodyBJointList,
  worldJoints[1] == joint,
  bodyAJoints[1] == joint,
  bodyBJointList[1] == joint,
  ax,
  ay,
  bx,
  by,
  fx,
  fy,
  torque,
  joint:getLength(),
  joint:getFrequency(),
  joint:getDampingRatio()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], 'DistanceJoint');
        expect(values[1], true);
        expect(values[2], true);
        expect(values[3], true);
        expect(values[4], 'distance');
        expect(values[5], true);
        expect(values[6], true);
        expect(values[7], true);
        expect(values[8], 'bridge');
        expect(values[9], 1);
        expect(values[10], 1);
        expect(values[11], 1);
        expect(values[12], 1);
        expect(values[13], true);
        expect(values[14], true);
        expect(values[15], true);
        expect(values[16], closeTo(0, 1e-6));
        expect(values[17], closeTo(0, 1e-6));
        expect(values[18], closeTo(90, 1e-6));
        expect(values[19], closeTo(0, 1e-6));
        expect(values[20], isA<num>());
        expect(values[21], isA<num>());
        expect(values[22], isA<num>());
        expect((values[23] as num).toDouble(), closeTo(75, 1e-6));
        expect((values[24] as num).toDouble(), closeTo(4.5, 1e-6));
        expect((values[25] as num).toDouble(), closeTo(0.25, 1e-6));
      },
    );

    test(
      'joint destruction updates inventories and invalidates wrappers',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 60, 0, 'dynamic')
local joint = love.physics.newDistanceJoint(bodyA, bodyB, 0, 0, 60, 0)

local beforeCount = world:getJointCount()
joint:destroy()

local getTypeOk, getTypeErr = pcall(function()
  return joint:getType()
end)

local bodyC = love.physics.newBody(world, 120, 0, 'dynamic')
local joint2 = love.physics.newDistanceJoint(bodyA, bodyC, 0, 0, 120, 0)
bodyA:destroy()

return
  beforeCount,
  world:getJointCount(),
  #world:getJoints(),
  #bodyB:getJoints(),
  joint:isDestroyed(),
  getTypeOk,
  string.find(getTypeErr, 'destroyed joint') ~= nil,
  joint2:isDestroyed(),
  world:getJointCount(),
  #bodyC:getJoints(),
  bodyA:isDestroyed(),
  bodyB:isDestroyed(),
  bodyC:isDestroyed()
''');

        expect(result, <Object?>[
          1,
          0,
          0,
          0,
          true,
          false,
          true,
          true,
          0,
          0,
          true,
          false,
          false,
        ]);
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
