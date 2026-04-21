part of '../love_api_bindings.dart';

const int _lovePhysicsMaxPolygonVertices = 8;

LovePhysicsState _physicsState(LibraryRegistrationContext context) {
  final runtime = context.interpreter;
  if (runtime == null) {
    throw StateError('No Lua runtime available for LOVE physics bindings');
  }

  return LovePhysicsState.attach(runtime);
}

LoveApiImplementation _bindPhysicsGetMeter(LibraryRegistrationContext context) {
  return (args) {
    final meter = _physicsState(context).meter;
    return meter == meter.roundToDouble() ? meter.round() : meter;
  };
}

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

LoveApiImplementation _bindPhysicsNewChainShape(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newChainShape';
    final loop = _requireBoolean(args, 0, symbol);
    final points = _coordinateSequence(args.skip(1).toList(growable: false), symbol);
    final shape = lovePhysicsChainShape(
      state: _physicsState(context),
      loop: loop,
      points: points,
    );
    shape.toForgeShape();
    return _wrapPhysicsShape(context, shape);
  });
}

LoveApiImplementation _bindPhysicsGetDistance(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.getDistance';
    final fixtureA = _requirePhysicsFixture(args, 0, symbol);
    final fixtureB = _requirePhysicsFixture(args, 1, symbol);
    final result = lovePhysicsDistance(_physicsState(context), fixtureA, fixtureB);
    return Value.multi(<Object?>[
      result.distance,
      result.pointAx,
      result.pointAy,
      result.pointBx,
      result.pointBy,
    ]);
  });
}
