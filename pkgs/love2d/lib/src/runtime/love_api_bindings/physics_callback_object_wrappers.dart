part of '../love_api_bindings.dart';

Value _buildPhysicsWorldUpdateBinding(
  LibraryContext context,
  BuiltinFunctionBuilder builder,
) {
  return Value(
    builder.create(
      (args) => _physicsWithLuaErrorsAsync(() async {
        final world = _requirePhysicsWorld(args, 0, 'World:update');
        final dt = _requireNumber(args, 1, 'World:update');
        final velocityIterations = args.length >= 3 && _valueAt(args, 2) != null
            ? _requireRoundedInt(args, 2, 'World:update')
            : null;
        final positionIterations = args.length >= 4 && _valueAt(args, 3) != null
            ? _requireRoundedInt(args, 3, 'World:update')
            : null;
        await _preparePhysicsWorldContactFilterIfNeeded(context, world, dt);
        await world.update(
          dt,
          velocityIterations: velocityIterations,
          positionIterations: positionIterations,
          callbackDispatcher: (event) =>
              _dispatchPhysicsWorldCallbackEvent(context, event),
        );
        return null;
      }),
    ),
    functionName: 'update',
  );
}

Value _buildPhysicsWorldGetCallbacksBinding(BuiltinFunctionBuilder builder) {
  return Value(
    builder.create((args) {
      final callbacks = _requirePhysicsWorld(
        args,
        0,
        'World:getCallbacks',
      ).callbacks;
      return Value.multi(<Object?>[
        callbacks.beginContact,
        callbacks.endContact,
        callbacks.preSolve,
        callbacks.postSolve,
      ]);
    }),
    functionName: 'getCallbacks',
  );
}

Value _buildPhysicsWorldSetCallbacksBinding(BuiltinFunctionBuilder builder) {
  return Value(
    builder.create((args) {
      final world = _requirePhysicsWorld(args, 0, 'World:setCallbacks');
      world.setCallbacks(
        beginContact: _physicsOptionalCallable(args, 1, 'World:setCallbacks'),
        endContact: _physicsOptionalCallable(args, 2, 'World:setCallbacks'),
        preSolve: _physicsOptionalCallable(args, 3, 'World:setCallbacks'),
        postSolve: _physicsOptionalCallable(args, 4, 'World:setCallbacks'),
      );
      return null;
    }),
    functionName: 'setCallbacks',
  );
}

Value? _physicsOptionalCallable(List<Object?> args, int index, String symbol) {
  final value = _valueAt(args, index);
  if (_rawValue(value) == null) {
    return null;
  }
  return _requireCallable(args, index, symbol);
}

Future<void> _dispatchPhysicsWorldCallbackEvent(
  LibraryContext context,
  LovePhysicsWorldQueuedCallback event,
) async {
  final fixtures = event.contact.fixtures;
  final callbackArgs = <Object?>[
    _wrapPhysicsFixture(context, fixtures.fixtureA),
    _wrapPhysicsFixture(context, fixtures.fixtureB),
    _wrapPhysicsContact(context, event.contact),
  ];

  final normalImpulses = event.normalImpulses;
  final tangentImpulses = event.tangentImpulses;
  if (normalImpulses != null && tangentImpulses != null) {
    for (var index = 0; index < normalImpulses.length; index++) {
      callbackArgs.add(normalImpulses[index]);
      callbackArgs.add(tangentImpulses[index]);
    }
  }

  await _physicsInvokeLuaCallback(
    context,
    event.callback,
    callbackArgs,
    _physicsWorldCallbackSymbol(event.kind),
  );
}

String _physicsWorldCallbackSymbol(LovePhysicsWorldCallbackKind kind) {
  return switch (kind) {
    LovePhysicsWorldCallbackKind.beginContact => 'World:setCallbacks.begin',
    LovePhysicsWorldCallbackKind.endContact => 'World:setCallbacks.end',
    LovePhysicsWorldCallbackKind.preSolve => 'World:setCallbacks.preSolve',
    LovePhysicsWorldCallbackKind.postSolve => 'World:setCallbacks.postSolve',
  };
}
