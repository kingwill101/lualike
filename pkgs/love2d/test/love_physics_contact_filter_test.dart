import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.physics world contact filters', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'World:getContactFilter roundtrips callback registration and clearing',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)

local filter = function() return true end
world:setContactFilter(filter)
local gotFilter = world:getContactFilter()

world:setContactFilter()
local cleared = world:getContactFilter()

return gotFilter == filter, cleared == nil
''');

        expect(result, <Object?>[true, true]);
      },
    );

    test('World:getContactFilter works from coroutines', () async {
      final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)

local filter = function() return true end
world:setContactFilter(filter)

local thread = coroutine.create(function()
  local gotFilter = world:getContactFilter()
  return gotFilter == filter
end)

local ok, matches = coroutine.resume(thread)
return ok, matches
''');

      expect(result, <Object?>[true, true]);
    });

    test('World:setContactFilter can suppress an initial overlap', () async {
      final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 15, 0, 'dynamic')

love.physics.newFixture(bodyA, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(10), 1)

local calls = 0
local locked = false

world:setContactFilter(function(fixtureA, fixtureB)
  calls = calls + 1
  locked = world:isLocked()
  return false
end)

world:update(1 / 60)

return calls, locked, world:getContactCount(), #world:getContacts()
''');

      expect(result, isA<List<Object?>>());
      final values = result! as List<Object?>;
      expect(values[0], isA<num>());
      expect((values[0] as num).toInt(), greaterThan(0));
      expect(values[1], true);
      expect(values[2], 0);
      expect(values[3], 0);
    });

    test(
      'World:setContactFilter refilters existing contacts on the next update',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 15, 0, 'dynamic')

love.physics.newFixture(bodyA, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(10), 1)

world:update(1 / 60)
local before = world:getContactCount()

local calls = 0
world:setContactFilter(function()
  calls = calls + 1
  return false
end)

world:update(1 / 60)

return before, calls, world:getContactCount(), #bodyB:getContacts()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], 1);
        expect(values[1], isA<num>());
        expect((values[1] as num).toInt(), greaterThan(0));
        expect(values[2], 0);
        expect(values[3], 0);
      },
    );

    test(
      'World:setContactFilter suppresses contacts that first arise mid-step',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 35, 0, 'dynamic')

love.physics.newFixture(bodyA, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(10), 1)

bodyB:setLinearVelocity(-1000, 0)

local calls = 0
world:setContactFilter(function(fixtureA, fixtureB)
  calls = calls + 1
  return false
end)

world:update(1 / 60)

return calls, world:getContactCount(), #bodyB:getContacts(), bodyB:getX()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], isA<num>());
        expect((values[0] as num).toInt(), greaterThan(0));
        expect(values[1], 0);
        expect(values[2], 0);
        expect(values[3], isA<num>());
        expect((values[3] as num).toDouble(), lessThan(20));
      },
    );

    test(
      'World:setContactFilter suppresses gravity-driven mid-step contacts from rest',
      () async {
        final result = await _execute(lua, '''
local function run(useFilter)
  local world = love.physics.newWorld(0, 7200, false)
  local floor = love.physics.newBody(world, 0, 0, 'static')
  local ball = love.physics.newBody(world, 0, -21, 'dynamic')

  love.physics.newFixture(floor, love.physics.newCircleShape(10), 1)
  love.physics.newFixture(ball, love.physics.newCircleShape(10), 1)

  local calls = 0
  if useFilter then
    world:setContactFilter(function()
      calls = calls + 1
      return false
    end)
  end

  world:update(1 / 60)

  return calls, world:getContactCount(), #ball:getContacts(), ball:getY()
end

local controlCalls, controlContacts, controlBodyContacts, controlY = run(false)
local filterCalls, filterContacts, filterBodyContacts, filterY = run(true)

return
  controlCalls,
  controlContacts,
  controlBodyContacts,
  controlY,
  filterCalls,
  filterContacts,
  filterBodyContacts,
  filterY
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values, hasLength(8));

        expect(values[0], 0);
        expect(values[1], 1);
        expect(values[2], 1);
        expect(values[3], isA<num>());
        expect((values[3] as num).toDouble(), greaterThan(-21));

        expect(values[4], isA<num>());
        expect((values[4] as num).toInt(), greaterThan(0));
        expect(values[5], 0);
        expect(values[6], 0);
        expect(values[7], isA<num>());
        expect((values[7] as num).toDouble(), greaterThan(-21));
      },
    );

    test(
      'World:setContactFilter suppresses rotation-driven mid-step contacts',
      () async {
        final result = await _execute(lua, '''
local function run(useFilter)
  local world = love.physics.newWorld(0, 0, false)
  local rotor = love.physics.newBody(world, 0, 0, 'dynamic')
  local obstacle = love.physics.newBody(world, 55, 0, 'static')

  love.physics.newFixture(rotor, love.physics.newRectangleShape(120, 10), 1)
  love.physics.newFixture(obstacle, love.physics.newCircleShape(10), 1)

  rotor:setAngle(math.pi / 2)
  rotor:setAngularVelocity(-120)

  local calls = 0
  if useFilter then
    world:setContactFilter(function()
      calls = calls + 1
      return false
    end)
  end

  world:update(1 / 60)

  return calls, world:getContactCount(), #rotor:getContacts(), rotor:getAngle()
end

local controlCalls, controlContacts, controlBodyContacts, controlAngle = run(false)
local filterCalls, filterContacts, filterBodyContacts, filterAngle = run(true)

return
  controlCalls,
  controlContacts,
  controlBodyContacts,
  controlAngle,
  filterCalls,
  filterContacts,
  filterBodyContacts,
  filterAngle
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values, hasLength(8));

        expect(values[0], 0);
        expect(values[1], 1);
        expect(values[2], 1);
        expect(values[3], isA<num>());
        expect((values[3] as num).toDouble(), lessThan(0.25));

        expect(values[4], isA<num>());
        expect((values[4] as num).toInt(), greaterThan(0));
        expect(values[5], 0);
        expect(values[6], 0);
        expect(values[7], isA<num>());
        expect((values[7] as num).toDouble(), lessThan(0.25));
      },
    );

    test(
      'World:setContactFilter suppresses contacts that only arise at an intermediate rotation sample',
      () async {
        final result = await _execute(lua, '''
local function run(useFilter)
  local world = love.physics.newWorld(0, 0, false)
  local rotor = love.physics.newBody(world, 0, 0, 'dynamic')
  local obstacle = love.physics.newBody(world, 54, 14, 'static')

  love.physics.newFixture(rotor, love.physics.newRectangleShape(100, 60), 1)
  love.physics.newFixture(obstacle, love.physics.newCircleShape(3), 1)

  rotor:setAngularVelocity(math.pi * 30)

  local calls = 0
  if useFilter then
    world:setContactFilter(function()
      calls = calls + 1
      return false
    end)
  end

  world:update(1 / 60)

  return calls, world:getContactCount(), #rotor:getContacts(), rotor:getAngle()
end

local controlCalls, controlContacts, controlBodyContacts, controlAngle = run(false)
local filterCalls, filterContacts, filterBodyContacts, filterAngle = run(true)

return
  controlCalls,
  controlContacts,
  controlBodyContacts,
  controlAngle,
  filterCalls,
  filterContacts,
  filterBodyContacts,
  filterAngle
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values, hasLength(8));

        expect(values[0], 0);
        expect(values[1], 1);
        expect(values[2], 1);
        expect(values[3], isA<num>());
        expect((values[3] as num).toDouble(), greaterThan(0.9));

        expect(values[4], isA<num>());
        expect((values[4] as num).toInt(), greaterThan(0));
        expect(values[5], 0);
        expect(values[6], 0);
        expect(values[7], isA<num>());
        expect((values[7] as num).toDouble(), greaterThan(0.9));
      },
    );

    test(
      'World:setContactFilter skips fixture pairs that cannot overlap this step',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 500, 0, 'dynamic')

love.physics.newFixture(bodyA, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(10), 1)

local calls = 0
world:setContactFilter(function()
  calls = calls + 1
  return false
end)

world:update(1 / 60)

return calls, world:getContactCount(), bodyB:getX()
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values[0], 0);
        expect(values[1], 0);
        expect(values[2], isA<num>());
        expect((values[2] as num).toDouble(), closeTo(500, 1e-4));
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
