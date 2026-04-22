part of '../love_runtime.dart';

/// Contact-filter state for a physics world.
final class LovePhysicsWorldContactFilterState {
  /// Creates contact-filter state for [world].
  LovePhysicsWorldContactFilterState(this.world)
    : filter = _LovePhysicsContactFilter._(world);

  /// The world that owns this contact filter.
  final LovePhysicsWorld world;

  /// The forge2d contact filter installed on [world].
  final forge2d.ContactFilter filter;

  /// Cached pair decisions prepared before stepping.
  final Map<(LovePhysicsFixture, LovePhysicsFixture), bool> _pairDecisions =
      <(LovePhysicsFixture, LovePhysicsFixture), bool>{};

  /// The Lua contact-filter callback, if one is registered.
  Value? _callback;

  /// The number of nested filter-dispatch operations in progress.
  int _dispatchDepth = 0;

  /// An optional synchronous contact-filter evaluator used during stepping.
  bool Function(LovePhysicsFixture fixtureA, LovePhysicsFixture fixtureB)?
  _syncEvaluator;

  /// The registered Lua contact-filter callback.
  Value? get callback => _callback;

  /// Whether a contact filter callback is currently being dispatched.
  bool get isDispatching => _dispatchDepth > 0;

  /// Replaces the registered Lua contact-filter [callback].
  void setCallback(Value? callback) {
    _callback = callback;
    _pairDecisions.clear();
  }

  /// Sets the synchronous contact-filter [evaluator].
  void setSyncEvaluator(
    bool Function(LovePhysicsFixture fixtureA, LovePhysicsFixture fixtureB)?
    evaluator,
  ) {
    _syncEvaluator = evaluator;
  }

  /// Precomputes contact-filter decisions for fixture pairs that may overlap
  /// during the next step of length [dt].
  Future<void> prepareDecisions(
    double dt,
    Future<bool> Function(
      LovePhysicsFixture fixtureA,
      LovePhysicsFixture fixtureB,
    )
    evaluator,
  ) async {
    _pairDecisions.clear();
    if (_callback == null) {
      return;
    }

    final fixtures = <LovePhysicsFixture>[
      for (final body in world.bodies) ...body.fixtures,
    ];

    _dispatchDepth++;
    try {
      for (var i = 0; i < fixtures.length; i++) {
        final fixtureA = fixtures[i];
        final bodyA = fixtureA.body;
        if (!bodyA._activeBody.isActive) {
          continue;
        }
        for (var j = i + 1; j < fixtures.length; j++) {
          final fixtureB = fixtures[j];
          final bodyB = fixtureB.body;

          if (identical(bodyA, bodyB)) {
            continue;
          }
          if (!bodyB._activeBody.isActive) {
            continue;
          }
          if (!bodyA._body.shouldCollide(bodyB._body)) {
            continue;
          }
          if (!_physicsDefaultShouldCollide(
            fixtureA._fixture,
            fixtureB._fixture,
          )) {
            continue;
          }
          if (!_physicsFixturesMayOverlapDuringStep(fixtureA, fixtureB, dt)) {
            continue;
          }

          final decision = await evaluator(fixtureA, fixtureB);
          _pairDecisions[(fixtureA, fixtureB)] = decision;
          _pairDecisions[(fixtureB, fixtureA)] = decision;
        }
      }
    } finally {
      _dispatchDepth--;
    }
  }

  /// Evaluates the contact filter synchronously for forge2d fixtures.
  ///
  /// Returns `null` when no synchronous evaluator is installed.
  bool? evaluateSync(forge2d.Fixture fixtureA, forge2d.Fixture fixtureB) {
    final evaluator = _syncEvaluator;
    if (evaluator == null || _callback == null) {
      return null;
    }

    _dispatchDepth++;
    try {
      return evaluator(
        world.fixtureForContact(fixtureA),
        world.fixtureForContact(fixtureB),
      );
    } finally {
      _dispatchDepth--;
    }
  }

  /// Returns the prepared decision for a fixture pair, if one exists.
  bool? decisionFor(forge2d.Fixture fixtureA, forge2d.Fixture fixtureB) {
    if (_callback == null) {
      return null;
    }

    final loveFixtureA = world.fixtureForContact(fixtureA);
    final loveFixtureB = world.fixtureForContact(fixtureB);
    return _pairDecisions[(loveFixtureA, loveFixtureB)];
  }

  /// Requests refiltering for every fixture in the world.
  void refilterAllFixtures() {
    for (final body in world.bodies) {
      for (final fixture in body.fixtures) {
        fixture._fixture.refilter();
      }
    }
  }

  /// Disposes filter state and clears cached decisions.
  void dispose() {
    _pairDecisions.clear();
    _callback = null;
    _syncEvaluator = null;
    _dispatchDepth = 0;
  }
}

/// A forge2d contact filter that consults LOVE's world contact-filter state.
final class _LovePhysicsContactFilter extends forge2d.ContactFilter {
  /// Creates a contact filter for [world].
  _LovePhysicsContactFilter._(this.world);

  /// The world whose filter state drives collision decisions.
  final LovePhysicsWorld world;

  @override
  /// Returns whether [fixtureA] and [fixtureB] should collide.
  bool shouldCollide(forge2d.Fixture fixtureA, forge2d.Fixture fixtureB) {
    final defaultDecision = super.shouldCollide(fixtureA, fixtureB);
    if (!defaultDecision) {
      return false;
    }

    final directDecision = world._contactFilterState.evaluateSync(
      fixtureA,
      fixtureB,
    );
    if (directDecision != null) {
      return directDecision;
    }

    return world._contactFilterState.decisionFor(fixtureA, fixtureB) ?? true;
  }
}

/// Returns the default forge2d-style collision decision for a fixture pair.
bool _physicsDefaultShouldCollide(
  forge2d.Fixture fixtureA,
  forge2d.Fixture fixtureB,
) {
  final filterA = fixtureA.filterData;
  final filterB = fixtureB.filterData;

  if (filterA.groupIndex == filterB.groupIndex && filterA.groupIndex != 0) {
    return filterA.groupIndex > 0;
  }

  return ((filterA.maskBits & filterB.categoryBits) != 0) &&
      ((filterA.categoryBits & filterB.maskBits) != 0);
}

/// Returns whether [fixtureA] and [fixtureB] may overlap during the next step
/// of length [dt].
bool _physicsFixturesMayOverlapDuringStep(
  LovePhysicsFixture fixtureA,
  LovePhysicsFixture fixtureB,
  double dt,
) {
  for (
    var childIndexA = 0;
    childIndexA < fixtureA.shape.childCount;
    childIndexA++
  ) {
    final sweptA = _physicsFixtureStepAabb(fixtureA, childIndexA, dt);
    for (
      var childIndexB = 0;
      childIndexB < fixtureB.shape.childCount;
      childIndexB++
    ) {
      final sweptB = _physicsFixtureStepAabb(fixtureB, childIndexB, dt);
      if (_physicsAabbOverlaps(
        minX: sweptA.minX,
        minY: sweptA.minY,
        maxX: sweptA.maxX,
        maxY: sweptA.maxY,
        otherMinX: sweptB.minX,
        otherMinY: sweptB.minY,
        otherMaxX: sweptB.maxX,
        otherMaxY: sweptB.maxY,
      )) {
        return true;
      }
    }
  }

  return false;
}

/// Sample fractions used to approximate swept fixture overlap during one step.
const List<double> _physicsStepOverlapSampleFractions = <double>[
  0.0,
  0.25,
  0.5,
  0.75,
  1.0,
];

/// Returns an approximate swept AABB for [fixture] child [childIndex] over a
/// time step of [dt].
({double minX, double minY, double maxX, double maxY}) _physicsFixtureStepAabb(
  LovePhysicsFixture fixture,
  int childIndex,
  double dt,
) {
  final rawFixture = fixture._fixture;
  if (dt <= 0) {
    final current = forge2d.AABB();
    rawFixture.shape.computeAABB(
      current,
      fixture.body._activeBody.transform,
      childIndex,
    );
    return (
      minX: current.lowerBound.x,
      minY: current.lowerBound.y,
      maxX: current.upperBound.x,
      maxY: current.upperBound.y,
    );
  }

  final body = fixture.body._activeBody;
  double? minX;
  double? minY;
  double? maxX;
  double? maxY;

  for (final fraction in _physicsStepOverlapSampleFractions) {
    final sample = forge2d.AABB();
    rawFixture.shape.computeAABB(
      sample,
      fraction == 0
          ? body.transform
          : _physicsPredictBodyTransform(body, dt * fraction),
      childIndex,
    );
    minX = minX == null
        ? sample.lowerBound.x
        : math.min(minX, sample.lowerBound.x);
    minY = minY == null
        ? sample.lowerBound.y
        : math.min(minY, sample.lowerBound.y);
    maxX = maxX == null
        ? sample.upperBound.x
        : math.max(maxX, sample.upperBound.x);
    maxY = maxY == null
        ? sample.upperBound.y
        : math.max(maxY, sample.upperBound.y);
  }

  return (minX: minX!, minY: minY!, maxX: maxX!, maxY: maxY!);
}

/// Predicts the body transform after advancing [body] by [dt] seconds.
forge2d.Transform _physicsPredictBodyTransform(forge2d.Body body, double dt) {
  final worldCenter = body.worldCenter.clone();
  final linearVelocity = body.linearVelocity.clone();
  var angularVelocity = body.angularVelocity;

  if (body.bodyType == forge2d.BodyType.dynamic) {
    final gravity = body.gravityOverride ?? body.world.gravity;
    linearVelocity.x +=
        dt *
        ((body.gravityScale?.x ?? 1) * gravity.x +
            body.inverseMass * body.force.x);
    linearVelocity.y +=
        dt *
        ((body.gravityScale?.y ?? 1) * gravity.y +
            body.inverseMass * body.force.y);
    angularVelocity += dt * body.inverseInertia * body.torque;

    final linearDamping = 1.0 / (1.0 + dt * body.linearDamping);
    linearVelocity.x *= linearDamping;
    linearVelocity.y *= linearDamping;
    angularVelocity *= 1.0 / (1.0 + dt * body.angularDamping);
  }

  worldCenter.x += dt * linearVelocity.x;
  worldCenter.y += dt * linearVelocity.y;
  final angle = body.angle + (dt * angularVelocity);

  final transform = forge2d.Transform.zero()..q.setAngle(angle);
  final localCenter = body.getLocalCenter();
  transform.p.setValues(
    worldCenter.x -
        (transform.q.cos * localCenter.x) +
        (transform.q.sin * localCenter.y),
    worldCenter.y -
        (transform.q.sin * localCenter.x) -
        (transform.q.cos * localCenter.y),
  );
  return transform;
}
