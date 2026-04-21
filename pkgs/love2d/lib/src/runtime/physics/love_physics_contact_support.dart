part of '../love_runtime.dart';

final Expando<Map<forge2d.Contact, LovePhysicsContact>>
_lovePhysicsContactObjectCache =
    Expando<Map<forge2d.Contact, LovePhysicsContact>>(
      'love2dPhysicsContactObjects',
    );

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

extension LovePhysicsWorldContactAccess on LovePhysicsWorld {
  List<LovePhysicsContact> get contacts {
    _checkActive('world');
    _pruneLovePhysicsContacts(this);
    return List<LovePhysicsContact>.unmodifiable(
      _world.contactManager.contacts.map(
        (contact) => _physicsContactForWorldContact(this, contact),
      ),
    );
  }

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

extension LovePhysicsBodyContactAccess on LovePhysicsBody {
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

final class LovePhysicsContact {
  LovePhysicsContact._({required this.world, required forge2d.Contact contact})
    : _contact = contact;

  final LovePhysicsWorld world;
  final forge2d.Contact _contact;
  bool _destroyed = false;
  int _transientRetainCount = 0;
  // Forge2D exposes contact friction/restitution as read-only values, so these
  // preserve LOVE-visible overrides even though the engine doesn't let us
  // mutate the underlying contact core directly.
  double? _frictionOverride;
  double? _restitutionOverride;
  bool? _pendingEnabled;

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

  forge2d.Contact get _activeContact {
    if (isDestroyed) {
      throw StateError('Attempt to use destroyed contact.');
    }
    return _contact;
  }

  ({int indexA, int indexB}) get children {
    final contact = _activeContact;
    return (indexA: contact.indexA + 1, indexB: contact.indexB + 1);
  }

  ({LovePhysicsFixture fixtureA, LovePhysicsFixture fixtureB}) get fixtures {
    final contact = _activeContact;
    return (
      fixtureA: world.fixtureForContact(contact.fixtureA),
      fixtureB: world.fixtureForContact(contact.fixtureB),
    );
  }

  double get friction => _frictionOverride ?? _activeContact.friction;

  ({double x, double y}) get normal {
    final manifold = forge2d.WorldManifold();
    _activeContact.getWorldManifold(manifold);
    return (x: manifold.normal.x, y: manifold.normal.y);
  }

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

  double get restitution => _restitutionOverride ?? _activeContact.restitution;

  bool get isEnabled => _activeContact.isEnabled;

  bool get isTouching => _activeContact.isTouching();

  void resetFriction() {
    _activeContact.resetFriction();
    _frictionOverride = null;
  }

  void resetRestitution() {
    _activeContact.resetRestitution();
    _restitutionOverride = null;
  }

  void setEnabled(bool enabled) {
    _activeContact.isEnabled = enabled;
    _pendingEnabled = enabled;
  }

  void setFriction(double friction) {
    _frictionOverride = friction;
    _applyPersistentFrictionOverride(friction);
    _activeContact.velocityConstraint.friction = friction;
  }

  void setRestitution(double restitution) {
    _restitutionOverride = restitution;
    _applyPersistentRestitutionOverride(restitution);
    _activeContact.velocityConstraint.restitution = restitution;
  }

  void _markDestroyed() {
    _destroyed = true;
  }

  void _retainTransient() {
    if (_destroyed || world.isDestroyed) {
      return;
    }
    _transientRetainCount++;
  }

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
