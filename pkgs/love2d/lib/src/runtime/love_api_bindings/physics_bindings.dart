part of '../love_api_bindings.dart';

/// The maximum polygon vertex count accepted by LOVE polygon shapes.
const int _lovePhysicsMaxPolygonVertices = 8;

/// Returns the shared physics state attached to the active Lua runtime.
LovePhysicsState _physicsState(LibraryRegistrationContext context) {
  final runtime = context.interpreter;
  if (runtime == null) {
    throw StateError('No Lua runtime available for LOVE physics bindings');
  }

  return LovePhysicsState.attach(runtime);
}

/// Binds `love.physics.getMeter`.
///
/// This preserves LOVE's habit of returning an integer-looking value as an
/// integer when the current meter has no fractional part.
LoveApiImplementation _bindPhysicsGetMeter(LibraryRegistrationContext context) {
  return (args) {
    final meter = _physicsState(context).meter;
    return meter == meter.roundToDouble() ? meter.round() : meter;
  };
}

/// Binds `love.physics.setMeter`.
///
/// LOVE requires the meter to be at least `1`.
LoveApiImplementation _bindPhysicsSetMeter(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'love.physics.setMeter';
    final meter = _requireNumber(args, 0, symbol);
    if (meter < 1) {
      throw LuaError('Physics error: invalid meter');
    }
    _physicsState(context).meter = meter;
    return null;
  };
}

/// Binds `love.physics.newWorld`.
///
/// Missing gravity arguments default to zero and the sleep flag defaults to
/// `true`, matching LOVE's constructor overload.
LoveApiImplementation _bindPhysicsNewWorld(LibraryRegistrationContext context) {
  return (args) {
    final state = _physicsState(context);
    final gravityX = _optionalNumber(
      args,
      0,
      'love.physics.newWorld',
      defaultValue: 0,
    );
    final gravityY = _optionalNumber(
      args,
      1,
      'love.physics.newWorld',
      defaultValue: 0,
    );
    final sleep = args.length >= 3
        ? _requireBoolean(args, 2, 'love.physics.newWorld')
        : true;
    return _wrapPhysicsWorld(
      context,
      state.newWorld(gravityX: gravityX, gravityY: gravityY, sleep: sleep),
    );
  };
}

/// Binds `love.physics.newBody`.
///
/// The body type defaults to `static` and the position defaults to `(0, 0)`
/// when omitted.
LoveApiImplementation _bindPhysicsNewBody(LibraryRegistrationContext context) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newBody';
    final world = _requirePhysicsWorld(args, 0, symbol);
    final x = _optionalNumber(args, 1, symbol, defaultValue: 0);
    final y = _optionalNumber(args, 2, symbol, defaultValue: 0);
    final type = args.length >= 4
        ? _requirePhysicsBodyType(args, 3, symbol)
        : 'static';
    return _wrapPhysicsBody(context, world.newBody(x: x, y: y, type: type));
  });
}

/// Binds `love.physics.newFixture`.
///
/// Fixture density defaults to `1.0` when the caller omits it.
LoveApiImplementation _bindPhysicsNewFixture(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newFixture';
    final body = _requirePhysicsBody(args, 0, symbol);
    final shape = _requirePhysicsShape(args, 1, symbol);
    final density = _optionalNumber(args, 2, symbol, defaultValue: 1.0);
    return _wrapPhysicsFixture(context, body.newFixture(shape, density));
  });
}

/// Binds `love.physics.newCircleShape`.
///
/// LOVE accepts either a radius-only overload centered at `(0, 0)` or an
/// explicit `(x, y, radius)` overload.
LoveApiImplementation _bindPhysicsNewCircleShape(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newCircleShape';
    late final LovePhysicsCircleShape shape;
    if (args.length == 1) {
      shape = lovePhysicsCircleShape(
        state: _physicsState(context),
        x: 0,
        y: 0,
        radius: _requireNumber(args, 0, symbol),
      );
    } else if (args.length == 3) {
      shape = lovePhysicsCircleShape(
        state: _physicsState(context),
        x: _requireNumber(args, 0, symbol),
        y: _requireNumber(args, 1, symbol),
        radius: _requireNumber(args, 2, symbol),
      );
    } else {
      throw LuaError('Incorrect number of parameters');
    }
    return _wrapPhysicsShape(context, shape);
  });
}

/// Binds `love.physics.newRectangleShape`.
///
/// LOVE accepts either `(width, height)` for a centered box or
/// `(x, y, width, height[, angle])` for an offset rectangle.
LoveApiImplementation _bindPhysicsNewRectangleShape(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newRectangleShape';
    if (args.length == 2) {
      return _wrapPhysicsShape(
        context,
        lovePhysicsRectangleShape(
          state: _physicsState(context),
          x: 0,
          y: 0,
          width: _requireNumber(args, 0, symbol),
          height: _requireNumber(args, 1, symbol),
          angle: 0,
        ),
      );
    }

    if (args.length == 4 || args.length == 5) {
      return _wrapPhysicsShape(
        context,
        lovePhysicsRectangleShape(
          state: _physicsState(context),
          x: _requireNumber(args, 0, symbol),
          y: _requireNumber(args, 1, symbol),
          width: _requireNumber(args, 2, symbol),
          height: _requireNumber(args, 3, symbol),
          angle: args.length >= 5 ? _requireNumber(args, 4, symbol) : 0,
        ),
      );
    }

    throw LuaError('Incorrect number of parameters');
  });
}

/// Binds `love.physics.newEdgeShape`.
///
/// This creates a single edge segment from two endpoints.
LoveApiImplementation _bindPhysicsNewEdgeShape(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newEdgeShape';
    return _wrapPhysicsShape(
      context,
      lovePhysicsEdgeShape(
        state: _physicsState(context),
        x1: _requireNumber(args, 0, symbol),
        y1: _requireNumber(args, 1, symbol),
        x2: _requireNumber(args, 2, symbol),
        y2: _requireNumber(args, 3, symbol),
      ),
    );
  });
}

/// Binds `love.physics.newPolygonShape`.
///
/// LOVE requires between `3` and [_lovePhysicsMaxPolygonVertices] vertices for
/// polygon shapes.
LoveApiImplementation _bindPhysicsNewPolygonShape(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newPolygonShape';
    final points = _coordinateSequence(args, symbol);
    if (points.length < 3) {
      throw LuaError('Expected a minimum of 3 vertices, got ${points.length}.');
    }
    if (points.length > _lovePhysicsMaxPolygonVertices) {
      throw LuaError(
        'Expected a maximum of $_lovePhysicsMaxPolygonVertices vertices, got ${points.length}.',
      );
    }
    return _wrapPhysicsShape(
      context,
      lovePhysicsPolygonShape(state: _physicsState(context), points: points),
    );
  });
}

/// Binds `love.physics.newChainShape`.
///
/// The first argument selects whether the chain is looped and the remaining
/// arguments are interpreted as a coordinate sequence.
LoveApiImplementation _bindPhysicsNewChainShape(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newChainShape';
    final loop = _requireBoolean(args, 0, symbol);
    final points = _coordinateSequence(
      args.skip(1).toList(growable: false),
      symbol,
    );
    final shape = lovePhysicsChainShape(
      state: _physicsState(context),
      loop: loop,
      points: points,
    );
    shape.toForgeShape();
    return _wrapPhysicsShape(context, shape);
  });
}

/// Binds `love.physics.getDistance`.
///
/// The returned values match LOVE's `(distance, x1, y1, x2, y2)` tuple.
LoveApiImplementation _bindPhysicsGetDistance(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.getDistance';
    final fixtureA = _requirePhysicsFixture(args, 0, symbol);
    final fixtureB = _requirePhysicsFixture(args, 1, symbol);
    final result = lovePhysicsDistance(
      _physicsState(context),
      fixtureA,
      fixtureB,
    );
    return Value.multi(<Object?>[
      result.distance,
      result.pointAx,
      result.pointAy,
      result.pointBx,
      result.pointBy,
    ]);
  });
}
