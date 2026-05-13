part of '../love_api_bindings.dart';

/// Builds the `World:update` binding for Lua physics worlds.
///
/// This forwards the step parameters into the wrapped world and selects either
/// synchronous or queued callback dispatch depending on whether the current
/// Lua runtime can safely run the registered callbacks inline.
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
        final useSyncCallbacks = _physicsCanUseSyncCallbacks(context, world);
        if (!useSyncCallbacks) {
          await _preparePhysicsWorldContactFilterIfNeeded(context, world, dt);
        }
        await world.update(
          dt,
          velocityIterations: velocityIterations,
          positionIterations: positionIterations,
          syncCallbackDispatcher: !useSyncCallbacks
              ? null
              : (event) =>
                    _dispatchPhysicsWorldCallbackEventSync(context, event),
          syncContactFilterEvaluator: !useSyncCallbacks
              ? null
              : _buildPhysicsWorldContactFilterSyncEvaluator(context, world),
          callbackDispatcher: !useSyncCallbacks
              ? (event) => _dispatchPhysicsWorldCallbackEvent(context, event)
              : null,
        );
        return null;
      }),
    ),
    functionName: 'update',
  );
}

/// Builds the `World:getCallbacks` binding.
///
/// The returned tuple preserves Love's callback ordering for begin-contact,
/// end-contact, pre-solve, and post-solve handlers.
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

/// Builds the `World:setCallbacks` binding.
///
/// Missing Lua arguments are treated as `nil`, which clears the corresponding
/// callback on the wrapped physics world.
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

/// Returns the optional callable at [index] or `null` when the Lua value is `nil`.
Value? _physicsOptionalCallable(List<Object?> args, int index, String symbol) {
  final value = _valueAt(args, index);
  if (_rawValue(value) == null) {
    return null;
  }
  return _requireCallable(args, index, symbol);
}

/// Dispatches a queued world callback through the asynchronous Lua bridge.
///
/// Contact callbacks always receive the two fixtures and the wrapped contact.
/// Post-solve callbacks append impulse pairs after those three base arguments.
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

/// Dispatches a world callback immediately through the synchronous Lua bridge.
void _dispatchPhysicsWorldCallbackEventSync(
  LibraryContext context,
  LovePhysicsWorldQueuedCallback event,
) {
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

  _physicsInvokeLuaCallbackSync(
    context,
    event.callback,
    callbackArgs,
    _physicsWorldCallbackSymbol(event.kind),
  );
}

/// Returns the diagnostic symbol used for a queued world callback kind.
String _physicsWorldCallbackSymbol(LovePhysicsWorldCallbackKind kind) {
  return switch (kind) {
    LovePhysicsWorldCallbackKind.beginContact => 'World:setCallbacks.begin',
    LovePhysicsWorldCallbackKind.endContact => 'World:setCallbacks.end',
    LovePhysicsWorldCallbackKind.preSolve => 'World:setCallbacks.preSolve',
    LovePhysicsWorldCallbackKind.postSolve => 'World:setCallbacks.postSolve',
  };
}
