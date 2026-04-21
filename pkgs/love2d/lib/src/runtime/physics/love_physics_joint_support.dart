part of '../love_runtime.dart';

final Expando<List<LovePhysicsJoint>> _lovePhysicsJointRegistry =
    Expando<List<LovePhysicsJoint>>('love2dPhysicsJoints');
final Expando<forge2d.Body> _lovePhysicsMouseJointGroundBodyRegistry =
    Expando<forge2d.Body>('love2dPhysicsMouseJointGroundBody');

const double _lovePhysicsMouseJointDefaultFrequency = 5.0;
const double _lovePhysicsMouseJointDefaultDampingRatio = 0.7;
const double _lovePhysicsFloatEpsilon = 1.1920928955078125e-7;

List<LovePhysicsJoint> _lovePhysicsJointsForWorld(LovePhysicsWorld world) {
  return _lovePhysicsJointRegistry[world] ??= <LovePhysicsJoint>[];
}

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

extension LovePhysicsWorldJointAccess on LovePhysicsWorld {
  List<LovePhysicsJoint> get joints {
    _checkActive('world');
    final joints = _lovePhysicsJointsForWorld(this);
    joints.removeWhere((joint) => joint.isDestroyed);
    return List<LovePhysicsJoint>.unmodifiable(joints);
  }

  int get jointCount => joints.length;

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

  void _unregisterJoint(LovePhysicsJoint joint) {
    _lovePhysicsJointRegistry[this]?.remove(joint);
  }

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

extension LovePhysicsBodyJointAccess on LovePhysicsBody {
  List<LovePhysicsJoint> get joints {
    _activeBody;
    return List<LovePhysicsJoint>.unmodifiable(
      world.joints.where(
        (joint) => identical(joint.bodyA, this) || identical(joint.bodyB, this),
      ),
    );
  }
}

abstract base class LovePhysicsJoint {
  LovePhysicsJoint._({
    required this.world,
    required this.bodyA,
    required this.bodyB,
    required bool collideConnected,
  }) : _collideConnected = collideConnected;

  final LovePhysicsWorld world;
  final LovePhysicsBody bodyA;
  final LovePhysicsBody bodyB;
  final bool _collideConnected;
  forge2d.Joint? _joint;
  bool _destroyed = false;
  Object? userData;

  String get objectType;

  String get jointType;

  LovePhysicsBody get luaBodyA => bodyA;

  LovePhysicsBody? get luaBodyB => bodyB;

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

  forge2d.Joint get _activeJoint {
    if (isDestroyed) {
      throw StateError('Attempt to use destroyed joint.');
    }
    return _joint!;
  }

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

  ({double x, double y}) reactionForce(double invDt) {
    final force = _activeJoint.reactionForce(invDt);
    return (
      x: world.state.scaleUpScalar(force.x),
      y: world.state.scaleUpScalar(force.y),
    );
  }

  double reactionTorque(double invDt) {
    return world.state.scaleUpSquared(_activeJoint.reactionTorque(invDt));
  }

  bool get collideConnected => _activeJoint.collideConnected;

  Object? get userDataValue {
    _activeJoint;
    return userData;
  }

  void setUserData(Object? value) {
    _activeJoint;
    userData = value;
  }

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

  void _replaceJoint(forge2d.Joint joint) {
    final previous = _joint;
    if (previous != null) {
      world._world.destroyJoint(previous);
    }
    _joint = joint;
    world._world.createJoint(joint);
  }

  void _markDestroyed() {
    _destroyed = true;
    _joint = null;
  }
}

final class LovePhysicsDistanceJoint extends LovePhysicsJoint {
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

  final forge2d.Vector2 _localAnchorA;
  final forge2d.Vector2 _localAnchorB;
  double _length;
  double _frequency;
  double _dampingRatio;

  @override
  String get objectType => 'DistanceJoint';

  @override
  String get jointType => 'distance';

  double get length {
    _activeJoint;
    return _length;
  }

  double get frequency {
    _activeJoint;
    return _frequency;
  }

  double get dampingRatio {
    _activeJoint;
    return _dampingRatio;
  }

  void setLength(double value) {
    _activeJoint;
    _length = value;
    _rebuildJoint();
  }

  void setFrequency(double value) {
    _activeJoint;
    _frequency = value;
    _rebuildJoint();
  }

  void setDampingRatio(double value) {
    _activeJoint;
    _dampingRatio = value;
    _rebuildJoint();
  }

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

final class LovePhysicsFrictionJoint extends LovePhysicsJoint {
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

  final forge2d.Vector2 _localAnchorA;
  final forge2d.Vector2 _localAnchorB;

  @override
  String get objectType => 'FrictionJoint';

  @override
  String get jointType => 'friction';

  forge2d.FrictionJoint get _activeFrictionJoint =>
      _activeJoint as forge2d.FrictionJoint;

  double get maxForce =>
      world.state.scaleUpScalar(_activeFrictionJoint.getMaxForce());

  double get maxTorque =>
      world.state.scaleUpSquared(_activeFrictionJoint.getMaxTorque());

  void setMaxForce(double value) {
    _activeFrictionJoint.setMaxForce(world.state.scaleDownScalar(value));
  }

  void setMaxTorque(double value) {
    _activeFrictionJoint.setMaxTorque(world.state.scaleDownSquared(value));
  }

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

final class LovePhysicsRopeJoint extends LovePhysicsJoint {
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

  final forge2d.Vector2 _localAnchorA;
  final forge2d.Vector2 _localAnchorB;
  double _maxLength;

  @override
  String get objectType => 'RopeJoint';

  @override
  String get jointType => 'rope';

  forge2d.RopeJoint get _activeRopeJoint => _activeJoint as forge2d.RopeJoint;

  double get maxLength {
    _activeJoint;
    return _maxLength;
  }

  void setMaxLength(double value) {
    _activeRopeJoint.maxLength = world.state.scaleDownScalar(value);
    _maxLength = value;
  }

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

final class LovePhysicsPulleyJoint extends LovePhysicsJoint {
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

  final forge2d.Vector2 _groundAnchorA;
  final forge2d.Vector2 _groundAnchorB;
  final forge2d.Vector2 _anchorA;
  final forge2d.Vector2 _anchorB;
  double _ratio;
  double _constant;
  double _referenceLengthA;
  double _referenceLengthB;
  double _maxLengthA = 0;
  double _maxLengthB = 0;

  @override
  String get objectType => 'PulleyJoint';

  @override
  String get jointType => 'pulley';

  forge2d.PulleyJoint get _activePulleyJoint =>
      _activeJoint as forge2d.PulleyJoint;

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

  double get lengthA =>
      world.state.scaleUpScalar(_activePulleyJoint.getLengthA());

  double get lengthB =>
      world.state.scaleUpScalar(_activePulleyJoint.getLengthB());

  double get ratio {
    _activeJoint;
    return _ratio;
  }

  double get constant {
    _activeJoint;
    return _constant;
  }

  ({double maxLengthA, double maxLengthB}) get maxLengths {
    _activeJoint;
    return (maxLengthA: _maxLengthA, maxLengthB: _maxLengthB);
  }

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

  void _syncMaxLengthsFromConstant() {
    _maxLengthA = _constant;
    _maxLengthB = _ratio == 0 ? 0 : _constant / _ratio;
  }

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

  void _rebuildJoint() {
    _replaceJoint(_buildJoint());
  }

  void _createJoint() {
    _replaceJoint(_buildJoint());
  }

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

final class LovePhysicsGearJoint extends LovePhysicsJoint {
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

  final LovePhysicsJoint _jointARef;
  final LovePhysicsJoint _jointBRef;
  double _ratio;

  @override
  String get objectType => 'GearJoint';

  @override
  String get jointType => 'gear';

  forge2d.GearJoint get _activeGearJoint => _activeJoint as forge2d.GearJoint;

  double get ratio => _activeGearJoint.ratio;

  ({LovePhysicsJoint jointA, LovePhysicsJoint jointB}) get joints {
    _activeJoint;
    return (jointA: _jointARef, jointB: _jointBRef);
  }

  void setRatio(double value) {
    _ratio = value;
    _activeGearJoint.ratio = value;
  }

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

final class LovePhysicsMotorJoint extends LovePhysicsJoint {
  LovePhysicsMotorJoint._({
    required super.world,
    required super.bodyA,
    required super.bodyB,
    required double correctionFactor,
    required super.collideConnected,
  }) : _correctionFactor = correctionFactor,
       super._();

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

  double _correctionFactor;

  @override
  String get objectType => 'MotorJoint';

  @override
  String get jointType => 'motor';

  forge2d.MotorJoint get _activeMotorJoint =>
      _activeJoint as forge2d.MotorJoint;

  ({double x, double y}) get linearOffset {
    final offset = _activeMotorJoint.getLinearOffset();
    return (
      x: world.state.scaleUpScalar(offset.x),
      y: world.state.scaleUpScalar(offset.y),
    );
  }

  double get angularOffset => _activeMotorJoint.getAngularOffset();

  double get maxForce =>
      world.state.scaleUpScalar(_activeMotorJoint.getMaxForce());

  double get maxTorque =>
      world.state.scaleUpSquared(_activeMotorJoint.getMaxTorque());

  double get correctionFactor {
    _activeJoint;
    return _correctionFactor;
  }

  void setLinearOffset(double x, double y) {
    _activeMotorJoint.setLinearOffset(world.state.scaleDownVectorXY(x, y));
  }

  void setAngularOffset(double value) {
    _activeMotorJoint.setAngularOffset(value);
  }

  void setMaxForce(double value) {
    if (value < 0) {
      throw StateError('MotorJoint max force must be a non-negative number.');
    }
    _activeMotorJoint.setMaxForce(world.state.scaleDownScalar(value));
  }

  void setMaxTorque(double value) {
    if (value < 0) {
      throw StateError('MotorJoint max torque must be a non-negative number.');
    }
    _activeMotorJoint.setMaxTorque(world.state.scaleDownSquared(value));
  }

  void setCorrectionFactor(double value) {
    if (value < 0 || value > 1) {
      throw StateError('MotorJoint correction factor must be between 0 and 1.');
    }
    _activeJoint;
    _correctionFactor = value;
    _rebuildJoint();
  }

  void _rebuildJoint() {
    _replaceJoint(_buildJoint());
  }

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

final class LovePhysicsRevoluteJoint extends LovePhysicsJoint {
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

  final forge2d.Vector2 _localAnchorA;
  final forge2d.Vector2 _localAnchorB;
  final double _referenceAngle;

  @override
  String get objectType => 'RevoluteJoint';

  @override
  String get jointType => 'revolute';

  forge2d.RevoluteJoint get _activeRevoluteJoint =>
      _activeJoint as forge2d.RevoluteJoint;

  double get jointAngle => _activeRevoluteJoint.jointAngle();

  double get jointSpeed => _activeRevoluteJoint.jointSpeed();

  bool get motorEnabled => _activeRevoluteJoint.motorEnabled;

  double get maxMotorTorque =>
      world.state.scaleUpSquared(_activeRevoluteJoint.maxMotorTorque);

  double get motorSpeed => _activeRevoluteJoint.motorSpeed;

  double motorTorque(double invDt) {
    return world.state.scaleUpSquared(_activeRevoluteJoint.motorTorque(invDt));
  }

  bool get limitsEnabled => _activeRevoluteJoint.limitEnabled;

  double get lowerLimit => _activeRevoluteJoint.lowerLimit;

  double get upperLimit => _activeRevoluteJoint.upperLimit;

  ({double lower, double upper}) get limits {
    final joint = _activeRevoluteJoint;
    return (lower: joint.lowerLimit, upper: joint.upperLimit);
  }

  double get referenceAngle => _activeRevoluteJoint.referenceAngle;

  void setMotorEnabled(bool value) {
    _activeRevoluteJoint.enableMotor(value);
  }

  void setMaxMotorTorque(double value) {
    _activeRevoluteJoint.setMaxMotorTorque(world.state.scaleDownSquared(value));
  }

  void setMotorSpeed(double value) {
    _activeRevoluteJoint.motorSpeed = value;
  }

  void setLimitsEnabled(bool value) {
    _activeRevoluteJoint.enableLimit(value);
  }

  void setUpperLimit(double value) {
    final joint = _activeRevoluteJoint;
    joint.setLimits(joint.lowerLimit, value);
  }

  void setLowerLimit(double value) {
    final joint = _activeRevoluteJoint;
    joint.setLimits(value, joint.upperLimit);
  }

  void setLimits(double lower, double upper) {
    _activeRevoluteJoint.setLimits(lower, upper);
  }

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

final class LovePhysicsWheelJoint extends LovePhysicsJoint {
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

  final forge2d.Vector2 _localAnchorA;
  final forge2d.Vector2 _localAnchorB;
  final forge2d.Vector2 _localAxisA;
  bool _motorEnabled;
  double _motorSpeed;
  double _maxMotorTorque;
  double _springFrequency;
  double _springDampingRatio;

  @override
  String get objectType => 'WheelJoint';

  @override
  String get jointType => 'wheel';

  forge2d.WheelJoint get _activeWheelJoint =>
      _activeJoint as forge2d.WheelJoint;

  double get jointTranslation {
    _activeJoint;
    final pointA = bodyA._activeBody.worldPoint(_localAnchorA);
    final pointB = bodyB._activeBody.worldPoint(_localAnchorB);
    final axis = bodyA._activeBody.worldVector(_localAxisA);
    pointB.sub(pointA);
    return world.state.scaleUpScalar(pointB.dot(axis));
  }

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

  bool get motorEnabled {
    _activeJoint;
    return _motorEnabled;
  }

  double get motorSpeed {
    _activeJoint;
    return _motorSpeed;
  }

  double get maxMotorTorque {
    _activeJoint;
    return _maxMotorTorque;
  }

  double motorTorque(double invDt) {
    return world.state.scaleUpSquared(_activeWheelJoint.getMotorTorque(invDt));
  }

  double get springFrequency {
    _activeJoint;
    return _springFrequency;
  }

  double get springDampingRatio {
    _activeJoint;
    return _springDampingRatio;
  }

  ({double x, double y}) get axis {
    _activeJoint;
    final vector = bodyA._activeBody.worldVector(_localAxisA);
    return (x: vector.x, y: vector.y);
  }

  void setMotorEnabled(bool value) {
    _motorEnabled = value;
    _activeWheelJoint.enableMotor(value);
  }

  void setMotorSpeed(double value) {
    _motorSpeed = value;
    _activeWheelJoint.motorSpeed = value;
  }

  void setMaxMotorTorque(double value) {
    _maxMotorTorque = value;
    _activeWheelJoint.setMaxMotorTorque(world.state.scaleDownSquared(value));
  }

  void setSpringFrequency(double value) {
    _activeJoint;
    _springFrequency = value;
    _rebuildJoint();
  }

  void setSpringDampingRatio(double value) {
    _activeJoint;
    _springDampingRatio = value;
    _rebuildJoint();
  }

  void _createJoint() {
    _replaceJoint(_buildJoint());
  }

  void _rebuildJoint() {
    _replaceJoint(_buildJoint());
  }

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

final class LovePhysicsPrismaticJoint extends LovePhysicsJoint {
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

  final forge2d.Vector2 _localAnchorA;
  final forge2d.Vector2 _localAnchorB;
  final forge2d.Vector2 _localAxisA;
  final double _referenceAngle;

  @override
  String get objectType => 'PrismaticJoint';

  @override
  String get jointType => 'prismatic';

  forge2d.PrismaticJoint get _activePrismaticJoint =>
      _activeJoint as forge2d.PrismaticJoint;

  double get jointTranslation {
    _activeJoint;
    final pointA = bodyA._activeBody.worldPoint(_localAnchorA);
    final pointB = bodyB._activeBody.worldPoint(_localAnchorB);
    final axis = bodyA._activeBody.worldVector(_localAxisA);
    pointB.sub(pointA);
    return world.state.scaleUpScalar(pointB.dot(axis));
  }

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

  bool get motorEnabled => _activePrismaticJoint.isMotorEnabled();

  double get maxMotorForce =>
      world.state.scaleUpScalar(_activePrismaticJoint.maxMotorForce);

  double get motorSpeed =>
      world.state.scaleUpScalar(_activePrismaticJoint.motorSpeed);

  double motorForce(double invDt) {
    return world.state.scaleUpScalar(
      _activePrismaticJoint.getMotorForce(invDt),
    );
  }

  bool get limitsEnabled => _activePrismaticJoint.isLimitEnabled();

  double get lowerLimit =>
      world.state.scaleUpScalar(_activePrismaticJoint.getLowerLimit());

  double get upperLimit =>
      world.state.scaleUpScalar(_activePrismaticJoint.getUpperLimit());

  ({double lower, double upper}) get limits {
    final joint = _activePrismaticJoint;
    return (
      lower: world.state.scaleUpScalar(joint.getLowerLimit()),
      upper: world.state.scaleUpScalar(joint.getUpperLimit()),
    );
  }

  ({double x, double y}) get axis {
    _activeJoint;
    final vector = bodyA._activeBody.worldVector(_localAxisA);
    return (x: vector.x, y: vector.y);
  }

  double get referenceAngle => _activePrismaticJoint.getReferenceAngle();

  void setMotorEnabled(bool value) {
    _activePrismaticJoint.enableMotor(value);
  }

  void setMaxMotorForce(double value) {
    _activePrismaticJoint.maxMotorForce = world.state.scaleDownScalar(value);
  }

  void setMotorSpeed(double value) {
    _activePrismaticJoint.motorSpeed = world.state.scaleDownScalar(value);
  }

  void setLimitsEnabled(bool value) {
    _activePrismaticJoint.enableLimit(value);
  }

  void setUpperLimit(double value) {
    final joint = _activePrismaticJoint;
    joint.setLimits(joint.getLowerLimit(), world.state.scaleDownScalar(value));
  }

  void setLowerLimit(double value) {
    final joint = _activePrismaticJoint;
    joint.setLimits(world.state.scaleDownScalar(value), joint.getUpperLimit());
  }

  void setLimits(double lower, double upper) {
    _activePrismaticJoint.setLimits(
      world.state.scaleDownScalar(lower),
      world.state.scaleDownScalar(upper),
    );
  }

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

final class LovePhysicsWeldJoint extends LovePhysicsJoint {
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

  final forge2d.Vector2 _localAnchorA;
  final forge2d.Vector2 _localAnchorB;
  final double _referenceAngle;
  double _frequency;
  double _dampingRatio;

  @override
  String get objectType => 'WeldJoint';

  @override
  String get jointType => 'weld';

  double get referenceAngle {
    _activeJoint;
    return _referenceAngle;
  }

  double get frequency {
    _activeJoint;
    return _frequency;
  }

  double get dampingRatio {
    _activeJoint;
    return _dampingRatio;
  }

  void setFrequency(double value) {
    _activeJoint;
    _frequency = value;
    _rebuildJoint();
  }

  void setDampingRatio(double value) {
    _activeJoint;
    _dampingRatio = value;
    _rebuildJoint();
  }

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

final class LovePhysicsMouseJoint extends LovePhysicsJoint {
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

  final LovePhysicsBody _body;
  final forge2d.Vector2 _localAnchorB;
  final forge2d.Vector2 _target;
  double _maxForce;
  double _frequency;
  double _dampingRatio;

  @override
  String get objectType => 'MouseJoint';

  @override
  String get jointType => 'mouse';

  @override
  LovePhysicsBody get luaBodyA => _body;

  @override
  LovePhysicsBody? get luaBodyB => null;

  forge2d.MouseJoint get _activeMouseJoint =>
      _activeJoint as forge2d.MouseJoint;

  ({double x, double y}) get target {
    _activeJoint;
    return (
      x: world.state.scaleUpScalar(_target.x),
      y: world.state.scaleUpScalar(_target.y),
    );
  }

  double get maxForce {
    _activeJoint;
    return _maxForce;
  }

  double get frequency {
    _activeJoint;
    return _frequency;
  }

  double get dampingRatio {
    _activeJoint;
    return _dampingRatio;
  }

  void setTarget(double x, double y) {
    final target = world.state.scaleDownVectorXY(x, y);
    _activeMouseJoint.setTarget(target);
    _target.setFrom(target);
  }

  void setMaxForce(double value) {
    _activeJoint;
    _maxForce = value;
    _rebuildJoint();
  }

  void setFrequency(double value) {
    _activeJoint;
    if (value <= _lovePhysicsFloatEpsilon * 2) {
      throw StateError('MouseJoint frequency must be a positive number.');
    }
    _frequency = value;
    _rebuildJoint();
  }

  void setDampingRatio(double value) {
    _activeJoint;
    _dampingRatio = value;
    _rebuildJoint();
  }

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
