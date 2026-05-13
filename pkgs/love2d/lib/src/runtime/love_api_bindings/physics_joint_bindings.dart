part of '../love_api_bindings.dart';

/// Binds `love.physics.newDistanceJoint`.
///
/// This creates a distance joint between two world-space anchor points and
/// defaults `collideConnected` to `false`.
LoveApiImplementation _bindPhysicsNewDistanceJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newDistanceJoint';
    final bodyA = _requirePhysicsBody(args, 0, symbol);
    final bodyB = _requirePhysicsBody(args, 1, symbol);
    return _wrapPhysicsJoint(
      context,
      bodyA.world.newDistanceJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        x1: _requireNumber(args, 2, symbol),
        y1: _requireNumber(args, 3, symbol),
        x2: _requireNumber(args, 4, symbol),
        y2: _requireNumber(args, 5, symbol),
        collideConnected: args.length >= 7
            ? _requireBoolean(args, 6, symbol)
            : false,
      ),
    );
  });
}

/// Binds `love.physics.newFrictionJoint`.
///
/// LOVE accepts either one shared anchor point for both bodies or explicit
/// anchor positions for body A and body B.
LoveApiImplementation _bindPhysicsNewFrictionJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newFrictionJoint';
    final bodyA = _requirePhysicsBody(args, 0, symbol);
    final bodyB = _requirePhysicsBody(args, 1, symbol);
    final xA = _requireNumber(args, 2, symbol);
    final yA = _requireNumber(args, 3, symbol);

    late final double xB;
    late final double yB;
    late final bool collideConnected;
    if (args.length >= 6 && _rawValue(_valueAt(args, 4)) is! bool) {
      xB = _requireNumber(args, 4, symbol);
      yB = _requireNumber(args, 5, symbol);
      collideConnected = args.length >= 7
          ? _requireBoolean(args, 6, symbol)
          : false;
    } else {
      xB = xA;
      yB = yA;
      collideConnected = args.length >= 5
          ? _requireBoolean(args, 4, symbol)
          : false;
    }

    return _wrapPhysicsJoint(
      context,
      bodyA.world.newFrictionJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        xA: xA,
        yA: yA,
        xB: xB,
        yB: yB,
        collideConnected: collideConnected,
      ),
    );
  });
}

/// Binds `love.physics.newRopeJoint`.
///
/// This limits the maximum distance between two anchors and defaults
/// `collideConnected` to `false`.
LoveApiImplementation _bindPhysicsNewRopeJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newRopeJoint';
    final bodyA = _requirePhysicsBody(args, 0, symbol);
    final bodyB = _requirePhysicsBody(args, 1, symbol);
    return _wrapPhysicsJoint(
      context,
      bodyA.world.newRopeJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        x1: _requireNumber(args, 2, symbol),
        y1: _requireNumber(args, 3, symbol),
        x2: _requireNumber(args, 4, symbol),
        y2: _requireNumber(args, 5, symbol),
        maxLength: _requireNumber(args, 6, symbol),
        collideConnected: args.length >= 8
            ? _requireBoolean(args, 7, symbol)
            : false,
      ),
    );
  });
}

/// Binds `love.physics.newWeldJoint`.
///
/// LOVE accepts either one shared anchor point or separate anchors, followed
/// by optional `collideConnected` and `referenceAngle` arguments.
LoveApiImplementation _bindPhysicsNewWeldJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newWeldJoint';
    final bodyA = _requirePhysicsBody(args, 0, symbol);
    final bodyB = _requirePhysicsBody(args, 1, symbol);
    final xA = _requireNumber(args, 2, symbol);
    final yA = _requireNumber(args, 3, symbol);

    late final double xB;
    late final double yB;
    late final bool collideConnected;
    late final double? referenceAngle;
    if (args.length >= 6 && _rawValue(_valueAt(args, 4)) is! bool) {
      xB = _requireNumber(args, 4, symbol);
      yB = _requireNumber(args, 5, symbol);
      collideConnected =
          args.length >= 7 && _rawValue(_valueAt(args, 6)) != null
          ? _requireBoolean(args, 6, symbol)
          : false;
      referenceAngle = args.length >= 8 && _rawValue(_valueAt(args, 7)) != null
          ? _requireNumber(args, 7, symbol)
          : null;
    } else {
      xB = xA;
      yB = yA;
      collideConnected =
          args.length >= 5 && _rawValue(_valueAt(args, 4)) != null
          ? _requireBoolean(args, 4, symbol)
          : false;
      referenceAngle = args.length >= 6 && _rawValue(_valueAt(args, 5)) != null
          ? _requireNumber(args, 5, symbol)
          : null;
    }

    return _wrapPhysicsJoint(
      context,
      bodyA.world.newWeldJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        xA: xA,
        yA: yA,
        xB: xB,
        yB: yB,
        collideConnected: collideConnected,
        referenceAngle: referenceAngle,
      ),
    );
  });
}

/// Binds `love.physics.newMouseJoint`.
///
/// This attaches a body to a target point that can be moved externally.
LoveApiImplementation _bindPhysicsNewMouseJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newMouseJoint';
    final body = _requirePhysicsBody(args, 0, symbol);
    return _wrapPhysicsJoint(
      context,
      body.world.newMouseJoint(
        body: body,
        x: _requireNumber(args, 1, symbol),
        y: _requireNumber(args, 2, symbol),
      ),
    );
  });
}

/// Binds `love.physics.newGearJoint`.
///
/// The joint ratio defaults to `1.0` and `collideConnected` defaults to
/// `false`.
LoveApiImplementation _bindPhysicsNewGearJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newGearJoint';
    final jointA = _requirePhysicsJoint(args, 0, symbol);
    final jointB = _requirePhysicsJoint(args, 1, symbol);
    final ratio = args.length >= 3 ? _requireNumber(args, 2, symbol) : 1.0;
    final collideConnected = args.length >= 4
        ? _requireBoolean(args, 3, symbol)
        : false;

    return _wrapPhysicsJoint(
      context,
      jointA.world.newGearJoint(
        jointA: jointA,
        jointB: jointB,
        ratio: ratio,
        collideConnected: collideConnected,
      ),
    );
  });
}

/// Binds `love.physics.newPulleyJoint`.
///
/// The pulley ratio defaults to `1.0`, while `collideConnected` defaults to
/// `true` for this constructor.
LoveApiImplementation _bindPhysicsNewPulleyJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newPulleyJoint';
    final bodyA = _requirePhysicsBody(args, 0, symbol);
    final bodyB = _requirePhysicsBody(args, 1, symbol);

    return _wrapPhysicsJoint(
      context,
      bodyA.world.newPulleyJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        gx1: _requireNumber(args, 2, symbol),
        gy1: _requireNumber(args, 3, symbol),
        gx2: _requireNumber(args, 4, symbol),
        gy2: _requireNumber(args, 5, symbol),
        x1: _requireNumber(args, 6, symbol),
        y1: _requireNumber(args, 7, symbol),
        x2: _requireNumber(args, 8, symbol),
        y2: _requireNumber(args, 9, symbol),
        ratio: args.length >= 11 ? _requireNumber(args, 10, symbol) : 1.0,
        collideConnected: args.length >= 12
            ? _requireBoolean(args, 11, symbol)
            : true,
      ),
    );
  });
}

/// Binds `love.physics.newMotorJoint`.
///
/// Missing arguments default to a correction factor of `0.3` and
/// `collideConnected = false`.
LoveApiImplementation _bindPhysicsNewMotorJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newMotorJoint';
    final bodyA = _requirePhysicsBody(args, 0, symbol);
    final bodyB = _requirePhysicsBody(args, 1, symbol);
    final correctionFactor =
        args.length >= 3 && _rawValue(_valueAt(args, 2)) != null
        ? _requireNumber(args, 2, symbol)
        : 0.3;
    final collideConnected = args.length >= 4
        ? _requireBoolean(args, 3, symbol)
        : false;

    return _wrapPhysicsJoint(
      context,
      bodyA.world.newMotorJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        correctionFactor: correctionFactor,
        collideConnected: collideConnected,
      ),
    );
  });
}

/// Binds `love.physics.newRevoluteJoint`.
///
/// LOVE accepts either one shared anchor point or explicit anchors for both
/// bodies, followed by optional `collideConnected` and `referenceAngle`.
LoveApiImplementation _bindPhysicsNewRevoluteJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newRevoluteJoint';
    final bodyA = _requirePhysicsBody(args, 0, symbol);
    final bodyB = _requirePhysicsBody(args, 1, symbol);
    final xA = _requireNumber(args, 2, symbol);
    final yA = _requireNumber(args, 3, symbol);

    late final double xB;
    late final double yB;
    late final bool collideConnected;
    late final double? referenceAngle;
    if (args.length >= 6 && _rawValue(_valueAt(args, 4)) is! bool) {
      xB = _requireNumber(args, 4, symbol);
      yB = _requireNumber(args, 5, symbol);
      collideConnected =
          args.length >= 7 && _rawValue(_valueAt(args, 6)) != null
          ? _requireBoolean(args, 6, symbol)
          : false;
      referenceAngle = args.length >= 8 && _rawValue(_valueAt(args, 7)) != null
          ? _requireNumber(args, 7, symbol)
          : null;
    } else {
      xB = xA;
      yB = yA;
      collideConnected =
          args.length >= 5 && _rawValue(_valueAt(args, 4)) != null
          ? _requireBoolean(args, 4, symbol)
          : false;
      referenceAngle = args.length >= 6 && _rawValue(_valueAt(args, 5)) != null
          ? _requireNumber(args, 5, symbol)
          : null;
    }

    return _wrapPhysicsJoint(
      context,
      bodyA.world.newRevoluteJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        xA: xA,
        yA: yA,
        xB: xB,
        yB: yB,
        collideConnected: collideConnected,
        referenceAngle: referenceAngle,
      ),
    );
  });
}

/// Binds `love.physics.newWheelJoint`.
///
/// LOVE accepts either one shared anchor point or explicit anchors for both
/// bodies, plus a suspension axis and optional `collideConnected`.
LoveApiImplementation _bindPhysicsNewWheelJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newWheelJoint';
    final bodyA = _requirePhysicsBody(args, 0, symbol);
    final bodyB = _requirePhysicsBody(args, 1, symbol);
    final xA = _requireNumber(args, 2, symbol);
    final yA = _requireNumber(args, 3, symbol);

    late final double xB;
    late final double yB;
    late final double ax;
    late final double ay;
    late final bool collideConnected;
    if (args.length >= 8) {
      xB = _requireNumber(args, 4, symbol);
      yB = _requireNumber(args, 5, symbol);
      ax = _requireNumber(args, 6, symbol);
      ay = _requireNumber(args, 7, symbol);
      collideConnected = args.length >= 9
          ? _requireBoolean(args, 8, symbol)
          : false;
    } else {
      xB = xA;
      yB = yA;
      ax = _requireNumber(args, 4, symbol);
      ay = _requireNumber(args, 5, symbol);
      collideConnected = args.length >= 7
          ? _requireBoolean(args, 6, symbol)
          : false;
    }

    return _wrapPhysicsJoint(
      context,
      bodyA.world.newWheelJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        xA: xA,
        yA: yA,
        xB: xB,
        yB: yB,
        ax: ax,
        ay: ay,
        collideConnected: collideConnected,
      ),
    );
  });
}

/// Binds `love.physics.newPrismaticJoint`.
///
/// LOVE accepts either one shared anchor point or explicit anchors for both
/// bodies, followed by an axis and optional `collideConnected` and
/// `referenceAngle`.
LoveApiImplementation _bindPhysicsNewPrismaticJoint(
  LibraryRegistrationContext context,
) {
  return (args) => _physicsWithLuaErrors(() {
    const symbol = 'love.physics.newPrismaticJoint';
    final bodyA = _requirePhysicsBody(args, 0, symbol);
    final bodyB = _requirePhysicsBody(args, 1, symbol);
    final xA = _requireNumber(args, 2, symbol);
    final yA = _requireNumber(args, 3, symbol);

    late final double xB;
    late final double yB;
    late final double ax;
    late final double ay;
    late final bool collideConnected;
    late final double? referenceAngle;
    if (args.length >= 8) {
      xB = _requireNumber(args, 4, symbol);
      yB = _requireNumber(args, 5, symbol);
      ax = _requireNumber(args, 6, symbol);
      ay = _requireNumber(args, 7, symbol);
      collideConnected =
          args.length >= 9 && _rawValue(_valueAt(args, 8)) != null
          ? _requireBoolean(args, 8, symbol)
          : false;
      referenceAngle = args.length >= 10 && _rawValue(_valueAt(args, 9)) != null
          ? _requireNumber(args, 9, symbol)
          : null;
    } else {
      xB = xA;
      yB = yA;
      ax = _requireNumber(args, 4, symbol);
      ay = _requireNumber(args, 5, symbol);
      collideConnected =
          args.length >= 7 && _rawValue(_valueAt(args, 6)) != null
          ? _requireBoolean(args, 6, symbol)
          : false;
      referenceAngle = args.length >= 8 && _rawValue(_valueAt(args, 7)) != null
          ? _requireNumber(args, 7, symbol)
          : null;
    }

    return _wrapPhysicsJoint(
      context,
      bodyA.world.newPrismaticJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        xA: xA,
        yA: yA,
        xB: xB,
        yB: yB,
        ax: ax,
        ay: ay,
        collideConnected: collideConnected,
        referenceAngle: referenceAngle,
      ),
    );
  });
}
