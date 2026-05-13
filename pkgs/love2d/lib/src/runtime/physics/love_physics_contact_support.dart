part of '../love_runtime.dart';

/// Per-world cache of wrapped forge2d contacts.
final Expando<Map<forge2d.Contact, LovePhysicsContact>>
_lovePhysicsContactObjectCache =
    Expando<Map<forge2d.Contact, LovePhysicsContact>>(
      'love2dPhysicsContactObjects',
    );

/// Marks all cached contacts for [world] as destroyed and clears the cache.
void _disposeLovePhysicsContacts(LovePhysicsWorld world) {
  final cache = _lovePhysicsContactObjectCache[world];
  if (cache == null) {
    return;
  }

  for (final contact in cache.values) {
    contact._markDestroyed();
  }
  cache.clear();
}

/// Removes cached contacts that are no longer active in [world].
void _pruneLovePhysicsContacts(LovePhysicsWorld world) {
  final cache = _lovePhysicsContactObjectCache[world];
  if (cache == null || cache.isEmpty) {
    return;
  }

  final activeContacts = world._world.contactManager.contacts.toSet();
  for (final entry in cache.entries.toList(growable: false)) {
    if (activeContacts.contains(entry.key)) {
      continue;
    }
    entry.value._markDestroyed();
    cache.remove(entry.key);
  }
}

/// Returns the wrapped LOVE contact for a forge2d [contact] in [world].
LovePhysicsContact _physicsContactForWorldContact(
  LovePhysicsWorld world,
  forge2d.Contact contact,
) {
  final cache = _lovePhysicsContactObjectCache[world] ??=
      <forge2d.Contact, LovePhysicsContact>{};
  return cache.putIfAbsent(
    contact,
    () => LovePhysicsContact._(world: world, contact: contact),
  );
}

/// Adds contact accessors to physics worlds.
extension LovePhysicsWorldContactAccess on LovePhysicsWorld {
  /// The active contacts currently owned by this world.
  List<LovePhysicsContact> get contacts {
    _checkActive('world');
    _pruneLovePhysicsContacts(this);
    return List<LovePhysicsContact>.unmodifiable(
      _world.contactManager.contacts.map(
        (contact) => _physicsContactForWorldContact(this, contact),
      ),
    );
  }

  /// Returns the LOVE fixture wrapper for forge2d [fixture].
  LovePhysicsFixture fixtureForContact(forge2d.Fixture fixture) {
    for (final body in bodies) {
      for (final candidate in body.fixtures) {
        if (identical(candidate._fixture, fixture)) {
          return candidate;
        }
      }
    }

    throw StateError('A fixture has escaped Memoizer!');
  }
}

/// Adds contact accessors to physics bodies.
extension LovePhysicsBodyContactAccess on LovePhysicsBody {
  /// The active contacts currently touching this body.
  List<LovePhysicsContact> get contacts {
    final body = _activeBody;
    _pruneLovePhysicsContacts(world);
    return List<LovePhysicsContact>.unmodifiable(
      body.contacts.map(
        (contact) => _physicsContactForWorldContact(world, contact),
      ),
    );
  }
}

/// A wrapped physics contact exposed through LOVE's contact API.
final class LovePhysicsContact {
  /// Creates a wrapped contact for [world].
  LovePhysicsContact._({required this.world, required forge2d.Contact contact})
    : _contact = contact;

  /// The world that owns this contact.
  final LovePhysicsWorld world;

  /// The underlying forge2d contact.
  final forge2d.Contact _contact;

  /// Whether this wrapper has been permanently destroyed.
  bool _destroyed = false;

  /// The number of outstanding transient retains on this contact.
  int _transientRetainCount = 0;
  // Forge2D exposes contact friction/restitution as read-only values, so these
  // preserve LOVE-visible overrides even though the engine doesn't let us
  // mutate the underlying contact core directly.

  /// The LOVE-visible friction override, if one has been set.
  double? _frictionOverride;

  /// The LOVE-visible restitution override, if one has been set.
  double? _restitutionOverride;

  /// The pending enabled state to replay during the next pre-solve callback.
  bool? _pendingEnabled;

  /// Whether this contact has been destroyed or is no longer active.
  bool get isDestroyed {
    if (_destroyed || world.isDestroyed) {
      return true;
    }
    if (_transientRetainCount > 0) {
      return false;
    }

    final active = world._world.contactManager.contacts.contains(_contact);
    if (!active) {
      _destroyed = true;
    }
    return _destroyed;
  }

  /// The active forge2d contact, or throws when the contact has been destroyed.
  forge2d.Contact get _activeContact {
    if (isDestroyed) {
      throw StateError('Attempt to use destroyed contact.');
    }
    return _contact;
  }

  /// The 1-based child indices for the colliding shapes.
  ({int indexA, int indexB}) get children {
    final contact = _activeContact;
    return (indexA: contact.indexA + 1, indexB: contact.indexB + 1);
  }

  /// The fixture wrappers participating in this contact.
  ({LovePhysicsFixture fixtureA, LovePhysicsFixture fixtureB}) get fixtures {
    final contact = _activeContact;
    return (
      fixtureA: world.fixtureForContact(contact.fixtureA),
      fixtureB: world.fixtureForContact(contact.fixtureB),
    );
  }

  /// The current contact friction.
  double get friction => _frictionOverride ?? _activeContact.friction;

  /// The world-space contact normal.
  ({double x, double y}) get normal {
    final manifold = forge2d.WorldManifold();
    _activeContact.getWorldManifold(manifold);
    return (x: manifold.normal.x, y: manifold.normal.y);
  }

  /// The world-space contact positions.
  List<({double x, double y})> get positions {
    final contact = _activeContact;
    final manifold = forge2d.WorldManifold();
    contact.getWorldManifold(manifold);

    final positions = <({double x, double y})>[];
    for (var index = 0; index < contact.manifold.pointCount; index++) {
      positions.add((
        x: world.state.scaleUpScalar(manifold.points[index].x),
        y: world.state.scaleUpScalar(manifold.points[index].y),
      ));
    }
    return List<({double x, double y})>.unmodifiable(positions);
  }

  /// The current contact restitution.
  double get restitution => _restitutionOverride ?? _activeContact.restitution;

  /// The current tangent speed for this contact.
  double get tangentSpeed => _activeContact.tangentSpeed;

  /// Whether this contact is enabled for collision resolution.
  bool get isEnabled => _activeContact.isEnabled;

  /// Whether the fixtures are currently touching.
  bool get isTouching => _activeContact.isTouching();

  /// Resets friction to the engine-computed default.
  void resetFriction() {
    _activeContact.resetFriction();
    _frictionOverride = null;
  }

  /// Resets restitution to the engine-computed default.
  void resetRestitution() {
    _activeContact.resetRestitution();
    _restitutionOverride = null;
  }

  /// Enables or disables this contact.
  void setEnabled(bool enabled) {
    _activeContact.isEnabled = enabled;
    _pendingEnabled = enabled;
  }

  /// Overrides the friction used for this contact.
  void setFriction(double friction) {
    _frictionOverride = friction;
    _applyPersistentFrictionOverride(friction);
    _activeContact.velocityConstraint.friction = friction;
  }

  /// Overrides the restitution used for this contact.
  void setRestitution(double restitution) {
    _restitutionOverride = restitution;
    _applyPersistentRestitutionOverride(restitution);
    _activeContact.velocityConstraint.restitution = restitution;
  }

  /// Sets the tangent speed used for this contact.
  void setTangentSpeed(double speed) {
    final contact = _activeContact;
    contact.tangentSpeed = speed;
    contact.velocityConstraint.tangentSpeed = speed;
  }

  /// Marks this wrapper as permanently destroyed.
  void _markDestroyed() {
    _destroyed = true;
  }

  /// Retains this contact while transient callback wrappers are in flight.
  void _retainTransient() {
    if (_destroyed || world.isDestroyed) {
      return;
    }
    _transientRetainCount++;
  }

  /// Releases one transient retain on this contact.
  void _releaseTransient() {
    if (_transientRetainCount <= 0) {
      return;
    }
    _transientRetainCount--;
    if (_transientRetainCount == 0 &&
        !world._world.contactManager.contacts.contains(_contact)) {
      _destroyed = true;
    }
  }

  /// Replays any pending pre-solve state back into the underlying contact.
  void _replayPendingPreSolveState() {
    if (_destroyed || world.isDestroyed) {
      return;
    }

    final pendingEnabled = _pendingEnabled;
    if (pendingEnabled != null) {
      _contact.isEnabled = pendingEnabled;
      _pendingEnabled = null;
    }
  }

  /// Applies a persistent friction override by temporarily patching fixtures
  /// and recalculating the contact.
  void _applyPersistentFrictionOverride(double friction) {
    final fixtureA = _contact.fixtureA;
    final fixtureB = _contact.fixtureB;
    final previousFrictionA = fixtureA.friction;
    final previousFrictionB = fixtureB.friction;
    fixtureA.friction = friction;
    fixtureB.friction = friction;
    try {
      _contact.resetFriction();
    } finally {
      fixtureA.friction = previousFrictionA;
      fixtureB.friction = previousFrictionB;
    }
  }

  /// Applies a persistent restitution override by temporarily patching
  /// fixtures and recalculating the contact.
  void _applyPersistentRestitutionOverride(double restitution) {
    final fixtureA = _contact.fixtureA;
    final fixtureB = _contact.fixtureB;
    final previousRestitutionA = fixtureA.restitution;
    final previousRestitutionB = fixtureB.restitution;
    fixtureA.restitution = restitution;
    fixtureB.restitution = restitution;
    try {
      _contact.resetRestitution();
    } finally {
      fixtureA.restitution = previousRestitutionA;
      fixtureB.restitution = previousRestitutionB;
    }
  }
}
