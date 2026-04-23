import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics prismatic joints', () {
    late LuaRuntime runtime;
    late LuaLike lua;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'love.physics.newPrismaticJoint supports LOVE overloads and motor-limit accessors',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 20, 0, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)
bodyB:setAngle(0.5)

local jointA = love.physics.newPrismaticJoint(bodyA, bodyB, 0, 0, 1, 0, true)
local ax1, ay1, bx1, by1 = jointA:getAnchors()
local axis1x, axis1y = jointA:getAxis()

local jointB = love.physics.newPrismaticJoint(bodyA, bodyB, 5, 0, 20, 0, 1, 0, false, 0.75)
jointB:setMotorEnabled(true)
jointB:setMaxMotorForce(90)
jointB:setMotorSpeed(4)
jointB:setLimitsEnabled(true)
jointB:setLimits(-4, 8)
jointB:setLowerLimit(-2)
jointB:setUpperLimit(6)

local lower, upper = jointB:getLimits()
local ax2, ay2, bx2, by2 = jointB:getAnchors()
local axis2x, axis2y = jointB:getAxis()

return
  jointA:getCollideConnected(),
  jointA:getReferenceAngle(),
  jointA:areLimitsEnabled(),
  jointA:hasLimitsEnabled(),
  ax1, ay1, bx1, by1,
  axis1x, axis1y,
  jointB:type(),
  jointB:typeOf('PrismaticJoint'),
  jointB:typeOf('Joint'),
  jointB:getType(),
  jointB:getCollideConnected(),
  jointB:getReferenceAngle(),
  jointB:getJointTranslation(),
  jointB:getJointSpeed(),
  jointB:isMotorEnabled(),
  jointB:getMaxMotorForce(),
  jointB:getMotorSpeed(),
  jointB:getMotorForce(60),
  jointB:areLimitsEnabled(),
  jointB:hasLimitsEnabled(),
  jointB:getLowerLimit(),
  jointB:getUpperLimit(),
  lower, upper,
  ax2, ay2, bx2, by2,
  axis2x, axis2y,
  world:getJointCount(),
  #bodyB:getJoints()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], true);
        expect((values[1] as num).toDouble(), closeTo(0.5, 1e-6));
        expect(values[2], true);
        expect(values[3], true);
        expect((values[4] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[5] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[6] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[7] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[8] as num).toDouble(), closeTo(1, 1e-6));
        expect((values[9] as num).toDouble(), closeTo(0, 1e-6));
        expect(values[10], 'PrismaticJoint');
        expect(values[11], true);
        expect(values[12], true);
        expect(values[13], 'prismatic');
        expect(values[14], false);
        expect((values[15] as num).toDouble(), closeTo(0.75, 1e-6));
        expect((values[16] as num).toDouble(), closeTo(15, 1e-5));
        expect((values[17] as num).toDouble(), closeTo(0, 1e-6));
        expect(values[18], true);
        expect((values[19] as num).toDouble(), closeTo(90, 1e-6));
        expect((values[20] as num).toDouble(), closeTo(4, 1e-6));
        expect(values[21], isA<num>());
        expect(values[22], true);
        expect(values[23], true);
        expect((values[24] as num).toDouble(), closeTo(-2, 1e-6));
        expect((values[25] as num).toDouble(), closeTo(6, 1e-6));
        expect((values[26] as num).toDouble(), closeTo(-2, 1e-6));
        expect((values[27] as num).toDouble(), closeTo(6, 1e-6));
        expect((values[28] as num).toDouble(), closeTo(5, 1e-5));
        expect((values[29] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[30] as num).toDouble(), closeTo(20, 1e-5));
        expect((values[31] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[32] as num).toDouble(), closeTo(1, 1e-6));
        expect((values[33] as num).toDouble(), closeTo(0, 1e-6));
        expect(values[34], 2);
        expect(values[35], 2);
      },
    );

    test(
      'PrismaticJoint destruction updates inventories and invalidates wrappers',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 20, 0, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)

local joint = love.physics.newPrismaticJoint(bodyA, bodyB, 0, 0, 20, 0, 1, 0, false, 0.75)
joint:destroy()

local ok, err = pcall(function()
  return joint:getJointTranslation()
end)

return
  joint:isDestroyed(),
  ok,
  string.find(err, 'destroyed joint') ~= nil,
  world:getJointCount(),
  #bodyB:getJointList()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], true);
        expect(values[1], false);
        expect(values[2], true);
        expect(values[3], 0);
        expect(values[4], 0);
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
