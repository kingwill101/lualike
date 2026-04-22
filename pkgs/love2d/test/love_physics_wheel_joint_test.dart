import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics wheel joints', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'love.physics.newWheelJoint supports LOVE overloads and spring-motor accessors',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 20, 0, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)

local jointA = love.physics.newWheelJoint(bodyA, bodyB, 0, 0, 0, 1, true)
local ax1, ay1, bx1, by1 = jointA:getAnchors()
local axis1x, axis1y = jointA:getAxis()

local jointB = love.physics.newWheelJoint(bodyA, bodyB, 5, 0, 20, 0, 1, 0, false)
jointB:setMotorEnabled(true)
jointB:setMotorSpeed(4)
jointB:setMaxMotorTorque(120)
jointB:setSpringFrequency(8)
jointB:setSpringDampingRatio(0.3)

local ax2, ay2, bx2, by2 = jointB:getAnchors()
local axis2x, axis2y = jointB:getAxis()

return
  jointA:getCollideConnected(),
  ax1, ay1, bx1, by1,
  axis1x, axis1y,
  jointB:type(),
  jointB:typeOf('WheelJoint'),
  jointB:typeOf('Joint'),
  jointB:getType(),
  jointB:getCollideConnected(),
  jointB:getJointTranslation(),
  jointB:getJointSpeed(),
  jointB:isMotorEnabled(),
  jointB:getMotorSpeed(),
  jointB:getMaxMotorTorque(),
  jointB:getMotorTorque(60),
  jointB:getSpringFrequency(),
  jointB:getSpringDampingRatio(),
  ax2, ay2, bx2, by2,
  axis2x, axis2y,
  world:getJointCount(),
  #bodyB:getJoints()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], true);
        expect((values[1] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[2] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[3] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[4] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[5] as num).toDouble(), closeTo(0, 1e-6));
        expect((values[6] as num).toDouble(), closeTo(1, 1e-6));
        expect(values[7], 'WheelJoint');
        expect(values[8], true);
        expect(values[9], true);
        expect(values[10], 'wheel');
        expect(values[11], false);
        expect((values[12] as num).toDouble(), closeTo(15, 1e-5));
        expect((values[13] as num).toDouble(), closeTo(0, 1e-6));
        expect(values[14], true);
        expect((values[15] as num).toDouble(), closeTo(4, 1e-6));
        expect((values[16] as num).toDouble(), closeTo(120, 1e-6));
        expect(values[17], isA<num>());
        expect((values[18] as num).toDouble(), closeTo(8, 1e-6));
        expect((values[19] as num).toDouble(), closeTo(0.3, 1e-6));
        expect((values[20] as num).toDouble(), closeTo(5, 1e-5));
        expect((values[21] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[22] as num).toDouble(), closeTo(20, 1e-5));
        expect((values[23] as num).toDouble(), closeTo(0, 1e-5));
        expect((values[24] as num).toDouble(), closeTo(1, 1e-6));
        expect((values[25] as num).toDouble(), closeTo(0, 1e-6));
        expect(values[26], 2);
        expect(values[27], 2);
      },
    );

    test(
      'WheelJoint destruction updates inventories and invalidates wrappers',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 20, 0, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)

local joint = love.physics.newWheelJoint(bodyA, bodyB, 0, 0, 20, 0, 1, 0, false)
joint:destroy()

local ok, err = pcall(function()
  return joint:getAxis()
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
