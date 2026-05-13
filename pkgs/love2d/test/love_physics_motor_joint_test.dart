import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics motor joints', () {
    late LuaRuntime runtime;
    late LuaLike lua;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'love.physics.newMotorJoint supports LOVE overloads and source motor accessors',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 5, 10, 'static')
local bodyB = love.physics.newBody(world, 25, 35, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)
bodyB:setAngle(0.5)

local jointA = love.physics.newMotorJoint(bodyA, bodyB)
local initialOffsetX, initialOffsetY = jointA:getLinearOffset()
local initialMaxForce = jointA:getMaxForce()
local initialMaxTorque = jointA:getMaxTorque()

local jointB = love.physics.newMotorJoint(bodyA, bodyB, 0.6, true)
jointB:setLinearOffset(7, 8)
jointB:setAngularOffset(1.25)
jointB:setMaxForce(90)
jointB:setMaxTorque(45)
jointB:setCorrectionFactor(0.4)

local body1, body2 = jointB:getBodies()
local ax, ay, bx, by = jointB:getAnchors()
local offsetX, offsetY = jointB:getLinearOffset()

return
  jointA:getCollideConnected(),
  jointA:getCorrectionFactor(),
  initialOffsetX, initialOffsetY,
  jointB:type(),
  jointB:typeOf('MotorJoint'),
  jointB:typeOf('Joint'),
  jointB:getType(),
  jointB:getCollideConnected(),
  body1 == bodyA,
  body2 == bodyB,
  ax, ay, bx, by,
  jointB:getAngularOffset(),
  offsetX, offsetY,
  initialMaxForce > 0,
  initialMaxTorque > 0,
  jointB:getMaxForce(),
  jointB:getMaxTorque(),
  jointB:getCorrectionFactor(),
  world:getJointCount(),
  #bodyB:getJoints()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], false);
        expect((values[1] as num).toDouble(), closeTo(0.3, 1e-6));
        expect((values[2] as num).toDouble(), closeTo(20, 1e-5));
        expect((values[3] as num).toDouble(), closeTo(25, 1e-5));
        expect(values[4], 'MotorJoint');
        expect(values[5], true);
        expect(values[6], true);
        expect(values[7], 'motor');
        expect(values[8], true);
        expect(values[9], true);
        expect(values[10], true);
        expect((values[11] as num).toDouble(), closeTo(5, 1e-5));
        expect((values[12] as num).toDouble(), closeTo(10, 1e-5));
        expect((values[13] as num).toDouble(), closeTo(25, 1e-5));
        expect((values[14] as num).toDouble(), closeTo(35, 1e-5));
        expect((values[15] as num).toDouble(), closeTo(1.25, 1e-6));
        expect((values[16] as num).toDouble(), closeTo(7, 1e-5));
        expect((values[17] as num).toDouble(), closeTo(8, 1e-5));
        expect(values[18], true);
        expect(values[19], true);
        expect((values[20] as num).toDouble(), closeTo(90, 1e-6));
        expect((values[21] as num).toDouble(), closeTo(45, 1e-6));
        expect((values[22] as num).toDouble(), closeTo(0.4, 1e-6));
        expect(values[23], 2);
        expect(values[24], 2);
      },
    );

    test(
      'MotorJoint validation and destruction preserve LOVE-style errors',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 10, 0, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)

local joint = love.physics.newMotorJoint(bodyA, bodyB, 0.4, false)

local correctionOk, correctionErr = pcall(function()
  joint:setCorrectionFactor(1.5)
end)

local forceOk, forceErr = pcall(function()
  joint:setMaxForce(-1)
end)

local torqueOk, torqueErr = pcall(function()
  joint:setMaxTorque(-1)
end)

joint:destroy()

local useOk, useErr = pcall(function()
  return joint:getLinearOffset()
end)

return
  correctionOk,
  string.find(correctionErr, 'between 0 and 1') ~= nil,
  forceOk,
  string.find(forceErr, 'non%-negative number') ~= nil,
  torqueOk,
  string.find(torqueErr, 'non%-negative number') ~= nil,
  joint:isDestroyed(),
  useOk,
  string.find(useErr, 'destroyed joint') ~= nil,
  world:getJointCount(),
  #bodyB:getJointList()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], false);
        expect(values[1], true);
        expect(values[2], false);
        expect(values[3], true);
        expect(values[4], false);
        expect(values[5], true);
        expect(values[6], true);
        expect(values[7], false);
        expect(values[8], true);
        expect(values[9], 0);
        expect(values[10], 0);
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
