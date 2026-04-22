import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics revolute joints', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'love.physics.newRevoluteJoint supports LOVE overloads and motor-limit accessors',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'dynamic')
local bodyB = love.physics.newBody(world, 20, 0, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)
bodyB:setAngle(0.5)

local jointA = love.physics.newRevoluteJoint(bodyA, bodyB, 0, 0, true)
local ax1, ay1, bx1, by1 = jointA:getAnchors()

local jointB = love.physics.newRevoluteJoint(bodyA, bodyB, 5, 0, 20, 0, false, 1.25)
jointB:setMotorEnabled(true)
jointB:setMaxMotorTorque(90)
jointB:setMotorSpeed(3.5)
jointB:setLimitsEnabled(true)
jointB:setLimits(-0.4, 0.8)
jointB:setLowerLimit(-0.2)
jointB:setUpperLimit(0.6)

local lower, upper = jointB:getLimits()
local ax2, ay2, bx2, by2 = jointB:getAnchors()

return
  jointA:getCollideConnected(),
  jointA:getReferenceAngle(),
  ax1, ay1, bx1, by1,
  jointB:type(),
  jointB:typeOf('RevoluteJoint'),
  jointB:typeOf('Joint'),
  jointB:getType(),
  jointB:getCollideConnected(),
  jointB:getReferenceAngle(),
  jointB:getJointAngle(),
  jointB:getJointSpeed(),
  jointB:isMotorEnabled(),
  jointB:getMaxMotorTorque(),
  jointB:getMotorSpeed(),
  jointB:getMotorTorque(60),
  jointB:areLimitsEnabled(),
  jointB:hasLimitsEnabled(),
  jointB:getLowerLimit(),
  jointB:getUpperLimit(),
  lower, upper,
  ax2, ay2, bx2, by2,
  world:getJointCount(),
  #bodyA:getJoints()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], true);
        expect((values[1] as num).toDouble(), closeTo(0.5, 1e-6));
        expect((values[2] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[3] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[4] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[5] as num).toDouble(), closeTo(0, 1e-5));
        expect(values[6], 'RevoluteJoint');
        expect(values[7], true);
        expect(values[8], true);
        expect(values[9], 'revolute');
        expect(values[10], false);
        expect((values[11] as num).toDouble(), closeTo(1.25, 1e-6));
        expect((values[12] as num).toDouble(), closeTo(-0.75, 1e-6));
        expect((values[13] as num).toDouble(), closeTo(0, 1e-6));
        expect(values[14], true);
        expect((values[15] as num).toDouble(), closeTo(90, 1e-6));
        expect((values[16] as num).toDouble(), closeTo(3.5, 1e-6));
        expect(values[17], isA<num>());
        expect(values[18], true);
        expect(values[19], true);
        expect((values[20] as num).toDouble(), closeTo(-0.2, 1e-6));
        expect((values[21] as num).toDouble(), closeTo(0.6, 1e-6));
        expect((values[22] as num).toDouble(), closeTo(-0.2, 1e-6));
        expect((values[23] as num).toDouble(), closeTo(0.6, 1e-6));
        expect((values[24] as num).toDouble(), closeTo(5, 1e-5));
        expect((values[25] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[26] as num).toDouble(), closeTo(20, 1e-5));
        expect((values[27] as num).toDouble(), closeTo(0, 1e-5));
        expect(values[28], 2);
        expect(values[29], 2);
      },
    );

    test(
      'RevoluteJoint destruction updates inventories and invalidates wrappers',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'dynamic')
local bodyB = love.physics.newBody(world, 20, 0, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)

local joint = love.physics.newRevoluteJoint(bodyA, bodyB, 0, 0, 20, 0, false, 0.75)
joint:destroy()

local ok, err = pcall(function()
  return joint:getJointAngle()
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
