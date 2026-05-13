part of '../love_api_bindings.dart';

/// Returns the wrapped physics joint stored in [value], if any.
LovePhysicsJoint? _physicsJointIfPresent(Object? value) {
  final table = _physicsWrapperTable(value);
  final joint = table?[_lovePhysicsJointObjectKey];
  return joint is LovePhysicsJoint ? joint : null;
}

/// Returns the wrapped distance joint stored in [value], if any.
LovePhysicsDistanceJoint? _physicsDistanceJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsDistanceJoint ? joint : null;
}

/// Returns the wrapped friction joint stored in [value], if any.
LovePhysicsFrictionJoint? _physicsFrictionJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsFrictionJoint ? joint : null;
}

/// Returns the wrapped rope joint stored in [value], if any.
LovePhysicsRopeJoint? _physicsRopeJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsRopeJoint ? joint : null;
}

/// Returns the wrapped gear joint stored in [value], if any.
LovePhysicsGearJoint? _physicsGearJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsGearJoint ? joint : null;
}

/// Returns the wrapped pulley joint stored in [value], if any.
LovePhysicsPulleyJoint? _physicsPulleyJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsPulleyJoint ? joint : null;
}

/// Returns the wrapped revolute joint stored in [value], if any.
LovePhysicsRevoluteJoint? _physicsRevoluteJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsRevoluteJoint ? joint : null;
}

/// Returns the wrapped wheel joint stored in [value], if any.
LovePhysicsWheelJoint? _physicsWheelJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsWheelJoint ? joint : null;
}

/// Returns the wrapped prismatic joint stored in [value], if any.
LovePhysicsPrismaticJoint? _physicsPrismaticJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsPrismaticJoint ? joint : null;
}

/// Returns the wrapped weld joint stored in [value], if any.
LovePhysicsWeldJoint? _physicsWeldJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsWeldJoint ? joint : null;
}

/// Returns the wrapped motor joint stored in [value], if any.
LovePhysicsMotorJoint? _physicsMotorJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsMotorJoint ? joint : null;
}

/// Returns the wrapped mouse joint stored in [value], if any.
LovePhysicsMouseJoint? _physicsMouseJointIfPresent(Object? value) {
  final joint = _physicsJointIfPresent(value);
  return joint is LovePhysicsMouseJoint ? joint : null;
}

/// Returns the live joint argument at [index].
LovePhysicsJoint _requirePhysicsJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'Joint',
    ifPresent: _physicsJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live distance joint argument at [index].
LovePhysicsDistanceJoint _requirePhysicsDistanceJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsDistanceJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'DistanceJoint',
    ifPresent: _physicsDistanceJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live friction joint argument at [index].
LovePhysicsFrictionJoint _requirePhysicsFrictionJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsFrictionJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'FrictionJoint',
    ifPresent: _physicsFrictionJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live rope joint argument at [index].
LovePhysicsRopeJoint _requirePhysicsRopeJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsRopeJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'RopeJoint',
    ifPresent: _physicsRopeJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live gear joint argument at [index].
LovePhysicsGearJoint _requirePhysicsGearJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsGearJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'GearJoint',
    ifPresent: _physicsGearJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live pulley joint argument at [index].
LovePhysicsPulleyJoint _requirePhysicsPulleyJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsPulleyJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'PulleyJoint',
    ifPresent: _physicsPulleyJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live revolute joint argument at [index].
LovePhysicsRevoluteJoint _requirePhysicsRevoluteJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsRevoluteJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'RevoluteJoint',
    ifPresent: _physicsRevoluteJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live wheel joint argument at [index].
LovePhysicsWheelJoint _requirePhysicsWheelJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsWheelJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'WheelJoint',
    ifPresent: _physicsWheelJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live prismatic joint argument at [index].
LovePhysicsPrismaticJoint _requirePhysicsPrismaticJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsPrismaticJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'PrismaticJoint',
    ifPresent: _physicsPrismaticJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live weld joint argument at [index].
LovePhysicsWeldJoint _requirePhysicsWeldJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsWeldJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'WeldJoint',
    ifPresent: _physicsWeldJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live motor joint argument at [index].
LovePhysicsMotorJoint _requirePhysicsMotorJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsMotorJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'MotorJoint',
    ifPresent: _physicsMotorJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Returns the live mouse joint argument at [index].
LovePhysicsMouseJoint _requirePhysicsMouseJoint(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsMouseJoint>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'MouseJoint',
    ifPresent: _physicsMouseJointIfPresent,
    isDestroyed: (joint) => joint.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed joint.',
  );
}

/// Dispatches [joint] to the matching Lua wrapper constructor.
Value _wrapPhysicsJoint(LibraryContext context, LovePhysicsJoint joint) {
  switch (joint) {
    case LovePhysicsDistanceJoint():
      return _wrapPhysicsDistanceJoint(context, joint);
    case LovePhysicsFrictionJoint():
      return _wrapPhysicsFrictionJoint(context, joint);
    case LovePhysicsGearJoint():
      return _wrapPhysicsGearJoint(context, joint);
    case LovePhysicsPulleyJoint():
      return _wrapPhysicsPulleyJoint(context, joint);
    case LovePhysicsRevoluteJoint():
      return _wrapPhysicsRevoluteJoint(context, joint);
    case LovePhysicsWheelJoint():
      return _wrapPhysicsWheelJoint(context, joint);
    case LovePhysicsPrismaticJoint():
      return _wrapPhysicsPrismaticJoint(context, joint);
    case LovePhysicsWeldJoint():
      return _wrapPhysicsWeldJoint(context, joint);
    case LovePhysicsMotorJoint():
      return _wrapPhysicsMotorJoint(context, joint);
    case LovePhysicsMouseJoint():
      return _wrapPhysicsMouseJoint(context, joint);
    case LovePhysicsRopeJoint():
      return _wrapPhysicsRopeJoint(context, joint);
  }

  throw StateError('Unsupported physics joint wrapper: ${joint.runtimeType}');
}

/// Builds the base `Joint` methods shared by all wrapped joint types.
Map<Object?, Object?> _physicsJointEntries(
  LibraryContext context,
  BuiltinFunctionBuilder builder,
  LovePhysicsJoint joint,
) {
  return <Object?, Object?>{
    _lovePhysicsJointObjectKey: joint,
    'getType': Value(
      builder.create(
        (args) => _requirePhysicsJoint(args, 0, 'Joint:getType').jointType,
      ),
      functionName: 'getType',
    ),
    'getBodies': Value(
      builder.create((args) {
        final joint = _requirePhysicsJoint(args, 0, 'Joint:getBodies');
        return Value.multi(<Object?>[
          _wrapPhysicsBody(context, joint.luaBodyA),
          joint.luaBodyB == null
              ? null
              : _wrapPhysicsBody(context, joint.luaBodyB!),
        ]);
      }),
      functionName: 'getBodies',
    ),
    'getAnchors': Value(
      builder.create((args) {
        final anchors = _requirePhysicsJoint(
          args,
          0,
          'Joint:getAnchors',
        ).anchors;
        return Value.multi(<Object?>[
          anchors.x1,
          anchors.y1,
          anchors.x2,
          anchors.y2,
        ]);
      }),
      functionName: 'getAnchors',
    ),
    'getReactionForce': Value(
      builder.create((args) {
        final force = _requirePhysicsJoint(
          args,
          0,
          'Joint:getReactionForce',
        ).reactionForce(_requireNumber(args, 1, 'Joint:getReactionForce'));
        return Value.multi(<Object?>[force.x, force.y]);
      }),
      functionName: 'getReactionForce',
    ),
    'getReactionTorque': Value(
      builder.create((args) {
        return _requirePhysicsJoint(
          args,
          0,
          'Joint:getReactionTorque',
        ).reactionTorque(_requireNumber(args, 1, 'Joint:getReactionTorque'));
      }),
      functionName: 'getReactionTorque',
    ),
    'getCollideConnected': Value(
      builder.create(
        (args) => _requirePhysicsJoint(
          args,
          0,
          'Joint:getCollideConnected',
        ).collideConnected,
      ),
      functionName: 'getCollideConnected',
    ),
    'setUserData': Value(
      builder.create((args) {
        _requirePhysicsJoint(
          args,
          0,
          'Joint:setUserData',
        ).setUserData(_valueAt(args, 1));
        return null;
      }),
      functionName: 'setUserData',
    ),
    'getUserData': Value(
      builder.create(
        (args) =>
            _requirePhysicsJoint(args, 0, 'Joint:getUserData').userDataValue,
      ),
      functionName: 'getUserData',
    ),
    'destroy': Value(
      builder.create((args) {
        final table = _requirePhysicsReceiverTable(
          args,
          0,
          'Joint:destroy',
          'Joint',
        );
        final joint = table[_lovePhysicsJointObjectKey] as LovePhysicsJoint?;
        joint?.destroy();
        return null;
      }),
      functionName: 'destroy',
    ),
    'isDestroyed': Value(
      builder.create((args) {
        final table = _requirePhysicsReceiverTable(
          args,
          0,
          'Joint:isDestroyed',
          'Joint',
        );
        final joint = table[_lovePhysicsJointObjectKey] as LovePhysicsJoint?;
        return joint?.isDestroyed ?? false;
      }),
      functionName: 'isDestroyed',
    ),
  };
}

/// Wraps a distance joint in the Lua-facing `DistanceJoint` API table.
///
/// Wrapper tables are cached per joint so repeated crossings between Dart and
/// Lua preserve object identity while this joint remains alive.
Value _wrapPhysicsDistanceJoint(
  LibraryContext context,
  LovePhysicsDistanceJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'DistanceJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'setLength': Value(
      builder.create((args) {
        _requirePhysicsDistanceJoint(
          args,
          0,
          'DistanceJoint:setLength',
        ).setLength(_requireNumber(args, 1, 'DistanceJoint:setLength'));
        return null;
      }),
      functionName: 'setLength',
    ),
    'getLength': Value(
      builder.create(
        (args) => _requirePhysicsDistanceJoint(
          args,
          0,
          'DistanceJoint:getLength',
        ).length,
      ),
      functionName: 'getLength',
    ),
    'setFrequency': Value(
      builder.create((args) {
        _requirePhysicsDistanceJoint(
          args,
          0,
          'DistanceJoint:setFrequency',
        ).setFrequency(_requireNumber(args, 1, 'DistanceJoint:setFrequency'));
        return null;
      }),
      functionName: 'setFrequency',
    ),
    'getFrequency': Value(
      builder.create(
        (args) => _requirePhysicsDistanceJoint(
          args,
          0,
          'DistanceJoint:getFrequency',
        ).frequency,
      ),
      functionName: 'getFrequency',
    ),
    'setDampingRatio': Value(
      builder.create((args) {
        _requirePhysicsDistanceJoint(
          args,
          0,
          'DistanceJoint:setDampingRatio',
        ).setDampingRatio(
          _requireNumber(args, 1, 'DistanceJoint:setDampingRatio'),
        );
        return null;
      }),
      functionName: 'setDampingRatio',
    ),
    'getDampingRatio': Value(
      builder.create(
        (args) => _requirePhysicsDistanceJoint(
          args,
          0,
          'DistanceJoint:getDampingRatio',
        ).dampingRatio,
      ),
      functionName: 'getDampingRatio',
    ),
    ..._physicsObjectEntries<LovePhysicsDistanceJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'DistanceJoint',
      hierarchy: const <String>{'DistanceJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsDistanceJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a friction joint in the Lua-facing `FrictionJoint` API table.
Value _wrapPhysicsFrictionJoint(
  LibraryContext context,
  LovePhysicsFrictionJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'FrictionJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'setMaxForce': Value(
      builder.create((args) {
        _requirePhysicsFrictionJoint(
          args,
          0,
          'FrictionJoint:setMaxForce',
        ).setMaxForce(_requireNumber(args, 1, 'FrictionJoint:setMaxForce'));
        return null;
      }),
      functionName: 'setMaxForce',
    ),
    'getMaxForce': Value(
      builder.create(
        (args) => _requirePhysicsFrictionJoint(
          args,
          0,
          'FrictionJoint:getMaxForce',
        ).maxForce,
      ),
      functionName: 'getMaxForce',
    ),
    'setMaxTorque': Value(
      builder.create((args) {
        _requirePhysicsFrictionJoint(
          args,
          0,
          'FrictionJoint:setMaxTorque',
        ).setMaxTorque(_requireNumber(args, 1, 'FrictionJoint:setMaxTorque'));
        return null;
      }),
      functionName: 'setMaxTorque',
    ),
    'getMaxTorque': Value(
      builder.create(
        (args) => _requirePhysicsFrictionJoint(
          args,
          0,
          'FrictionJoint:getMaxTorque',
        ).maxTorque,
      ),
      functionName: 'getMaxTorque',
    ),
    ..._physicsObjectEntries<LovePhysicsFrictionJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'FrictionJoint',
      hierarchy: const <String>{'FrictionJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsFrictionJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a gear joint in the Lua-facing `GearJoint` API table.
///
/// The resulting wrapper exposes the coupled child joints through
/// [LovePhysicsGearJoint.joints] by rewrapping them with [_wrapPhysicsJoint].
Value _wrapPhysicsGearJoint(
  LibraryContext context,
  LovePhysicsGearJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'GearJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'setRatio': Value(
      builder.create((args) {
        _requirePhysicsGearJoint(
          args,
          0,
          'GearJoint:setRatio',
        ).setRatio(_requireNumber(args, 1, 'GearJoint:setRatio'));
        return null;
      }),
      functionName: 'setRatio',
    ),
    'getRatio': Value(
      builder.create(
        (args) => _requirePhysicsGearJoint(args, 0, 'GearJoint:getRatio').ratio,
      ),
      functionName: 'getRatio',
    ),
    'getJoints': Value(
      builder.create((args) {
        final joints = _requirePhysicsGearJoint(
          args,
          0,
          'GearJoint:getJoints',
        ).joints;
        return Value.multi(<Object?>[
          _wrapPhysicsJoint(context, joints.jointA),
          _wrapPhysicsJoint(context, joints.jointB),
        ]);
      }),
      functionName: 'getJoints',
    ),
    ..._physicsObjectEntries<LovePhysicsGearJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'GearJoint',
      hierarchy: const <String>{'GearJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsGearJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a pulley joint in the Lua-facing `PulleyJoint` API table.
///
/// Mutating pulley parameters is routed through [_physicsWithLuaErrors] because
/// the underlying host API can reject invalid pulley constraints.
Value _wrapPhysicsPulleyJoint(
  LibraryContext context,
  LovePhysicsPulleyJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'PulleyJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'getConstant': Value(
      builder.create(
        (args) => _requirePhysicsPulleyJoint(
          args,
          0,
          'PulleyJoint:getConstant',
        ).constant,
      ),
      functionName: 'getConstant',
    ),
    'getGroundAnchors': Value(
      builder.create((args) {
        final anchors = _requirePhysicsPulleyJoint(
          args,
          0,
          'PulleyJoint:getGroundAnchors',
        ).groundAnchors;
        return Value.multi(<Object?>[
          anchors.x1,
          anchors.y1,
          anchors.x2,
          anchors.y2,
        ]);
      }),
      functionName: 'getGroundAnchors',
    ),
    'getLengthA': Value(
      builder.create(
        (args) => _requirePhysicsPulleyJoint(
          args,
          0,
          'PulleyJoint:getLengthA',
        ).lengthA,
      ),
      functionName: 'getLengthA',
    ),
    'getLengthB': Value(
      builder.create(
        (args) => _requirePhysicsPulleyJoint(
          args,
          0,
          'PulleyJoint:getLengthB',
        ).lengthB,
      ),
      functionName: 'getLengthB',
    ),
    'getRatio': Value(
      builder.create(
        (args) =>
            _requirePhysicsPulleyJoint(args, 0, 'PulleyJoint:getRatio').ratio,
      ),
      functionName: 'getRatio',
    ),
    'getMaxLengths': Value(
      builder.create((args) {
        final lengths = _requirePhysicsPulleyJoint(
          args,
          0,
          'PulleyJoint:getMaxLengths',
        ).maxLengths;
        return Value.multi(<Object?>[lengths.maxLengthA, lengths.maxLengthB]);
      }),
      functionName: 'getMaxLengths',
    ),
    'setConstant': Value(
      builder.create((args) {
        _physicsWithLuaErrors(() {
          _requirePhysicsPulleyJoint(
            args,
            0,
            'PulleyJoint:setConstant',
          ).setConstant(_requireNumber(args, 1, 'PulleyJoint:setConstant'));
        });
        return null;
      }),
      functionName: 'setConstant',
    ),
    'setMaxLengths': Value(
      builder.create((args) {
        _physicsWithLuaErrors(() {
          _requirePhysicsPulleyJoint(
            args,
            0,
            'PulleyJoint:setMaxLengths',
          ).setMaxLengths(
            _requireNumber(args, 1, 'PulleyJoint:setMaxLengths'),
            _requireNumber(args, 2, 'PulleyJoint:setMaxLengths'),
          );
        });
        return null;
      }),
      functionName: 'setMaxLengths',
    ),
    'setRatio': Value(
      builder.create((args) {
        _physicsWithLuaErrors(() {
          _requirePhysicsPulleyJoint(
            args,
            0,
            'PulleyJoint:setRatio',
          ).setRatio(_requireNumber(args, 1, 'PulleyJoint:setRatio'));
        });
        return null;
      }),
      functionName: 'setRatio',
    ),
    ..._physicsObjectEntries<LovePhysicsPulleyJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'PulleyJoint',
      hierarchy: const <String>{'PulleyJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsPulleyJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a revolute joint in the Lua-facing `RevoluteJoint` API table.
///
/// This exposes angular motor controls, angular limits, and the joint's
/// reference angle through Love-compatible method names.
Value _wrapPhysicsRevoluteJoint(
  LibraryContext context,
  LovePhysicsRevoluteJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'RevoluteJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'getJointAngle': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:getJointAngle',
        ).jointAngle,
      ),
      functionName: 'getJointAngle',
    ),
    'getJointSpeed': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:getJointSpeed',
        ).jointSpeed,
      ),
      functionName: 'getJointSpeed',
    ),
    'setMotorEnabled': Value(
      builder.create((args) {
        _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:setMotorEnabled',
        ).setMotorEnabled(
          _requireBoolean(args, 1, 'RevoluteJoint:setMotorEnabled'),
        );
        return null;
      }),
      functionName: 'setMotorEnabled',
    ),
    'isMotorEnabled': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:isMotorEnabled',
        ).motorEnabled,
      ),
      functionName: 'isMotorEnabled',
    ),
    'setMaxMotorTorque': Value(
      builder.create((args) {
        _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:setMaxMotorTorque',
        ).setMaxMotorTorque(
          _requireNumber(args, 1, 'RevoluteJoint:setMaxMotorTorque'),
        );
        return null;
      }),
      functionName: 'setMaxMotorTorque',
    ),
    'getMaxMotorTorque': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:getMaxMotorTorque',
        ).maxMotorTorque,
      ),
      functionName: 'getMaxMotorTorque',
    ),
    'setMotorSpeed': Value(
      builder.create((args) {
        _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:setMotorSpeed',
        ).setMotorSpeed(_requireNumber(args, 1, 'RevoluteJoint:setMotorSpeed'));
        return null;
      }),
      functionName: 'setMotorSpeed',
    ),
    'getMotorSpeed': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:getMotorSpeed',
        ).motorSpeed,
      ),
      functionName: 'getMotorSpeed',
    ),
    'getMotorTorque': Value(
      builder.create((args) {
        return _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:getMotorTorque',
        ).motorTorque(_requireNumber(args, 1, 'RevoluteJoint:getMotorTorque'));
      }),
      functionName: 'getMotorTorque',
    ),
    'setLimitsEnabled': Value(
      builder.create((args) {
        _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:setLimitsEnabled',
        ).setLimitsEnabled(
          _requireBoolean(args, 1, 'RevoluteJoint:setLimitsEnabled'),
        );
        return null;
      }),
      functionName: 'setLimitsEnabled',
    ),
    'areLimitsEnabled': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:areLimitsEnabled',
        ).limitsEnabled,
      ),
      functionName: 'areLimitsEnabled',
    ),
    'hasLimitsEnabled': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:hasLimitsEnabled',
        ).limitsEnabled,
      ),
      functionName: 'hasLimitsEnabled',
    ),
    'setUpperLimit': Value(
      builder.create((args) {
        _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:setUpperLimit',
        ).setUpperLimit(_requireNumber(args, 1, 'RevoluteJoint:setUpperLimit'));
        return null;
      }),
      functionName: 'setUpperLimit',
    ),
    'setLowerLimit': Value(
      builder.create((args) {
        _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:setLowerLimit',
        ).setLowerLimit(_requireNumber(args, 1, 'RevoluteJoint:setLowerLimit'));
        return null;
      }),
      functionName: 'setLowerLimit',
    ),
    'setLimits': Value(
      builder.create((args) {
        _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:setLimits',
        ).setLimits(
          _requireNumber(args, 1, 'RevoluteJoint:setLimits'),
          _requireNumber(args, 2, 'RevoluteJoint:setLimits'),
        );
        return null;
      }),
      functionName: 'setLimits',
    ),
    'getLowerLimit': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:getLowerLimit',
        ).lowerLimit,
      ),
      functionName: 'getLowerLimit',
    ),
    'getUpperLimit': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:getUpperLimit',
        ).upperLimit,
      ),
      functionName: 'getUpperLimit',
    ),
    'getLimits': Value(
      builder.create((args) {
        final limits = _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:getLimits',
        ).limits;
        return Value.multi(<Object?>[limits.lower, limits.upper]);
      }),
      functionName: 'getLimits',
    ),
    'getReferenceAngle': Value(
      builder.create(
        (args) => _requirePhysicsRevoluteJoint(
          args,
          0,
          'RevoluteJoint:getReferenceAngle',
        ).referenceAngle,
      ),
      functionName: 'getReferenceAngle',
    ),
    ..._physicsObjectEntries<LovePhysicsRevoluteJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'RevoluteJoint',
      hierarchy: const <String>{'RevoluteJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsRevoluteJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a wheel joint in the Lua-facing `WheelJoint` API table.
///
/// The wrapper exposes the suspension axis plus the joint's motor and spring
/// controls using Love's expected naming.
Value _wrapPhysicsWheelJoint(
  LibraryContext context,
  LovePhysicsWheelJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'WheelJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'getAxis': Value(
      builder.create((args) {
        final axis = _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:getAxis',
        ).axis;
        return Value.multi(<Object?>[axis.x, axis.y]);
      }),
      functionName: 'getAxis',
    ),
    'getJointTranslation': Value(
      builder.create(
        (args) => _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:getJointTranslation',
        ).jointTranslation,
      ),
      functionName: 'getJointTranslation',
    ),
    'getJointSpeed': Value(
      builder.create(
        (args) => _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:getJointSpeed',
        ).jointSpeed,
      ),
      functionName: 'getJointSpeed',
    ),
    'setMotorEnabled': Value(
      builder.create((args) {
        _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:setMotorEnabled',
        ).setMotorEnabled(
          _requireBoolean(args, 1, 'WheelJoint:setMotorEnabled'),
        );
        return null;
      }),
      functionName: 'setMotorEnabled',
    ),
    'isMotorEnabled': Value(
      builder.create(
        (args) => _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:isMotorEnabled',
        ).motorEnabled,
      ),
      functionName: 'isMotorEnabled',
    ),
    'setMotorSpeed': Value(
      builder.create((args) {
        _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:setMotorSpeed',
        ).setMotorSpeed(_requireNumber(args, 1, 'WheelJoint:setMotorSpeed'));
        return null;
      }),
      functionName: 'setMotorSpeed',
    ),
    'getMotorSpeed': Value(
      builder.create(
        (args) => _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:getMotorSpeed',
        ).motorSpeed,
      ),
      functionName: 'getMotorSpeed',
    ),
    'setMaxMotorTorque': Value(
      builder.create((args) {
        _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:setMaxMotorTorque',
        ).setMaxMotorTorque(
          _requireNumber(args, 1, 'WheelJoint:setMaxMotorTorque'),
        );
        return null;
      }),
      functionName: 'setMaxMotorTorque',
    ),
    'getMaxMotorTorque': Value(
      builder.create(
        (args) => _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:getMaxMotorTorque',
        ).maxMotorTorque,
      ),
      functionName: 'getMaxMotorTorque',
    ),
    'getMotorTorque': Value(
      builder.create((args) {
        return _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:getMotorTorque',
        ).motorTorque(_requireNumber(args, 1, 'WheelJoint:getMotorTorque'));
      }),
      functionName: 'getMotorTorque',
    ),
    'setSpringFrequency': Value(
      builder.create((args) {
        _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:setSpringFrequency',
        ).setSpringFrequency(
          _requireNumber(args, 1, 'WheelJoint:setSpringFrequency'),
        );
        return null;
      }),
      functionName: 'setSpringFrequency',
    ),
    'getSpringFrequency': Value(
      builder.create(
        (args) => _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:getSpringFrequency',
        ).springFrequency,
      ),
      functionName: 'getSpringFrequency',
    ),
    'setSpringDampingRatio': Value(
      builder.create((args) {
        _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:setSpringDampingRatio',
        ).setSpringDampingRatio(
          _requireNumber(args, 1, 'WheelJoint:setSpringDampingRatio'),
        );
        return null;
      }),
      functionName: 'setSpringDampingRatio',
    ),
    'getSpringDampingRatio': Value(
      builder.create(
        (args) => _requirePhysicsWheelJoint(
          args,
          0,
          'WheelJoint:getSpringDampingRatio',
        ).springDampingRatio,
      ),
      functionName: 'getSpringDampingRatio',
    ),
    ..._physicsObjectEntries<LovePhysicsWheelJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'WheelJoint',
      hierarchy: const <String>{'WheelJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsWheelJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a prismatic joint in the Lua-facing `PrismaticJoint` API table.
///
/// This wrapper exposes translation, linear motor settings, axis queries, and
/// linear limit controls along the joint's constrained axis.
Value _wrapPhysicsPrismaticJoint(
  LibraryContext context,
  LovePhysicsPrismaticJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'PrismaticJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'getJointTranslation': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getJointTranslation',
        ).jointTranslation,
      ),
      functionName: 'getJointTranslation',
    ),
    'getJointSpeed': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getJointSpeed',
        ).jointSpeed,
      ),
      functionName: 'getJointSpeed',
    ),
    'setMotorEnabled': Value(
      builder.create((args) {
        _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:setMotorEnabled',
        ).setMotorEnabled(
          _requireBoolean(args, 1, 'PrismaticJoint:setMotorEnabled'),
        );
        return null;
      }),
      functionName: 'setMotorEnabled',
    ),
    'isMotorEnabled': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:isMotorEnabled',
        ).motorEnabled,
      ),
      functionName: 'isMotorEnabled',
    ),
    'setMaxMotorForce': Value(
      builder.create((args) {
        _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:setMaxMotorForce',
        ).setMaxMotorForce(
          _requireNumber(args, 1, 'PrismaticJoint:setMaxMotorForce'),
        );
        return null;
      }),
      functionName: 'setMaxMotorForce',
    ),
    'setMotorSpeed': Value(
      builder.create((args) {
        _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:setMotorSpeed',
        ).setMotorSpeed(
          _requireNumber(args, 1, 'PrismaticJoint:setMotorSpeed'),
        );
        return null;
      }),
      functionName: 'setMotorSpeed',
    ),
    'getMotorSpeed': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getMotorSpeed',
        ).motorSpeed,
      ),
      functionName: 'getMotorSpeed',
    ),
    'getMotorForce': Value(
      builder.create((args) {
        return _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getMotorForce',
        ).motorForce(_requireNumber(args, 1, 'PrismaticJoint:getMotorForce'));
      }),
      functionName: 'getMotorForce',
    ),
    'getMaxMotorForce': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getMaxMotorForce',
        ).maxMotorForce,
      ),
      functionName: 'getMaxMotorForce',
    ),
    'setLimitsEnabled': Value(
      builder.create((args) {
        _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:setLimitsEnabled',
        ).setLimitsEnabled(
          _requireBoolean(args, 1, 'PrismaticJoint:setLimitsEnabled'),
        );
        return null;
      }),
      functionName: 'setLimitsEnabled',
    ),
    'areLimitsEnabled': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:areLimitsEnabled',
        ).limitsEnabled,
      ),
      functionName: 'areLimitsEnabled',
    ),
    'hasLimitsEnabled': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:hasLimitsEnabled',
        ).limitsEnabled,
      ),
      functionName: 'hasLimitsEnabled',
    ),
    'setUpperLimit': Value(
      builder.create((args) {
        _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:setUpperLimit',
        ).setUpperLimit(
          _requireNumber(args, 1, 'PrismaticJoint:setUpperLimit'),
        );
        return null;
      }),
      functionName: 'setUpperLimit',
    ),
    'setLowerLimit': Value(
      builder.create((args) {
        _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:setLowerLimit',
        ).setLowerLimit(
          _requireNumber(args, 1, 'PrismaticJoint:setLowerLimit'),
        );
        return null;
      }),
      functionName: 'setLowerLimit',
    ),
    'setLimits': Value(
      builder.create((args) {
        _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:setLimits',
        ).setLimits(
          _requireNumber(args, 1, 'PrismaticJoint:setLimits'),
          _requireNumber(args, 2, 'PrismaticJoint:setLimits'),
        );
        return null;
      }),
      functionName: 'setLimits',
    ),
    'getLowerLimit': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getLowerLimit',
        ).lowerLimit,
      ),
      functionName: 'getLowerLimit',
    ),
    'getUpperLimit': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getUpperLimit',
        ).upperLimit,
      ),
      functionName: 'getUpperLimit',
    ),
    'getLimits': Value(
      builder.create((args) {
        final limits = _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getLimits',
        ).limits;
        return Value.multi(<Object?>[limits.lower, limits.upper]);
      }),
      functionName: 'getLimits',
    ),
    'getAxis': Value(
      builder.create((args) {
        final axis = _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getAxis',
        ).axis;
        return Value.multi(<Object?>[axis.x, axis.y]);
      }),
      functionName: 'getAxis',
    ),
    'getReferenceAngle': Value(
      builder.create(
        (args) => _requirePhysicsPrismaticJoint(
          args,
          0,
          'PrismaticJoint:getReferenceAngle',
        ).referenceAngle,
      ),
      functionName: 'getReferenceAngle',
    ),
    ..._physicsObjectEntries<LovePhysicsPrismaticJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'PrismaticJoint',
      hierarchy: const <String>{'PrismaticJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsPrismaticJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a weld joint in the Lua-facing `WeldJoint` API table.
///
/// The wrapper exposes the soft-weld spring parameters and the joint's
/// reference angle through Love-compatible accessors.
Value _wrapPhysicsWeldJoint(
  LibraryContext context,
  LovePhysicsWeldJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'WeldJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'setFrequency': Value(
      builder.create((args) {
        _requirePhysicsWeldJoint(
          args,
          0,
          'WeldJoint:setFrequency',
        ).setFrequency(_requireNumber(args, 1, 'WeldJoint:setFrequency'));
        return null;
      }),
      functionName: 'setFrequency',
    ),
    'getFrequency': Value(
      builder.create(
        (args) => _requirePhysicsWeldJoint(
          args,
          0,
          'WeldJoint:getFrequency',
        ).frequency,
      ),
      functionName: 'getFrequency',
    ),
    'setDampingRatio': Value(
      builder.create((args) {
        _requirePhysicsWeldJoint(
          args,
          0,
          'WeldJoint:setDampingRatio',
        ).setDampingRatio(_requireNumber(args, 1, 'WeldJoint:setDampingRatio'));
        return null;
      }),
      functionName: 'setDampingRatio',
    ),
    'getDampingRatio': Value(
      builder.create(
        (args) => _requirePhysicsWeldJoint(
          args,
          0,
          'WeldJoint:getDampingRatio',
        ).dampingRatio,
      ),
      functionName: 'getDampingRatio',
    ),
    'getReferenceAngle': Value(
      builder.create(
        (args) => _requirePhysicsWeldJoint(
          args,
          0,
          'WeldJoint:getReferenceAngle',
        ).referenceAngle,
      ),
      functionName: 'getReferenceAngle',
    ),
    ..._physicsObjectEntries<LovePhysicsWeldJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'WeldJoint',
      hierarchy: const <String>{'WeldJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsWeldJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a motor joint in the Lua-facing `MotorJoint` API table.
///
/// Host-side validation for offset and force changes is funneled through
/// [_physicsWithLuaErrors] so invalid motor parameters surface as Lua errors.
Value _wrapPhysicsMotorJoint(
  LibraryContext context,
  LovePhysicsMotorJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'MotorJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'setLinearOffset': Value(
      builder.create((args) {
        _physicsWithLuaErrors(() {
          _requirePhysicsMotorJoint(
            args,
            0,
            'MotorJoint:setLinearOffset',
          ).setLinearOffset(
            _requireNumber(args, 1, 'MotorJoint:setLinearOffset'),
            _requireNumber(args, 2, 'MotorJoint:setLinearOffset'),
          );
        });
        return null;
      }),
      functionName: 'setLinearOffset',
    ),
    'getLinearOffset': Value(
      builder.create((args) {
        final offset = _requirePhysicsMotorJoint(
          args,
          0,
          'MotorJoint:getLinearOffset',
        ).linearOffset;
        return Value.multi(<Object?>[offset.x, offset.y]);
      }),
      functionName: 'getLinearOffset',
    ),
    'setAngularOffset': Value(
      builder.create((args) {
        _physicsWithLuaErrors(() {
          _requirePhysicsMotorJoint(
            args,
            0,
            'MotorJoint:setAngularOffset',
          ).setAngularOffset(
            _requireNumber(args, 1, 'MotorJoint:setAngularOffset'),
          );
        });
        return null;
      }),
      functionName: 'setAngularOffset',
    ),
    'getAngularOffset': Value(
      builder.create(
        (args) => _requirePhysicsMotorJoint(
          args,
          0,
          'MotorJoint:getAngularOffset',
        ).angularOffset,
      ),
      functionName: 'getAngularOffset',
    ),
    'setMaxForce': Value(
      builder.create((args) {
        _physicsWithLuaErrors(() {
          _requirePhysicsMotorJoint(
            args,
            0,
            'MotorJoint:setMaxForce',
          ).setMaxForce(_requireNumber(args, 1, 'MotorJoint:setMaxForce'));
        });
        return null;
      }),
      functionName: 'setMaxForce',
    ),
    'getMaxForce': Value(
      builder.create(
        (args) => _requirePhysicsMotorJoint(
          args,
          0,
          'MotorJoint:getMaxForce',
        ).maxForce,
      ),
      functionName: 'getMaxForce',
    ),
    'setMaxTorque': Value(
      builder.create((args) {
        _physicsWithLuaErrors(() {
          _requirePhysicsMotorJoint(
            args,
            0,
            'MotorJoint:setMaxTorque',
          ).setMaxTorque(_requireNumber(args, 1, 'MotorJoint:setMaxTorque'));
        });
        return null;
      }),
      functionName: 'setMaxTorque',
    ),
    'getMaxTorque': Value(
      builder.create(
        (args) => _requirePhysicsMotorJoint(
          args,
          0,
          'MotorJoint:getMaxTorque',
        ).maxTorque,
      ),
      functionName: 'getMaxTorque',
    ),
    'setCorrectionFactor': Value(
      builder.create((args) {
        _physicsWithLuaErrors(() {
          _requirePhysicsMotorJoint(
            args,
            0,
            'MotorJoint:setCorrectionFactor',
          ).setCorrectionFactor(
            _requireNumber(args, 1, 'MotorJoint:setCorrectionFactor'),
          );
        });
        return null;
      }),
      functionName: 'setCorrectionFactor',
    ),
    'getCorrectionFactor': Value(
      builder.create(
        (args) => _requirePhysicsMotorJoint(
          args,
          0,
          'MotorJoint:getCorrectionFactor',
        ).correctionFactor,
      ),
      functionName: 'getCorrectionFactor',
    ),
    ..._physicsObjectEntries<LovePhysicsMotorJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'MotorJoint',
      hierarchy: const <String>{'MotorJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsMotorJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a mouse joint in the Lua-facing `MouseJoint` API table.
///
/// This wrapper exposes the drag target along with the force and spring tuning
/// parameters that Love uses to control mouse-driven bodies.
Value _wrapPhysicsMouseJoint(
  LibraryContext context,
  LovePhysicsMouseJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'MouseJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'setTarget': Value(
      builder.create((args) {
        _requirePhysicsMouseJoint(args, 0, 'MouseJoint:setTarget').setTarget(
          _requireNumber(args, 1, 'MouseJoint:setTarget'),
          _requireNumber(args, 2, 'MouseJoint:setTarget'),
        );
        return null;
      }),
      functionName: 'setTarget',
    ),
    'getTarget': Value(
      builder.create((args) {
        final target = _requirePhysicsMouseJoint(
          args,
          0,
          'MouseJoint:getTarget',
        ).target;
        return Value.multi(<Object?>[target.x, target.y]);
      }),
      functionName: 'getTarget',
    ),
    'setMaxForce': Value(
      builder.create((args) {
        _requirePhysicsMouseJoint(
          args,
          0,
          'MouseJoint:setMaxForce',
        ).setMaxForce(_requireNumber(args, 1, 'MouseJoint:setMaxForce'));
        return null;
      }),
      functionName: 'setMaxForce',
    ),
    'getMaxForce': Value(
      builder.create(
        (args) => _requirePhysicsMouseJoint(
          args,
          0,
          'MouseJoint:getMaxForce',
        ).maxForce,
      ),
      functionName: 'getMaxForce',
    ),
    'setFrequency': Value(
      builder.create((args) {
        _requirePhysicsMouseJoint(
          args,
          0,
          'MouseJoint:setFrequency',
        ).setFrequency(_requireNumber(args, 1, 'MouseJoint:setFrequency'));
        return null;
      }),
      functionName: 'setFrequency',
    ),
    'getFrequency': Value(
      builder.create(
        (args) => _requirePhysicsMouseJoint(
          args,
          0,
          'MouseJoint:getFrequency',
        ).frequency,
      ),
      functionName: 'getFrequency',
    ),
    'setDampingRatio': Value(
      builder.create((args) {
        _requirePhysicsMouseJoint(
          args,
          0,
          'MouseJoint:setDampingRatio',
        ).setDampingRatio(
          _requireNumber(args, 1, 'MouseJoint:setDampingRatio'),
        );
        return null;
      }),
      functionName: 'setDampingRatio',
    ),
    'getDampingRatio': Value(
      builder.create(
        (args) => _requirePhysicsMouseJoint(
          args,
          0,
          'MouseJoint:getDampingRatio',
        ).dampingRatio,
      ),
      functionName: 'getDampingRatio',
    ),
    ..._physicsObjectEntries<LovePhysicsMouseJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'MouseJoint',
      hierarchy: const <String>{'MouseJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsMouseJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}

/// Wraps a rope joint in the Lua-facing `RopeJoint` API table.
///
/// Rope joints only expose their maximum length in addition to the shared base
/// joint methods.
Value _wrapPhysicsRopeJoint(
  LibraryContext context,
  LovePhysicsRopeJoint joint,
) {
  final cached = _lovePhysicsJointWrapperCache[joint];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'RopeJoint')) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    ..._physicsJointEntries(context, builder, joint),
    'setMaxLength': Value(
      builder.create((args) {
        _requirePhysicsRopeJoint(
          args,
          0,
          'RopeJoint:setMaxLength',
        ).setMaxLength(_requireNumber(args, 1, 'RopeJoint:setMaxLength'));
        return null;
      }),
      functionName: 'setMaxLength',
    ),
    'getMaxLength': Value(
      builder.create(
        (args) => _requirePhysicsRopeJoint(
          args,
          0,
          'RopeJoint:getMaxLength',
        ).maxLength,
      ),
      functionName: 'getMaxLength',
    ),
    ..._physicsObjectEntries<LovePhysicsRopeJoint>(
      builder: builder,
      object: joint,
      objectKey: _lovePhysicsJointObjectKey,
      typeName: 'RopeJoint',
      hierarchy: const <String>{'RopeJoint', 'Joint', 'Object'},
      requireObject: (args, symbol) =>
          _requirePhysicsRopeJoint(args, 0, symbol),
    ),
  });
  _lovePhysicsJointWrapperCache[joint] = table;
  return table;
}
