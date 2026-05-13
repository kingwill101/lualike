part of '../love_runtime.dart';

/// The default meter-to-physics scale used by LOVE physics.
const int _lovePhysicsDefaultMeter = 30;

/// The maximum number of vertices allowed in polygon shapes.
const int _lovePhysicsMaxPolygonVertices = 8;

/// A callback invoked when a wrapped physics shape changes.
typedef LovePhysicsShapeChanged = void Function();

/// Per-runtime LOVE physics state.
final class LovePhysicsState {
  /// Creates empty physics state.
  LovePhysicsState();

  /// The physics state attached to each Lua runtime.
  static final Expando<LovePhysicsState> _states = Expando<LovePhysicsState>(
    'love2d.physics',
  );

  /// Attaches physics state to [runtime].
  static LovePhysicsState attach(LuaRuntime runtime) {
    final existing = _states[runtime];
    if (existing != null) {
      return existing;
    }

    final state = LovePhysicsState();
    _states[runtime] = state;
    return state;
  }

  /// Returns the physics state attached to [runtime].
  static LovePhysicsState of(LuaRuntime runtime) {
    return _states[runtime] ?? attach(runtime);
  }

  /// The current meter conversion used between LOVE units and forge2d units.
  double meter = _lovePhysicsDefaultMeter.toDouble();

  /// The physics worlds created from this state.
  final List<LovePhysicsWorld> _worlds = <LovePhysicsWorld>[];

  /// Scales a LOVE scalar down into forge2d world units.
  double scaleDownScalar(double value) => value / meter;

  /// Scales a forge2d scalar up into LOVE world units.
  double scaleUpScalar(double value) => value * meter;

  /// Scales an area-like value down into forge2d units.
  double scaleDownSquared(double value) =>
      scaleDownScalar(scaleDownScalar(value));

  /// Scales an area-like value up into LOVE units.
  double scaleUpSquared(double value) => scaleUpScalar(scaleUpScalar(value));

  /// Scales [value] down into forge2d world units.
  forge2d.Vector2 scaleDownVector(forge2d.Vector2 value) =>
      forge2d.Vector2(scaleDownScalar(value.x), scaleDownScalar(value.y));

  /// Creates a forge2d vector from LOVE-space coordinates [x] and [y].
  forge2d.Vector2 scaleDownVectorXY(double x, double y) =>
      forge2d.Vector2(scaleDownScalar(x), scaleDownScalar(y));

  /// Scales [value] up into LOVE world units.
  forge2d.Vector2 scaleUpVector(forge2d.Vector2 value) =>
      forge2d.Vector2(scaleUpScalar(value.x), scaleUpScalar(value.y));

  /// Creates a new physics world.
  LovePhysicsWorld newWorld({
    double gravityX = 0,
    double gravityY = 0,
    bool sleep = true,
  }) {
    final world = LovePhysicsWorld._(
      state: this,
      gravityX: gravityX,
      gravityY: gravityY,
      sleep: sleep,
    );
    _worlds.add(world);
    return world;
  }

  /// Removes [world] from this state's tracked worlds.
  void unregisterWorld(LovePhysicsWorld world) {
    _worlds.remove(world);
  }
}

/// A LOVE physics world backed by forge2d.
final class LovePhysicsWorld {
  /// Creates a physics world with the given gravity and sleep behavior.
  LovePhysicsWorld._({
    required this.state,
    required double gravityX,
    required double gravityY,
    required bool sleep,
  }) : _world = forge2d.World(
         forge2d.Vector2(
           state.scaleDownScalar(gravityX),
           state.scaleDownScalar(gravityY),
         ),
       ) {
    _world.setAllowSleep(sleep);
    _world.setContactListener(_callbackState.listener);
    _world.setContactFilter(_contactFilterState.filter);
  }

  /// The physics state that owns this world.
  final LovePhysicsState state;

  /// The underlying forge2d world.
  final forge2d.World _world;

  /// The callback state used for contact event delivery.
  late final LovePhysicsWorldCallbackState _callbackState =
      LovePhysicsWorldCallbackState(this);

  /// The contact-filter state used for collision filtering.
  late final LovePhysicsWorldContactFilterState _contactFilterState =
      LovePhysicsWorldContactFilterState(this);

  /// The bodies created in this world.
  final List<LovePhysicsBody> _bodies = <LovePhysicsBody>[];

  /// Whether this world has been destroyed.
  bool _destroyed = false;

  /// Whether this world has been destroyed.
  bool get isDestroyed => _destroyed;

  /// Whether the world is locked against structural mutation.
  bool get isLocked =>
      !_destroyed &&
      (_world.isLocked ||
          _callbackState.isDispatching ||
          _contactFilterState.isDispatching);

  /// Whether sleeping is currently allowed in this world.
  bool get sleepingAllowed => _destroyed ? true : _world.isAllowSleep();

  /// The currently registered contact callbacks.
  ({Value? beginContact, Value? endContact, Value? preSolve, Value? postSolve})
  get callbacks => _callbackState.callbacks;

  /// The currently registered contact-filter callback.
  Value? get contactFilter => _contactFilterState.callback;

  /// The active bodies currently owned by this world.
  List<LovePhysicsBody> get bodies => List<LovePhysicsBody>.unmodifiable(
    _bodies.where((body) => !body.isDestroyed),
  );

  /// The number of active bodies in this world.
  int get bodyCount => bodies.length;

  /// The number of active contacts currently tracked by forge2d.
  int get contactCount =>
      _destroyed ? 0 : _world.contactManager.contacts.length;

  /// The world gravity in LOVE units.
  ({double x, double y}) get gravity {
    final gravity = _world.gravity;
    return (
      x: state.scaleUpScalar(gravity.x),
      y: state.scaleUpScalar(gravity.y),
    );
  }

  /// Creates a new body in this world.
  LovePhysicsBody newBody({
    double x = 0,
    double y = 0,
    String type = 'static',
  }) {
    _checkActive('world');
    final definition = forge2d.BodyDef(
      type: _physicsBodyTypeFromString(type),
      position: state.scaleDownVectorXY(x, y),
    );
    final body = LovePhysicsBody._(
      world: this,
      body: _world.createBody(definition),
    );
    _bodies.add(body);
    return body;
  }

  /// Updates the world's gravity.
  void setGravity(double x, double y) {
    _checkActive('world');
    _world.gravity.setValues(
      state.scaleDownScalar(x),
      state.scaleDownScalar(y),
    );
  }

  /// Enables or disables sleeping for bodies in this world.
  void setSleepingAllowed(bool allow) {
    _checkActive('world');
    _world.setAllowSleep(allow);
  }

  /// Translates the world origin by [x] and [y] LOVE units.
  void translateOrigin(double x, double y) {
    _checkActive('world');
    final delta = state.scaleDownVectorXY(x, y);
    for (final body in List<LovePhysicsBody>.from(_bodies)) {
      if (body.isDestroyed) {
        continue;
      }
      final position = body._body.position.clone()..sub(delta);
      body._body.setTransform(position, body._body.angle);
    }
  }

  /// Replaces the registered contact callbacks for this world.
  void setCallbacks({
    Value? beginContact,
    Value? endContact,
    Value? preSolve,
    Value? postSolve,
  }) {
    _checkActive('world');
    _callbackState.setCallbacks(
      beginContact: beginContact,
      endContact: endContact,
      preSolve: preSolve,
      postSolve: postSolve,
    );
  }

  /// Replaces the registered contact-filter callback for this world.
  void setContactFilter(Value? callback) {
    _checkActive('world');
    _contactFilterState.setCallback(callback);
    _contactFilterState.refilterAllFixtures();
  }

  /// Precomputes contact-filter decisions for the next step of length [dt].
  Future<void> prepareContactFilterDecisions(
    double dt,
    Future<bool> Function(
      LovePhysicsFixture fixtureA,
      LovePhysicsFixture fixtureB,
    )
    evaluator,
  ) {
    _checkActive('world');
    return _contactFilterState.prepareDecisions(dt, evaluator);
  }

  /// Advances the world by [dt] seconds.
  ///
  /// Optional callback dispatchers allow callers to handle contact callbacks and
  /// contact filters either synchronously during stepping or asynchronously
  /// after the step completes.
  Future<void> update(
    double dt, {
    int? velocityIterations,
    int? positionIterations,
    void Function(LovePhysicsWorldQueuedCallback event)? syncCallbackDispatcher,
    bool Function(LovePhysicsFixture fixtureA, LovePhysicsFixture fixtureB)?
    syncContactFilterEvaluator,
    Future<void> Function(LovePhysicsWorldQueuedCallback event)?
    callbackDispatcher,
  }) async {
    _checkActive('world');
    _callbackState.setSyncDispatcher(syncCallbackDispatcher);
    _contactFilterState.setSyncEvaluator(syncContactFilterEvaluator);
    try {
      if (velocityIterations == null && positionIterations == null) {
        _world.stepDt(dt);
      } else {
        final previousVelocityIterations = forge2d.velocityIterations;
        final previousPositionIterations = forge2d.positionIterations;
        forge2d.velocityIterations =
            velocityIterations ?? previousVelocityIterations;
        forge2d.positionIterations =
            positionIterations ?? previousPositionIterations;
        try {
          _world.stepDt(dt);
        } finally {
          forge2d.velocityIterations = previousVelocityIterations;
          forge2d.positionIterations = previousPositionIterations;
        }
      }
    } finally {
      _callbackState.setSyncDispatcher(null);
      _contactFilterState.setSyncEvaluator(null);
    }
    _callbackState.throwPendingSyncError();
    await _callbackState.flush(callbackDispatcher);
  }

  /// Invokes [callback] for fixtures whose bounding boxes overlap the given
  /// axis-aligned query box.
  Future<void> queryBoundingBox(
    double minX,
    double minY,
    double maxX,
    double maxY,
    FutureOr<bool> Function(LovePhysicsFixture fixture) callback,
  ) async {
    _checkActive('world');

    for (final body in bodies) {
      for (final fixture in body.fixtures) {
        for (
          var childIndex = 1;
          childIndex <= fixture.shape.childCount;
          childIndex++
        ) {
          final box = fixture.getBoundingBox(childIndex);
          if (!_physicsAabbOverlaps(
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            otherMinX: box.minX,
            otherMinY: box.minY,
            otherMaxX: box.maxX,
            otherMaxY: box.maxY,
          )) {
            continue;
          }

          if (!await callback(fixture)) {
            return;
          }
        }
      }
    }
  }

  /// Ray-casts from (`x1`, `y1`) to (`x2`, `y2`) and forwards sorted hits to
  /// [callback].
  Future<void> rayCast(
    double x1,
    double y1,
    double x2,
    double y2,
    FutureOr<double> Function(
      LovePhysicsFixture fixture,
      double x,
      double y,
      double normalX,
      double normalY,
      double fraction,
    )
    callback,
  ) async {
    _checkActive('world');

    final hits =
        <
          ({
            LovePhysicsFixture fixture,
            double x,
            double y,
            double normalX,
            double normalY,
            double fraction,
          })
        >[];

    for (final body in bodies) {
      for (final fixture in body.fixtures) {
        for (
          var childIndex = 1;
          childIndex <= fixture.shape.childCount;
          childIndex++
        ) {
          final hit = fixture.rayCast(
            x1,
            y1,
            x2,
            y2,
            1,
            childIndex: childIndex,
          );
          if (hit == null) {
            continue;
          }

          hits.add((
            fixture: fixture,
            x: x1 + ((x2 - x1) * hit.fraction),
            y: y1 + ((y2 - y1) * hit.fraction),
            normalX: hit.normalX,
            normalY: hit.normalY,
            fraction: hit.fraction,
          ));
        }
      }
    }

    hits.sort((left, right) => left.fraction.compareTo(right.fraction));

    var maxFraction = 1.0;
    for (final hit in hits) {
      if (hit.fraction > maxFraction) {
        continue;
      }

      final response = await callback(
        hit.fixture,
        hit.x,
        hit.y,
        hit.normalX,
        hit.normalY,
        hit.fraction,
      );

      if (response == 0) {
        return;
      }
      if (response < 0) {
        continue;
      }
      if (response < maxFraction) {
        maxFraction = response;
      }
    }
  }

  /// Destroys this world and all bodies that belong to it.
  void destroy() {
    if (_destroyed) {
      return;
    }

    final bodies = List<LovePhysicsBody>.from(_bodies);
    for (final body in bodies) {
      body.destroy();
    }
    _bodies.clear();
    _disposeLovePhysicsJoints(this);
    _callbackState.dispose();
    _contactFilterState.dispose();
    _disposeLovePhysicsContacts(this);
    _destroyed = true;
    state.unregisterWorld(this);
  }

  /// Destroys [body] inside the underlying forge2d world.
  void _destroyBody(LovePhysicsBody body) {
    if (_destroyed || body.isDestroyed) {
      return;
    }
    _world.destroyBody(body._body);
    _bodies.remove(body);
  }

  /// Throws when this world has been destroyed.
  void _checkActive(String objectName) {
    if (_destroyed) {
      throw StateError('Attempt to use destroyed $objectName.');
    }
  }
}

/// A LOVE physics body backed by a forge2d body.
final class LovePhysicsBody {
  /// Creates a wrapped body for [world].
  LovePhysicsBody._({required this.world, required forge2d.Body body})
    : _body = body;

  /// The world that owns this body.
  final LovePhysicsWorld world;

  /// The underlying forge2d body.
  final forge2d.Body _body;

  /// The fixtures currently attached to this body.
  final List<LovePhysicsFixture> _fixtures = <LovePhysicsFixture>[];

  /// Whether this body has been destroyed.
  bool _destroyed = false;

  /// Arbitrary user data associated with this body.
  Object? userData;

  /// Whether this body has been destroyed.
  bool get isDestroyed => _destroyed;

  /// The owning physics state.
  LovePhysicsState get _state => world.state;

  /// The active underlying body, or throws when this body is destroyed.
  forge2d.Body get _activeBody {
    if (_destroyed) {
      throw StateError('Attempt to use destroyed body.');
    }
    return _body;
  }

  /// The active fixtures currently attached to this body.
  List<LovePhysicsFixture> get fixtures =>
      List<LovePhysicsFixture>.unmodifiable(
        _fixtures.where((fixture) => !fixture.isDestroyed),
      );

  /// Creates and attaches a new fixture built from [sourceShape].
  LovePhysicsFixture newFixture(LovePhysicsShape sourceShape, double density) {
    final fixture = LovePhysicsFixture._create(
      body: this,
      sourceShape: sourceShape,
      density: density,
    );
    _fixtures.add(fixture);
    return fixture;
  }

  /// The body's world position in LOVE units.
  ({double x, double y}) get position {
    final position = _activeBody.position;
    return (
      x: _state.scaleUpScalar(position.x),
      y: _state.scaleUpScalar(position.y),
    );
  }

  /// The body's linear velocity in LOVE units.
  ({double x, double y}) get linearVelocity {
    final velocity = _activeBody.linearVelocity;
    return (
      x: _state.scaleUpScalar(velocity.x),
      y: _state.scaleUpScalar(velocity.y),
    );
  }

  /// The body's world-space center of mass in LOVE units.
  ({double x, double y}) get worldCenter {
    final center = _activeBody.worldCenter;
    return (
      x: _state.scaleUpScalar(center.x),
      y: _state.scaleUpScalar(center.y),
    );
  }

  /// The body's local center of mass in LOVE units.
  ({double x, double y}) get localCenter {
    final center = _activeBody.getLocalCenter();
    return (
      x: _state.scaleUpScalar(center.x),
      y: _state.scaleUpScalar(center.y),
    );
  }

  /// The body's x-position in LOVE units.
  double get x => position.x;

  /// The body's y-position in LOVE units.
  double get y => position.y;

  /// The body's rotation in radians.
  double get angle => _activeBody.angle;

  /// The body's angular velocity in radians per second.
  double get angularVelocity => _activeBody.angularVelocity;

  /// The body's mass.
  double get mass => _activeBody.mass;

  /// The body's rotational inertia in LOVE units.
  double get inertia => _state.scaleUpSquared(_activeBody.getInertia());

  /// The body's mass data in LOVE units.
  ({double x, double y, double mass, double inertia}) get massData {
    final data = _currentMassData();
    return (
      x: _state.scaleUpScalar(data.center.x),
      y: _state.scaleUpScalar(data.center.y),
      mass: data.mass,
      inertia: _state.scaleUpSquared(data.I),
    );
  }

  /// The body's angular damping.
  double get angularDamping => _activeBody.angularDamping;

  /// The body's linear damping.
  double get linearDamping => _activeBody.linearDamping;

  /// The body's gravity scale.
  double get gravityScale => _activeBody.gravityScale?.x ?? 1.0;

  /// The LOVE string name for this body's type.
  String get type => _physicsBodyTypeToString(_activeBody.bodyType);

  /// The arbitrary user data associated with this body.
  Object? get userDataValue => userData;

  /// Whether this body is active.
  bool get isActive => _activeBody.isActive;

  /// Whether this body is awake.
  bool get isAwake => _activeBody.isAwake;

  /// Whether this body is treated as a bullet.
  bool get isBullet => _activeBody.isBullet;

  /// Whether sleeping is allowed for this body.
  bool get isSleepingAllowed => _activeBody.isSleepingAllowed();

  /// Whether this body has fixed rotation.
  bool get isFixedRotation => _activeBody.isFixedRotation();

  /// Returns whether this body is touching [other].
  bool isTouching(LovePhysicsBody other) {
    final body = _activeBody;
    final otherBody = other._activeBody;
    return body.contacts.any(
      (contact) => contact.containsBody(otherBody) && contact.isTouching(),
    );
  }

  /// Converts a world-space point to local body coordinates.
  ({double x, double y}) getLocalPoint(double worldX, double worldY) {
    final point = _activeBody.localPoint(
      _state.scaleDownVectorXY(worldX, worldY),
    );
    return (x: _state.scaleUpScalar(point.x), y: _state.scaleUpScalar(point.y));
  }

  /// Converts world-space [points] to local body coordinates.
  List<({double x, double y})> getLocalPoints(
    Iterable<({double x, double y})> points,
  ) {
    return List<({double x, double y})>.unmodifiable(
      points.map((point) => getLocalPoint(point.x, point.y)),
    );
  }

  /// Converts a world-space vector to local body coordinates.
  ({double x, double y}) getLocalVector(double worldX, double worldY) {
    final vector = _activeBody.localVector(
      _state.scaleDownVectorXY(worldX, worldY),
    );
    return (
      x: _state.scaleUpScalar(vector.x),
      y: _state.scaleUpScalar(vector.y),
    );
  }

  /// Converts a local-space point to world coordinates.
  ({double x, double y}) getWorldPoint(double localX, double localY) {
    final point = _activeBody.worldPoint(
      _state.scaleDownVectorXY(localX, localY),
    );
    return (x: _state.scaleUpScalar(point.x), y: _state.scaleUpScalar(point.y));
  }

  /// Converts local-space [points] to world coordinates.
  List<({double x, double y})> getWorldPoints(
    Iterable<({double x, double y})> points,
  ) {
    return List<({double x, double y})>.unmodifiable(
      points.map((point) => getWorldPoint(point.x, point.y)),
    );
  }

  /// Converts a local-space vector to world coordinates.
  ({double x, double y}) getWorldVector(double localX, double localY) {
    final vector = _activeBody.worldVector(
      _state.scaleDownVectorXY(localX, localY),
    );
    return (
      x: _state.scaleUpScalar(vector.x),
      y: _state.scaleUpScalar(vector.y),
    );
  }

  /// Returns the linear velocity at the world-space point (`x`, `y`).
  ({double x, double y}) getLinearVelocityFromWorldPoint(double x, double y) {
    final velocity = _activeBody.linearVelocityFromWorldPoint(
      _state.scaleDownVectorXY(x, y),
    );
    return (
      x: _state.scaleUpScalar(velocity.x),
      y: _state.scaleUpScalar(velocity.y),
    );
  }

  /// Returns the linear velocity at the local-space point (`x`, `y`).
  ({double x, double y}) getLinearVelocityFromLocalPoint(double x, double y) {
    final velocity = _activeBody.linearVelocityFromLocalPoint(
      _state.scaleDownVectorXY(x, y),
    );
    return (
      x: _state.scaleUpScalar(velocity.x),
      y: _state.scaleUpScalar(velocity.y),
    );
  }

  /// Applies a linear impulse to this body.
  void applyLinearImpulse(
    double x,
    double y, {
    double? pointX,
    double? pointY,
    bool wake = true,
  }) {
    _activeBody.applyLinearImpulse(
      _state.scaleDownVectorXY(x, y),
      point: pointX == null || pointY == null
          ? null
          : _state.scaleDownVectorXY(pointX, pointY),
      wake: wake,
    );
  }

  /// Applies an angular impulse to this body.
  void applyAngularImpulse(double impulse, {bool wake = true}) {
    if (!wake && !_activeBody.isAwake) {
      return;
    }
    if (wake && !_activeBody.isAwake) {
      _activeBody.setAwake(true);
    }
    _activeBody.applyAngularImpulse(_state.scaleDownSquared(impulse));
  }

  /// Applies torque to this body.
  void applyTorque(double torque, {bool wake = true}) {
    if (!wake && !_activeBody.isAwake) {
      return;
    }
    if (wake && !_activeBody.isAwake) {
      _activeBody.setAwake(true);
    }
    _activeBody.applyTorque(_state.scaleDownSquared(torque));
  }

  /// Applies a force to this body.
  void applyForce(
    double x,
    double y, {
    double? pointX,
    double? pointY,
    bool wake = true,
  }) {
    if (!wake && !_activeBody.isAwake) {
      return;
    }
    if (wake && !_activeBody.isAwake) {
      _activeBody.setAwake(true);
    }
    _activeBody.applyForce(
      _state.scaleDownVectorXY(x, y),
      point: pointX == null || pointY == null
          ? null
          : _state.scaleDownVectorXY(pointX, pointY),
    );
  }

  /// Sets the body's x-position, preserving the current y-position and angle.
  void setX(double x) {
    _activeBody.setTransform(_state.scaleDownVectorXY(x, y), angle);
  }

  /// Sets the body's y-position, preserving the current x-position and angle.
  void setY(double y) {
    _activeBody.setTransform(_state.scaleDownVectorXY(x, y), angle);
  }

  /// Sets the body's linear velocity.
  void setLinearVelocity(double x, double y) {
    _activeBody.linearVelocity = _state.scaleDownVectorXY(x, y);
  }

  /// Sets the body's angle.
  void setAngle(double angle) {
    _activeBody.setTransform(_activeBody.position.clone(), angle);
  }

  /// Sets the body's angular velocity.
  void setAngularVelocity(double value) {
    _activeBody.angularVelocity = value;
  }

  /// Sets the body's position.
  void setPosition(double x, double y) {
    _activeBody.setTransform(_state.scaleDownVectorXY(x, y), angle);
  }

  /// Recomputes the body's mass data from its fixtures.
  void resetMassData() {
    _activeBody.resetMassData();
  }

  /// Sets the body's full mass data in LOVE units.
  void setMassData(double x, double y, double mass, double inertia) {
    _activeBody.setMassData(
      forge2d.MassData()
        ..center.setValues(_state.scaleDownScalar(x), _state.scaleDownScalar(y))
        ..mass = mass
        ..I = _state.scaleDownSquared(inertia),
    );
  }

  /// Sets the body's mass.
  void setMass(double mass) {
    final data = _currentMassData()..mass = mass;
    _activeBody.setMassData(data);
  }

  /// Sets the body's inertia in LOVE units.
  void setInertia(double inertia) {
    final data = _currentMassData()..I = _state.scaleDownSquared(inertia);
    _activeBody.setMassData(data);
  }

  /// Sets the body's angular damping.
  void setAngularDamping(double damping) {
    _activeBody.angularDamping = damping;
  }

  /// Sets the body's linear damping.
  void setLinearDamping(double damping) {
    _activeBody.linearDamping = damping;
  }

  /// Sets the body's gravity scale.
  void setGravityScale(double scale) {
    _activeBody.gravityScale = forge2d.Vector2.all(scale);
  }

  /// Sets the body's type.
  void setType(String type) {
    _activeBody.setType(_physicsBodyTypeFromString(type));
  }

  /// Enables or disables this body.
  void setActive(bool active) {
    _activeBody.setActive(active);
  }

  /// Wakes or sleeps this body.
  void setAwake(bool awake) {
    _activeBody.setAwake(awake);
  }

  /// Enables or disables bullet mode for this body.
  void setBullet(bool bullet) {
    _activeBody.isBullet = bullet;
  }

  /// Enables or disables sleeping for this body.
  void setSleepingAllowed(bool allow) {
    _activeBody.setSleepingAllowed(allow);
  }

  /// Enables or disables fixed rotation for this body.
  void setFixedRotation(bool fixedRotation) {
    _activeBody.setFixedRotation(fixedRotation);
  }

  /// Sets the body's full transform.
  void setTransform(double x, double y, double angle) {
    _activeBody.setTransform(_state.scaleDownVectorXY(x, y), angle);
  }

  /// Associates arbitrary [value] with this body.
  void setUserData(Object? value) {
    userData = value;
    _activeBody.userData = value;
  }

  /// Destroys this body and all fixtures and joints attached to it.
  void destroy() {
    if (_destroyed) {
      return;
    }

    for (final joint in List<LovePhysicsJoint>.from(joints)) {
      joint.destroy();
    }
    for (final fixture in List<LovePhysicsFixture>.from(_fixtures)) {
      fixture._markDestroyed();
    }
    _fixtures.clear();
    world._destroyBody(this);
    _destroyed = true;
  }

  /// Returns the current mass data for the underlying body.
  forge2d.MassData _currentMassData() {
    return forge2d.MassData()
      ..center.setFrom(_activeBody.getLocalCenter())
      ..mass = _activeBody.mass
      ..I = _activeBody.getInertia();
  }
}

/// A LOVE physics fixture attached to a body.
final class LovePhysicsFixture {
  /// Creates an unattached wrapped fixture.
  LovePhysicsFixture._({
    required this.body,
    required this.shape,
    required this.density,
  });

  /// Creates and attaches a fixture built from [sourceShape].
  static LovePhysicsFixture _create({
    required LovePhysicsBody body,
    required LovePhysicsShape sourceShape,
    required double density,
  }) {
    final fixture = LovePhysicsFixture._(
      body: body,
      shape: sourceShape.clone(),
      density: density,
    );
    fixture.shape.attach(fixture._rebuildUnderlyingFixture);
    fixture._fixture = body._activeBody.createFixture(
      fixture._buildFixtureDef(density: density),
    );
    return fixture;
  }

  /// The body that owns this fixture.
  final LovePhysicsBody body;

  /// The LOVE shape currently describing this fixture.
  late final LovePhysicsShape shape;

  /// The underlying forge2d fixture.
  late forge2d.Fixture _fixture;

  /// Whether this fixture has been destroyed.
  bool _destroyed = false;

  /// The fixture density.
  double density;

  /// Arbitrary user data associated with this fixture.
  Object? userData;

  /// Whether this fixture has been destroyed.
  bool get isDestroyed => _destroyed;

  /// The active underlying fixture, or throws when destroyed.
  forge2d.Fixture get _activeFixture {
    if (_destroyed) {
      throw StateError('Attempt to use destroyed fixture.');
    }
    return _fixture;
  }

  /// The LOVE-visible shape type name.
  String get type => shape.shapeTypeName;

  /// The fixture friction.
  double get friction => _activeFixture.friction;

  /// The fixture restitution.
  double get restitution => _activeFixture.restitution;

  /// Whether this fixture is a sensor.
  bool get isSensor => _activeFixture.isSensor;

  /// The arbitrary user data associated with this fixture.
  Object? get userDataValue => userData;

  /// The raw filter data for this fixture.
  ({int categories, int mask, int group}) get filterData {
    final filter = _activeFixture.filterData;
    return (
      categories: filter.categoryBits,
      mask: filter.maskBits,
      group: filter.groupIndex,
    );
  }

  /// The enabled category numbers for this fixture.
  List<int> get categories =>
      _physicsCategoriesFromBits(_activeFixture.filterData.categoryBits);

  /// The masked-out category numbers for this fixture.
  List<int> get maskCategories => _physicsCategoriesFromBits(
    (~_activeFixture.filterData.maskBits) & 0xFFFF,
  );

  /// The fixture group index.
  int get groupIndex => _activeFixture.filterData.groupIndex;

  /// Sets the fixture friction.
  void setFriction(double value) {
    _activeFixture.friction = value;
  }

  /// Sets the fixture restitution.
  void setRestitution(double value) {
    _activeFixture.restitution = value;
  }

  /// Sets whether this fixture acts as a sensor.
  void setSensor(bool value) {
    _activeFixture.setSensor(value);
  }

  /// Associates arbitrary [value] with this fixture.
  void setUserData(Object? value) {
    userData = value;
    if (!_destroyed) {
      _fixture.userData = value;
    }
  }

  /// Sets the raw filter data for this fixture.
  void setFilterData(int categories, int mask, int group) {
    final filter = forge2d.Filter()
      ..categoryBits = categories & 0xFFFF
      ..maskBits = mask & 0xFFFF
      ..groupIndex = group;
    _activeFixture.filterData = filter;
  }

  /// Sets the categories this fixture belongs to.
  void setCategories(Iterable<int> values) {
    final filter = forge2d.Filter()..set(_activeFixture.filterData);
    filter.categoryBits = _physicsBitsFromCategories(values);
    _activeFixture.filterData = filter;
  }

  /// Sets the categories this fixture should ignore.
  void setMaskCategories(Iterable<int> values) {
    final filter = forge2d.Filter()..set(_activeFixture.filterData);
    filter.maskBits = (~_physicsBitsFromCategories(values)) & 0xFFFF;
    _activeFixture.filterData = filter;
  }

  /// Sets the group index for this fixture.
  void setGroupIndex(int value) {
    final filter = forge2d.Filter()..set(_activeFixture.filterData);
    filter.groupIndex = value;
    _activeFixture.filterData = filter;
  }

  /// Sets the fixture density and rebuilds the underlying forge2d fixture.
  void setDensity(double value) {
    density = value;
    _rebuildUnderlyingFixture();
  }

  /// Returns whether the fixture contains the point (`x`, `y`).
  bool testPoint(double x, double y) {
    return _activeFixture.testPoint(body._state.scaleDownVectorXY(x, y));
  }

  /// Ray-casts against this fixture.
  ({double normalX, double normalY, double fraction})? rayCast(
    double x1,
    double y1,
    double x2,
    double y2,
    double maxFraction, {
    int childIndex = 1,
  }) {
    if (childIndex < 1 || childIndex > shape.childCount) {
      throw StateError('Physics error: index out of bounds');
    }

    final input = forge2d.RayCastInput()
      ..p1.setValues(
        body._state.scaleDownScalar(x1),
        body._state.scaleDownScalar(y1),
      )
      ..p2.setValues(
        body._state.scaleDownScalar(x2),
        body._state.scaleDownScalar(y2),
      )
      ..maxFraction = maxFraction;
    final output = forge2d.RayCastOutput();
    if (!_activeFixture.raycast(output, input, childIndex - 1)) {
      return null;
    }

    return (
      normalX: output.normal.x,
      normalY: output.normal.y,
      fraction: output.fraction,
    );
  }

  /// Returns the axis-aligned bounding box for this fixture child.
  ({double minX, double minY, double maxX, double maxY}) getBoundingBox([
    int childIndex = 1,
  ]) {
    if (childIndex < 1 || childIndex > shape.childCount) {
      throw StateError('Physics error: index out of bounds');
    }

    final box = _activeFixture.getAABB(childIndex - 1);
    return (
      minX: body._state.scaleUpScalar(box.lowerBound.x),
      minY: body._state.scaleUpScalar(box.lowerBound.y),
      maxX: body._state.scaleUpScalar(box.upperBound.x),
      maxY: body._state.scaleUpScalar(box.upperBound.y),
    );
  }

  /// Returns the mass data for this fixture.
  ({double x, double y, double mass, double inertia}) getMassData() {
    final data = forge2d.MassData();
    _activeFixture.getMassData(data);
    return (
      x: body._state.scaleUpScalar(data.center.x),
      y: body._state.scaleUpScalar(data.center.y),
      mass: data.mass,
      inertia: data.I,
    );
  }

  /// Destroys this fixture.
  void destroy() {
    if (_destroyed) {
      return;
    }

    body._activeBody.destroyFixture(_fixture);
    body._fixtures.remove(this);
    _markDestroyed();
  }

  /// Marks this fixture as destroyed.
  void _markDestroyed() {
    _destroyed = true;
  }

  /// Rebuilds the underlying forge2d fixture after a structural shape change.
  void _rebuildUnderlyingFixture() {
    if (_destroyed || body.isDestroyed) {
      return;
    }

    final previous = _fixture;
    final filter = forge2d.Filter()..set(previous.filterData);
    final friction = previous.friction;
    final restitution = previous.restitution;
    final sensor = previous.isSensor;

    body._activeBody.destroyFixture(previous);
    _fixture = body._activeBody.createFixture(
      forge2d.FixtureDef(
        shape.toForgeShape(),
        density: density,
        friction: friction,
        restitution: restitution,
        isSensor: sensor,
        filter: filter,
      )..userData = userData,
    );
  }

  /// Builds a forge2d fixture definition from this fixture's current shape.
  forge2d.FixtureDef _buildFixtureDef({required double density}) {
    return forge2d.FixtureDef(shape.toForgeShape(), density: density)
      ..userData = userData;
  }
}

/// Base class for LOVE physics shapes.
abstract base class LovePhysicsShape {
  /// Creates a physics shape tied to [state].
  LovePhysicsShape({required this.state, LovePhysicsShapeChanged? onChanged})
    : _onChanged = onChanged;

  /// The owning physics state used for LOVE-to-forge2d conversions.
  final LovePhysicsState state;

  /// The callback invoked when this shape changes structurally.
  LovePhysicsShapeChanged? _onChanged;

  /// The LOVE object type name for this shape.
  String get objectTypeName;

  /// The LOVE shape type name for this shape.
  String get shapeTypeName;

  /// The number of child shapes exposed by this shape.
  int get childCount;

  /// The shape radius in LOVE units.
  double get radius;

  /// Returns a copy of this shape.
  LovePhysicsShape clone({LovePhysicsShapeChanged? onChanged});

  /// Builds the equivalent forge2d shape.
  forge2d.Shape toForgeShape();

  /// Attaches an on-change callback to this shape.
  void attach(LovePhysicsShapeChanged onChanged) {
    _onChanged = onChanged;
  }

  /// Marks this shape as changed and notifies the attached callback.
  void markChanged() {
    _onChanged?.call();
  }

  /// Computes the shape AABB in LOVE units for the given transform.
  ({double minX, double minY, double maxX, double maxY}) computeAabb(
    double x,
    double y,
    double angle, {
    int childIndex = 1,
  }) {
    _checkChildIndex(childIndex);
    final aabb = forge2d.AABB();
    final transform = forge2d.Transform.zero()
      ..p.setValues(state.scaleDownScalar(x), state.scaleDownScalar(y))
      ..q.setAngle(angle);
    toForgeShape().computeAABB(aabb, transform, childIndex - 1);
    return (
      minX: state.scaleUpScalar(aabb.lowerBound.x),
      minY: state.scaleUpScalar(aabb.lowerBound.y),
      maxX: state.scaleUpScalar(aabb.upperBound.x),
      maxY: state.scaleUpScalar(aabb.upperBound.y),
    );
  }

  /// Computes the mass properties for this shape at [density].
  ({double x, double y, double mass, double inertia}) computeMass(
    double density,
  ) {
    final data = forge2d.MassData();
    toForgeShape().computeMass(data, density);
    return (
      x: state.scaleUpScalar(data.center.x),
      y: state.scaleUpScalar(data.center.y),
      mass: data.mass,
      inertia: state.scaleUpSquared(data.I),
    );
  }

  /// Returns whether the point (`px`, `py`) lies inside this shape.
  bool testPoint(double x, double y, double angle, double px, double py) {
    final transform = forge2d.Transform.zero()
      ..p.setValues(state.scaleDownScalar(x), state.scaleDownScalar(y))
      ..q.setAngle(angle);
    return toForgeShape().testPoint(transform, state.scaleDownVectorXY(px, py));
  }

  /// Ray-casts against this shape with the given transform.
  ({double normalX, double normalY, double fraction})? rayCast(
    double x1,
    double y1,
    double x2,
    double y2,
    double maxFraction,
    double x,
    double y,
    double angle, {
    int childIndex = 1,
  }) {
    _checkChildIndex(childIndex);
    final input = forge2d.RayCastInput()
      ..p1.setValues(state.scaleDownScalar(x1), state.scaleDownScalar(y1))
      ..p2.setValues(state.scaleDownScalar(x2), state.scaleDownScalar(y2))
      ..maxFraction = maxFraction;
    final transform = forge2d.Transform.zero()
      ..p.setValues(state.scaleDownScalar(x), state.scaleDownScalar(y))
      ..q.setAngle(angle);
    final output = forge2d.RayCastOutput();
    if (!toForgeShape().raycast(output, input, transform, childIndex - 1)) {
      return null;
    }

    return (
      normalX: output.normal.x,
      normalY: output.normal.y,
      fraction: output.fraction,
    );
  }

  /// Validates a 1-based [childIndex] for this shape.
  void _checkChildIndex(int childIndex) {
    if (childIndex < 1 || childIndex > childCount) {
      throw StateError('Physics error: index out of bounds');
    }
  }
}

/// A LOVE circle shape.
final class LovePhysicsCircleShape extends LovePhysicsShape {
  /// Creates a circle shape with [center] and [radius].
  LovePhysicsCircleShape({
    required super.state,
    super.onChanged,
    required forge2d.Vector2 center,
    required double radius,
  }) : _center = center.clone(),
       _radius = radius;

  /// The circle center in forge2d units.
  final forge2d.Vector2 _center;

  /// The circle radius in forge2d units.
  double _radius;

  @override
  /// The LOVE object type name.
  String get objectTypeName => 'CircleShape';

  @override
  /// The LOVE shape type name.
  String get shapeTypeName => 'circle';

  @override
  /// The number of child shapes.
  int get childCount => 1;

  @override
  /// The circle radius in LOVE units.
  double get radius => state.scaleUpScalar(_radius);

  /// The circle center in LOVE units.
  ({double x, double y}) get point =>
      (x: state.scaleUpScalar(_center.x), y: state.scaleUpScalar(_center.y));

  /// Sets the circle radius in LOVE units.
  void setRadius(double radius) {
    _radius = state.scaleDownScalar(radius);
    markChanged();
  }

  /// Sets the circle center in LOVE units.
  void setPoint(double x, double y) {
    _center.setValues(state.scaleDownScalar(x), state.scaleDownScalar(y));
    markChanged();
  }

  @override
  /// Returns a copy of this circle shape.
  LovePhysicsCircleShape clone({LovePhysicsShapeChanged? onChanged}) {
    return LovePhysicsCircleShape(
      state: state,
      onChanged: onChanged,
      center: _center,
      radius: _radius,
    );
  }

  @override
  /// Builds the equivalent forge2d circle shape.
  forge2d.CircleShape toForgeShape() {
    return forge2d.CircleShape(position: _center.clone(), radius: _radius);
  }
}

/// A LOVE polygon shape.
final class LovePhysicsPolygonShape extends LovePhysicsShape {
  /// Creates a polygon shape from [vertices].
  LovePhysicsPolygonShape({
    required super.state,
    super.onChanged,
    required Iterable<forge2d.Vector2> vertices,
  }) : _vertices = List<forge2d.Vector2>.unmodifiable(
         vertices.map((vertex) => vertex.clone()),
       );

  /// The polygon vertices in forge2d units.
  final List<forge2d.Vector2> _vertices;

  @override
  /// The LOVE object type name.
  String get objectTypeName => 'PolygonShape';

  @override
  /// The LOVE shape type name.
  String get shapeTypeName => 'polygon';

  @override
  /// The number of child shapes.
  int get childCount => 1;

  @override
  /// The polygon radius in LOVE units.
  double get radius => state.scaleUpScalar(forge2d.polygonRadius);

  /// The polygon vertices in LOVE units.
  List<({double x, double y})> get points =>
      List<({double x, double y})>.unmodifiable(
        _vertices.map(
          (vertex) => (
            x: state.scaleUpScalar(vertex.x),
            y: state.scaleUpScalar(vertex.y),
          ),
        ),
      );

  /// Returns whether this polygon is valid according to forge2d.
  bool validate() {
    return toForgeShape().validate();
  }

  @override
  /// Returns a copy of this polygon shape.
  LovePhysicsPolygonShape clone({LovePhysicsShapeChanged? onChanged}) {
    return LovePhysicsPolygonShape(
      state: state,
      onChanged: onChanged,
      vertices: _vertices,
    );
  }

  @override
  /// Builds the equivalent forge2d polygon shape.
  forge2d.PolygonShape toForgeShape() {
    final shape = forge2d.PolygonShape();
    shape.set(
      _vertices.map((vertex) => vertex.clone()).toList(growable: false),
    );
    return shape;
  }
}

/// A LOVE edge shape.
final class LovePhysicsEdgeShape extends LovePhysicsShape {
  /// Creates an edge shape from [vertex1] to [vertex2].
  LovePhysicsEdgeShape({
    required super.state,
    super.onChanged,
    required forge2d.Vector2 vertex1,
    required forge2d.Vector2 vertex2,
    forge2d.Vector2? previousVertex,
    forge2d.Vector2? nextVertex,
  }) : _vertex1 = vertex1.clone(),
       _vertex2 = vertex2.clone(),
       _previousVertex = previousVertex?.clone(),
       _nextVertex = nextVertex?.clone();

  /// The first edge vertex in forge2d units.
  final forge2d.Vector2 _vertex1;

  /// The second edge vertex in forge2d units.
  final forge2d.Vector2 _vertex2;

  /// The optional previous adjacent vertex.
  forge2d.Vector2? _previousVertex;

  /// The optional next adjacent vertex.
  forge2d.Vector2? _nextVertex;

  @override
  /// The LOVE object type name.
  String get objectTypeName => 'EdgeShape';

  @override
  /// The LOVE shape type name.
  String get shapeTypeName => 'edge';

  @override
  /// The number of child shapes.
  int get childCount => 1;

  @override
  /// The edge radius in LOVE units.
  double get radius => state.scaleUpScalar(forge2d.polygonRadius);

  /// The edge endpoints in LOVE units.
  List<({double x, double y})> get points => <({double x, double y})>[
    (x: state.scaleUpScalar(_vertex1.x), y: state.scaleUpScalar(_vertex1.y)),
    (x: state.scaleUpScalar(_vertex2.x), y: state.scaleUpScalar(_vertex2.y)),
  ];

  /// The next adjacent vertex in LOVE units, if one exists.
  ({double x, double y})? get nextVertex => _nextVertex == null
      ? null
      : (
          x: state.scaleUpScalar(_nextVertex!.x),
          y: state.scaleUpScalar(_nextVertex!.y),
        );

  /// The previous adjacent vertex in LOVE units, if one exists.
  ({double x, double y})? get previousVertex => _previousVertex == null
      ? null
      : (
          x: state.scaleUpScalar(_previousVertex!.x),
          y: state.scaleUpScalar(_previousVertex!.y),
        );

  /// Sets or clears the next adjacent vertex.
  void setNextVertex([double? x, double? y]) {
    if (x == null || y == null) {
      _nextVertex = null;
    } else {
      _nextVertex = state.scaleDownVectorXY(x, y);
    }
    markChanged();
  }

  /// Sets or clears the previous adjacent vertex.
  void setPreviousVertex([double? x, double? y]) {
    if (x == null || y == null) {
      _previousVertex = null;
    } else {
      _previousVertex = state.scaleDownVectorXY(x, y);
    }
    markChanged();
  }

  @override
  /// Returns a copy of this edge shape.
  LovePhysicsEdgeShape clone({LovePhysicsShapeChanged? onChanged}) {
    return LovePhysicsEdgeShape(
      state: state,
      onChanged: onChanged,
      vertex1: _vertex1,
      vertex2: _vertex2,
      previousVertex: _previousVertex,
      nextVertex: _nextVertex,
    );
  }

  @override
  /// Builds the equivalent forge2d edge shape.
  forge2d.EdgeShape toForgeShape() {
    final shape = forge2d.EdgeShape()..set(_vertex1.clone(), _vertex2.clone());
    if (_previousVertex != null) {
      shape.vertex0.setFrom(_previousVertex!);
      shape.hasVertex0 = true;
    }
    if (_nextVertex != null) {
      shape.vertex3.setFrom(_nextVertex!);
      shape.hasVertex3 = true;
    }
    return shape;
  }
}

/// A LOVE chain shape.
final class LovePhysicsChainShape extends LovePhysicsShape {
  /// Creates a stored chain shape from [vertices].
  LovePhysicsChainShape._({
    required super.state,
    super.onChanged,
    required List<forge2d.Vector2> vertices,
    required bool loop,
    forge2d.Vector2? previousVertex,
    forge2d.Vector2? nextVertex,
  }) : _vertices = List<forge2d.Vector2>.unmodifiable(
         vertices.map((vertex) => vertex.clone()),
       ),
       _loop = loop,
       _previousVertex = previousVertex?.clone(),
       _nextVertex = nextVertex?.clone();

  /// Creates a chain shape from [vertices], optionally closing it into a loop.
  factory LovePhysicsChainShape.create({
    required LovePhysicsState state,
    LovePhysicsShapeChanged? onChanged,
    required List<forge2d.Vector2> vertices,
    required bool loop,
  }) {
    if (loop && vertices.length < 3) {
      throw StateError("A loop can't be created with less than 3 vertices");
    }
    if (!loop && vertices.length < 2) {
      throw StateError(
        'Expected a minimum of 2 vertices, got ${vertices.length}.',
      );
    }

    final stored = List<forge2d.Vector2>.from(
      vertices.map((vertex) => vertex.clone()),
      growable: true,
    );
    forge2d.Vector2? previousVertex;
    forge2d.Vector2? nextVertex;
    if (loop) {
      stored.add(stored.first.clone());
      previousVertex = stored[stored.length - 2].clone();
      nextVertex = stored[1].clone();
    }

    return LovePhysicsChainShape._(
      state: state,
      onChanged: onChanged,
      vertices: stored,
      loop: loop,
      previousVertex: previousVertex,
      nextVertex: nextVertex,
    );
  }

  /// The chain vertices in forge2d units.
  final List<forge2d.Vector2> _vertices;

  /// Whether this chain is closed into a loop.
  final bool _loop;

  /// The optional previous adjacent vertex.
  forge2d.Vector2? _previousVertex;

  /// The optional next adjacent vertex.
  forge2d.Vector2? _nextVertex;

  @override
  /// The LOVE object type name.
  String get objectTypeName => 'ChainShape';

  @override
  /// The LOVE shape type name.
  String get shapeTypeName => 'chain';

  @override
  /// The number of child edges in this chain.
  int get childCount => _vertices.length - 1;

  @override
  /// The chain radius in LOVE units.
  double get radius => state.scaleUpScalar(forge2d.polygonRadius);

  /// The number of stored vertices.
  int get vertexCount => _vertices.length;

  /// The next adjacent vertex in LOVE units, if one exists.
  ({double x, double y})? get nextVertex => _nextVertex == null
      ? null
      : (
          x: state.scaleUpScalar(_nextVertex!.x),
          y: state.scaleUpScalar(_nextVertex!.y),
        );

  /// The previous adjacent vertex in LOVE units, if one exists.
  ({double x, double y})? get previousVertex => _previousVertex == null
      ? null
      : (
          x: state.scaleUpScalar(_previousVertex!.x),
          y: state.scaleUpScalar(_previousVertex!.y),
        );

  /// The chain vertices in LOVE units.
  List<({double x, double y})> get points =>
      List<({double x, double y})>.unmodifiable(
        _vertices.map(
          (vertex) => (
            x: state.scaleUpScalar(vertex.x),
            y: state.scaleUpScalar(vertex.y),
          ),
        ),
      );

  /// Returns the vertex at the 1-based [index].
  ({double x, double y}) pointAt(int index) {
    if (index < 1 || index > _vertices.length) {
      throw StateError('Physics error: index out of bounds');
    }
    final vertex = _vertices[index - 1];
    return (x: state.scaleUpScalar(vertex.x), y: state.scaleUpScalar(vertex.y));
  }

  /// Returns the child edge at the 1-based [index].
  LovePhysicsEdgeShape childEdgeAt(int index) {
    if (index < 1 || index >= _vertices.length) {
      throw StateError('Physics error: index out of bounds');
    }

    final edgeIndex = index - 1;
    final previousVertex = edgeIndex > 0
        ? _vertices[edgeIndex - 1]
        : _previousVertex;
    final nextVertex = edgeIndex < _vertices.length - 2
        ? _vertices[edgeIndex + 2]
        : _nextVertex;
    return LovePhysicsEdgeShape(
      state: state,
      vertex1: _vertices[edgeIndex],
      vertex2: _vertices[edgeIndex + 1],
      previousVertex: previousVertex,
      nextVertex: nextVertex,
    );
  }

  /// Sets or clears the next adjacent vertex.
  void setNextVertex([double? x, double? y]) {
    if (x == null || y == null) {
      _nextVertex = null;
    } else {
      _nextVertex = state.scaleDownVectorXY(x, y);
    }
    markChanged();
  }

  /// Sets or clears the previous adjacent vertex.
  void setPreviousVertex([double? x, double? y]) {
    if (x == null || y == null) {
      _previousVertex = null;
    } else {
      _previousVertex = state.scaleDownVectorXY(x, y);
    }
    markChanged();
  }

  @override
  /// Returns a copy of this chain shape.
  LovePhysicsChainShape clone({LovePhysicsShapeChanged? onChanged}) {
    return LovePhysicsChainShape._(
      state: state,
      onChanged: onChanged,
      vertices: _vertices,
      loop: _loop,
      previousVertex: _previousVertex,
      nextVertex: _nextVertex,
    );
  }

  @override
  /// Builds the equivalent forge2d chain shape.
  forge2d.ChainShape toForgeShape() {
    final shape = forge2d.ChainShape();
    if (_loop) {
      shape.createLoop(
        _vertices
            .take(_vertices.length - 1)
            .map((vertex) => vertex.clone())
            .toList(growable: false),
      );
    } else {
      shape.createChain(
        _vertices.map((vertex) => vertex.clone()).toList(growable: false),
      );
      if (_previousVertex != null) {
        shape.prevVertex = _previousVertex!.clone();
      }
      if (_nextVertex != null) {
        shape.nextVertex = _nextVertex!.clone();
      }
    }
    return shape;
  }
}

/// Creates a rectangle polygon shape centered at (`x`, `y`).
LovePhysicsShape lovePhysicsRectangleShape({
  required LovePhysicsState state,
  required double x,
  required double y,
  required double width,
  required double height,
  required double angle,
}) {
  final shape = forge2d.PolygonShape()
    ..setAsBox(
      state.scaleDownScalar(width / 2),
      state.scaleDownScalar(height / 2),
      state.scaleDownVectorXY(x, y),
      angle,
    );
  return LovePhysicsPolygonShape(state: state, vertices: shape.vertices);
}

/// Creates a polygon shape from LOVE-space [points].
LovePhysicsShape lovePhysicsPolygonShape({
  required LovePhysicsState state,
  required List<({double x, double y})> points,
}) {
  if (points.length > _lovePhysicsMaxPolygonVertices) {
    throw StateError(
      'Expected a maximum of $_lovePhysicsMaxPolygonVertices vertices, got ${points.length}.',
    );
  }
  final shape = forge2d.PolygonShape()
    ..set(
      points
          .map((point) => state.scaleDownVectorXY(point.x, point.y))
          .toList(growable: false),
    );
  return LovePhysicsPolygonShape(state: state, vertices: shape.vertices);
}

/// Creates an edge shape from (`x1`, `y1`) to (`x2`, `y2`).
LovePhysicsEdgeShape lovePhysicsEdgeShape({
  required LovePhysicsState state,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
}) {
  return LovePhysicsEdgeShape(
    state: state,
    vertex1: state.scaleDownVectorXY(x1, y1),
    vertex2: state.scaleDownVectorXY(x2, y2),
  );
}

/// Creates a chain shape from LOVE-space [points].
LovePhysicsChainShape lovePhysicsChainShape({
  required LovePhysicsState state,
  required bool loop,
  required List<({double x, double y})> points,
}) {
  return LovePhysicsChainShape.create(
    state: state,
    loop: loop,
    vertices: points
        .map((point) => state.scaleDownVectorXY(point.x, point.y))
        .toList(growable: false),
  );
}

/// Creates a circle shape centered at (`x`, `y`) with [radius].
LovePhysicsCircleShape lovePhysicsCircleShape({
  required LovePhysicsState state,
  required double x,
  required double y,
  required double radius,
}) {
  return LovePhysicsCircleShape(
    state: state,
    center: state.scaleDownVectorXY(x, y),
    radius: state.scaleDownScalar(radius),
  );
}

/// Computes the distance between two fixtures.
({
  double distance,
  double pointAx,
  double pointAy,
  double pointBx,
  double pointBy,
})
lovePhysicsDistance(
  LovePhysicsState state,
  LovePhysicsFixture fixtureA,
  LovePhysicsFixture fixtureB,
) {
  final proxyA = forge2d.DistanceProxy()..set(fixtureA._activeFixture.shape, 0);
  final proxyB = forge2d.DistanceProxy()..set(fixtureB._activeFixture.shape, 0);
  final input = forge2d.DistanceInput()
    ..proxyA = proxyA
    ..proxyB = proxyB
    ..transformA = fixtureA.body._activeBody.transform
    ..transformB = fixtureB.body._activeBody.transform
    ..useRadii = true;
  final output = forge2d.DistanceOutput();
  final cache = forge2d.SimplexCache()..count = 0;
  forge2d.Distance().compute(output, cache, input);
  return (
    distance: state.scaleUpScalar(output.distance),
    pointAx: state.scaleUpScalar(output.pointA.x),
    pointAy: state.scaleUpScalar(output.pointA.y),
    pointBx: state.scaleUpScalar(output.pointB.x),
    pointBy: state.scaleUpScalar(output.pointB.y),
  );
}

/// Converts a LOVE body type string to a forge2d body type.
forge2d.BodyType _physicsBodyTypeFromString(String type) {
  return switch (type) {
    'static' => forge2d.BodyType.static,
    'dynamic' => forge2d.BodyType.dynamic,
    'kinematic' => forge2d.BodyType.kinematic,
    _ => throw StateError('Unknown body type: $type'),
  };
}

/// Converts a forge2d body type to LOVE's string representation.
String _physicsBodyTypeToString(forge2d.BodyType type) {
  return switch (type) {
    forge2d.BodyType.static => 'static',
    forge2d.BodyType.dynamic => 'dynamic',
    forge2d.BodyType.kinematic => 'kinematic',
  };
}

/// Converts 1-based category values to the fixture bit mask used by forge2d.
int _physicsBitsFromCategories(Iterable<int> values) {
  var bits = 0;
  for (final value in values) {
    if (value < 1 || value > 16) {
      throw StateError('Values must be in range 1-16.');
    }
    bits |= 1 << (value - 1);
  }
  return bits;
}

/// Converts a fixture bit mask to 1-based LOVE category values.
List<int> _physicsCategoriesFromBits(int bits) {
  final categories = <int>[];
  for (var index = 0; index < 16; index++) {
    if ((bits & (1 << index)) != 0) {
      categories.add(index + 1);
    }
  }
  return List<int>.unmodifiable(categories);
}

/// Returns whether two axis-aligned bounding boxes overlap.
bool _physicsAabbOverlaps({
  required double minX,
  required double minY,
  required double maxX,
  required double maxY,
  required double otherMinX,
  required double otherMinY,
  required double otherMaxX,
  required double otherMaxY,
}) {
  return maxX >= otherMinX &&
      maxY >= otherMinY &&
      otherMaxX >= minX &&
      otherMaxY >= minY;
}
