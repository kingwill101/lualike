part of '../love_runtime.dart';

/// Per-world registry of wrapped LOVE joints.
final Expando<List<LovePhysicsJoint>> _lovePhysicsJointRegistry =
    Expando<List<LovePhysicsJoint>>('love2dPhysicsJoints');

/// Per-world synthetic ground body used by mouse joints.
final Expando<forge2d.Body> _lovePhysicsMouseJointGroundBodyRegistry =
    Expando<forge2d.Body>('love2dPhysicsMouseJointGroundBody');

/// The default spring frequency used for mouse joints.
const double _lovePhysicsMouseJointDefaultFrequency = 5.0;

/// The default damping ratio used for mouse joints.
const double _lovePhysicsMouseJointDefaultDampingRatio = 0.7;

/// A small epsilon used for floating-point pulley calculations.
const double _lovePhysicsFloatEpsilon = 1.1920928955078125e-7;

/// Returns the mutable joint registry for [world].
List<LovePhysicsJoint> _lovePhysicsJointsForWorld(LovePhysicsWorld world) {
  return _lovePhysicsJointRegistry[world] ??= <LovePhysicsJoint>[];
}

/// Marks all joints in [world] as destroyed and clears the registry.
void _disposeLovePhysicsJoints(LovePhysicsWorld world) {
  final joints = _lovePhysicsJointRegistry[world];
  if (joints == null) {
    return;
  }

  for (final joint in joints) {
    joint._markDestroyed();
  }
  joints.clear();
}

/// Adds joint accessors and joint factories to physics worlds.
extension LovePhysicsWorldJointAccess on LovePhysicsWorld {
  /// The active joints currently owned by this world.
  List<LovePhysicsJoint> get joints {
    _checkActive('world');
    final joints = _lovePhysicsJointsForWorld(this);
    joints.removeWhere((joint) => joint.isDestroyed);
    return List<LovePhysicsJoint>.unmodifiable(joints);
  }

  /// The number of active joints in this world.
  int get jointCount => joints.length;

  /// Creates a new distance joint between [bodyA] and [bodyB].
  LovePhysicsDistanceJoint newDistanceJoint({
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    bool collideConnected = false,
  }) {
    _checkActive('world');
    bodyA._activeBody;
    bodyB._activeBody;
    if (!identical(bodyA.world, this) || !identical(bodyB.world, this)) {
      throw ArgumentError('Bodies must belong to the same world.');
    }
    if (identical(bodyA, bodyB)) {
      throw ArgumentError('Bodies must be different.');
    }

    final joint = LovePhysicsDistanceJoint._create(
      world: this,
      bodyA: bodyA,
      bodyB: bodyB,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      collideConnected: collideConnected,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new friction joint between [bodyA] and [bodyB].
  LovePhysicsFrictionJoint newFrictionJoint({
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    bool collideConnected = false,
  }) {
    _checkActive('world');
    bodyA._activeBody;
    bodyB._activeBody;
    if (!identical(bodyA.world, this) || !identical(bodyB.world, this)) {
      throw ArgumentError('Bodies must belong to the same world.');
    }
    if (identical(bodyA, bodyB)) {
      throw ArgumentError('Bodies must be different.');
    }

    final joint = LovePhysicsFrictionJoint._create(
      world: this,
      bodyA: bodyA,
      bodyB: bodyB,
      xA: xA,
      yA: yA,
      xB: xB,
      yB: yB,
      collideConnected: collideConnected,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new rope joint between [bodyA] and [bodyB].
  LovePhysicsRopeJoint newRopeJoint({
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double maxLength,
    bool collideConnected = false,
  }) {
    _checkActive('world');
    bodyA._activeBody;
    bodyB._activeBody;
    if (!identical(bodyA.world, this) || !identical(bodyB.world, this)) {
      throw ArgumentError('Bodies must belong to the same world.');
    }
    if (identical(bodyA, bodyB)) {
      throw ArgumentError('Bodies must be different.');
    }

    final joint = LovePhysicsRopeJoint._create(
      world: this,
      bodyA: bodyA,
      bodyB: bodyB,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      maxLength: maxLength,
      collideConnected: collideConnected,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new weld joint between [bodyA] and [bodyB].
  LovePhysicsWeldJoint newWeldJoint({
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    bool collideConnected = false,
    double? referenceAngle,
  }) {
    _checkActive('world');
    bodyA._activeBody;
    bodyB._activeBody;
    if (!identical(bodyA.world, this) || !identical(bodyB.world, this)) {
      throw ArgumentError('Bodies must belong to the same world.');
    }
    if (identical(bodyA, bodyB)) {
      throw ArgumentError('Bodies must be different.');
    }

    final joint = LovePhysicsWeldJoint._create(
      world: this,
      bodyA: bodyA,
      bodyB: bodyB,
      xA: xA,
      yA: yA,
      xB: xB,
      yB: yB,
      collideConnected: collideConnected,
      referenceAngle: referenceAngle,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new mouse joint attached to [body].
  LovePhysicsMouseJoint newMouseJoint({
    required LovePhysicsBody body,
    required double x,
    required double y,
  }) {
    _checkActive('world');
    final rawBody = body._activeBody;
    if (!identical(body.world, this)) {
      throw ArgumentError('Body must belong to the same world.');
    }
    if (rawBody.bodyType == forge2d.BodyType.kinematic) {
      throw StateError('Cannot attach a MouseJoint to a kinematic body');
    }

    final joint = LovePhysicsMouseJoint._create(
      world: this,
      body: body,
      x: x,
      y: y,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new gear joint coupling [jointA] and [jointB].
  LovePhysicsGearJoint newGearJoint({
    required LovePhysicsJoint jointA,
    required LovePhysicsJoint jointB,
    double ratio = 1,
    bool collideConnected = false,
  }) {
    _checkActive('world');
    jointA._activeJoint;
    jointB._activeJoint;
    if (!identical(jointA.world, this) || !identical(jointB.world, this)) {
      throw ArgumentError('Joints must belong to the same world.');
    }
    if ((jointA is! LovePhysicsRevoluteJoint &&
            jointA is! LovePhysicsPrismaticJoint) ||
        (jointB is! LovePhysicsRevoluteJoint &&
            jointB is! LovePhysicsPrismaticJoint)) {
      throw StateError('GearJoint requires revolute or prismatic joints.');
    }

    final joint = LovePhysicsGearJoint._create(
      world: this,
      jointA: jointA,
      jointB: jointB,
      ratio: ratio,
      collideConnected: collideConnected,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new pulley joint between [bodyA] and [bodyB].
  LovePhysicsPulleyJoint newPulleyJoint({
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double gx1,
    required double gy1,
    required double gx2,
    required double gy2,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    double ratio = 1,
    bool collideConnected = true,
  }) {
    _checkActive('world');
    bodyA._activeBody;
    bodyB._activeBody;
    if (!identical(bodyA.world, this) || !identical(bodyB.world, this)) {
      throw ArgumentError('Bodies must belong to the same world.');
    }
    if (identical(bodyA, bodyB)) {
      throw ArgumentError('Bodies must be different.');
    }

    final joint = LovePhysicsPulleyJoint._create(
      world: this,
      bodyA: bodyA,
      bodyB: bodyB,
      gx1: gx1,
      gy1: gy1,
      gx2: gx2,
      gy2: gy2,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      ratio: ratio,
      collideConnected: collideConnected,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new motor joint between [bodyA] and [bodyB].
  LovePhysicsMotorJoint newMotorJoint({
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    double correctionFactor = 0.3,
    bool collideConnected = false,
  }) {
    _checkActive('world');
    bodyA._activeBody;
    bodyB._activeBody;
    if (!identical(bodyA.world, this) || !identical(bodyB.world, this)) {
      throw ArgumentError('Bodies must belong to the same world.');
    }
    if (identical(bodyA, bodyB)) {
      throw ArgumentError('Bodies must be different.');
    }

    final joint = LovePhysicsMotorJoint._create(
      world: this,
      bodyA: bodyA,
      bodyB: bodyB,
      correctionFactor: correctionFactor,
      collideConnected: collideConnected,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new revolute joint between [bodyA] and [bodyB].
  LovePhysicsRevoluteJoint newRevoluteJoint({
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    bool collideConnected = false,
    double? referenceAngle,
  }) {
    _checkActive('world');
    bodyA._activeBody;
    bodyB._activeBody;
    if (!identical(bodyA.world, this) || !identical(bodyB.world, this)) {
      throw ArgumentError('Bodies must belong to the same world.');
    }
    if (identical(bodyA, bodyB)) {
      throw ArgumentError('Bodies must be different.');
    }

    final joint = LovePhysicsRevoluteJoint._create(
      world: this,
      bodyA: bodyA,
      bodyB: bodyB,
      xA: xA,
      yA: yA,
      xB: xB,
      yB: yB,
      collideConnected: collideConnected,
      referenceAngle: referenceAngle,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new wheel joint between [bodyA] and [bodyB].
  LovePhysicsWheelJoint newWheelJoint({
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    required double ax,
    required double ay,
    bool collideConnected = false,
  }) {
    _checkActive('world');
    bodyA._activeBody;
    bodyB._activeBody;
    if (!identical(bodyA.world, this) || !identical(bodyB.world, this)) {
      throw ArgumentError('Bodies must belong to the same world.');
    }
    if (identical(bodyA, bodyB)) {
      throw ArgumentError('Bodies must be different.');
    }

    final joint = LovePhysicsWheelJoint._create(
      world: this,
      bodyA: bodyA,
      bodyB: bodyB,
      xA: xA,
      yA: yA,
      xB: xB,
      yB: yB,
      ax: ax,
      ay: ay,
      collideConnected: collideConnected,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Creates a new prismatic joint between [bodyA] and [bodyB].
  LovePhysicsPrismaticJoint newPrismaticJoint({
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    required double ax,
    required double ay,
    bool collideConnected = false,
    double? referenceAngle,
  }) {
    _checkActive('world');
    bodyA._activeBody;
    bodyB._activeBody;
    if (!identical(bodyA.world, this) || !identical(bodyB.world, this)) {
      throw ArgumentError('Bodies must belong to the same world.');
    }
    if (identical(bodyA, bodyB)) {
      throw ArgumentError('Bodies must be different.');
    }

    final joint = LovePhysicsPrismaticJoint._create(
      world: this,
      bodyA: bodyA,
      bodyB: bodyB,
      xA: xA,
      yA: yA,
      xB: xB,
      yB: yB,
      ax: ax,
      ay: ay,
      collideConnected: collideConnected,
      referenceAngle: referenceAngle,
    );
    _lovePhysicsJointsForWorld(this).add(joint);
    return joint;
  }

  /// Removes [joint] from this world's registry.
  void _unregisterJoint(LovePhysicsJoint joint) {
    _lovePhysicsJointRegistry[this]?.remove(joint);
  }

  /// The synthetic static ground body used by mouse joints.
  forge2d.Body get _mouseJointGroundBody {
    _checkActive('world');
    final existing = _lovePhysicsMouseJointGroundBodyRegistry[this];
    if (existing != null) {
      return existing;
    }

    final groundBody = _world.createBody(forge2d.BodyDef());
    _lovePhysicsMouseJointGroundBodyRegistry[this] = groundBody;
    return groundBody;
  }
}

/// Adds joint accessors to physics bodies.
extension LovePhysicsBodyJointAccess on LovePhysicsBody {
  /// The joints attached to this body.
  List<LovePhysicsJoint> get joints {
    _activeBody;
    return List<LovePhysicsJoint>.unmodifiable(
      world.joints.where(
        (joint) => identical(joint.bodyA, this) || identical(joint.bodyB, this),
      ),
    );
  }
}

/// Base class for LOVE physics joints.
abstract base class LovePhysicsJoint {
  /// Creates a wrapped joint between [bodyA] and [bodyB].
  LovePhysicsJoint._({
    required this.world,
    required this.bodyA,
    required this.bodyB,
    required bool collideConnected,
  }) : _collideConnected = collideConnected;

  /// The world that owns this joint.
  final LovePhysicsWorld world;

  /// The first body attached to this joint.
  final LovePhysicsBody bodyA;

  /// The second body attached to this joint.
  final LovePhysicsBody bodyB;

  /// Whether the connected bodies should collide.
  final bool _collideConnected;

  /// The underlying forge2d joint, when active.
  forge2d.Joint? _joint;

  /// Whether this joint has been destroyed.
  bool _destroyed = false;

  /// Arbitrary user data associated with this joint.
  Object? userData;

  /// The LOVE object type name.
  String get objectType;

  /// The LOVE joint type name.
  String get jointType;

  /// The first body exposed to Lua.
  LovePhysicsBody get luaBodyA => bodyA;

  /// The second body exposed to Lua.
  LovePhysicsBody? get luaBodyB => bodyB;

  /// Whether this joint has been destroyed.
  bool get isDestroyed {
    if (_destroyed || world.isDestroyed) {
      return true;
    }

    final joint = _joint;
    if (joint == null || !world._world.joints.contains(joint)) {
      _markDestroyed();
    }
    return _destroyed;
  }

  /// The active underlying joint, or throws when destroyed.
  forge2d.Joint get _activeJoint {
    if (isDestroyed) {
      throw StateError('Attempt to use destroyed joint.');
    }
    return _joint!;
  }

  /// The joint anchors in LOVE units.
  ({double x1, double y1, double x2, double y2}) get anchors {
    final joint = _activeJoint;
    final anchorA = joint.anchorA;
    final anchorB = joint.anchorB;
    return (
      x1: world.state.scaleUpScalar(anchorA.x),
      y1: world.state.scaleUpScalar(anchorA.y),
      x2: world.state.scaleUpScalar(anchorB.x),
      y2: world.state.scaleUpScalar(anchorB.y),
    );
  }

  /// The reaction force in LOVE units for the inverse timestep [invDt].
  ({double x, double y}) reactionForce(double invDt) {
    final force = _activeJoint.reactionForce(invDt);
    return (
      x: world.state.scaleUpScalar(force.x),
      y: world.state.scaleUpScalar(force.y),
    );
  }

  /// The reaction torque in LOVE units for the inverse timestep [invDt].
  double reactionTorque(double invDt) {
    return world.state.scaleUpSquared(_activeJoint.reactionTorque(invDt));
  }

  /// Whether the connected bodies collide.
  bool get collideConnected => _activeJoint.collideConnected;

  /// The arbitrary user data associated with this joint.
  Object? get userDataValue {
    _activeJoint;
    return userData;
  }

  /// Associates arbitrary [value] with this joint.
  void setUserData(Object? value) {
    _activeJoint;
    userData = value;
  }

  /// Destroys this joint.
  void destroy() {
    if (_destroyed) {
      return;
    }

    final joint = _joint;
    world._unregisterJoint(this);
    _markDestroyed();
    if (!world.isDestroyed && joint != null) {
      world._world.destroyJoint(joint);
    }
  }

  /// Replaces the underlying forge2d joint with [joint].
  void _replaceJoint(forge2d.Joint joint) {
    final previous = _joint;
    if (previous != null) {
      world._world.destroyJoint(previous);
    }
    _joint = joint;
    world._world.createJoint(joint);
  }

  /// Marks this joint as destroyed.
  void _markDestroyed() {
    _destroyed = true;
    _joint = null;
  }
}

/// A LOVE distance joint.
final class LovePhysicsDistanceJoint extends LovePhysicsJoint {
  /// Creates a stored distance joint.
  LovePhysicsDistanceJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required forge2d.Vector2 localAnchorA,
    required forge2d.Vector2 localAnchorB,
    required double length,
    required double frequency,
    required double dampingRatio,
    required super.collideConnected,
  }) : _localAnchorA = localAnchorA,
       _localAnchorB = localAnchorB,
       _length = length,
       _frequency = frequency,
       _dampingRatio = dampingRatio,
       super._();

  /// Creates and initializes a distance joint from world-space anchors.
  factory LovePhysicsDistanceJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required bool collideConnected,
  }) {
    final anchorA = world.state.scaleDownVectorXY(x1, y1);
    final anchorB = world.state.scaleDownVectorXY(x2, y2);
    final joint = LovePhysicsDistanceJoint._(
      world: world,
      bodyA: bodyA,
      bodyB: bodyB,
      localAnchorA: bodyA._activeBody.localPoint(anchorA).clone(),
      localAnchorB: bodyB._activeBody.localPoint(anchorB).clone(),
      length: math.sqrt(((x2 - x1) * (x2 - x1)) + ((y2 - y1) * (y2 - y1))),
      frequency: 0,
      dampingRatio: 0,
      collideConnected: collideConnected,
    );
    joint._rebuildJoint();
    return joint;
  }

  /// The local anchor on body A.
  final forge2d.Vector2 _localAnchorA;

  /// The local anchor on body B.
  final forge2d.Vector2 _localAnchorB;

  /// The target joint length in LOVE units.
  double _length;

  /// The joint spring frequency.
  double _frequency;

  /// The joint damping ratio.
  double _dampingRatio;

  @override
  /// The LOVE object type name.
  String get objectType => 'DistanceJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'distance';

  /// The target distance between the anchors in LOVE units.
  double get length {
    _activeJoint;
    return _length;
  }

  /// The joint spring frequency.
  double get frequency {
    _activeJoint;
    return _frequency;
  }

  /// The joint damping ratio.
  double get dampingRatio {
    _activeJoint;
    return _dampingRatio;
  }

  /// Sets the target [length] in LOVE units.
  void setLength(double value) {
    _activeJoint;
    _length = value;
    _rebuildJoint();
  }

  /// Sets the spring [frequency].
  void setFrequency(double value) {
    _activeJoint;
    _frequency = value;
    _rebuildJoint();
  }

  /// Sets the spring [dampingRatio].
  void setDampingRatio(double value) {
    _activeJoint;
    _dampingRatio = value;
    _rebuildJoint();
  }

  /// Rebuilds the underlying forge2d distance joint.
  void _rebuildJoint() {
    final definition = forge2d.DistanceJointDef<forge2d.Body, forge2d.Body>()
      ..bodyA = bodyA._activeBody
      ..bodyB = bodyB._activeBody
      ..localAnchorA.setFrom(_localAnchorA)
      ..localAnchorB.setFrom(_localAnchorB)
      ..length = world.state.scaleDownScalar(_length)
      ..frequencyHz = _frequency
      ..dampingRatio = _dampingRatio
      ..collideConnected = _collideConnected;
    _replaceJoint(forge2d.DistanceJoint(definition));
  }
}

/// A LOVE friction joint.
final class LovePhysicsFrictionJoint extends LovePhysicsJoint {
  /// Creates a stored friction joint.
  LovePhysicsFrictionJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required forge2d.Vector2 localAnchorA,
    required forge2d.Vector2 localAnchorB,
    required super.collideConnected,
  }) : _localAnchorA = localAnchorA,
       _localAnchorB = localAnchorB,
       super._();

  /// Creates and initializes a friction joint from world-space anchors.
  factory LovePhysicsFrictionJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    required bool collideConnected,
  }) {
    final anchorA = world.state.scaleDownVectorXY(xA, yA);
    final anchorB = world.state.scaleDownVectorXY(xB, yB);
    final joint = LovePhysicsFrictionJoint._(
      world: world,
      bodyA: bodyA,
      bodyB: bodyB,
      localAnchorA: bodyA._activeBody.localPoint(anchorA).clone(),
      localAnchorB: bodyB._activeBody.localPoint(anchorB).clone(),
      collideConnected: collideConnected,
    );
    joint._createJoint();
    return joint;
  }

  /// The local anchor on body A.
  final forge2d.Vector2 _localAnchorA;

  /// The local anchor on body B.
  final forge2d.Vector2 _localAnchorB;

  @override
  /// The LOVE object type name.
  String get objectType => 'FrictionJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'friction';

  /// The active underlying friction joint.
  forge2d.FrictionJoint get _activeFrictionJoint =>
      _activeJoint as forge2d.FrictionJoint;

  /// The maximum friction force in LOVE units.
  double get maxForce =>
      world.state.scaleUpScalar(_activeFrictionJoint.getMaxForce());

  /// The maximum friction torque in LOVE units.
  double get maxTorque =>
      world.state.scaleUpSquared(_activeFrictionJoint.getMaxTorque());

  /// Sets the maximum friction force in LOVE units.
  void setMaxForce(double value) {
    _activeFrictionJoint.setMaxForce(world.state.scaleDownScalar(value));
  }

  /// Sets the maximum friction torque in LOVE units.
  void setMaxTorque(double value) {
    _activeFrictionJoint.setMaxTorque(world.state.scaleDownSquared(value));
  }

  /// Creates the underlying forge2d friction joint.
  void _createJoint() {
    final definition = forge2d.FrictionJointDef<forge2d.Body, forge2d.Body>()
      ..bodyA = bodyA._activeBody
      ..bodyB = bodyB._activeBody
      ..localAnchorA.setFrom(_localAnchorA)
      ..localAnchorB.setFrom(_localAnchorB)
      ..collideConnected = _collideConnected;
    _replaceJoint(forge2d.FrictionJoint(definition));
  }
}

/// A LOVE rope joint.
final class LovePhysicsRopeJoint extends LovePhysicsJoint {
  /// Creates a stored rope joint.
  LovePhysicsRopeJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required forge2d.Vector2 localAnchorA,
    required forge2d.Vector2 localAnchorB,
    required double maxLength,
    required super.collideConnected,
  }) : _localAnchorA = localAnchorA,
       _localAnchorB = localAnchorB,
       _maxLength = maxLength,
       super._();

  /// Creates and initializes a rope joint from world-space anchors.
  factory LovePhysicsRopeJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double maxLength,
    required bool collideConnected,
  }) {
    final anchorA = world.state.scaleDownVectorXY(x1, y1);
    final anchorB = world.state.scaleDownVectorXY(x2, y2);
    final joint = LovePhysicsRopeJoint._(
      world: world,
      bodyA: bodyA,
      bodyB: bodyB,
      localAnchorA: bodyA._activeBody.localPoint(anchorA).clone(),
      localAnchorB: bodyB._activeBody.localPoint(anchorB).clone(),
      maxLength: maxLength,
      collideConnected: collideConnected,
    );
    joint._createJoint();
    return joint;
  }

  /// The local anchor on body A.
  final forge2d.Vector2 _localAnchorA;

  /// The local anchor on body B.
  final forge2d.Vector2 _localAnchorB;

  /// The maximum rope length in LOVE units.
  double _maxLength;

  @override
  /// The LOVE object type name.
  String get objectType => 'RopeJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'rope';

  /// The active underlying rope joint.
  forge2d.RopeJoint get _activeRopeJoint => _activeJoint as forge2d.RopeJoint;

  /// The maximum rope length in LOVE units.
  double get maxLength {
    _activeJoint;
    return _maxLength;
  }

  /// Sets the maximum rope [length] in LOVE units.
  void setMaxLength(double value) {
    _activeRopeJoint.maxLength = world.state.scaleDownScalar(value);
    _maxLength = value;
  }

  /// Creates the underlying forge2d rope joint.
  void _createJoint() {
    final definition = forge2d.RopeJointDef<forge2d.Body, forge2d.Body>()
      ..bodyA = bodyA._activeBody
      ..bodyB = bodyB._activeBody
      ..localAnchorA.setFrom(_localAnchorA)
      ..localAnchorB.setFrom(_localAnchorB)
      ..maxLength = world.state.scaleDownScalar(_maxLength)
      ..collideConnected = _collideConnected;
    _replaceJoint(forge2d.RopeJoint(definition));
  }
}

/// A LOVE pulley joint.
final class LovePhysicsPulleyJoint extends LovePhysicsJoint {
  /// Creates a stored pulley joint.
  LovePhysicsPulleyJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required forge2d.Vector2 groundAnchorA,
    required forge2d.Vector2 groundAnchorB,
    required forge2d.Vector2 anchorA,
    required forge2d.Vector2 anchorB,
    required double ratio,
    required double constant,
    required double referenceLengthA,
    required double referenceLengthB,
    required super.collideConnected,
  }) : _groundAnchorA = groundAnchorA,
       _groundAnchorB = groundAnchorB,
       _anchorA = anchorA,
       _anchorB = anchorB,
       _ratio = ratio,
       _constant = constant,
       _referenceLengthA = referenceLengthA,
       _referenceLengthB = referenceLengthB,
       super._();

  /// Creates and initializes a pulley joint from world-space anchors.
  factory LovePhysicsPulleyJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double gx1,
    required double gy1,
    required double gx2,
    required double gy2,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double ratio,
    required bool collideConnected,
  }) {
    if (ratio <= 0) {
      throw StateError('PulleyJoint ratio must be a positive number.');
    }
    final initialLengthA = forge2d.Vector2(x1 - gx1, y1 - gy1).length;
    final initialLengthB = forge2d.Vector2(x2 - gx2, y2 - gy2).length;
    final joint = LovePhysicsPulleyJoint._(
      world: world,
      bodyA: bodyA,
      bodyB: bodyB,
      groundAnchorA: world.state.scaleDownVectorXY(gx1, gy1),
      groundAnchorB: world.state.scaleDownVectorXY(gx2, gy2),
      anchorA: world.state.scaleDownVectorXY(x1, y1),
      anchorB: world.state.scaleDownVectorXY(x2, y2),
      ratio: ratio,
      constant: initialLengthA + ratio * initialLengthB,
      referenceLengthA: initialLengthA,
      referenceLengthB: initialLengthB,
      collideConnected: collideConnected,
    );
    joint._syncMaxLengthsFromConstant();
    joint._createJoint();
    return joint;
  }

  /// The first ground anchor in forge2d units.
  final forge2d.Vector2 _groundAnchorA;

  /// The second ground anchor in forge2d units.
  final forge2d.Vector2 _groundAnchorB;

  /// The first body anchor in forge2d units.
  final forge2d.Vector2 _anchorA;

  /// The second body anchor in forge2d units.
  final forge2d.Vector2 _anchorB;

  /// The pulley ratio.
  double _ratio;

  /// The total pulley constant in LOVE units.
  double _constant;

  /// The current reference length for rope segment A.
  double _referenceLengthA;

  /// The current reference length for rope segment B.
  double _referenceLengthB;

  /// The implied maximum length for segment A.
  double _maxLengthA = 0;

  /// The implied maximum length for segment B.
  double _maxLengthB = 0;

  @override
  /// The LOVE object type name.
  String get objectType => 'PulleyJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'pulley';

  /// The active underlying pulley joint.
  forge2d.PulleyJoint get _activePulleyJoint =>
      _activeJoint as forge2d.PulleyJoint;

  /// The pulley ground anchors in LOVE units.
  ({double x1, double y1, double x2, double y2}) get groundAnchors {
    final anchorA = _activePulleyJoint.getGroundAnchorA();
    final anchorB = _activePulleyJoint.getGroundAnchorB();
    return (
      x1: world.state.scaleUpScalar(anchorA.x),
      y1: world.state.scaleUpScalar(anchorA.y),
      x2: world.state.scaleUpScalar(anchorB.x),
      y2: world.state.scaleUpScalar(anchorB.y),
    );
  }

  /// The current rope length on segment A in LOVE units.
  double get lengthA =>
      world.state.scaleUpScalar(_activePulleyJoint.getLengthA());

  /// The current rope length on segment B in LOVE units.
  double get lengthB =>
      world.state.scaleUpScalar(_activePulleyJoint.getLengthB());

  /// The pulley ratio.
  double get ratio {
    _activeJoint;
    return _ratio;
  }

  /// The pulley constant in LOVE units.
  double get constant {
    _activeJoint;
    return _constant;
  }

  /// The implied maximum rope lengths in LOVE units.
  ({double maxLengthA, double maxLengthB}) get maxLengths {
    _activeJoint;
    return (maxLengthA: _maxLengthA, maxLengthB: _maxLengthB);
  }

  /// Sets the pulley [constant] in LOVE units.
  void setConstant(double value) {
    if (value < 0) {
      throw StateError('PulleyJoint constant must be a non-negative number.');
    }
    _activeJoint;
    _constant = value;
    _syncMaxLengthsFromConstant();
    _scaleReferenceLengthsToConstant();
    _rebuildJoint();
  }

  /// Sets the implied maximum rope lengths in LOVE units.
  void setMaxLengths(double maxLengthA, double maxLengthB) {
    if (maxLengthA < 0 || maxLengthB < 0) {
      throw StateError('PulleyJoint max lengths must be non-negative numbers.');
    }
    _activeJoint;
    _constant = _clampPulleyConstantForMaxLengths(maxLengthA, maxLengthB);
    _syncMaxLengthsFromConstant();
    _scaleReferenceLengthsToConstant();
    _rebuildJoint();
  }

  /// Sets the pulley [ratio].
  void setRatio(double value) {
    if (value <= 0) {
      throw StateError('PulleyJoint ratio must be a positive number.');
    }
    _activeJoint;
    _ratio = value;
    _syncMaxLengthsFromConstant();
    _scaleReferenceLengthsToConstant();
    _rebuildJoint();
  }

  /// Recomputes implied max lengths from the current constant and ratio.
  void _syncMaxLengthsFromConstant() {
    _maxLengthA = _constant;
    _maxLengthB = _ratio == 0 ? 0 : _constant / _ratio;
  }

  /// Scales the stored reference lengths to match the current constant.
  void _scaleReferenceLengthsToConstant() {
    final currentTotal = _referenceLengthA + _ratio * _referenceLengthB;
    if (currentTotal <= _lovePhysicsFloatEpsilon) {
      _referenceLengthA = _constant;
      _referenceLengthB = 0;
      return;
    }

    final scale = _constant / currentTotal;
    _referenceLengthA *= scale;
    _referenceLengthB *= scale;
  }

  /// Clamps the pulley constant so it fits within the requested max lengths.
  double _clampPulleyConstantForMaxLengths(
    double maxLengthA,
    double maxLengthB,
  ) {
    final constantFromA = maxLengthA;
    final constantFromB = _ratio * maxLengthB;
    final clamped = <double>[
      _constant,
      constantFromA,
      constantFromB,
    ].reduce((value, element) => value < element ? value : element);
    return clamped < 0 ? 0 : clamped;
  }

  /// Rebuilds the underlying pulley joint.
  void _rebuildJoint() {
    _replaceJoint(_buildJoint());
  }

  /// Creates the underlying pulley joint.
  void _createJoint() {
    _replaceJoint(_buildJoint());
  }

  /// Builds the forge2d pulley joint from the stored configuration.
  forge2d.PulleyJoint _buildJoint() {
    final definition = forge2d.PulleyJointDef<forge2d.Body, forge2d.Body>()
      ..initialize(
        bodyA._activeBody,
        bodyB._activeBody,
        _groundAnchorA.clone(),
        _groundAnchorB.clone(),
        _anchorA.clone(),
        _anchorB.clone(),
        _ratio,
      )
      ..lengthA = world.state.scaleDownScalar(_referenceLengthA)
      ..lengthB = world.state.scaleDownScalar(_referenceLengthB)
      ..collideConnected = _collideConnected;
    return forge2d.PulleyJoint(definition);
  }
}

/// A LOVE gear joint.
final class LovePhysicsGearJoint extends LovePhysicsJoint {
  /// Creates a stored gear joint.
  LovePhysicsGearJoint._({
    required super.world,
    required LovePhysicsJoint jointA,
    required LovePhysicsJoint jointB,
    required double ratio,
    required super.collideConnected,
  }) : _jointARef = jointA,
       _jointBRef = jointB,
       _ratio = ratio,
       super._(bodyA: jointA.bodyB, bodyB: jointB.bodyB);

  /// Creates and initializes a gear joint connecting [jointA] and [jointB].
  factory LovePhysicsGearJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsJoint jointA,
    required LovePhysicsJoint jointB,
    required double ratio,
    required bool collideConnected,
  }) {
    final joint = LovePhysicsGearJoint._(
      world: world,
      jointA: jointA,
      jointB: jointB,
      ratio: ratio,
      collideConnected: collideConnected,
    );
    joint._createJoint();
    return joint;
  }

  /// The first referenced joint.
  final LovePhysicsJoint _jointARef;

  /// The second referenced joint.
  final LovePhysicsJoint _jointBRef;

  /// The gear ratio.
  double _ratio;

  @override
  /// The LOVE object type name.
  String get objectType => 'GearJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'gear';

  /// The active underlying gear joint.
  forge2d.GearJoint get _activeGearJoint => _activeJoint as forge2d.GearJoint;

  /// The current gear ratio.
  double get ratio => _activeGearJoint.ratio;

  /// The referenced joints participating in this gear joint.
  ({LovePhysicsJoint jointA, LovePhysicsJoint jointB}) get joints {
    _activeJoint;
    return (jointA: _jointARef, jointB: _jointBRef);
  }

  /// Sets the gear [ratio].
  void setRatio(double value) {
    _ratio = value;
    _activeGearJoint.ratio = value;
  }

  /// Creates the underlying forge2d gear joint.
  void _createJoint() {
    final rawJointA = _jointARef._activeJoint;
    final rawJointB = _jointBRef._activeJoint;
    final definition = forge2d.GearJointDef<forge2d.Body, forge2d.Body>()
      ..joint1 = rawJointA
      ..joint2 = rawJointB
      ..bodyA = rawJointA.bodyB
      ..bodyB = rawJointB.bodyB
      ..ratio = _ratio
      ..collideConnected = _collideConnected;
    _replaceJoint(forge2d.GearJoint(definition));
  }
}

/// A LOVE motor joint.
final class LovePhysicsMotorJoint extends LovePhysicsJoint {
  /// Creates a stored motor joint.
  LovePhysicsMotorJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required double correctionFactor,
    required super.collideConnected,
  }) : _correctionFactor = correctionFactor,
       super._();

  /// Creates and initializes a motor joint between [bodyA] and [bodyB].
  factory LovePhysicsMotorJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double correctionFactor,
    required bool collideConnected,
  }) {
    if (correctionFactor < 0 || correctionFactor > 1) {
      throw StateError('MotorJoint correction factor must be between 0 and 1.');
    }
    final joint = LovePhysicsMotorJoint._(
      world: world,
      bodyA: bodyA,
      bodyB: bodyB,
      correctionFactor: correctionFactor,
      collideConnected: collideConnected,
    );
    joint._rebuildJoint();
    return joint;
  }

  /// The correction factor used when solving this joint.
  double _correctionFactor;

  @override
  /// The LOVE object type name.
  String get objectType => 'MotorJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'motor';

  /// The active underlying motor joint.
  forge2d.MotorJoint get _activeMotorJoint =>
      _activeJoint as forge2d.MotorJoint;

  /// The linear offset in LOVE units.
  ({double x, double y}) get linearOffset {
    final offset = _activeMotorJoint.getLinearOffset();
    return (
      x: world.state.scaleUpScalar(offset.x),
      y: world.state.scaleUpScalar(offset.y),
    );
  }

  /// The angular offset in radians.
  double get angularOffset => _activeMotorJoint.getAngularOffset();

  /// The maximum force in LOVE units.
  double get maxForce =>
      world.state.scaleUpScalar(_activeMotorJoint.getMaxForce());

  /// The maximum torque in LOVE units.
  double get maxTorque =>
      world.state.scaleUpSquared(_activeMotorJoint.getMaxTorque());

  /// The correction factor.
  double get correctionFactor {
    _activeJoint;
    return _correctionFactor;
  }

  /// Sets the linear offset in LOVE units.
  void setLinearOffset(double x, double y) {
    _activeMotorJoint.setLinearOffset(world.state.scaleDownVectorXY(x, y));
  }

  /// Sets the angular offset in radians.
  void setAngularOffset(double value) {
    _activeMotorJoint.setAngularOffset(value);
  }

  /// Sets the maximum force in LOVE units.
  void setMaxForce(double value) {
    if (value < 0) {
      throw StateError('MotorJoint max force must be a non-negative number.');
    }
    _activeMotorJoint.setMaxForce(world.state.scaleDownScalar(value));
  }

  /// Sets the maximum torque in LOVE units.
  void setMaxTorque(double value) {
    if (value < 0) {
      throw StateError('MotorJoint max torque must be a non-negative number.');
    }
    _activeMotorJoint.setMaxTorque(world.state.scaleDownSquared(value));
  }

  /// Sets the correction [factor].
  void setCorrectionFactor(double value) {
    if (value < 0 || value > 1) {
      throw StateError('MotorJoint correction factor must be between 0 and 1.');
    }
    _activeJoint;
    _correctionFactor = value;
    _rebuildJoint();
  }

  /// Rebuilds the underlying motor joint.
  void _rebuildJoint() {
    _replaceJoint(_buildJoint());
  }

  /// Builds the forge2d motor joint from the stored configuration.
  forge2d.MotorJoint _buildJoint() {
    final definition = forge2d.MotorJointDef<forge2d.Body, forge2d.Body>()
      ..initialize(bodyA._activeBody, bodyB._activeBody)
      ..correctionFactor = _correctionFactor
      ..collideConnected = _collideConnected;

    if (_joint case final forge2d.MotorJoint current) {
      definition.linearOffset.setFrom(current.getLinearOffset());
      definition.angularOffset = current.getAngularOffset();
      definition.maxForce = current.getMaxForce();
      definition.maxTorque = current.getMaxTorque();
    }

    return forge2d.MotorJoint(definition);
  }
}

/// A LOVE revolute joint.
final class LovePhysicsRevoluteJoint extends LovePhysicsJoint {
  /// Creates a stored revolute joint.
  LovePhysicsRevoluteJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required forge2d.Vector2 localAnchorA,
    required forge2d.Vector2 localAnchorB,
    required double referenceAngle,
    required super.collideConnected,
  }) : _localAnchorA = localAnchorA,
       _localAnchorB = localAnchorB,
       _referenceAngle = referenceAngle,
       super._();

  /// Creates and initializes a revolute joint from world-space anchors.
  factory LovePhysicsRevoluteJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    required bool collideConnected,
    required double? referenceAngle,
  }) {
    final anchorA = world.state.scaleDownVectorXY(xA, yA);
    final anchorB = world.state.scaleDownVectorXY(xB, yB);
    final joint = LovePhysicsRevoluteJoint._(
      world: world,
      bodyA: bodyA,
      bodyB: bodyB,
      localAnchorA: bodyA._activeBody.localPoint(anchorA).clone(),
      localAnchorB: bodyB._activeBody.localPoint(anchorB).clone(),
      referenceAngle:
          referenceAngle ?? bodyB._activeBody.angle - bodyA._activeBody.angle,
      collideConnected: collideConnected,
    );
    joint._createJoint();
    return joint;
  }

  /// The local anchor on body A.
  final forge2d.Vector2 _localAnchorA;

  /// The local anchor on body B.
  final forge2d.Vector2 _localAnchorB;

  /// The stored reference angle.
  final double _referenceAngle;

  @override
  /// The LOVE object type name.
  String get objectType => 'RevoluteJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'revolute';

  /// The active underlying revolute joint.
  forge2d.RevoluteJoint get _activeRevoluteJoint =>
      _activeJoint as forge2d.RevoluteJoint;

  /// The current joint angle in radians.
  double get jointAngle => _activeRevoluteJoint.jointAngle();

  /// The current joint speed in radians per second.
  double get jointSpeed => _activeRevoluteJoint.jointSpeed();

  /// Whether the motor is enabled.
  bool get motorEnabled => _activeRevoluteJoint.motorEnabled;

  /// The maximum motor torque in LOVE units.
  double get maxMotorTorque =>
      world.state.scaleUpSquared(_activeRevoluteJoint.maxMotorTorque);

  /// The target motor speed in radians per second.
  double get motorSpeed => _activeRevoluteJoint.motorSpeed;

  /// The motor torque in LOVE units for inverse timestep [invDt].
  double motorTorque(double invDt) {
    return world.state.scaleUpSquared(_activeRevoluteJoint.motorTorque(invDt));
  }

  /// Whether limits are enabled.
  bool get limitsEnabled => _activeRevoluteJoint.limitEnabled;

  /// The lower angular limit in radians.
  double get lowerLimit => _activeRevoluteJoint.lowerLimit;

  /// The upper angular limit in radians.
  double get upperLimit => _activeRevoluteJoint.upperLimit;

  /// Both angular limits in radians.
  ({double lower, double upper}) get limits {
    final joint = _activeRevoluteJoint;
    return (lower: joint.lowerLimit, upper: joint.upperLimit);
  }

  /// The reference angle in radians.
  double get referenceAngle => _activeRevoluteJoint.referenceAngle;

  /// Enables or disables the motor.
  void setMotorEnabled(bool value) {
    _activeRevoluteJoint.enableMotor(value);
  }

  /// Sets the maximum motor torque in LOVE units.
  void setMaxMotorTorque(double value) {
    _activeRevoluteJoint.setMaxMotorTorque(world.state.scaleDownSquared(value));
  }

  /// Sets the target motor speed in radians per second.
  void setMotorSpeed(double value) {
    _activeRevoluteJoint.motorSpeed = value;
  }

  /// Enables or disables joint limits.
  void setLimitsEnabled(bool value) {
    _activeRevoluteJoint.enableLimit(value);
  }

  /// Sets the upper angular limit in radians.
  void setUpperLimit(double value) {
    final joint = _activeRevoluteJoint;
    joint.setLimits(joint.lowerLimit, value);
  }

  /// Sets the lower angular limit in radians.
  void setLowerLimit(double value) {
    final joint = _activeRevoluteJoint;
    joint.setLimits(value, joint.upperLimit);
  }

  /// Sets both angular limits in radians.
  void setLimits(double lower, double upper) {
    _activeRevoluteJoint.setLimits(lower, upper);
  }

  /// Creates the underlying forge2d revolute joint.
  void _createJoint() {
    final definition = forge2d.RevoluteJointDef<forge2d.Body, forge2d.Body>()
      ..bodyA = bodyA._activeBody
      ..bodyB = bodyB._activeBody
      ..localAnchorA.setFrom(_localAnchorA)
      ..localAnchorB.setFrom(_localAnchorB)
      ..referenceAngle = _referenceAngle
      ..collideConnected = _collideConnected;
    _replaceJoint(forge2d.RevoluteJoint(definition));
  }
}

/// A LOVE wheel joint.
final class LovePhysicsWheelJoint extends LovePhysicsJoint {
  /// Creates a stored wheel joint.
  LovePhysicsWheelJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required forge2d.Vector2 localAnchorA,
    required forge2d.Vector2 localAnchorB,
    required forge2d.Vector2 localAxisA,
    required bool motorEnabled,
    required double motorSpeed,
    required double maxMotorTorque,
    required double springFrequency,
    required double springDampingRatio,
    required super.collideConnected,
  }) : _localAnchorA = localAnchorA,
       _localAnchorB = localAnchorB,
       _localAxisA = localAxisA,
       _motorEnabled = motorEnabled,
       _motorSpeed = motorSpeed,
       _maxMotorTorque = maxMotorTorque,
       _springFrequency = springFrequency,
       _springDampingRatio = springDampingRatio,
       super._();

  /// Creates and initializes a wheel joint from world-space anchors and axis.
  factory LovePhysicsWheelJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    required double ax,
    required double ay,
    required bool collideConnected,
  }) {
    final anchorA = world.state.scaleDownVectorXY(xA, yA);
    final anchorB = world.state.scaleDownVectorXY(xB, yB);
    final axis = forge2d.Vector2(ax, ay);
    final joint = LovePhysicsWheelJoint._(
      world: world,
      bodyA: bodyA,
      bodyB: bodyB,
      localAnchorA: bodyA._activeBody.localPoint(anchorA).clone(),
      localAnchorB: bodyB._activeBody.localPoint(anchorB).clone(),
      localAxisA: bodyA._activeBody.localVector(axis).clone(),
      motorEnabled: false,
      motorSpeed: 0,
      maxMotorTorque: 0,
      springFrequency: 0,
      springDampingRatio: 0,
      collideConnected: collideConnected,
    );
    joint._createJoint();
    return joint;
  }

  /// The local anchor on body A.
  final forge2d.Vector2 _localAnchorA;

  /// The local anchor on body B.
  final forge2d.Vector2 _localAnchorB;

  /// The suspension axis in body A local coordinates.
  final forge2d.Vector2 _localAxisA;

  /// Whether the wheel motor is enabled.
  bool _motorEnabled;

  /// The wheel motor speed.
  double _motorSpeed;

  /// The maximum motor torque in LOVE units.
  double _maxMotorTorque;

  /// The suspension spring frequency.
  double _springFrequency;

  /// The suspension damping ratio.
  double _springDampingRatio;

  @override
  /// The LOVE object type name.
  String get objectType => 'WheelJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'wheel';

  /// The active underlying wheel joint.
  forge2d.WheelJoint get _activeWheelJoint =>
      _activeJoint as forge2d.WheelJoint;

  /// The joint translation in LOVE units.
  double get jointTranslation {
    _activeJoint;
    final pointA = bodyA._activeBody.worldPoint(_localAnchorA);
    final pointB = bodyB._activeBody.worldPoint(_localAnchorB);
    final axis = bodyA._activeBody.worldVector(_localAxisA);
    pointB.sub(pointA);
    return world.state.scaleUpScalar(pointB.dot(axis));
  }

  /// The current joint speed in LOVE units per second.
  double get jointSpeed {
    _activeJoint;
    final rawBodyA = bodyA._activeBody;
    final rawBodyB = bodyB._activeBody;
    final temp = forge2d.Vector2.zero();
    final rA = forge2d.Vector2.zero();
    final rB = forge2d.Vector2.zero();
    final pointA = forge2d.Vector2.zero();
    final pointB = forge2d.Vector2.zero();
    final delta = forge2d.Vector2.zero();
    final axis = forge2d.Vector2.zero();
    final axisAngular = forge2d.Vector2.zero();
    final bodyAngularB = forge2d.Vector2.zero();
    final bodyAngularA = forge2d.Vector2.zero();

    temp
      ..setFrom(_localAnchorA)
      ..sub(rawBodyA.sweep.localCenter);
    rA.setFrom(forge2d.Rot.mulVec2(rawBodyA.transform.q, temp));

    temp
      ..setFrom(_localAnchorB)
      ..sub(rawBodyB.sweep.localCenter);
    rB.setFrom(forge2d.Rot.mulVec2(rawBodyB.transform.q, temp));

    pointA
      ..setFrom(rawBodyA.sweep.c)
      ..add(rA);
    pointB
      ..setFrom(rawBodyB.sweep.c)
      ..add(rB);

    delta
      ..setFrom(pointB)
      ..sub(pointA);
    axis.setFrom(forge2d.Rot.mulVec2(rawBodyA.transform.q, _localAxisA));

    final velocityA = rawBodyA.linearVelocity;
    final velocityB = rawBodyB.linearVelocity;
    final angularVelocityA = rawBodyA.angularVelocity;
    final angularVelocityB = rawBodyB.angularVelocity;

    axis.scaleOrthogonalInto(angularVelocityA, axisAngular);
    rB.scaleOrthogonalInto(angularVelocityB, bodyAngularB);
    rA.scaleOrthogonalInto(angularVelocityA, bodyAngularA);

    bodyAngularB
      ..add(velocityB)
      ..sub(velocityA)
      ..sub(bodyAngularA);
    final speed = delta.dot(axisAngular) + axis.dot(bodyAngularB);

    return world.state.scaleUpScalar(speed);
  }

  /// Whether the wheel motor is enabled.
  bool get motorEnabled {
    _activeJoint;
    return _motorEnabled;
  }

  /// The wheel motor speed.
  double get motorSpeed {
    _activeJoint;
    return _motorSpeed;
  }

  /// The maximum motor torque in LOVE units.
  double get maxMotorTorque {
    _activeJoint;
    return _maxMotorTorque;
  }

  /// The motor torque in LOVE units for inverse timestep [invDt].
  double motorTorque(double invDt) {
    return world.state.scaleUpSquared(_activeWheelJoint.getMotorTorque(invDt));
  }

  /// The suspension spring frequency.
  double get springFrequency {
    _activeJoint;
    return _springFrequency;
  }

  /// The suspension damping ratio.
  double get springDampingRatio {
    _activeJoint;
    return _springDampingRatio;
  }

  /// The suspension axis in world coordinates.
  ({double x, double y}) get axis {
    _activeJoint;
    final vector = bodyA._activeBody.worldVector(_localAxisA);
    return (x: vector.x, y: vector.y);
  }

  /// Enables or disables the wheel motor.
  void setMotorEnabled(bool value) {
    _motorEnabled = value;
    _activeWheelJoint.enableMotor(value);
  }

  /// Sets the wheel motor speed.
  void setMotorSpeed(double value) {
    _motorSpeed = value;
    _activeWheelJoint.motorSpeed = value;
  }

  /// Sets the maximum motor torque in LOVE units.
  void setMaxMotorTorque(double value) {
    _maxMotorTorque = value;
    _activeWheelJoint.setMaxMotorTorque(world.state.scaleDownSquared(value));
  }

  /// Sets the suspension spring frequency.
  void setSpringFrequency(double value) {
    _activeJoint;
    _springFrequency = value;
    _rebuildJoint();
  }

  /// Sets the suspension damping ratio.
  void setSpringDampingRatio(double value) {
    _activeJoint;
    _springDampingRatio = value;
    _rebuildJoint();
  }

  /// Creates the underlying wheel joint.
  void _createJoint() {
    _replaceJoint(_buildJoint());
  }

  /// Rebuilds the underlying wheel joint.
  void _rebuildJoint() {
    _replaceJoint(_buildJoint());
  }

  /// Builds the forge2d wheel joint from the stored configuration.
  forge2d.WheelJoint _buildJoint() {
    final definition = forge2d.WheelJointDef<forge2d.Body, forge2d.Body>()
      ..bodyA = bodyA._activeBody
      ..bodyB = bodyB._activeBody
      ..localAnchorA.setFrom(_localAnchorA)
      ..localAnchorB.setFrom(_localAnchorB)
      ..localAxisA.setFrom(_localAxisA)
      ..enableMotor = _motorEnabled
      ..motorSpeed = _motorSpeed
      ..maxMotorTorque = world.state.scaleDownSquared(_maxMotorTorque)
      ..frequencyHz = _springFrequency
      ..dampingRatio = _springDampingRatio
      ..collideConnected = _collideConnected;
    return forge2d.WheelJoint(definition);
  }
}

/// A LOVE prismatic joint.
final class LovePhysicsPrismaticJoint extends LovePhysicsJoint {
  /// Creates a stored prismatic joint.
  LovePhysicsPrismaticJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required forge2d.Vector2 localAnchorA,
    required forge2d.Vector2 localAnchorB,
    required forge2d.Vector2 localAxisA,
    required double referenceAngle,
    required super.collideConnected,
  }) : _localAnchorA = localAnchorA,
       _localAnchorB = localAnchorB,
       _localAxisA = localAxisA,
       _referenceAngle = referenceAngle,
       super._();

  /// Creates and initializes a prismatic joint from world-space anchors and
  /// axis.
  factory LovePhysicsPrismaticJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    required double ax,
    required double ay,
    required bool collideConnected,
    required double? referenceAngle,
  }) {
    final anchorA = world.state.scaleDownVectorXY(xA, yA);
    final anchorB = world.state.scaleDownVectorXY(xB, yB);
    final axis = forge2d.Vector2(ax, ay);
    final joint = LovePhysicsPrismaticJoint._(
      world: world,
      bodyA: bodyA,
      bodyB: bodyB,
      localAnchorA: bodyA._activeBody.localPoint(anchorA).clone(),
      localAnchorB: bodyB._activeBody.localPoint(anchorB).clone(),
      localAxisA: bodyA._activeBody.localVector(axis).clone(),
      referenceAngle:
          referenceAngle ?? bodyB._activeBody.angle - bodyA._activeBody.angle,
      collideConnected: collideConnected,
    );
    joint._createJoint();
    return joint;
  }

  /// The local anchor on body A.
  final forge2d.Vector2 _localAnchorA;

  /// The local anchor on body B.
  final forge2d.Vector2 _localAnchorB;

  /// The slide axis in body A local coordinates.
  final forge2d.Vector2 _localAxisA;

  /// The stored reference angle.
  final double _referenceAngle;

  @override
  /// The LOVE object type name.
  String get objectType => 'PrismaticJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'prismatic';

  /// The active underlying prismatic joint.
  forge2d.PrismaticJoint get _activePrismaticJoint =>
      _activeJoint as forge2d.PrismaticJoint;

  /// The joint translation in LOVE units.
  double get jointTranslation {
    _activeJoint;
    final pointA = bodyA._activeBody.worldPoint(_localAnchorA);
    final pointB = bodyB._activeBody.worldPoint(_localAnchorB);
    final axis = bodyA._activeBody.worldVector(_localAxisA);
    pointB.sub(pointA);
    return world.state.scaleUpScalar(pointB.dot(axis));
  }

  /// The current joint speed in LOVE units per second.
  double get jointSpeed {
    _activeJoint;
    final rawBodyA = bodyA._activeBody;
    final rawBodyB = bodyB._activeBody;
    final temp = forge2d.Vector2.zero();
    final rA = forge2d.Vector2.zero();
    final rB = forge2d.Vector2.zero();
    final pointA = forge2d.Vector2.zero();
    final pointB = forge2d.Vector2.zero();
    final delta = forge2d.Vector2.zero();
    final axis = forge2d.Vector2.zero();
    final axisAngular = forge2d.Vector2.zero();
    final bodyAngularB = forge2d.Vector2.zero();
    final bodyAngularA = forge2d.Vector2.zero();

    temp
      ..setFrom(_localAnchorA)
      ..sub(rawBodyA.sweep.localCenter);
    rA.setFrom(forge2d.Rot.mulVec2(rawBodyA.transform.q, temp));

    temp
      ..setFrom(_localAnchorB)
      ..sub(rawBodyB.sweep.localCenter);
    rB.setFrom(forge2d.Rot.mulVec2(rawBodyB.transform.q, temp));

    pointA
      ..setFrom(rawBodyA.sweep.c)
      ..add(rA);
    pointB
      ..setFrom(rawBodyB.sweep.c)
      ..add(rB);

    delta
      ..setFrom(pointB)
      ..sub(pointA);
    axis.setFrom(forge2d.Rot.mulVec2(rawBodyA.transform.q, _localAxisA));

    final velocityA = rawBodyA.linearVelocity;
    final velocityB = rawBodyB.linearVelocity;
    final angularVelocityA = rawBodyA.angularVelocity;
    final angularVelocityB = rawBodyB.angularVelocity;

    axis.scaleOrthogonalInto(angularVelocityA, axisAngular);
    rB.scaleOrthogonalInto(angularVelocityB, bodyAngularB);
    rA.scaleOrthogonalInto(angularVelocityA, bodyAngularA);

    bodyAngularB
      ..add(velocityB)
      ..sub(velocityA)
      ..sub(bodyAngularA);
    final speed = delta.dot(axisAngular) + axis.dot(bodyAngularB);

    return world.state.scaleUpScalar(speed);
  }

  /// Whether the motor is enabled.
  bool get motorEnabled => _activePrismaticJoint.isMotorEnabled();

  /// The maximum motor force in LOVE units.
  double get maxMotorForce =>
      world.state.scaleUpScalar(_activePrismaticJoint.maxMotorForce);

  /// The motor speed in LOVE units per second.
  double get motorSpeed =>
      world.state.scaleUpScalar(_activePrismaticJoint.motorSpeed);

  /// The motor force in LOVE units for inverse timestep [invDt].
  double motorForce(double invDt) {
    return world.state.scaleUpScalar(
      _activePrismaticJoint.getMotorForce(invDt),
    );
  }

  /// Whether translation limits are enabled.
  bool get limitsEnabled => _activePrismaticJoint.isLimitEnabled();

  /// The lower translation limit in LOVE units.
  double get lowerLimit =>
      world.state.scaleUpScalar(_activePrismaticJoint.getLowerLimit());

  /// The upper translation limit in LOVE units.
  double get upperLimit =>
      world.state.scaleUpScalar(_activePrismaticJoint.getUpperLimit());

  /// Both translation limits in LOVE units.
  ({double lower, double upper}) get limits {
    final joint = _activePrismaticJoint;
    return (
      lower: world.state.scaleUpScalar(joint.getLowerLimit()),
      upper: world.state.scaleUpScalar(joint.getUpperLimit()),
    );
  }

  /// The slide axis in world coordinates.
  ({double x, double y}) get axis {
    _activeJoint;
    final vector = bodyA._activeBody.worldVector(_localAxisA);
    return (x: vector.x, y: vector.y);
  }

  /// The reference angle in radians.
  double get referenceAngle => _activePrismaticJoint.getReferenceAngle();

  /// Enables or disables the motor.
  void setMotorEnabled(bool value) {
    _activePrismaticJoint.enableMotor(value);
  }

  /// Sets the maximum motor force in LOVE units.
  void setMaxMotorForce(double value) {
    _activePrismaticJoint.maxMotorForce = world.state.scaleDownScalar(value);
  }

  /// Sets the motor speed in LOVE units per second.
  void setMotorSpeed(double value) {
    _activePrismaticJoint.motorSpeed = world.state.scaleDownScalar(value);
  }

  /// Enables or disables translation limits.
  void setLimitsEnabled(bool value) {
    _activePrismaticJoint.enableLimit(value);
  }

  /// Sets the upper translation limit in LOVE units.
  void setUpperLimit(double value) {
    final joint = _activePrismaticJoint;
    joint.setLimits(joint.getLowerLimit(), world.state.scaleDownScalar(value));
  }

  /// Sets the lower translation limit in LOVE units.
  void setLowerLimit(double value) {
    final joint = _activePrismaticJoint;
    joint.setLimits(world.state.scaleDownScalar(value), joint.getUpperLimit());
  }

  /// Sets both translation limits in LOVE units.
  void setLimits(double lower, double upper) {
    _activePrismaticJoint.setLimits(
      world.state.scaleDownScalar(lower),
      world.state.scaleDownScalar(upper),
    );
  }

  /// Creates the underlying forge2d prismatic joint.
  void _createJoint() {
    final definition = forge2d.PrismaticJointDef<forge2d.Body, forge2d.Body>()
      ..bodyA = bodyA._activeBody
      ..bodyB = bodyB._activeBody
      ..localAnchorA.setFrom(_localAnchorA)
      ..localAnchorB.setFrom(_localAnchorB)
      ..localAxisA.setFrom(_localAxisA)
      ..referenceAngle = _referenceAngle
      ..lowerTranslation = 0
      ..upperTranslation = world.state.scaleDownScalar(100)
      ..enableLimit = true
      ..collideConnected = _collideConnected;
    _replaceJoint(forge2d.PrismaticJoint(definition));
  }
}

/// A LOVE weld joint.
final class LovePhysicsWeldJoint extends LovePhysicsJoint {
  /// Creates a stored weld joint.
  LovePhysicsWeldJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required forge2d.Vector2 localAnchorA,
    required forge2d.Vector2 localAnchorB,
    required double referenceAngle,
    required double frequency,
    required double dampingRatio,
    required super.collideConnected,
  }) : _localAnchorA = localAnchorA,
       _localAnchorB = localAnchorB,
       _referenceAngle = referenceAngle,
       _frequency = frequency,
       _dampingRatio = dampingRatio,
       super._();

  /// Creates and initializes a weld joint from world-space anchors.
  factory LovePhysicsWeldJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody bodyA,
    required LovePhysicsBody bodyB,
    required double xA,
    required double yA,
    required double xB,
    required double yB,
    required bool collideConnected,
    required double? referenceAngle,
  }) {
    final anchorA = world.state.scaleDownVectorXY(xA, yA);
    final anchorB = world.state.scaleDownVectorXY(xB, yB);
    final joint = LovePhysicsWeldJoint._(
      world: world,
      bodyA: bodyA,
      bodyB: bodyB,
      localAnchorA: bodyA._activeBody.localPoint(anchorA).clone(),
      localAnchorB: bodyB._activeBody.localPoint(anchorB).clone(),
      referenceAngle:
          referenceAngle ?? bodyB._activeBody.angle - bodyA._activeBody.angle,
      frequency: 0,
      dampingRatio: 0,
      collideConnected: collideConnected,
    );
    joint._rebuildJoint();
    return joint;
  }

  /// The local anchor on body A.
  final forge2d.Vector2 _localAnchorA;

  /// The local anchor on body B.
  final forge2d.Vector2 _localAnchorB;

  /// The stored reference angle.
  final double _referenceAngle;

  /// The weld spring frequency.
  double _frequency;

  /// The weld damping ratio.
  double _dampingRatio;

  @override
  /// The LOVE object type name.
  String get objectType => 'WeldJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'weld';

  /// The reference angle in radians.
  double get referenceAngle {
    _activeJoint;
    return _referenceAngle;
  }

  /// The weld spring frequency.
  double get frequency {
    _activeJoint;
    return _frequency;
  }

  /// The weld damping ratio.
  double get dampingRatio {
    _activeJoint;
    return _dampingRatio;
  }

  /// Sets the weld spring frequency.
  void setFrequency(double value) {
    _activeJoint;
    _frequency = value;
    _rebuildJoint();
  }

  /// Sets the weld damping ratio.
  void setDampingRatio(double value) {
    _activeJoint;
    _dampingRatio = value;
    _rebuildJoint();
  }

  /// Rebuilds the underlying weld joint.
  void _rebuildJoint() {
    final definition = forge2d.WeldJointDef<forge2d.Body, forge2d.Body>()
      ..bodyA = bodyA._activeBody
      ..bodyB = bodyB._activeBody
      ..localAnchorA.setFrom(_localAnchorA)
      ..localAnchorB.setFrom(_localAnchorB)
      ..referenceAngle = _referenceAngle
      ..frequencyHz = _frequency
      ..dampingRatio = _dampingRatio
      ..collideConnected = _collideConnected;
    _replaceJoint(forge2d.WeldJoint(definition));
  }
}

/// A LOVE mouse joint.
final class LovePhysicsMouseJoint extends LovePhysicsJoint {
  /// Creates a stored mouse joint.
  LovePhysicsMouseJoint._({
    required super.world,
    required LovePhysicsBody body,
    required forge2d.Vector2 localAnchorB,
    required forge2d.Vector2 target,
    required double maxForce,
    required double frequency,
    required double dampingRatio,
  }) : _body = body,
       _localAnchorB = localAnchorB,
       _target = target,
       _maxForce = maxForce,
       _frequency = frequency,
       _dampingRatio = dampingRatio,
       super._(bodyA: body, bodyB: body, collideConnected: false);

  /// Creates and initializes a mouse joint targeting (`x`, `y`).
  factory LovePhysicsMouseJoint._create({
    required LovePhysicsWorld world,
    required LovePhysicsBody body,
    required double x,
    required double y,
  }) {
    final target = world.state.scaleDownVectorXY(x, y);
    final rawBody = body._activeBody;
    final joint = LovePhysicsMouseJoint._(
      world: world,
      body: body,
      localAnchorB: rawBody.localPoint(target).clone(),
      target: target.clone(),
      maxForce: world.state.scaleUpScalar(1000 * rawBody.mass),
      frequency: _lovePhysicsMouseJointDefaultFrequency,
      dampingRatio: _lovePhysicsMouseJointDefaultDampingRatio,
    );
    joint._rebuildJoint();
    return joint;
  }

  /// The single body controlled by this mouse joint.
  final LovePhysicsBody _body;

  /// The local anchor on the controlled body.
  final forge2d.Vector2 _localAnchorB;

  /// The current target position in forge2d units.
  final forge2d.Vector2 _target;

  /// The maximum force in LOVE units.
  double _maxForce;

  /// The spring frequency.
  double _frequency;

  /// The damping ratio.
  double _dampingRatio;

  @override
  /// The LOVE object type name.
  String get objectType => 'MouseJoint';

  @override
  /// The LOVE joint type name.
  String get jointType => 'mouse';

  @override
  /// The controlled body exposed as body A to Lua.
  LovePhysicsBody get luaBodyA => _body;

  @override
  /// Mouse joints do not expose a second body to Lua.
  LovePhysicsBody? get luaBodyB => null;

  /// The active underlying mouse joint.
  forge2d.MouseJoint get _activeMouseJoint =>
      _activeJoint as forge2d.MouseJoint;

  /// The current target position in LOVE units.
  ({double x, double y}) get target {
    _activeJoint;
    return (
      x: world.state.scaleUpScalar(_target.x),
      y: world.state.scaleUpScalar(_target.y),
    );
  }

  /// The maximum force in LOVE units.
  double get maxForce {
    _activeJoint;
    return _maxForce;
  }

  /// The spring frequency.
  double get frequency {
    _activeJoint;
    return _frequency;
  }

  /// The damping ratio.
  double get dampingRatio {
    _activeJoint;
    return _dampingRatio;
  }

  /// Sets the target position in LOVE units.
  void setTarget(double x, double y) {
    final target = world.state.scaleDownVectorXY(x, y);
    _activeMouseJoint.setTarget(target);
    _target.setFrom(target);
  }

  /// Sets the maximum force in LOVE units.
  void setMaxForce(double value) {
    _activeJoint;
    _maxForce = value;
    _rebuildJoint();
  }

  /// Sets the spring frequency.
  void setFrequency(double value) {
    _activeJoint;
    if (value <= _lovePhysicsFloatEpsilon * 2) {
      throw StateError('MouseJoint frequency must be a positive number.');
    }
    _frequency = value;
    _rebuildJoint();
  }

  /// Sets the damping ratio.
  void setDampingRatio(double value) {
    _activeJoint;
    _dampingRatio = value;
    _rebuildJoint();
  }

  /// Rebuilds the underlying mouse joint.
  void _rebuildJoint() {
    final definition = forge2d.MouseJointDef<forge2d.Body, forge2d.Body>()
      ..bodyA = world._mouseJointGroundBody
      ..bodyB = _body._activeBody
      ..target.setFrom(_target)
      ..maxForce = world.state.scaleDownScalar(_maxForce)
      ..frequencyHz = _frequency
      ..dampingRatio = _dampingRatio;
    final joint = forge2d.MouseJoint(definition);
    joint.localAnchorB.setFrom(_localAnchorB);
    _replaceJoint(joint);
  }
}
