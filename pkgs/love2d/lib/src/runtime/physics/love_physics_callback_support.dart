part of '../love_runtime.dart';

enum LovePhysicsWorldCallbackKind {
  beginContact,
  endContact,
  preSolve,
  postSolve,
}

final class LovePhysicsWorldQueuedCallback {
  LovePhysicsWorldQueuedCallback._({
    required this.kind,
    required this.callback,
    required this.contact,
    this.normalImpulses,
    this.tangentImpulses,
  });

  final LovePhysicsWorldCallbackKind kind;
  final Value callback;
  final LovePhysicsContact contact;
  final List<double>? normalImpulses;
  final List<double>? tangentImpulses;

  void release() {
    contact._releaseTransient();
  }
}

final class LovePhysicsWorldCallbackState {
  LovePhysicsWorldCallbackState(this.world)
    : listener = _LovePhysicsContactListener._(world);

  final LovePhysicsWorld world;
  final forge2d.ContactListener listener;
  final Queue<LovePhysicsWorldQueuedCallback> _queuedCallbacks =
      Queue<LovePhysicsWorldQueuedCallback>();

  Value? _beginContact;
  Value? _endContact;
  Value? _preSolve;
  Value? _postSolve;
  bool _isDispatching = false;

  bool get isDispatching => _isDispatching;

  ({Value? beginContact, Value? endContact, Value? preSolve, Value? postSolve})
  get callbacks => (
    beginContact: _beginContact,
    endContact: _endContact,
    preSolve: _preSolve,
    postSolve: _postSolve,
  );

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

  void queueBeginContact(forge2d.Contact contact) {
    _queueContactEvent(LovePhysicsWorldCallbackKind.beginContact, contact);
  }

  void queueEndContact(forge2d.Contact contact) {
    _queueContactEvent(LovePhysicsWorldCallbackKind.endContact, contact);
  }

  void queuePreSolve(forge2d.Contact contact) {
    _queueContactEvent(LovePhysicsWorldCallbackKind.preSolve, contact);
  }

  void queuePostSolve(forge2d.Contact contact, forge2d.ContactImpulse impulse) {
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

    _isDispatching = true;
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
      _isDispatching = false;
      _releasePendingCallbacks();
    }
  }

  void dispose() {
    _releasePendingCallbacks();
    _beginContact = null;
    _endContact = null;
    _preSolve = null;
    _postSolve = null;
  }

  Value? _callbackForKind(LovePhysicsWorldCallbackKind kind) {
    return switch (kind) {
      LovePhysicsWorldCallbackKind.beginContact => _beginContact,
      LovePhysicsWorldCallbackKind.endContact => _endContact,
      LovePhysicsWorldCallbackKind.preSolve => _preSolve,
      LovePhysicsWorldCallbackKind.postSolve => _postSolve,
    };
  }

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

  void _releasePendingCallbacks() {
    while (_queuedCallbacks.isNotEmpty) {
      _queuedCallbacks.removeFirst().release();
    }
  }
}

final class _LovePhysicsContactListener extends forge2d.ContactListener {
  _LovePhysicsContactListener._(this.world);

  final LovePhysicsWorld world;

  LovePhysicsWorldCallbackState get _callbacks => world._callbackState;

  @override
  void beginContact(forge2d.Contact contact) {
    _callbacks.queueBeginContact(contact);
  }

  @override
  void endContact(forge2d.Contact contact) {
    _callbacks.queueEndContact(contact);
  }

  @override
  void preSolve(forge2d.Contact contact, forge2d.Manifold oldManifold) {
    _physicsContactForWorldContact(world, contact)._replayPendingPreSolveState();
    _callbacks.queuePreSolve(contact);
  }

  @override
  void postSolve(forge2d.Contact contact, forge2d.ContactImpulse impulse) {
    _callbacks.queuePostSolve(contact, impulse);
  }
}
