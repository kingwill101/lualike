part of '../love_runtime.dart';

/// The contact callback kinds that a physics world can dispatch.
enum LovePhysicsWorldCallbackKind {
  /// A contact has begun.
  beginContact,

  /// A contact has ended.
  endContact,

  /// A contact is about to be solved.
  preSolve,

  /// A contact has already been solved.
  postSolve,
}

/// A queued physics-world callback event and its retained transient contact.
final class LovePhysicsWorldQueuedCallback {
  /// Creates a queued world callback event.
  LovePhysicsWorldQueuedCallback._({
    required this.kind,
    required this.callback,
    required this.contact,
    this.normalImpulses,
    this.tangentImpulses,
  });

  /// The kind of world callback to dispatch.
  final LovePhysicsWorldCallbackKind kind;

  /// The Lua callback to invoke.
  final Value callback;

  /// The wrapped contact passed to the callback.
  final LovePhysicsContact contact;

  /// The normal impulses for post-solve callbacks, if any.
  final List<double>? normalImpulses;

  /// The tangent impulses for post-solve callbacks, if any.
  final List<double>? tangentImpulses;

  /// Releases the transient contact retained for this callback.
  void release() {
    contact._releaseTransient();
  }
}

/// Callback dispatch state for a physics world.
final class LovePhysicsWorldCallbackState {
  /// Creates callback state for [world].
  LovePhysicsWorldCallbackState(this.world)
    : listener = _LovePhysicsContactListener._(world);

  /// The world that owns this callback state.
  final LovePhysicsWorld world;

  /// The forge2d contact listener that forwards callbacks into this state.
  final forge2d.ContactListener listener;

  /// Deferred callbacks waiting to be flushed after stepping.
  final Queue<LovePhysicsWorldQueuedCallback> _queuedCallbacks =
      Queue<LovePhysicsWorldQueuedCallback>();

  /// The registered begin-contact callback.
  Value? _beginContact;

  /// The registered end-contact callback.
  Value? _endContact;

  /// The registered pre-solve callback.
  Value? _preSolve;

  /// The registered post-solve callback.
  Value? _postSolve;

  /// The number of nested dispatches currently in progress.
  int _dispatchDepth = 0;

  /// An optional dispatcher for synchronous callback delivery.
  void Function(LovePhysicsWorldQueuedCallback event)? _syncDispatcher;

  /// A captured synchronous-dispatch error waiting to be rethrown.
  Object? _pendingSyncError;

  /// The stack trace paired with [_pendingSyncError].
  StackTrace? _pendingSyncErrorStackTrace;

  /// Whether callbacks are currently being dispatched.
  bool get isDispatching => _dispatchDepth > 0;

  /// The currently registered contact callbacks.
  ({Value? beginContact, Value? endContact, Value? preSolve, Value? postSolve})
  get callbacks => (
    beginContact: _beginContact,
    endContact: _endContact,
    preSolve: _preSolve,
    postSolve: _postSolve,
  );

  /// Replaces the registered contact callbacks.
  void setCallbacks({
    Value? beginContact,
    Value? endContact,
    Value? preSolve,
    Value? postSolve,
  }) {
    _beginContact = beginContact;
    _endContact = endContact;
    _preSolve = preSolve;
    _postSolve = postSolve;
  }

  /// Sets the synchronous callback [dispatcher] used while stepping.
  void setSyncDispatcher(
    void Function(LovePhysicsWorldQueuedCallback event)? dispatcher,
  ) {
    _syncDispatcher = dispatcher;
    if (dispatcher == null) {
      _pendingSyncError = null;
      _pendingSyncErrorStackTrace = null;
    }
  }

  /// Rethrows any error captured during synchronous callback dispatch.
  void throwPendingSyncError() {
    if (_pendingSyncError == null || _pendingSyncErrorStackTrace == null) {
      return;
    }
    final error = _pendingSyncError!;
    final stackTrace = _pendingSyncErrorStackTrace!;
    _pendingSyncError = null;
    _pendingSyncErrorStackTrace = null;
    Error.throwWithStackTrace(error, stackTrace);
  }

  /// Queues or synchronously dispatches a begin-contact callback.
  void queueBeginContact(forge2d.Contact contact) {
    if (_dispatchContactEventNow(
      LovePhysicsWorldCallbackKind.beginContact,
      contact,
    )) {
      return;
    }
    _queueContactEvent(LovePhysicsWorldCallbackKind.beginContact, contact);
  }

  /// Queues or synchronously dispatches an end-contact callback.
  void queueEndContact(forge2d.Contact contact) {
    if (_dispatchContactEventNow(
      LovePhysicsWorldCallbackKind.endContact,
      contact,
    )) {
      return;
    }
    _queueContactEvent(LovePhysicsWorldCallbackKind.endContact, contact);
  }

  /// Queues or synchronously dispatches a pre-solve callback.
  void queuePreSolve(forge2d.Contact contact) {
    if (_dispatchContactEventNow(
      LovePhysicsWorldCallbackKind.preSolve,
      contact,
    )) {
      return;
    }
    _queueContactEvent(LovePhysicsWorldCallbackKind.preSolve, contact);
  }

  /// Queues or synchronously dispatches a post-solve callback.
  void queuePostSolve(forge2d.Contact contact, forge2d.ContactImpulse impulse) {
    if (_dispatchContactEventNow(
      LovePhysicsWorldCallbackKind.postSolve,
      contact,
      impulse: impulse,
    )) {
      return;
    }
    final callback = _callbackForKind(LovePhysicsWorldCallbackKind.postSolve);
    if (callback == null) {
      return;
    }

    final wrappedContact = _physicsContactForWorldContact(world, contact);
    wrappedContact._retainTransient();
    _queuedCallbacks.add(
      LovePhysicsWorldQueuedCallback._(
        kind: LovePhysicsWorldCallbackKind.postSolve,
        callback: callback,
        contact: wrappedContact,
        normalImpulses: List<double>.generate(
          impulse.count,
          (index) => world.state.scaleUpScalar(impulse.normalImpulses[index]),
          growable: false,
        ),
        tangentImpulses: List<double>.generate(
          impulse.count,
          (index) => world.state.scaleUpScalar(impulse.tangentImpulses[index]),
          growable: false,
        ),
      ),
    );
  }

  /// Flushes queued callbacks through [dispatcher].
  ///
  /// When [dispatcher] is `null`, queued callbacks are discarded after their
  /// transient state is released.
  Future<void> flush(
    Future<void> Function(LovePhysicsWorldQueuedCallback event)? dispatcher,
  ) async {
    if (_queuedCallbacks.isEmpty) {
      return;
    }

    if (dispatcher == null) {
      _releasePendingCallbacks();
      return;
    }

    _dispatchDepth++;
    try {
      while (_queuedCallbacks.isNotEmpty) {
        final event = _queuedCallbacks.removeFirst();
        try {
          await dispatcher(event);
        } finally {
          event.release();
        }
      }
    } finally {
      _dispatchDepth--;
      _releasePendingCallbacks();
    }
  }

  /// Disposes callback state and clears all registered callbacks.
  void dispose() {
    _releasePendingCallbacks();
    _syncDispatcher = null;
    _pendingSyncError = null;
    _pendingSyncErrorStackTrace = null;
    _beginContact = null;
    _endContact = null;
    _preSolve = null;
    _postSolve = null;
  }

  /// Returns the registered callback for [kind], if one exists.
  Value? _callbackForKind(LovePhysicsWorldCallbackKind kind) {
    return switch (kind) {
      LovePhysicsWorldCallbackKind.beginContact => _beginContact,
      LovePhysicsWorldCallbackKind.endContact => _endContact,
      LovePhysicsWorldCallbackKind.preSolve => _preSolve,
      LovePhysicsWorldCallbackKind.postSolve => _postSolve,
    };
  }

  /// Queues a deferred contact callback of [kind].
  void _queueContactEvent(
    LovePhysicsWorldCallbackKind kind,
    forge2d.Contact contact,
  ) {
    final callback = _callbackForKind(kind);
    if (callback == null) {
      return;
    }

    final wrappedContact = _physicsContactForWorldContact(world, contact);
    wrappedContact._retainTransient();
    _queuedCallbacks.add(
      LovePhysicsWorldQueuedCallback._(
        kind: kind,
        callback: callback,
        contact: wrappedContact,
      ),
    );
  }

  /// Releases any queued callbacks without dispatching them.
  void _releasePendingCallbacks() {
    while (_queuedCallbacks.isNotEmpty) {
      _queuedCallbacks.removeFirst().release();
    }
  }

  /// Attempts to dispatch a contact callback synchronously.
  ///
  /// Returns `true` when a synchronous dispatcher handled the event.
  bool _dispatchContactEventNow(
    LovePhysicsWorldCallbackKind kind,
    forge2d.Contact contact, {
    forge2d.ContactImpulse? impulse,
  }) {
    final dispatcher = _syncDispatcher;
    final callback = _callbackForKind(kind);
    if (dispatcher == null || callback == null) {
      return false;
    }

    final wrappedContact = _physicsContactForWorldContact(world, contact);
    wrappedContact._retainTransient();
    final event = LovePhysicsWorldQueuedCallback._(
      kind: kind,
      callback: callback,
      contact: wrappedContact,
      normalImpulses: impulse == null
          ? null
          : List<double>.generate(
              impulse.count,
              (index) =>
                  world.state.scaleUpScalar(impulse.normalImpulses[index]),
              growable: false,
            ),
      tangentImpulses: impulse == null
          ? null
          : List<double>.generate(
              impulse.count,
              (index) =>
                  world.state.scaleUpScalar(impulse.tangentImpulses[index]),
              growable: false,
            ),
    );

    _dispatchDepth++;
    try {
      dispatcher(event);
    } catch (error, stackTrace) {
      _pendingSyncError ??= error;
      _pendingSyncErrorStackTrace ??= stackTrace;
    } finally {
      _dispatchDepth--;
      event.release();
    }
    return true;
  }
}

/// A forge2d contact listener that forwards events into LOVE callback state.
final class _LovePhysicsContactListener extends forge2d.ContactListener {
  /// Creates a contact listener for [world].
  _LovePhysicsContactListener._(this.world);

  /// The world whose callback state receives contact events.
  final LovePhysicsWorld world;

  /// The callback state attached to [world].
  LovePhysicsWorldCallbackState get _callbacks => world._callbackState;

  @override
  /// Forwards a begin-contact event.
  void beginContact(forge2d.Contact contact) {
    _callbacks.queueBeginContact(contact);
  }

  @override
  /// Forwards an end-contact event.
  void endContact(forge2d.Contact contact) {
    _callbacks.queueEndContact(contact);
  }

  @override
  /// Replays pending pre-solve state and forwards the pre-solve event.
  void preSolve(forge2d.Contact contact, forge2d.Manifold oldManifold) {
    _physicsContactForWorldContact(
      world,
      contact,
    )._replayPendingPreSolveState();
    _callbacks.queuePreSolve(contact);
  }

  @override
  /// Forwards a post-solve event.
  void postSolve(forge2d.Contact contact, forge2d.ContactImpulse impulse) {
    _callbacks.queuePostSolve(contact, impulse);
  }
}
