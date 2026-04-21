part of '../love_api_bindings.dart';

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
