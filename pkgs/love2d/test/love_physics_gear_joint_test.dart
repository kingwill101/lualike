import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.physics gear joints', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'love.physics.newGearJoint connects revolute and prismatic joints with ratio accessors',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)

local groundA = love.physics.newBody(world, 0, 0, 'static')
local bodyA = love.physics.newBody(world, 20, 0, 'dynamic')
love.physics.newFixture(groundA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)

local groundB = love.physics.newBody(world, 60, 0, 'static')
local bodyB = love.physics.newBody(world, 80, 0, 'dynamic')
love.physics.newFixture(groundB, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)

local revolute = love.physics.newRevoluteJoint(groundA, bodyA, 20, 0, false)
local prismatic = love.physics.newPrismaticJoint(groundB, bodyB, 80, 0, 1, 0, false)
local gear = love.physics.newGearJoint(revolute, prismatic, 2.5, true)
local joint1, joint2 = gear:getJoints()
gear:setRatio(1.25)

return
  gear:type(),
  gear:typeOf('GearJoint'),
  gear:typeOf('Joint'),
  gear:getType(),
  gear:getCollideConnected(),
  gear:getRatio(),
  joint1 == revolute,
  joint2 == prismatic,
  world:getJointCount(),
  #bodyA:getJoints(),
  #bodyB:getJoints()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], 'GearJoint');
        expect(values[1], true);
        expect(values[2], true);
        expect(values[3], 'gear');
        expect(values[4], true);
        expect((values[5] as num).toDouble(), closeTo(1.25, 1e-6));
        expect(values[6], true);
        expect(values[7], true);
        expect(values[8], 3);
        expect(values[9], 2);
        expect(values[10], 2);
      },
    );

    test(
      'GearJoint rejects unsupported joints and destruction updates inventories',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)

local groundA = love.physics.newBody(world, 0, 0, 'static')
local bodyA = love.physics.newBody(world, 20, 0, 'dynamic')
love.physics.newFixture(groundA, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyA, love.physics.newCircleShape(5), 1)

local groundB = love.physics.newBody(world, 60, 0, 'static')
local bodyB = love.physics.newBody(world, 80, 0, 'dynamic')
love.physics.newFixture(groundB, love.physics.newCircleShape(5), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(5), 1)

local revolute = love.physics.newRevoluteJoint(groundA, bodyA, 20, 0, false)
local prismatic = love.physics.newPrismaticJoint(groundB, bodyB, 80, 0, 1, 0, false)
local friction = love.physics.newFrictionJoint(groundA, bodyA, 0, 0, false)

local ctorOk, ctorErr = pcall(function()
  return love.physics.newGearJoint(friction, revolute, 1, false)
end)

local gear = love.physics.newGearJoint(revolute, prismatic, 2, false)
gear:destroy()

local useOk, useErr = pcall(function()
  return gear:getRatio()
end)

return
  ctorOk,
  string.find(ctorErr, 'revolute or prismatic joints') ~= nil,
  gear:isDestroyed(),
  useOk,
  string.find(useErr, 'destroyed joint') ~= nil,
  world:getJointCount(),
  #bodyA:getJointList(),
  #bodyB:getJointList()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], false);
        expect(values[1], true);
        expect(values[2], true);
        expect(values[3], false);
        expect(values[4], true);
        expect(values[5], 3);
        expect(values[6], 2);
        expect(values[7], 1);
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return _resolveCallResult(lua.execute(code, scriptPath: scriptPath));
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
