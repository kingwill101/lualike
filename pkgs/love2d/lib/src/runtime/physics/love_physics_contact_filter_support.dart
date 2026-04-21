part of '../love_runtime.dart';

final class LovePhysicsWorldContactFilterState {
  LovePhysicsWorldContactFilterState(this.world)
    : filter = _LovePhysicsContactFilter._(world);

  final LovePhysicsWorld world;
  final forge2d.ContactFilter filter;
  final Map<(LovePhysicsFixture, LovePhysicsFixture), bool> _pairDecisions =
      <(LovePhysicsFixture, LovePhysicsFixture), bool>{};

  Value? _callback;
  bool _isDispatching = false;

  Value? get callback => _callback;

  bool get isDispatching => _isDispatching;

  void setCallback(Value? callback) {
    _callback = callback;
    _pairDecisions.clear();
  }

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

    _isDispatching = true;
    try {
      for (var i = 0; i < fixtures.length; i++) {
        final fixtureA = fixtures[i];
        final bodyA = fixtureA.body;
        for (var j = i + 1; j < fixtures.length; j++) {
          final fixtureB = fixtures[j];
          final bodyB = fixtureB.body;

          if (identical(bodyA, bodyB)) {
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
          if (
            !_physicsFixturesMayOverlapDuringStep(
              fixtureA,
              fixtureB,
              dt,
            )
          ) {
            continue;
          }

          final decision = await evaluator(fixtureA, fixtureB);
          _pairDecisions[(fixtureA, fixtureB)] = decision;
          _pairDecisions[(fixtureB, fixtureA)] = decision;
        }
      }
    } finally {
      _isDispatching = false;
    }
  }

  bool? decisionFor(forge2d.Fixture fixtureA, forge2d.Fixture fixtureB) {
    if (_callback == null) {
      return null;
    }

    final loveFixtureA = world.fixtureForContact(fixtureA);
    final loveFixtureB = world.fixtureForContact(fixtureB);
    return _pairDecisions[(loveFixtureA, loveFixtureB)];
  }

  void refilterAllFixtures() {
    for (final body in world.bodies) {
      for (final fixture in body.fixtures) {
        fixture._fixture.refilter();
      }
    }
  }

  void dispose() {
    _pairDecisions.clear();
    _callback = null;
    _isDispatching = false;
  }
}

final class _LovePhysicsContactFilter extends forge2d.ContactFilter {
  _LovePhysicsContactFilter._(this.world);

  final LovePhysicsWorld world;

  @override
  bool shouldCollide(forge2d.Fixture fixtureA, forge2d.Fixture fixtureB) {
    final defaultDecision = super.shouldCollide(fixtureA, fixtureB);
    if (!defaultDecision) {
      return false;
    }

    return world._contactFilterState.decisionFor(fixtureA, fixtureB) ?? true;
  }
}

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
    final boxA = fixtureA._fixture.getAABB(childIndexA);
    final sweptA = _physicsSweptAabb(
      boxA,
      fixtureA.body._activeBody.linearVelocity,
      dt,
    );
    for (
      var childIndexB = 0;
      childIndexB < fixtureB.shape.childCount;
      childIndexB++
    ) {
      final boxB = fixtureB._fixture.getAABB(childIndexB);
      final sweptB = _physicsSweptAabb(
        boxB,
        fixtureB.body._activeBody.linearVelocity,
        dt,
      );
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

({double minX, double minY, double maxX, double maxY}) _physicsSweptAabb(
  forge2d.AABB box,
  forge2d.Vector2 linearVelocity,
  double dt,
) {
  final deltaX = linearVelocity.x * dt;
  final deltaY = linearVelocity.y * dt;
  final minX = box.lowerBound.x;
  final minY = box.lowerBound.y;
  final maxX = box.upperBound.x;
  final maxY = box.upperBound.y;
  return (
    minX: math.min(minX, minX + deltaX),
    minY: math.min(minY, minY + deltaY),
    maxX: math.max(maxX, maxX + deltaX),
    maxY: math.max(maxY, maxY + deltaY),
  );
}
