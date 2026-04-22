import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics mouse joints', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'love.physics.newMouseJoint exposes LOVE mouse joint semantics',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local body = love.physics.newBody(world, 10, 20, 'dynamic')
local shape = love.physics.newCircleShape(5)
love.physics.newFixture(body, shape, 2)

local joint = love.physics.newMouseJoint(body, 15, 20)
local initialMaxForce = joint:getMaxForce()

joint:setTarget(30, 40)
joint:setFrequency(9)
joint:setDampingRatio(0.25)
joint:setMaxForce(1234)

local bodyA, bodyB = joint:getBodies()
local tx, ty = joint:getTarget()
local ax, ay, bx, by = joint:getAnchors()

return
  joint:type(),
  joint:typeOf('MouseJoint'),
  joint:typeOf('Joint'),
  joint:getType(),
  joint:getCollideConnected(),
  bodyA == body,
  bodyB == nil,
  initialMaxForce > 0,
  joint:getMaxForce(),
  joint:getFrequency(),
  joint:getDampingRatio(),
  tx, ty,
  ax, ay, bx, by,
  world:getJointCount(),
  #world:getJoints(),
  #body:getJointList()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], 'MouseJoint');
        expect(values[1], true);
        expect(values[2], true);
        expect(values[3], 'mouse');
        expect(values[4], false);
        expect(values[5], true);
        expect(values[6], true);
        expect(values[7], true);
        expect((values[8] as num).toDouble(), closeTo(1234, 1e-6));
        expect((values[9] as num).toDouble(), closeTo(9, 1e-6));
        expect((values[10] as num).toDouble(), closeTo(0.25, 1e-6));
        expect((values[11] as num).toDouble(), closeTo(30, 1e-5));
        expect((values[12] as num).toDouble(), closeTo(40, 1e-5));
        expect((values[13] as num).toDouble(), closeTo(30, 1e-5));
        expect((values[14] as num).toDouble(), closeTo(40, 1e-5));
        expect((values[15] as num).toDouble(), closeTo(15, 1e-5));
        expect((values[16] as num).toDouble(), closeTo(20, 1e-5));
        expect(values[17], 1);
        expect(values[18], 1);
        expect(values[19], 1);
      },
    );

    test(
      'MouseJoint rejects kinematic bodies and preserves destroyed errors',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local kinematic = love.physics.newBody(world, 0, 0, 'kinematic')

local ctorOk, ctorErr = pcall(function()
  return love.physics.newMouseJoint(kinematic, 0, 0)
end)

local body = love.physics.newBody(world, 0, 0, 'dynamic')
love.physics.newFixture(body, love.physics.newCircleShape(5), 1)
local joint = love.physics.newMouseJoint(body, 0, 0)
joint:setFrequency(4)

local frequencyOk, frequencyErr = pcall(function()
  joint:setFrequency(0)
end)

local frequency = joint:getFrequency()
joint:destroy()

local useOk, useErr = pcall(function()
  return joint:getTarget()
end)

return
  ctorOk,
  string.find(ctorErr, 'Cannot attach a MouseJoint to a kinematic body') ~= nil,
  frequencyOk,
  string.find(frequencyErr, 'positive number') ~= nil,
  frequency,
  joint:isDestroyed(),
  useOk,
  string.find(useErr, 'destroyed joint') ~= nil,
  world:getJointCount(),
  #body:getJoints()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], false);
        expect(values[1], true);
        expect(values[2], false);
        expect(values[3], true);
        expect((values[4] as num).toDouble(), closeTo(4, 1e-6));
        expect(values[5], true);
        expect(values[6], false);
        expect(values[7], true);
        expect(values[8], 0);
        expect(values[9], 0);
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
