import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';
import 'test_support/physics_test_support.dart';

void main() {
  group('love.physics world callbacks', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test(
      'World:getCallbacks roundtrips callback registration and clearing',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)

local begin = function() end
local pre = function() end
local post = function() end

world:setCallbacks(begin, nil, pre, post)
local gotBegin, gotEnd, gotPre, gotPost = world:getCallbacks()

world:setCallbacks()
local clearedBegin, clearedEnd, clearedPre, clearedPost = world:getCallbacks()

return
  gotBegin == begin,
  gotEnd == nil,
  gotPre == pre,
  gotPost == post,
  clearedBegin == nil,
  clearedEnd == nil,
  clearedPre == nil,
  clearedPost == nil
''');

        expect(result, <Object?>[
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
        ]);
      },
    );

    test('World:getCallbacks works from coroutines', () async {
      final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)

local begin = function() end
local finish = function() end

world:setCallbacks(begin, nil, nil, finish)

local thread = coroutine.create(function()
  local gotBegin, gotEnd, gotPre, gotPost = world:getCallbacks()
  return gotBegin == begin, gotEnd == nil, gotPre == nil, gotPost == finish
end)

local ok, beginMatches, endCleared, preCleared, postMatches = coroutine.resume(thread)
return ok, beginMatches, endCleared, preCleared, postMatches
''');

      expect(result, <Object?>[true, true, true, true, true]);
    });

    test(
      'World:setCallbacks preserves queued callback order across collide, TOI, and end-contact paths',
      () async {
        final result = await _execute(lua, '''
local world = love.physics.newWorld(0, 0, false)
local bodyA = love.physics.newBody(world, 0, 0, 'static')
local bodyB = love.physics.newBody(world, 15, 0, 'dynamic')

love.physics.newFixture(bodyA, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(10), 1)

local events = {}

world:setCallbacks(
  function(fixtureA, fixtureB, contact)
    events[#events + 1] = {
      'begin',
      fixtureA:getType(),
      fixtureB:getType(),
      contact:type(),
      contact:isTouching(),
      world:isLocked(),
    }
  end,
  function(fixtureA, fixtureB, contact)
    local endA, endB = contact:getFixtures()
    events[#events + 1] = {
      'end',
      endA:getType(),
      endB:getType(),
      contact:type(),
      contact:isTouching(),
      world:isLocked(),
    }
  end,
  function(fixtureA, fixtureB, contact)
    events[#events + 1] = {
      'pre',
      fixtureA:getType(),
      fixtureB:getType(),
      contact:isEnabled(),
      world:isLocked(),
    }
  end,
  function(fixtureA, fixtureB, contact, ni1, ti1)
    events[#events + 1] = {
      'post',
      fixtureA:getType(),
      fixtureB:getType(),
      contact:type(),
      ni1,
      ti1,
      world:isLocked(),
    }
  end
)

world:update(1 / 60)
bodyB:setPosition(100, 0)
world:update(1 / 60)

return events
''');

        expect(result, isA<Map>());
        final events = indexedValues(result! as Map);
        expect(events, hasLength(6));

        final begin = indexedValues(events[0] as Map);
        expect(begin, <Object?>[
          'begin',
          'circle',
          'circle',
          'Contact',
          true,
          true,
        ]);

        final pre = indexedValues(events[1] as Map);
        expect(pre, <Object?>['pre', 'circle', 'circle', true, true]);

        final post = indexedValues(events[2] as Map);
        expect(post[0], 'post');
        expect(post[1], 'circle');
        expect(post[2], 'circle');
        expect(post[3], 'Contact');
        expect(post[4], isA<num>());
        expect((post[4] as num).toDouble(), closeTo(0, 1e-5));
        expect(post[5], isA<num>());
        expect((post[5] as num).toDouble(), closeTo(0, 1e-5));
        expect(post[6], true);

        final secondPre = indexedValues(events[3] as Map);
        expect(secondPre, <Object?>['pre', 'circle', 'circle', true, true]);

        final secondPost = indexedValues(events[4] as Map);
        expect(secondPost[0], 'post');
        expect(secondPost[1], 'circle');
        expect(secondPost[2], 'circle');
        expect(secondPost[3], 'Contact');
        expect(secondPost[4], isA<num>());
        expect((secondPost[4] as num).toDouble(), closeTo(0, 1e-5));
        expect(secondPost[5], isA<num>());
        expect((secondPost[5] as num).toDouble(), closeTo(0, 1e-5));
        expect(secondPost[6], true);

        final end = indexedValues(events[5] as Map);
        expect(end, <Object?>[
          'end',
          'circle',
          'circle',
          'Contact',
          true,
          true,
        ]);
      },
    );

    test(
      'World:setCallbacks applies preSolve contact disabling during the same step',
      () async {
        final result = await _execute(lua, '''
local function run(disableDuringPreSolve)
  local world = love.physics.newWorld(0, 0, false)
  local bodyA = love.physics.newBody(world, 0, 0, 'static')
  local bodyB = love.physics.newBody(world, 35, 0, 'dynamic')

  love.physics.newFixture(bodyA, love.physics.newCircleShape(10), 1)
  love.physics.newFixture(bodyB, love.physics.newCircleShape(10), 1)

  bodyB:setLinearVelocity(-3000, 0)

  local preCount = 0
  local postCount = 0

  world:setCallbacks(
    nil,
    nil,
    function(_, _, contact)
      preCount = preCount + 1
      if disableDuringPreSolve then
        contact:setEnabled(false)
      end
    end,
    function()
      postCount = postCount + 1
    end
  )

  world:update(1 / 60)
  return preCount, postCount, world:getContactCount(), #bodyB:getContacts(), bodyB:getX()
end

local controlPre, controlPost, controlContacts, controlBodyContacts, controlX = run(false)
local disabledPre, disabledPost, disabledContacts, disabledBodyContacts, disabledX = run(true)

return
  controlPre,
  controlPost,
  controlContacts,
  controlBodyContacts,
  controlX,
  disabledPre,
  disabledPost,
  disabledContacts,
  disabledBodyContacts,
  disabledX
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values, hasLength(10));

        expect(values[0], 1);
        expect(values[1], 1);
        expect(values[2], 1);
        expect(values[3], 1);
        expect(values[4], isA<num>());
        expect((values[4] as num).toDouble(), greaterThan(0));

        expect(values[5], 1);
        expect(values[6], 0);
        expect(values[7], isA<num>());
        expect(values[8], isA<num>());
        expect(values[9], isA<num>());
        expect((values[9] as num).toDouble(), lessThan(0));
        expect((values[9] as num).toDouble(), lessThan((values[4] as num)));
      },
    );

    test(
      'World:setCallbacks replays preSolve friction changes on later steps',
      () async {
        final result = await _execute(lua, '''
local function runScenario(overrideContactFriction)
  local world = love.physics.newWorld(0, 1000, false)
  local floor = love.physics.newBody(world, 0, 100, 'static')
  local box = love.physics.newBody(world, 0, 80, 'dynamic')

  local floorFixture = love.physics.newFixture(
    floor,
    love.physics.newRectangleShape(400, 20),
    1
  )
  local boxFixture = love.physics.newFixture(
    box,
    love.physics.newRectangleShape(20, 20),
    1
  )

  floorFixture:setFriction(4)
  boxFixture:setFriction(4)
  floorFixture:setRestitution(0)
  boxFixture:setRestitution(0)
  box:setFixedRotation(true)
  box:setLinearVelocity(120, 0)

  local firstPreSolve = true
  world:setCallbacks(
    nil,
    nil,
    function(_, _, contact)
      if overrideContactFriction and firstPreSolve then
        contact:setFriction(0)
        firstPreSolve = false
      end
    end
  )

  world:update(1 / 60)
  for i = 1, 20 do
    world:update(1 / 60)
  end

  return box:getLinearVelocity()
end

local controlDx = runScenario(false)
local overrideDx = runScenario(true)
return controlDx, overrideDx
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values, hasLength(2));

        final controlDx = (values[0] as num).toDouble();
        final overrideDx = (values[1] as num).toDouble();

        expect(controlDx, lessThan(overrideDx));
        expect(controlDx, lessThan(50));
        expect(overrideDx, greaterThan(controlDx * 1.5));
        expect(overrideDx, greaterThan(45));
      },
    );

    test(
      'World:setCallbacks replays preSolve restitution changes on later steps',
      () async {
        final result = await _execute(lua, '''
local function runScenario(overrideContactRestitution)
  local world = love.physics.newWorld(0, 0, false)
  local floor = love.physics.newBody(world, 0, 100, 'static')
  local ball = love.physics.newBody(world, 0, 80, 'dynamic')

  local floorFixture = love.physics.newFixture(
    floor,
    love.physics.newRectangleShape(400, 20),
    1
  )
  local ballFixture = love.physics.newFixture(
    ball,
    love.physics.newCircleShape(10),
    1
  )

  floorFixture:setRestitution(0)
  ballFixture:setRestitution(0)

  local firstPreSolve = true
  world:setCallbacks(
    nil,
    nil,
    function(_, _, contact)
      if overrideContactRestitution and firstPreSolve then
        contact:setRestitution(1)
        firstPreSolve = false
      end
    end
  )

  world:update(1 / 60)
  ball:setLinearVelocity(0, 240)
  world:update(1 / 60)

  local _, dy = ball:getLinearVelocity()
  return dy
end

local controlDy = runScenario(false)
local overrideDy = runScenario(true)
return controlDy, overrideDy
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values, hasLength(2));

        final controlDy = (values[0] as num).toDouble();
        final overrideDy = (values[1] as num).toDouble();

        expect(controlDy, greaterThan(-1));
        expect(overrideDy, lessThan(controlDy - 100));
        expect(overrideDy, lessThan(-50));
      },
    );

    test(
      'World:setCallbacks replays preSolve tangent speed changes on later steps',
      () async {
        final result = await _execute(lua, '''
local function runScenario(overrideContactTangentSpeed)
  local world = love.physics.newWorld(0, 1000, false)
  local floor = love.physics.newBody(world, 0, 100, 'static')
  local box = love.physics.newBody(world, 0, 80, 'dynamic')

  local floorFixture = love.physics.newFixture(
    floor,
    love.physics.newRectangleShape(400, 20),
    1
  )
  local boxFixture = love.physics.newFixture(
    box,
    love.physics.newRectangleShape(20, 20),
    1
  )

  floorFixture:setFriction(8)
  boxFixture:setFriction(8)
  floorFixture:setRestitution(0)
  boxFixture:setRestitution(0)
  box:setFixedRotation(true)

  local firstPreSolve = true
  world:setCallbacks(
    nil,
    nil,
    function(_, _, contact)
      if overrideContactTangentSpeed and firstPreSolve then
        contact:setTangentSpeed(5)
        firstPreSolve = false
      end
    end
  )

  world:update(1 / 60)
  for i = 1, 20 do
    world:update(1 / 60)
  end

  return box:getLinearVelocity()
end

local controlDx = runScenario(false)
local overrideDx = runScenario(true)
return controlDx, overrideDx
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values, hasLength(2));

        final controlDx = (values[0] as num).toDouble();
        final overrideDx = (values[1] as num).toDouble();

        expect(controlDx.abs(), lessThan(10));
        expect(overrideDx.abs(), greaterThan(controlDx.abs() + 40));
        expect(overrideDx.abs(), greaterThan(60));
      },
    );

    test(
      'World:setCallbacks replays preSolve friction resets on later steps',
      () async {
        final result = await _execute(lua, '''
local function runScenario(mode)
  local world = love.physics.newWorld(0, 1000, false)
  local floor = love.physics.newBody(world, 0, 100, 'static')
  local box = love.physics.newBody(world, 0, 80, 'dynamic')

  local floorFixture = love.physics.newFixture(
    floor,
    love.physics.newRectangleShape(400, 20),
    1
  )
  local boxFixture = love.physics.newFixture(
    box,
    love.physics.newRectangleShape(20, 20),
    1
  )

  floorFixture:setFriction(4)
  boxFixture:setFriction(4)
  floorFixture:setRestitution(0)
  boxFixture:setRestitution(0)
  box:setFixedRotation(true)

  local phase = 0
  world:setCallbacks(
    nil,
    nil,
    function(_, _, contact)
      if mode == 'override' and phase == 0 then
        contact:setFriction(0)
        phase = 1
      elseif mode == 'reset' then
        if phase == 0 then
          contact:setFriction(0)
          phase = 1
        elseif phase == 1 then
          contact:resetFriction()
          phase = 2
        end
      end
    end
  )

  world:update(1 / 60)
  world:update(1 / 60)
  box:setLinearVelocity(120, 0)
  for i = 1, 20 do
    world:update(1 / 60)
  end

  local dx = box:getLinearVelocity()
  return dx
end

local controlDx = runScenario('control')
local overrideDx = runScenario('override')
local resetDx = runScenario('reset')
return controlDx, overrideDx, resetDx
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values, hasLength(3));

        final controlDx = (values[0] as num).toDouble();
        final overrideDx = (values[1] as num).toDouble();
        final resetDx = (values[2] as num).toDouble();

        expect(controlDx, lessThan(overrideDx));
        expect(resetDx, lessThan(overrideDx - 10));
        expect(resetDx, lessThan(controlDx + 15));
      },
    );

    test(
      'World:setCallbacks replays preSolve restitution resets on later steps',
      () async {
        final result = await _execute(lua, '''
local function runScenario(mode)
  local world = love.physics.newWorld(0, 0, false)
  local floor = love.physics.newBody(world, 0, 100, 'static')
  local ball = love.physics.newBody(world, 0, 80, 'dynamic')

  local floorFixture = love.physics.newFixture(
    floor,
    love.physics.newRectangleShape(400, 20),
    1
  )
  local ballFixture = love.physics.newFixture(
    ball,
    love.physics.newCircleShape(10),
    1
  )

  floorFixture:setRestitution(0)
  ballFixture:setRestitution(0)

  local phase = 0
  world:setCallbacks(
    nil,
    nil,
    function(_, _, contact)
      if mode == 'override' and phase == 0 then
        contact:setRestitution(1)
        phase = 1
      elseif mode == 'reset' then
        if phase == 0 then
          contact:setRestitution(1)
          phase = 1
        elseif phase == 1 then
          contact:resetRestitution()
          phase = 2
        end
      end
    end
  )

  world:update(1 / 60)
  world:update(1 / 60)
  ball:setLinearVelocity(0, 240)
  world:update(1 / 60)

  local _, dy = ball:getLinearVelocity()
  return dy
end

local controlDy = runScenario('control')
local overrideDy = runScenario('override')
local resetDy = runScenario('reset')
return controlDy, overrideDy, resetDy
''');

        expect(result, isA<List<Object?>>());
        final values = result! as List<Object?>;
        expect(values, hasLength(3));

        final controlDy = (values[0] as num).toDouble();
        final overrideDy = (values[1] as num).toDouble();
        final resetDy = (values[2] as num).toDouble();

        expect(controlDy, greaterThan(-1));
        expect(overrideDy, lessThan(-50));
        expect(resetDy, greaterThan(overrideDy + 100));
        expect(resetDy, greaterThan(-5));
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
