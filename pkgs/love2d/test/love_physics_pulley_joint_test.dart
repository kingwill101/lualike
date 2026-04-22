import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics pulley joints', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'love.physics.newPulleyJoint exposes pulley getters and compatibility setters',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 10, 40, 'dynamic')
local bodyB = love.physics.newBody(world, 50, 40, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)

local joint = love.physics.newPulleyJoint(
  bodyA, bodyB,
  10, 10,
  50, 10,
  10, 40,
  50, 40,
  2,
  false
)

local gx1, gy1, gx2, gy2 = joint:getGroundAnchors()
local constantA = joint:getConstant()
local maxA1, maxB1 = joint:getMaxLengths()

joint:setConstant(120)
local constantB = joint:getConstant()
local maxA2, maxB2 = joint:getMaxLengths()

joint:setRatio(3)
local ratioB = joint:getRatio()
local maxA3, maxB3 = joint:getMaxLengths()

joint:setMaxLengths(90, 20)
local constantC = joint:getConstant()
local maxA4, maxB4 = joint:getMaxLengths()

return
  joint:type(),
  joint:typeOf('PulleyJoint'),
  joint:typeOf('Joint'),
  joint:getType(),
  joint:getCollideConnected(),
  gx1, gy1, gx2, gy2,
  joint:getLengthA(),
  joint:getLengthB(),
  constantA,
  maxA1, maxB1,
  constantB,
  maxA2, maxB2,
  ratioB,
  maxA3, maxB3,
  constantC,
  maxA4, maxB4,
  world:getJointCount(),
  #bodyA:getJoints(),
  #bodyB:getJoints()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], 'PulleyJoint');
        expect(values[1], true);
        expect(values[2], true);
        expect(values[3], 'pulley');
        expect(values[4], false);
        expect((values[5] as num).toDouble(), closeTo(10, 1e-5));
        expect((values[6] as num).toDouble(), closeTo(10, 1e-5));
        expect((values[7] as num).toDouble(), closeTo(50, 1e-5));
        expect((values[8] as num).toDouble(), closeTo(10, 1e-5));
        expect((values[9] as num).toDouble(), closeTo(15, 1e-5));
        expect((values[10] as num).toDouble(), closeTo(15, 1e-5));
        expect((values[11] as num).toDouble(), closeTo(90, 1e-6));
        expect((values[12] as num).toDouble(), closeTo(90, 1e-6));
        expect((values[13] as num).toDouble(), closeTo(45, 1e-6));
        expect((values[14] as num).toDouble(), closeTo(120, 1e-6));
        expect((values[15] as num).toDouble(), closeTo(120, 1e-6));
        expect((values[16] as num).toDouble(), closeTo(60, 1e-6));
        expect((values[17] as num).toDouble(), closeTo(3, 1e-6));
        expect((values[18] as num).toDouble(), closeTo(120, 1e-6));
        expect((values[19] as num).toDouble(), closeTo(40, 1e-6));
        expect((values[20] as num).toDouble(), closeTo(60, 1e-6));
        expect((values[21] as num).toDouble(), closeTo(60, 1e-6));
        expect((values[22] as num).toDouble(), closeTo(20, 1e-6));
        expect(values[23], 1);
        expect(values[24], 1);
        expect(values[25], 1);
      },
    );

    test(
      'PulleyJoint destruction updates inventories and invalidates wrappers',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 10, 40, 'dynamic')
local bodyB = love.physics.newBody(world, 50, 40, 'dynamic')
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)

local joint = love.physics.newPulleyJoint(
  bodyA, bodyB,
  10, 10,
  50, 10,
  10, 40,
  50, 40
)

local constantOk, constantErr = pcall(function()
  joint:setConstant(-1)
end)

local maxOk, maxErr = pcall(function()
  joint:setMaxLengths(-1, 5)
end)

local ratioOk, ratioErr = pcall(function()
  joint:setRatio(0)
end)

joint:destroy()

local ok, err = pcall(function()
  return joint:getLengthA()
end)

return
  constantOk,
  string.find(constantErr, 'non%-negative number') ~= nil,
  maxOk,
  string.find(maxErr, 'non%-negative numbers') ~= nil,
  ratioOk,
  string.find(ratioErr, 'positive number') ~= nil,
  joint:isDestroyed(),
  ok,
  string.find(err, 'destroyed joint') ~= nil,
  world:getJointCount(),
  #bodyA:getJointList(),
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
        expect(values[11], 0);
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
