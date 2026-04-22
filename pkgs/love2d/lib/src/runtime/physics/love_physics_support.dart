part of '../love_runtime.dart';

const int _lovePhysicsDefaultMeter = 30;
const int _lovePhysicsMaxPolygonVertices = 8;

typedef LovePhysicsShapeChanged = void Function();

final class LovePhysicsState {
  LovePhysicsState();

  static final Expando<LovePhysicsState> _states = Expando<LovePhysicsState>(
    'love2d.physics',
  );

  static LovePhysicsState attach(LuaRuntime runtime) {
    final existing = _states[runtime];
    if (existing != null) {
      return existing;
    }

    final state = LovePhysicsState();
    _states[runtime] = state;
    return state;
  }

  static LovePhysicsState of(LuaRuntime runtime) {
    return _states[runtime] ?? attach(runtime);
  }

  double _meter = _lovePhysicsDefaultMeter.toDouble();
  final List<LovePhysicsWorld> _worlds = <LovePhysicsWorld>[];

  double get meter => _meter;

  set meter(double value) {
    _meter = value;
  }

  double scaleDownScalar(double value) => value / _meter;

  double scaleUpScalar(double value) => value * _meter;

  double scaleDownSquared(double value) =>
      scaleDownScalar(scaleDownScalar(value));

  double scaleUpSquared(double value) => scaleUpScalar(scaleUpScalar(value));

  forge2d.Vector2 scaleDownVector(forge2d.Vector2 value) =>
      forge2d.Vector2(scaleDownScalar(value.x), scaleDownScalar(value.y));

  forge2d.Vector2 scaleDownVectorXY(double x, double y) =>
      forge2d.Vector2(scaleDownScalar(x), scaleDownScalar(y));

  forge2d.Vector2 scaleUpVector(forge2d.Vector2 value) =>
      forge2d.Vector2(scaleUpScalar(value.x), scaleUpScalar(value.y));

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

  void unregisterWorld(LovePhysicsWorld world) {
    _worlds.remove(world);
  }
}

final class LovePhysicsWorld {
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

  final LovePhysicsState state;
  final forge2d.World _world;
  late final LovePhysicsWorldCallbackState _callbackState =
      LovePhysicsWorldCallbackState(this);
  late final LovePhysicsWorldContactFilterState _contactFilterState =
      LovePhysicsWorldContactFilterState(this);
  final List<LovePhysicsBody> _bodies = <LovePhysicsBody>[];
  bool _destroyed = false;

  bool get isDestroyed => _destroyed;

  bool get isLocked =>
      !_destroyed &&
      (_world.isLocked ||
          _callbackState.isDispatching ||
          _contactFilterState.isDispatching);

  bool get sleepingAllowed => _destroyed ? true : _world.isAllowSleep();

  ({Value? beginContact, Value? endContact, Value? preSolve, Value? postSolve})
  get callbacks => _callbackState.callbacks;

  Value? get contactFilter => _contactFilterState.callback;

  List<LovePhysicsBody> get bodies => List<LovePhysicsBody>.unmodifiable(
    _bodies.where((body) => !body.isDestroyed),
  );

  int get bodyCount => bodies.length;

  int get contactCount =>
      _destroyed ? 0 : _world.contactManager.contacts.length;

  ({double x, double y}) get gravity {
    final gravity = _world.gravity;
    return (
      x: state.scaleUpScalar(gravity.x),
      y: state.scaleUpScalar(gravity.y),
    );
  }

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

  void setGravity(double x, double y) {
    _checkActive('world');
    _world.gravity.setValues(
      state.scaleDownScalar(x),
      state.scaleDownScalar(y),
    );
  }

  void setSleepingAllowed(bool allow) {
    _checkActive('world');
    _world.setAllowSleep(allow);
  }

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

  void setContactFilter(Value? callback) {
    _checkActive('world');
    _contactFilterState.setCallback(callback);
    _contactFilterState.refilterAllFixtures();
  }

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

  void _destroyBody(LovePhysicsBody body) {
    if (_destroyed || body.isDestroyed) {
      return;
    }
    _world.destroyBody(body._body);
    _bodies.remove(body);
  }

  void _checkActive(String objectName) {
    if (_destroyed) {
      throw StateError('Attempt to use destroyed $objectName.');
    }
  }
}

final class LovePhysicsBody {
  LovePhysicsBody._({required this.world, required forge2d.Body body})
    : _body = body;

  final LovePhysicsWorld world;
  final forge2d.Body _body;
  final List<LovePhysicsFixture> _fixtures = <LovePhysicsFixture>[];
  bool _destroyed = false;
  Object? userData;

  bool get isDestroyed => _destroyed;

  LovePhysicsState get _state => world.state;

  forge2d.Body get _activeBody {
    if (_destroyed) {
      throw StateError('Attempt to use destroyed body.');
    }
    return _body;
  }

  List<LovePhysicsFixture> get fixtures =>
      List<LovePhysicsFixture>.unmodifiable(
        _fixtures.where((fixture) => !fixture.isDestroyed),
      );

  LovePhysicsFixture newFixture(LovePhysicsShape sourceShape, double density) {
    final fixture = LovePhysicsFixture._create(
      body: this,
      sourceShape: sourceShape,
      density: density,
    );
    _fixtures.add(fixture);
    return fixture;
  }

  ({double x, double y}) get position {
    final position = _activeBody.position;
    return (
      x: _state.scaleUpScalar(position.x),
      y: _state.scaleUpScalar(position.y),
    );
  }

  ({double x, double y}) get linearVelocity {
    final velocity = _activeBody.linearVelocity;
    return (
      x: _state.scaleUpScalar(velocity.x),
      y: _state.scaleUpScalar(velocity.y),
    );
  }

  ({double x, double y}) get worldCenter {
    final center = _activeBody.worldCenter;
    return (
      x: _state.scaleUpScalar(center.x),
      y: _state.scaleUpScalar(center.y),
    );
  }

  ({double x, double y}) get localCenter {
    final center = _activeBody.getLocalCenter();
    return (
      x: _state.scaleUpScalar(center.x),
      y: _state.scaleUpScalar(center.y),
    );
  }

  double get x => position.x;

  double get y => position.y;

  double get angle => _activeBody.angle;

  double get angularVelocity => _activeBody.angularVelocity;

  double get mass => _activeBody.mass;

  double get inertia => _state.scaleUpSquared(_activeBody.getInertia());

  ({double x, double y, double mass, double inertia}) get massData {
    final data = _currentMassData();
    return (
      x: _state.scaleUpScalar(data.center.x),
      y: _state.scaleUpScalar(data.center.y),
      mass: data.mass,
      inertia: _state.scaleUpSquared(data.I),
    );
  }

  double get angularDamping => _activeBody.angularDamping;

  double get linearDamping => _activeBody.linearDamping;

  double get gravityScale => _activeBody.gravityScale?.x ?? 1.0;

  String get type => _physicsBodyTypeToString(_activeBody.bodyType);

  Object? get userDataValue => userData;

  bool get isActive => _activeBody.isActive;

  bool get isAwake => _activeBody.isAwake;

  bool get isBullet => _activeBody.isBullet;

  bool get isSleepingAllowed => _activeBody.isSleepingAllowed();

  bool get isFixedRotation => _activeBody.isFixedRotation();

  bool isTouching(LovePhysicsBody other) {
    final body = _activeBody;
    final otherBody = other._activeBody;
    return body.contacts.any(
      (contact) => contact.containsBody(otherBody) && contact.isTouching(),
    );
  }

  ({double x, double y}) getLocalPoint(double worldX, double worldY) {
    final point = _activeBody.localPoint(
      _state.scaleDownVectorXY(worldX, worldY),
    );
    return (x: _state.scaleUpScalar(point.x), y: _state.scaleUpScalar(point.y));
  }

  List<({double x, double y})> getLocalPoints(
    Iterable<({double x, double y})> points,
  ) {
    return List<({double x, double y})>.unmodifiable(
      points.map((point) => getLocalPoint(point.x, point.y)),
    );
  }

  ({double x, double y}) getLocalVector(double worldX, double worldY) {
    final vector = _activeBody.localVector(
      _state.scaleDownVectorXY(worldX, worldY),
    );
    return (
      x: _state.scaleUpScalar(vector.x),
      y: _state.scaleUpScalar(vector.y),
    );
  }

  ({double x, double y}) getWorldPoint(double localX, double localY) {
    final point = _activeBody.worldPoint(
      _state.scaleDownVectorXY(localX, localY),
    );
    return (x: _state.scaleUpScalar(point.x), y: _state.scaleUpScalar(point.y));
  }

  List<({double x, double y})> getWorldPoints(
    Iterable<({double x, double y})> points,
  ) {
    return List<({double x, double y})>.unmodifiable(
      points.map((point) => getWorldPoint(point.x, point.y)),
    );
  }

  ({double x, double y}) getWorldVector(double localX, double localY) {
    final vector = _activeBody.worldVector(
      _state.scaleDownVectorXY(localX, localY),
    );
    return (
      x: _state.scaleUpScalar(vector.x),
      y: _state.scaleUpScalar(vector.y),
    );
  }

  ({double x, double y}) getLinearVelocityFromWorldPoint(double x, double y) {
    final velocity = _activeBody.linearVelocityFromWorldPoint(
      _state.scaleDownVectorXY(x, y),
    );
    return (
      x: _state.scaleUpScalar(velocity.x),
      y: _state.scaleUpScalar(velocity.y),
    );
  }

  ({double x, double y}) getLinearVelocityFromLocalPoint(double x, double y) {
    final velocity = _activeBody.linearVelocityFromLocalPoint(
      _state.scaleDownVectorXY(x, y),
    );
    return (
      x: _state.scaleUpScalar(velocity.x),
      y: _state.scaleUpScalar(velocity.y),
    );
  }

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

  void applyAngularImpulse(double impulse, {bool wake = true}) {
    if (!wake && !_activeBody.isAwake) {
      return;
    }
    if (wake && !_activeBody.isAwake) {
      _activeBody.setAwake(true);
    }
    _activeBody.applyAngularImpulse(_state.scaleDownSquared(impulse));
  }

  void applyTorque(double torque, {bool wake = true}) {
    if (!wake && !_activeBody.isAwake) {
      return;
    }
    if (wake && !_activeBody.isAwake) {
      _activeBody.setAwake(true);
    }
    _activeBody.applyTorque(_state.scaleDownSquared(torque));
  }

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

  void setX(double x) {
    _activeBody.setTransform(_state.scaleDownVectorXY(x, y), angle);
  }

  void setY(double y) {
    _activeBody.setTransform(_state.scaleDownVectorXY(x, y), angle);
  }

  void setLinearVelocity(double x, double y) {
    _activeBody.linearVelocity = _state.scaleDownVectorXY(x, y);
  }

  void setAngle(double angle) {
    _activeBody.setTransform(_activeBody.position.clone(), angle);
  }

  void setAngularVelocity(double value) {
    _activeBody.angularVelocity = value;
  }

  void setPosition(double x, double y) {
    _activeBody.setTransform(_state.scaleDownVectorXY(x, y), angle);
  }

  void resetMassData() {
    _activeBody.resetMassData();
  }

  void setMassData(double x, double y, double mass, double inertia) {
    _activeBody.setMassData(
      forge2d.MassData()
        ..center.setValues(_state.scaleDownScalar(x), _state.scaleDownScalar(y))
        ..mass = mass
        ..I = _state.scaleDownSquared(inertia),
    );
  }

  void setMass(double mass) {
    final data = _currentMassData()..mass = mass;
    _activeBody.setMassData(data);
  }

  void setInertia(double inertia) {
    final data = _currentMassData()..I = _state.scaleDownSquared(inertia);
    _activeBody.setMassData(data);
  }

  void setAngularDamping(double damping) {
    _activeBody.angularDamping = damping;
  }

  void setLinearDamping(double damping) {
    _activeBody.linearDamping = damping;
  }

  void setGravityScale(double scale) {
    _activeBody.gravityScale = forge2d.Vector2.all(scale);
  }

  void setType(String type) {
    _activeBody.setType(_physicsBodyTypeFromString(type));
  }

  void setActive(bool active) {
    _activeBody.setActive(active);
  }

  void setAwake(bool awake) {
    _activeBody.setAwake(awake);
  }

  void setBullet(bool bullet) {
    _activeBody.isBullet = bullet;
  }

  void setSleepingAllowed(bool allow) {
    _activeBody.setSleepingAllowed(allow);
  }

  void setFixedRotation(bool fixedRotation) {
    _activeBody.setFixedRotation(fixedRotation);
  }

  void setTransform(double x, double y, double angle) {
    _activeBody.setTransform(_state.scaleDownVectorXY(x, y), angle);
  }

  void setUserData(Object? value) {
    userData = value;
    _activeBody.userData = value;
  }

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

  forge2d.MassData _currentMassData() {
    return forge2d.MassData()
      ..center.setFrom(_activeBody.getLocalCenter())
      ..mass = _activeBody.mass
      ..I = _activeBody.getInertia();
  }
}

final class LovePhysicsFixture {
  LovePhysicsFixture._({
    required this.body,
    required this.shape,
    required this.density,
  });

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

  final LovePhysicsBody body;
  late final LovePhysicsShape shape;
  late forge2d.Fixture _fixture;
  bool _destroyed = false;
  double density;
  Object? userData;

  bool get isDestroyed => _destroyed;

  forge2d.Fixture get _activeFixture {
    if (_destroyed) {
      throw StateError('Attempt to use destroyed fixture.');
    }
    return _fixture;
  }

  String get type => shape.shapeTypeName;

  double get friction => _activeFixture.friction;

  double get restitution => _activeFixture.restitution;

  bool get isSensor => _activeFixture.isSensor;

  Object? get userDataValue => userData;

  ({int categories, int mask, int group}) get filterData {
    final filter = _activeFixture.filterData;
    return (
      categories: filter.categoryBits,
      mask: filter.maskBits,
      group: filter.groupIndex,
    );
  }

  List<int> get categories =>
      _physicsCategoriesFromBits(_activeFixture.filterData.categoryBits);

  List<int> get maskCategories => _physicsCategoriesFromBits(
    (~_activeFixture.filterData.maskBits) & 0xFFFF,
  );

  int get groupIndex => _activeFixture.filterData.groupIndex;

  void setFriction(double value) {
    _activeFixture.friction = value;
  }

  void setRestitution(double value) {
    _activeFixture.restitution = value;
  }

  void setSensor(bool value) {
    _activeFixture.setSensor(value);
  }

  void setUserData(Object? value) {
    userData = value;
    if (!_destroyed) {
      _fixture.userData = value;
    }
  }

  void setFilterData(int categories, int mask, int group) {
    final filter = forge2d.Filter()
      ..categoryBits = categories & 0xFFFF
      ..maskBits = mask & 0xFFFF
      ..groupIndex = group;
    _activeFixture.filterData = filter;
  }

  void setCategories(Iterable<int> values) {
    final filter = forge2d.Filter()..set(_activeFixture.filterData);
    filter.categoryBits = _physicsBitsFromCategories(values);
    _activeFixture.filterData = filter;
  }

  void setMaskCategories(Iterable<int> values) {
    final filter = forge2d.Filter()..set(_activeFixture.filterData);
    filter.maskBits = (~_physicsBitsFromCategories(values)) & 0xFFFF;
    _activeFixture.filterData = filter;
  }

  void setGroupIndex(int value) {
    final filter = forge2d.Filter()..set(_activeFixture.filterData);
    filter.groupIndex = value;
    _activeFixture.filterData = filter;
  }

  void setDensity(double value) {
    density = value;
    _rebuildUnderlyingFixture();
  }

  bool testPoint(double x, double y) {
    return _activeFixture.testPoint(body._state.scaleDownVectorXY(x, y));
  }

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

  void destroy() {
    if (_destroyed) {
      return;
    }

    body._activeBody.destroyFixture(_fixture);
    body._fixtures.remove(this);
    _markDestroyed();
  }

  void _markDestroyed() {
    _destroyed = true;
  }

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

  forge2d.FixtureDef _buildFixtureDef({required double density}) {
    return forge2d.FixtureDef(shape.toForgeShape(), density: density)
      ..userData = userData;
  }
}

abstract base class LovePhysicsShape {
  LovePhysicsShape({required this.state, LovePhysicsShapeChanged? onChanged})
    : _onChanged = onChanged;

  final LovePhysicsState state;
  LovePhysicsShapeChanged? _onChanged;

  String get objectTypeName;

  String get shapeTypeName;

  int get childCount;

  double get radius;

  LovePhysicsShape clone({LovePhysicsShapeChanged? onChanged});

  forge2d.Shape toForgeShape();

  void attach(LovePhysicsShapeChanged onChanged) {
    _onChanged = onChanged;
  }

  void markChanged() {
    _onChanged?.call();
  }

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

  bool testPoint(double x, double y, double angle, double px, double py) {
    final transform = forge2d.Transform.zero()
      ..p.setValues(state.scaleDownScalar(x), state.scaleDownScalar(y))
      ..q.setAngle(angle);
    return toForgeShape().testPoint(transform, state.scaleDownVectorXY(px, py));
  }

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

  void _checkChildIndex(int childIndex) {
    if (childIndex < 1 || childIndex > childCount) {
      throw StateError('Physics error: index out of bounds');
    }
  }
}

final class LovePhysicsCircleShape extends LovePhysicsShape {
  LovePhysicsCircleShape({
    required super.state,
    super.onChanged,
    required forge2d.Vector2 center,
    required double radius,
  }) : _center = center.clone(),
       _radius = radius;

  final forge2d.Vector2 _center;
  double _radius;

  @override
  String get objectTypeName => 'CircleShape';

  @override
  String get shapeTypeName => 'circle';

  @override
  int get childCount => 1;

  @override
  double get radius => state.scaleUpScalar(_radius);

  ({double x, double y}) get point =>
      (x: state.scaleUpScalar(_center.x), y: state.scaleUpScalar(_center.y));

  void setRadius(double radius) {
    _radius = state.scaleDownScalar(radius);
    markChanged();
  }

  void setPoint(double x, double y) {
    _center.setValues(state.scaleDownScalar(x), state.scaleDownScalar(y));
    markChanged();
  }

  @override
  LovePhysicsCircleShape clone({LovePhysicsShapeChanged? onChanged}) {
    return LovePhysicsCircleShape(
      state: state,
      onChanged: onChanged,
      center: _center,
      radius: _radius,
    );
  }

  @override
  forge2d.CircleShape toForgeShape() {
    return forge2d.CircleShape(position: _center.clone(), radius: _radius);
  }
}

final class LovePhysicsPolygonShape extends LovePhysicsShape {
  LovePhysicsPolygonShape({
    required super.state,
    super.onChanged,
    required Iterable<forge2d.Vector2> vertices,
  }) : _vertices = List<forge2d.Vector2>.unmodifiable(
         vertices.map((vertex) => vertex.clone()),
       );

  final List<forge2d.Vector2> _vertices;

  @override
  String get objectTypeName => 'PolygonShape';

  @override
  String get shapeTypeName => 'polygon';

  @override
  int get childCount => 1;

  @override
  double get radius => state.scaleUpScalar(forge2d.polygonRadius);

  List<({double x, double y})> get points =>
      List<({double x, double y})>.unmodifiable(
        _vertices.map(
          (vertex) => (
            x: state.scaleUpScalar(vertex.x),
            y: state.scaleUpScalar(vertex.y),
          ),
        ),
      );

  bool validate() {
    return toForgeShape().validate();
  }

  @override
  LovePhysicsPolygonShape clone({LovePhysicsShapeChanged? onChanged}) {
    return LovePhysicsPolygonShape(
      state: state,
      onChanged: onChanged,
      vertices: _vertices,
    );
  }

  @override
  forge2d.PolygonShape toForgeShape() {
    final shape = forge2d.PolygonShape();
    shape.set(
      _vertices.map((vertex) => vertex.clone()).toList(growable: false),
    );
    return shape;
  }
}

final class LovePhysicsEdgeShape extends LovePhysicsShape {
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

  final forge2d.Vector2 _vertex1;
  final forge2d.Vector2 _vertex2;
  forge2d.Vector2? _previousVertex;
  forge2d.Vector2? _nextVertex;

  @override
  String get objectTypeName => 'EdgeShape';

  @override
  String get shapeTypeName => 'edge';

  @override
  int get childCount => 1;

  @override
  double get radius => state.scaleUpScalar(forge2d.polygonRadius);

  List<({double x, double y})> get points => <({double x, double y})>[
    (x: state.scaleUpScalar(_vertex1.x), y: state.scaleUpScalar(_vertex1.y)),
    (x: state.scaleUpScalar(_vertex2.x), y: state.scaleUpScalar(_vertex2.y)),
  ];

  ({double x, double y})? get nextVertex => _nextVertex == null
      ? null
      : (
          x: state.scaleUpScalar(_nextVertex!.x),
          y: state.scaleUpScalar(_nextVertex!.y),
        );

  ({double x, double y})? get previousVertex => _previousVertex == null
      ? null
      : (
          x: state.scaleUpScalar(_previousVertex!.x),
          y: state.scaleUpScalar(_previousVertex!.y),
        );

  void setNextVertex([double? x, double? y]) {
    if (x == null || y == null) {
      _nextVertex = null;
    } else {
      _nextVertex = state.scaleDownVectorXY(x, y);
    }
    markChanged();
  }

  void setPreviousVertex([double? x, double? y]) {
    if (x == null || y == null) {
      _previousVertex = null;
    } else {
      _previousVertex = state.scaleDownVectorXY(x, y);
    }
    markChanged();
  }

  @override
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

final class LovePhysicsChainShape extends LovePhysicsShape {
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

  final List<forge2d.Vector2> _vertices;
  final bool _loop;
  forge2d.Vector2? _previousVertex;
  forge2d.Vector2? _nextVertex;

  @override
  String get objectTypeName => 'ChainShape';

  @override
  String get shapeTypeName => 'chain';

  @override
  int get childCount => _vertices.length - 1;

  @override
  double get radius => state.scaleUpScalar(forge2d.polygonRadius);

  int get vertexCount => _vertices.length;

  ({double x, double y})? get nextVertex => _nextVertex == null
      ? null
      : (
          x: state.scaleUpScalar(_nextVertex!.x),
          y: state.scaleUpScalar(_nextVertex!.y),
        );

  ({double x, double y})? get previousVertex => _previousVertex == null
      ? null
      : (
          x: state.scaleUpScalar(_previousVertex!.x),
          y: state.scaleUpScalar(_previousVertex!.y),
        );

  List<({double x, double y})> get points =>
      List<({double x, double y})>.unmodifiable(
        _vertices.map(
          (vertex) => (
            x: state.scaleUpScalar(vertex.x),
            y: state.scaleUpScalar(vertex.y),
          ),
        ),
      );

  ({double x, double y}) pointAt(int index) {
    if (index < 1 || index > _vertices.length) {
      throw StateError('Physics error: index out of bounds');
    }
    final vertex = _vertices[index - 1];
    return (x: state.scaleUpScalar(vertex.x), y: state.scaleUpScalar(vertex.y));
  }

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

  void setNextVertex([double? x, double? y]) {
    if (x == null || y == null) {
      _nextVertex = null;
    } else {
      _nextVertex = state.scaleDownVectorXY(x, y);
    }
    markChanged();
  }

  void setPreviousVertex([double? x, double? y]) {
    if (x == null || y == null) {
      _previousVertex = null;
    } else {
      _previousVertex = state.scaleDownVectorXY(x, y);
    }
    markChanged();
  }

  @override
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

forge2d.BodyType _physicsBodyTypeFromString(String type) {
  return switch (type) {
    'static' => forge2d.BodyType.static,
    'dynamic' => forge2d.BodyType.dynamic,
    'kinematic' => forge2d.BodyType.kinematic,
    _ => throw StateError('Unknown body type: $type'),
  };
}

String _physicsBodyTypeToString(forge2d.BodyType type) {
  return switch (type) {
    forge2d.BodyType.static => 'static',
    forge2d.BodyType.dynamic => 'dynamic',
    forge2d.BodyType.kinematic => 'kinematic',
  };
}

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

List<int> _physicsCategoriesFromBits(int bits) {
  final categories = <int>[];
  for (var index = 0; index < 16; index++) {
    if ((bits & (1 << index)) != 0) {
      categories.add(index + 1);
    }
  }
  return List<int>.unmodifiable(categories);
}

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
