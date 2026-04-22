part of '../love_api_bindings.dart';

/// Builds the `World:getContactFilter` binding.
Value _buildPhysicsWorldGetContactFilterBinding(
  BuiltinFunctionBuilder builder,
) {
  return Value(
    builder.create(
      (args) =>
          _requirePhysicsWorld(args, 0, 'World:getContactFilter').contactFilter,
    ),
    functionName: 'getContactFilter',
  );
}

/// Builds the `World:setContactFilter` binding.
///
/// Passing `nil` clears the current contact filter callback on this world.
Value _buildPhysicsWorldSetContactFilterBinding(
  BuiltinFunctionBuilder builder,
) {
  return Value(
    builder.create((args) {
      final world = _requirePhysicsWorld(args, 0, 'World:setContactFilter');
      world.setContactFilter(
        _physicsOptionalCallable(args, 1, 'World:setContactFilter'),
      );
      return null;
    }),
    functionName: 'setContactFilter',
  );
}

/// Precomputes contact-filter decisions for worlds that use asynchronous callbacks.
///
/// Each fixture pair is wrapped into the Lua-facing fixture objects before the
/// filter callback is invoked. Lua truthiness determines whether the contact is
/// accepted.
Future<void> _preparePhysicsWorldContactFilterIfNeeded(
  LibraryContext context,
  LovePhysicsWorld world,
  double dt,
) async {
  final callback = world.contactFilter;
  if (callback == null) {
    return;
  }

  await world.prepareContactFilterDecisions(dt, (fixtureA, fixtureB) async {
    final result = await _physicsInvokeLuaCallback(context, callback, <Object?>[
      _wrapPhysicsFixture(context, fixtureA),
      _wrapPhysicsFixture(context, fixtureB),
    ], 'World:setContactFilter');
    return _physicsLuaTruthy(result);
  });
}

/// Builds a synchronous contact-filter evaluator when inline Lua calls are safe.
///
/// Returns `null` when there is no filter callback or when the current runtime
/// cannot invoke that callback synchronously.
bool Function(LovePhysicsFixture fixtureA, LovePhysicsFixture fixtureB)?
_buildPhysicsWorldContactFilterSyncEvaluator(
  LibraryContext context,
  LovePhysicsWorld world,
) {
  final callback = world.contactFilter;
  if (callback == null ||
      !_physicsCanInvokeLuaCallbackSync(context, callback)) {
    return null;
  }

  return (fixtureA, fixtureB) {
    final result = _physicsInvokeLuaCallbackSync(context, callback, <Object?>[
      _wrapPhysicsFixture(context, fixtureA),
      _wrapPhysicsFixture(context, fixtureB),
    ], 'World:setContactFilter');
    return _physicsLuaTruthy(result);
  };
}
