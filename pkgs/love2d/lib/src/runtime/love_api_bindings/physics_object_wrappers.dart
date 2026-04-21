part of '../love_api_bindings.dart';

T _physicsWithLuaErrors<T>(T Function() callback) {
  try {
    return callback();
  } on LuaError {
    rethrow;
  } on StateError catch (error) {
    throw LuaError(error.message.toString());
  } on ArgumentError catch (error) {
    throw LuaError('${error.message}');
  } catch (error) {
    throw LuaError('$error');
  }
}

Future<T> _physicsWithLuaErrorsAsync<T>(Future<T> Function() callback) async {
  try {
    return await callback();
  } on LuaError {
    rethrow;
  } on StateError catch (error) {
    throw LuaError(error.message.toString());
  } on ArgumentError catch (error) {
    throw LuaError('${error.message}');
  } catch (error) {
    throw LuaError('$error');
  }
}

Map<dynamic, dynamic>? _physicsWrapperTable(Object? value) {
  return _tableIfPresent(value);
}

LovePhysicsWorld? _physicsWorldIfPresent(Object? value) {
  final table = _physicsWrapperTable(value);
  final world = table?[_lovePhysicsWorldObjectKey];
  return world is LovePhysicsWorld ? world : null;
}

LovePhysicsBody? _physicsBodyIfPresent(Object? value) {
  final table = _physicsWrapperTable(value);
  final body = table?[_lovePhysicsBodyObjectKey];
  return body is LovePhysicsBody ? body : null;
}

LovePhysicsFixture? _physicsFixtureIfPresent(Object? value) {
  final table = _physicsWrapperTable(value);
  final fixture = table?[_lovePhysicsFixtureObjectKey];
  return fixture is LovePhysicsFixture ? fixture : null;
}

LovePhysicsShape? _physicsShapeIfPresent(Object? value) {
  final table = _physicsWrapperTable(value);
  final shape = table?[_lovePhysicsShapeObjectKey];
  return shape is LovePhysicsShape ? shape : null;
}

LovePhysicsWorld _requirePhysicsWorld(
  List<Object?> args,
  int index,
  String symbol,
) {
  final world = _physicsWorldIfPresent(_valueAt(args, index));
  if (world == null) {
    throw LuaError('$symbol expected a World at argument ${index + 1}');
  }
  if (world.isDestroyed) {
    throw LuaError('Attempt to use destroyed world.');
  }
  return world;
}

LovePhysicsBody _requirePhysicsBody(
  List<Object?> args,
  int index,
  String symbol,
) {
  final body = _physicsBodyIfPresent(_valueAt(args, index));
  if (body == null) {
    throw LuaError('$symbol expected a Body at argument ${index + 1}');
  }
  if (body.isDestroyed) {
    throw LuaError('Attempt to use destroyed body.');
  }
  return body;
}

LovePhysicsFixture _requirePhysicsFixture(
  List<Object?> args,
  int index,
  String symbol,
) {
  final fixture = _physicsFixtureIfPresent(_valueAt(args, index));
  if (fixture == null) {
    throw LuaError('$symbol expected a Fixture at argument ${index + 1}');
  }
  if (fixture.isDestroyed) {
    throw LuaError('Attempt to use destroyed fixture.');
  }
  return fixture;
}

LovePhysicsShape _requirePhysicsShape(
  List<Object?> args,
  int index,
  String symbol,
) {
  final shape = _physicsShapeIfPresent(_valueAt(args, index));
  if (shape != null) {
    return shape;
  }

  throw LuaError('$symbol expected a Shape at argument ${index + 1}');
}

String _requirePhysicsBodyType(List<Object?> args, int index, String symbol) {
  final type = _requireString(args, index, symbol);
  switch (type) {
    case 'static':
    case 'dynamic':
    case 'kinematic':
      return type;
  }
  throw LuaError('$symbol expected a valid Body type at argument ${index + 1}');
}

Value _physicsArray(Iterable<Object?> values) {
  final list = values.toList(growable: false);
  return ValueClass.table(<Object?, Object?>{
    for (var index = 0; index < list.length; index++) index + 1: list[index],
  });
}

Value _physicsPointMulti(Iterable<({double x, double y})> points) {
  final values = <Object?>[];
  for (final point in points) {
    values.add(point.x);
    values.add(point.y);
  }
  return Value.multi(values);
}

List<int> _physicsCategorySequence(
  List<Object?> args,
  int startIndex,
  String symbol,
) {
  final count = args.length - startIndex;
  if (count <= 0) {
    return const <int>[];
  }

  final table = count == 1 ? _tableIfPresent(_valueAt(args, startIndex)) : null;
  if (table != null) {
    final values = <int>[];
    for (var index = 1; ; index++) {
      final entry = _tableIndexedEntry(table, index);
      if (entry == null) {
        break;
      }

      final raw = _rawValue(entry);
      if (raw is! num) {
        throw LuaError('$symbol expected numeric category values in table');
      }

      final category = raw.round();
      if (category < 1 || category > 16) {
        throw LuaError('Values must be in range 1-16.');
      }
      values.add(category);
    }
    return List<int>.unmodifiable(values);
  }

  return List<int>.generate(count, (offset) {
    final category = _requireRoundedInt(args, startIndex + offset, symbol);
    if (category < 1 || category > 16) {
      throw LuaError('Values must be in range 1-16.');
    }
    return category;
  }, growable: false);
}

Object? _physicsFirstResult(Object? value) {
  final raw = switch (value) {
    final Value wrapped when wrapped.isMulti => wrapped.raw,
    _ => value,
  };
  if (raw is List && raw.isNotEmpty) {
    return _physicsFirstResult(raw.first);
  }
  return _rawValue(raw);
}

bool _physicsLuaTruthy(Object? value) {
  final first = _physicsFirstResult(value);
  return first != null && first != false;
}

Future<Object?> _physicsInvokeLuaCallback(
  LibraryContext context,
  Value callback,
  List<Object?> args,
  String symbol,
) async {
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw LuaError('$symbol requires an interpreter runtime');
  }
  return _physicsFirstResult(
    await interpreter.callFunction(
      callback,
      args,
      debugName: symbol,
      debugNameWhat: 'method',
    ),
  );
}

Value _physicsNoResults() => Value.multi(const <Object?>[]);

Map<Object?, Object?> _physicsObjectEntries<T>({
  required BuiltinFunctionBuilder builder,
  required T object,
  required String typeName,
  required Set<String> hierarchy,
  required T Function(List<Object?> args, String symbol) requireObject,
}) {
  return <Object?, Object?>{
    'release': Value(
      builder.create((args) {
        final object = requireObject(args, 'Object:release');
        if (_lovePhysicsObjectReleased[object as Object] == true) {
          return false;
        }
        _lovePhysicsObjectReleased[object] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        requireObject(args, 'Object:type');
        return typeName;
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        requireObject(args, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  };
}

Value _wrapPhysicsWorld(LibraryContext context, LovePhysicsWorld world) {
  final cached = _lovePhysicsWorldWrapperCache[world];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _lovePhysicsWorldObjectKey: world,
    'update': _buildPhysicsWorldUpdateBinding(context, builder),
    'setCallbacks': _buildPhysicsWorldSetCallbacksBinding(builder),
    'getCallbacks': _buildPhysicsWorldGetCallbacksBinding(builder),
    'setContactFilter': _buildPhysicsWorldSetContactFilterBinding(builder),
    'getContactFilter': _buildPhysicsWorldGetContactFilterBinding(builder),
    'setGravity': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          _requirePhysicsWorld(args, 0, 'World:setGravity').setGravity(
            _requireNumber(args, 1, 'World:setGravity'),
            _requireNumber(args, 2, 'World:setGravity'),
          );
          return null;
        }),
      ),
      functionName: 'setGravity',
    ),
    'getGravity': Value(
      builder.create((args) {
        final gravity = _requirePhysicsWorld(
          args,
          0,
          'World:getGravity',
        ).gravity;
        return Value.multi(<Object?>[gravity.x, gravity.y]);
      }),
      functionName: 'getGravity',
    ),
    'translateOrigin': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          _requirePhysicsWorld(
            args,
            0,
            'World:translateOrigin',
          ).translateOrigin(
            _requireNumber(args, 1, 'World:translateOrigin'),
            _requireNumber(args, 2, 'World:translateOrigin'),
          );
          return null;
        }),
      ),
      functionName: 'translateOrigin',
    ),
    'setSleepingAllowed': Value(
      builder.create((args) {
        _requirePhysicsWorld(
          args,
          0,
          'World:setSleepingAllowed',
        ).setSleepingAllowed(
          _requireBoolean(args, 1, 'World:setSleepingAllowed'),
        );
        return null;
      }),
      functionName: 'setSleepingAllowed',
    ),
    'isSleepingAllowed': Value(
      builder.create(
        (args) => _requirePhysicsWorld(
          args,
          0,
          'World:isSleepingAllowed',
        ).sleepingAllowed,
      ),
      functionName: 'isSleepingAllowed',
    ),
    'isLocked': Value(
      builder.create(
        (args) => _requirePhysicsWorld(args, 0, 'World:isLocked').isLocked,
      ),
      functionName: 'isLocked',
    ),
    'getBodyCount': Value(
      builder.create(
        (args) => _requirePhysicsWorld(args, 0, 'World:getBodyCount').bodyCount,
      ),
      functionName: 'getBodyCount',
    ),
    'getContactCount': Value(
      builder.create(
        (args) =>
            _requirePhysicsWorld(args, 0, 'World:getContactCount').contactCount,
      ),
      functionName: 'getContactCount',
    ),
    'getContacts': Value(
      builder.create((args) {
        final world = _requirePhysicsWorld(args, 0, 'World:getContacts');
        return _physicsArray(
          world.contacts.map(
            (contact) => _wrapPhysicsContact(context, contact),
          ),
        );
      }),
      functionName: 'getContacts',
    ),
    'getContactList': Value(
      builder.create((args) {
        final world = _requirePhysicsWorld(args, 0, 'World:getContactList');
        return _physicsArray(
          world.contacts.map(
            (contact) => _wrapPhysicsContact(context, contact),
          ),
        );
      }),
      functionName: 'getContactList',
    ),
    'getBodies': Value(
      builder.create((args) {
        final world = _requirePhysicsWorld(args, 0, 'World:getBodies');
        return _physicsArray(
          world.bodies.map((body) => _wrapPhysicsBody(context, body)),
        );
      }),
      functionName: 'getBodies',
    ),
    'getBodyList': Value(
      builder.create((args) {
        final world = _requirePhysicsWorld(args, 0, 'World:getBodyList');
        return _physicsArray(
          world.bodies.map((body) => _wrapPhysicsBody(context, body)),
        );
      }),
      functionName: 'getBodyList',
    ),
    'getJointCount': Value(
      builder.create((args) {
        return _requirePhysicsWorld(args, 0, 'World:getJointCount').jointCount;
      }),
      functionName: 'getJointCount',
    ),
    'getJoints': Value(
      builder.create((args) {
        final world = _requirePhysicsWorld(args, 0, 'World:getJoints');
        return _physicsArray(
          world.joints.map((joint) => _wrapPhysicsJoint(context, joint)),
        );
      }),
      functionName: 'getJoints',
    ),
    'getJointList': Value(
      builder.create((args) {
        final world = _requirePhysicsWorld(args, 0, 'World:getJointList');
        return _physicsArray(
          world.joints.map((joint) => _wrapPhysicsJoint(context, joint)),
        );
      }),
      functionName: 'getJointList',
    ),
    'queryBoundingBox': Value(
      builder.create(
        (args) => _physicsWithLuaErrorsAsync(() async {
          final world = _requirePhysicsWorld(args, 0, 'World:queryBoundingBox');
          final callback = _requireCallable(args, 5, 'World:queryBoundingBox');
          await world.queryBoundingBox(
            _requireNumber(args, 1, 'World:queryBoundingBox'),
            _requireNumber(args, 2, 'World:queryBoundingBox'),
            _requireNumber(args, 3, 'World:queryBoundingBox'),
            _requireNumber(args, 4, 'World:queryBoundingBox'),
            (fixture) async => _physicsLuaTruthy(
              await _physicsInvokeLuaCallback(context, callback, <Object?>[
                _wrapPhysicsFixture(context, fixture),
              ], 'World:queryBoundingBox'),
            ),
          );
          return null;
        }),
      ),
      functionName: 'queryBoundingBox',
    ),
    'rayCast': Value(
      builder.create(
        (args) => _physicsWithLuaErrorsAsync(() async {
          final world = _requirePhysicsWorld(args, 0, 'World:rayCast');
          final callback = _requireCallable(args, 5, 'World:rayCast');
          await world.rayCast(
            _requireNumber(args, 1, 'World:rayCast'),
            _requireNumber(args, 2, 'World:rayCast'),
            _requireNumber(args, 3, 'World:rayCast'),
            _requireNumber(args, 4, 'World:rayCast'),
            (fixture, x, y, normalX, normalY, fraction) async {
              final result = await _physicsInvokeLuaCallback(
                context,
                callback,
                <Object?>[
                  _wrapPhysicsFixture(context, fixture),
                  x,
                  y,
                  normalX,
                  normalY,
                  fraction,
                ],
                'World:rayCast',
              );
              final number = _numberIfPresent(result);
              if (number == null) {
                throw LuaError("Raycast callback didn't return a number!");
              }
              return number;
            },
          );
          return null;
        }),
      ),
      functionName: 'rayCast',
    ),
    'destroy': Value(
      builder.create((args) {
        _physicsWorldIfPresent(_valueAt(args, 0))?.destroy();
        return null;
      }),
      functionName: 'destroy',
    ),
    'isDestroyed': Value(
      builder.create(
        (args) =>
            (_physicsWorldIfPresent(_valueAt(args, 0))?.isDestroyed) ?? false,
      ),
      functionName: 'isDestroyed',
    ),
    ..._physicsObjectEntries<LovePhysicsWorld>(
      builder: builder,
      object: world,
      typeName: 'World',
      hierarchy: const <String>{'World', 'Object'},
      requireObject: (args, symbol) => _requirePhysicsWorld(args, 0, symbol),
    ),
  });
  _lovePhysicsWorldWrapperCache[world] = table;
  return table;
}

Value _wrapPhysicsBody(LibraryContext context, LovePhysicsBody body) {
  final cached = _lovePhysicsBodyWrapperCache[body];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _lovePhysicsBodyObjectKey: body,
    'getX': Value(
      builder.create((args) => _requirePhysicsBody(args, 0, 'Body:getX').x),
      functionName: 'getX',
    ),
    'getY': Value(
      builder.create((args) => _requirePhysicsBody(args, 0, 'Body:getY').y),
      functionName: 'getY',
    ),
    'getAngle': Value(
      builder.create(
        (args) => _requirePhysicsBody(args, 0, 'Body:getAngle').angle,
      ),
      functionName: 'getAngle',
    ),
    'getPosition': Value(
      builder.create((args) {
        final position = _requirePhysicsBody(
          args,
          0,
          'Body:getPosition',
        ).position;
        return Value.multi(<Object?>[position.x, position.y]);
      }),
      functionName: 'getPosition',
    ),
    'getTransform': Value(
      builder.create((args) {
        final body = _requirePhysicsBody(args, 0, 'Body:getTransform');
        final position = body.position;
        return Value.multi(<Object?>[position.x, position.y, body.angle]);
      }),
      functionName: 'getTransform',
    ),
    'getLinearVelocity': Value(
      builder.create((args) {
        final velocity = _requirePhysicsBody(
          args,
          0,
          'Body:getLinearVelocity',
        ).linearVelocity;
        return Value.multi(<Object?>[velocity.x, velocity.y]);
      }),
      functionName: 'getLinearVelocity',
    ),
    'getLinearVelocityFromLocalPoint': Value(
      builder.create((args) {
        final velocity =
            _requirePhysicsBody(
              args,
              0,
              'Body:getLinearVelocityFromLocalPoint',
            ).getLinearVelocityFromLocalPoint(
              _requireNumber(args, 1, 'Body:getLinearVelocityFromLocalPoint'),
              _requireNumber(args, 2, 'Body:getLinearVelocityFromLocalPoint'),
            );
        return Value.multi(<Object?>[velocity.x, velocity.y]);
      }),
      functionName: 'getLinearVelocityFromLocalPoint',
    ),
    'getLinearVelocityFromWorldPoint': Value(
      builder.create((args) {
        final velocity =
            _requirePhysicsBody(
              args,
              0,
              'Body:getLinearVelocityFromWorldPoint',
            ).getLinearVelocityFromWorldPoint(
              _requireNumber(args, 1, 'Body:getLinearVelocityFromWorldPoint'),
              _requireNumber(args, 2, 'Body:getLinearVelocityFromWorldPoint'),
            );
        return Value.multi(<Object?>[velocity.x, velocity.y]);
      }),
      functionName: 'getLinearVelocityFromWorldPoint',
    ),
    'getWorldCenter': Value(
      builder.create((args) {
        final center = _requirePhysicsBody(
          args,
          0,
          'Body:getWorldCenter',
        ).worldCenter;
        return Value.multi(<Object?>[center.x, center.y]);
      }),
      functionName: 'getWorldCenter',
    ),
    'getWorldPoint': Value(
      builder.create((args) {
        final point = _requirePhysicsBody(args, 0, 'Body:getWorldPoint')
            .getWorldPoint(
              _requireNumber(args, 1, 'Body:getWorldPoint'),
              _requireNumber(args, 2, 'Body:getWorldPoint'),
            );
        return Value.multi(<Object?>[point.x, point.y]);
      }),
      functionName: 'getWorldPoint',
    ),
    'getWorldPoints': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          final points = _coordinateSequence(
            args.skip(1).toList(growable: false),
            'Body:getWorldPoints',
          );
          return _physicsPointMulti(
            _requirePhysicsBody(
              args,
              0,
              'Body:getWorldPoints',
            ).getWorldPoints(points),
          );
        }),
      ),
      functionName: 'getWorldPoints',
    ),
    'getWorldVector': Value(
      builder.create((args) {
        final vector = _requirePhysicsBody(args, 0, 'Body:getWorldVector')
            .getWorldVector(
              _requireNumber(args, 1, 'Body:getWorldVector'),
              _requireNumber(args, 2, 'Body:getWorldVector'),
            );
        return Value.multi(<Object?>[vector.x, vector.y]);
      }),
      functionName: 'getWorldVector',
    ),
    'getLocalCenter': Value(
      builder.create((args) {
        final center = _requirePhysicsBody(
          args,
          0,
          'Body:getLocalCenter',
        ).localCenter;
        return Value.multi(<Object?>[center.x, center.y]);
      }),
      functionName: 'getLocalCenter',
    ),
    'getLocalPoint': Value(
      builder.create((args) {
        final point = _requirePhysicsBody(args, 0, 'Body:getLocalPoint')
            .getLocalPoint(
              _requireNumber(args, 1, 'Body:getLocalPoint'),
              _requireNumber(args, 2, 'Body:getLocalPoint'),
            );
        return Value.multi(<Object?>[point.x, point.y]);
      }),
      functionName: 'getLocalPoint',
    ),
    'getLocalPoints': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          final points = _coordinateSequence(
            args.skip(1).toList(growable: false),
            'Body:getLocalPoints',
          );
          return _physicsPointMulti(
            _requirePhysicsBody(
              args,
              0,
              'Body:getLocalPoints',
            ).getLocalPoints(points),
          );
        }),
      ),
      functionName: 'getLocalPoints',
    ),
    'getLocalVector': Value(
      builder.create((args) {
        final vector = _requirePhysicsBody(args, 0, 'Body:getLocalVector')
            .getLocalVector(
              _requireNumber(args, 1, 'Body:getLocalVector'),
              _requireNumber(args, 2, 'Body:getLocalVector'),
            );
        return Value.multi(<Object?>[vector.x, vector.y]);
      }),
      functionName: 'getLocalVector',
    ),
    'getAngularVelocity': Value(
      builder.create(
        (args) => _requirePhysicsBody(
          args,
          0,
          'Body:getAngularVelocity',
        ).angularVelocity,
      ),
      functionName: 'getAngularVelocity',
    ),
    'getMass': Value(
      builder.create(
        (args) => _requirePhysicsBody(args, 0, 'Body:getMass').mass,
      ),
      functionName: 'getMass',
    ),
    'getInertia': Value(
      builder.create(
        (args) => _requirePhysicsBody(args, 0, 'Body:getInertia').inertia,
      ),
      functionName: 'getInertia',
    ),
    'getMassData': Value(
      builder.create((args) {
        final data = _requirePhysicsBody(args, 0, 'Body:getMassData').massData;
        return Value.multi(<Object?>[data.x, data.y, data.mass, data.inertia]);
      }),
      functionName: 'getMassData',
    ),
    'isTouching': Value(
      builder.create((args) {
        return _physicsWithLuaErrors(
          () => _requirePhysicsBody(
            args,
            0,
            'Body:isTouching',
          ).isTouching(_requirePhysicsBody(args, 1, 'Body:isTouching')),
        );
      }),
      functionName: 'isTouching',
    ),
    'getAngularDamping': Value(
      builder.create(
        (args) => _requirePhysicsBody(
          args,
          0,
          'Body:getAngularDamping',
        ).angularDamping,
      ),
      functionName: 'getAngularDamping',
    ),
    'getLinearDamping': Value(
      builder.create(
        (args) =>
            _requirePhysicsBody(args, 0, 'Body:getLinearDamping').linearDamping,
      ),
      functionName: 'getLinearDamping',
    ),
    'getGravityScale': Value(
      builder.create(
        (args) =>
            _requirePhysicsBody(args, 0, 'Body:getGravityScale').gravityScale,
      ),
      functionName: 'getGravityScale',
    ),
    'getType': Value(
      builder.create(
        (args) => _requirePhysicsBody(args, 0, 'Body:getType').type,
      ),
      functionName: 'getType',
    ),
    'getUserData': Value(
      builder.create(
        (args) =>
            _requirePhysicsBody(args, 0, 'Body:getUserData').userDataValue,
      ),
      functionName: 'getUserData',
    ),
    'applyLinearImpulse': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          const symbol = 'Body:applyLinearImpulse';
          final body = _requirePhysicsBody(args, 0, symbol);
          final impulseX = _requireNumber(args, 1, symbol);
          final impulseY = _requireNumber(args, 2, symbol);
          if (args.length <= 4 ||
              (args.length == 4 && _rawValue(_valueAt(args, 3)) is bool)) {
            final wake = args.length >= 4
                ? _requireBoolean(args, 3, symbol)
                : true;
            body.applyLinearImpulse(impulseX, impulseY, wake: wake);
            return null;
          }
          body.applyLinearImpulse(
            impulseX,
            impulseY,
            pointX: _requireNumber(args, 3, symbol),
            pointY: _requireNumber(args, 4, symbol),
            wake: args.length >= 6 ? _requireBoolean(args, 5, symbol) : true,
          );
          return null;
        }),
      ),
      functionName: 'applyLinearImpulse',
    ),
    'applyAngularImpulse': Value(
      builder.create((args) {
        final body = _requirePhysicsBody(args, 0, 'Body:applyAngularImpulse');
        body.applyAngularImpulse(
          _requireNumber(args, 1, 'Body:applyAngularImpulse'),
          wake: args.length >= 3
              ? _requireBoolean(args, 2, 'Body:applyAngularImpulse')
              : true,
        );
        return null;
      }),
      functionName: 'applyAngularImpulse',
    ),
    'applyTorque': Value(
      builder.create((args) {
        final body = _requirePhysicsBody(args, 0, 'Body:applyTorque');
        body.applyTorque(
          _requireNumber(args, 1, 'Body:applyTorque'),
          wake: args.length >= 3
              ? _requireBoolean(args, 2, 'Body:applyTorque')
              : true,
        );
        return null;
      }),
      functionName: 'applyTorque',
    ),
    'applyForce': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          const symbol = 'Body:applyForce';
          final body = _requirePhysicsBody(args, 0, symbol);
          final forceX = _requireNumber(args, 1, symbol);
          final forceY = _requireNumber(args, 2, symbol);
          if (args.length <= 4 ||
              (args.length == 4 && _rawValue(_valueAt(args, 3)) is bool)) {
            final wake = args.length >= 4
                ? _requireBoolean(args, 3, symbol)
                : true;
            body.applyForce(forceX, forceY, wake: wake);
            return null;
          }
          body.applyForce(
            forceX,
            forceY,
            pointX: _requireNumber(args, 3, symbol),
            pointY: _requireNumber(args, 4, symbol),
            wake: args.length >= 6 ? _requireBoolean(args, 5, symbol) : true,
          );
          return null;
        }),
      ),
      functionName: 'applyForce',
    ),
    'setX': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setX',
        ).setX(_requireNumber(args, 1, 'Body:setX'));
        return null;
      }),
      functionName: 'setX',
    ),
    'setY': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setY',
        ).setY(_requireNumber(args, 1, 'Body:setY'));
        return null;
      }),
      functionName: 'setY',
    ),
    'setLinearVelocity': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setLinearVelocity',
        ).setLinearVelocity(
          _requireNumber(args, 1, 'Body:setLinearVelocity'),
          _requireNumber(args, 2, 'Body:setLinearVelocity'),
        );
        return null;
      }),
      functionName: 'setLinearVelocity',
    ),
    'setAngle': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setAngle',
        ).setAngle(_requireNumber(args, 1, 'Body:setAngle'));
        return null;
      }),
      functionName: 'setAngle',
    ),
    'setAngularVelocity': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setAngularVelocity',
        ).setAngularVelocity(
          _requireNumber(args, 1, 'Body:setAngularVelocity'),
        );
        return null;
      }),
      functionName: 'setAngularVelocity',
    ),
    'setPosition': Value(
      builder.create((args) {
        _requirePhysicsBody(args, 0, 'Body:setPosition').setPosition(
          _requireNumber(args, 1, 'Body:setPosition'),
          _requireNumber(args, 2, 'Body:setPosition'),
        );
        return null;
      }),
      functionName: 'setPosition',
    ),
    'resetMassData': Value(
      builder.create((args) {
        _requirePhysicsBody(args, 0, 'Body:resetMassData').resetMassData();
        return null;
      }),
      functionName: 'resetMassData',
    ),
    'setMassData': Value(
      builder.create((args) {
        final body = _requirePhysicsBody(args, 0, 'Body:setMassData');
        final packedMassData = _rawValue(_valueAt(args, 1));
        if (args.length == 2 &&
            packedMassData is List &&
            packedMassData.length >= 4) {
          final x = packedMassData[0];
          final y = packedMassData[1];
          final mass = packedMassData[2];
          final inertia = packedMassData[3];
          if (x is num && y is num && mass is num && inertia is num) {
            body.setMassData(
              x.toDouble(),
              y.toDouble(),
              mass.toDouble(),
              inertia.toDouble(),
            );
            return null;
          }
        }
        body.setMassData(
          _requireNumber(args, 1, 'Body:setMassData'),
          _requireNumber(args, 2, 'Body:setMassData'),
          _requireNumber(args, 3, 'Body:setMassData'),
          _requireNumber(args, 4, 'Body:setMassData'),
        );
        return null;
      }),
      functionName: 'setMassData',
    ),
    'setMass': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setMass',
        ).setMass(_requireNumber(args, 1, 'Body:setMass'));
        return null;
      }),
      functionName: 'setMass',
    ),
    'setInertia': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setInertia',
        ).setInertia(_requireNumber(args, 1, 'Body:setInertia'));
        return null;
      }),
      functionName: 'setInertia',
    ),
    'setAngularDamping': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setAngularDamping',
        ).setAngularDamping(_requireNumber(args, 1, 'Body:setAngularDamping'));
        return null;
      }),
      functionName: 'setAngularDamping',
    ),
    'setLinearDamping': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setLinearDamping',
        ).setLinearDamping(_requireNumber(args, 1, 'Body:setLinearDamping'));
        return null;
      }),
      functionName: 'setLinearDamping',
    ),
    'setGravityScale': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setGravityScale',
        ).setGravityScale(_requireNumber(args, 1, 'Body:setGravityScale'));
        return null;
      }),
      functionName: 'setGravityScale',
    ),
    'setType': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setType',
        ).setType(_requirePhysicsBodyType(args, 1, 'Body:setType'));
        return null;
      }),
      functionName: 'setType',
    ),
    'setUserData': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setUserData',
        ).setUserData(_valueAt(args, 1));
        return null;
      }),
      functionName: 'setUserData',
    ),
    'isBullet': Value(
      builder.create(
        (args) => _requirePhysicsBody(args, 0, 'Body:isBullet').isBullet,
      ),
      functionName: 'isBullet',
    ),
    'setBullet': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setBullet',
        ).setBullet(_requireBoolean(args, 1, 'Body:setBullet'));
        return null;
      }),
      functionName: 'setBullet',
    ),
    'isActive': Value(
      builder.create(
        (args) => _requirePhysicsBody(args, 0, 'Body:isActive').isActive,
      ),
      functionName: 'isActive',
    ),
    'isAwake': Value(
      builder.create(
        (args) => _requirePhysicsBody(args, 0, 'Body:isAwake').isAwake,
      ),
      functionName: 'isAwake',
    ),
    'setSleepingAllowed': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setSleepingAllowed',
        ).setSleepingAllowed(
          _requireBoolean(args, 1, 'Body:setSleepingAllowed'),
        );
        return null;
      }),
      functionName: 'setSleepingAllowed',
    ),
    'isSleepingAllowed': Value(
      builder.create(
        (args) => _requirePhysicsBody(
          args,
          0,
          'Body:isSleepingAllowed',
        ).isSleepingAllowed,
      ),
      functionName: 'isSleepingAllowed',
    ),
    'setActive': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setActive',
        ).setActive(_requireBoolean(args, 1, 'Body:setActive'));
        return null;
      }),
      functionName: 'setActive',
    ),
    'setAwake': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setAwake',
        ).setAwake(_requireBoolean(args, 1, 'Body:setAwake'));
        return null;
      }),
      functionName: 'setAwake',
    ),
    'setFixedRotation': Value(
      builder.create((args) {
        _requirePhysicsBody(
          args,
          0,
          'Body:setFixedRotation',
        ).setFixedRotation(_requireBoolean(args, 1, 'Body:setFixedRotation'));
        return null;
      }),
      functionName: 'setFixedRotation',
    ),
    'isFixedRotation': Value(
      builder.create(
        (args) => _requirePhysicsBody(
          args,
          0,
          'Body:isFixedRotation',
        ).isFixedRotation,
      ),
      functionName: 'isFixedRotation',
    ),
    'getWorld': Value(
      builder.create((args) {
        return _wrapPhysicsWorld(
          context,
          _requirePhysicsBody(args, 0, 'Body:getWorld').world,
        );
      }),
      functionName: 'getWorld',
    ),
    'getFixtures': Value(
      builder.create((args) {
        final body = _requirePhysicsBody(args, 0, 'Body:getFixtures');
        return _physicsArray(
          body.fixtures.map((fixture) => _wrapPhysicsFixture(context, fixture)),
        );
      }),
      functionName: 'getFixtures',
    ),
    'getJoints': Value(
      builder.create((args) {
        final body = _requirePhysicsBody(args, 0, 'Body:getJoints');
        return _physicsArray(
          body.joints.map((joint) => _wrapPhysicsJoint(context, joint)),
        );
      }),
      functionName: 'getJoints',
    ),
    'getJointList': Value(
      builder.create((args) {
        final body = _requirePhysicsBody(args, 0, 'Body:getJointList');
        return _physicsArray(
          body.joints.map((joint) => _wrapPhysicsJoint(context, joint)),
        );
      }),
      functionName: 'getJointList',
    ),
    'getContacts': Value(
      builder.create((args) {
        final body = _requirePhysicsBody(args, 0, 'Body:getContacts');
        return _physicsArray(
          body.contacts.map((contact) => _wrapPhysicsContact(context, contact)),
        );
      }),
      functionName: 'getContacts',
    ),
    'getContactList': Value(
      builder.create((args) {
        final body = _requirePhysicsBody(args, 0, 'Body:getContactList');
        return _physicsArray(
          body.contacts.map((contact) => _wrapPhysicsContact(context, contact)),
        );
      }),
      functionName: 'getContactList',
    ),
    'destroy': Value(
      builder.create((args) {
        _physicsBodyIfPresent(_valueAt(args, 0))?.destroy();
        return null;
      }),
      functionName: 'destroy',
    ),
    'isDestroyed': Value(
      builder.create(
        (args) =>
            (_physicsBodyIfPresent(_valueAt(args, 0))?.isDestroyed) ?? false,
      ),
      functionName: 'isDestroyed',
    ),
    'setTransform': Value(
      builder.create((args) {
        _requirePhysicsBody(args, 0, 'Body:setTransform').setTransform(
          _requireNumber(args, 1, 'Body:setTransform'),
          _requireNumber(args, 2, 'Body:setTransform'),
          _requireNumber(args, 3, 'Body:setTransform'),
        );
        return null;
      }),
      functionName: 'setTransform',
    ),
    ..._physicsObjectEntries<LovePhysicsBody>(
      builder: builder,
      object: body,
      typeName: 'Body',
      hierarchy: const <String>{'Body', 'Object'},
      requireObject: (args, symbol) => _requirePhysicsBody(args, 0, symbol),
    ),
  });
  _lovePhysicsBodyWrapperCache[body] = table;
  return table;
}

Value _wrapPhysicsFixture(LibraryContext context, LovePhysicsFixture fixture) {
  final cached = _lovePhysicsFixtureWrapperCache[fixture];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _lovePhysicsFixtureObjectKey: fixture,
    'getType': Value(
      builder.create(
        (args) => _requirePhysicsFixture(args, 0, 'Fixture:getType').type,
      ),
      functionName: 'getType',
    ),
    'setFriction': Value(
      builder.create((args) {
        _requirePhysicsFixture(
          args,
          0,
          'Fixture:setFriction',
        ).setFriction(_requireNumber(args, 1, 'Fixture:setFriction'));
        return null;
      }),
      functionName: 'setFriction',
    ),
    'setRestitution': Value(
      builder.create((args) {
        _requirePhysicsFixture(
          args,
          0,
          'Fixture:setRestitution',
        ).setRestitution(_requireNumber(args, 1, 'Fixture:setRestitution'));
        return null;
      }),
      functionName: 'setRestitution',
    ),
    'setDensity': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          _requirePhysicsFixture(
            args,
            0,
            'Fixture:setDensity',
          ).setDensity(_requireNumber(args, 1, 'Fixture:setDensity'));
          return null;
        }),
      ),
      functionName: 'setDensity',
    ),
    'setSensor': Value(
      builder.create((args) {
        _requirePhysicsFixture(
          args,
          0,
          'Fixture:setSensor',
        ).setSensor(_requireBoolean(args, 1, 'Fixture:setSensor'));
        return null;
      }),
      functionName: 'setSensor',
    ),
    'setUserData': Value(
      builder.create((args) {
        _requirePhysicsFixture(
          args,
          0,
          'Fixture:setUserData',
        ).setUserData(_valueAt(args, 1));
        return null;
      }),
      functionName: 'setUserData',
    ),
    'setFilterData': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          _requirePhysicsFixture(
            args,
            0,
            'Fixture:setFilterData',
          ).setFilterData(
            _requireRoundedInt(args, 1, 'Fixture:setFilterData'),
            _requireRoundedInt(args, 2, 'Fixture:setFilterData'),
            _requireRoundedInt(args, 3, 'Fixture:setFilterData'),
          );
          return null;
        }),
      ),
      functionName: 'setFilterData',
    ),
    'setCategory': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          _requirePhysicsFixture(args, 0, 'Fixture:setCategory').setCategories(
            _physicsCategorySequence(args, 1, 'Fixture:setCategory'),
          );
          return null;
        }),
      ),
      functionName: 'setCategory',
    ),
    'setMask': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          _requirePhysicsFixture(args, 0, 'Fixture:setMask').setMaskCategories(
            _physicsCategorySequence(args, 1, 'Fixture:setMask'),
          );
          return null;
        }),
      ),
      functionName: 'setMask',
    ),
    'setGroupIndex': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          _requirePhysicsFixture(
            args,
            0,
            'Fixture:setGroupIndex',
          ).setGroupIndex(_requireRoundedInt(args, 1, 'Fixture:setGroupIndex'));
          return null;
        }),
      ),
      functionName: 'setGroupIndex',
    ),
    'getFriction': Value(
      builder.create(
        (args) =>
            _requirePhysicsFixture(args, 0, 'Fixture:getFriction').friction,
      ),
      functionName: 'getFriction',
    ),
    'getRestitution': Value(
      builder.create(
        (args) => _requirePhysicsFixture(
          args,
          0,
          'Fixture:getRestitution',
        ).restitution,
      ),
      functionName: 'getRestitution',
    ),
    'getDensity': Value(
      builder.create(
        (args) => _requirePhysicsFixture(args, 0, 'Fixture:getDensity').density,
      ),
      functionName: 'getDensity',
    ),
    'getFilterData': Value(
      builder.create((args) {
        final filterData = _requirePhysicsFixture(
          args,
          0,
          'Fixture:getFilterData',
        ).filterData;
        return Value.multi(<Object?>[
          filterData.categories,
          filterData.mask,
          filterData.group,
        ]);
      }),
      functionName: 'getFilterData',
    ),
    'getCategory': Value(
      builder.create((args) {
        final fixture = _requirePhysicsFixture(args, 0, 'Fixture:getCategory');
        return Value.multi(fixture.categories.cast<Object?>());
      }),
      functionName: 'getCategory',
    ),
    'getMask': Value(
      builder.create((args) {
        final fixture = _requirePhysicsFixture(args, 0, 'Fixture:getMask');
        return Value.multi(fixture.maskCategories.cast<Object?>());
      }),
      functionName: 'getMask',
    ),
    'getGroupIndex': Value(
      builder.create(
        (args) =>
            _requirePhysicsFixture(args, 0, 'Fixture:getGroupIndex').groupIndex,
      ),
      functionName: 'getGroupIndex',
    ),
    'getBody': Value(
      builder.create((args) {
        return _wrapPhysicsBody(
          context,
          _requirePhysicsFixture(args, 0, 'Fixture:getBody').body,
        );
      }),
      functionName: 'getBody',
    ),
    'getShape': Value(
      builder.create((args) {
        return _wrapPhysicsShape(
          context,
          _requirePhysicsFixture(args, 0, 'Fixture:getShape').shape,
        );
      }),
      functionName: 'getShape',
    ),
    'getUserData': Value(
      builder.create(
        (args) => _requirePhysicsFixture(
          args,
          0,
          'Fixture:getUserData',
        ).userDataValue,
      ),
      functionName: 'getUserData',
    ),
    'isSensor': Value(
      builder.create(
        (args) => _requirePhysicsFixture(args, 0, 'Fixture:isSensor').isSensor,
      ),
      functionName: 'isSensor',
    ),
    'getBoundingBox': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          final box = _requirePhysicsFixture(args, 0, 'Fixture:getBoundingBox')
              .getBoundingBox(
                args.length >= 2 && _valueAt(args, 1) != null
                    ? _requireRoundedInt(args, 1, 'Fixture:getBoundingBox')
                    : 1,
              );
          return Value.multi(<Object?>[box.minX, box.minY, box.maxX, box.maxY]);
        }),
      ),
      functionName: 'getBoundingBox',
    ),
    'getMassData': Value(
      builder.create((args) {
        final data = _requirePhysicsFixture(
          args,
          0,
          'Fixture:getMassData',
        ).getMassData();
        return Value.multi(<Object?>[data.x, data.y, data.mass, data.inertia]);
      }),
      functionName: 'getMassData',
    ),
    'rayCast': Value(
      builder.create((args) {
        final hit = _physicsWithLuaErrors(
          () => _requirePhysicsFixture(args, 0, 'Fixture:rayCast').rayCast(
            _requireNumber(args, 1, 'Fixture:rayCast'),
            _requireNumber(args, 2, 'Fixture:rayCast'),
            _requireNumber(args, 3, 'Fixture:rayCast'),
            _requireNumber(args, 4, 'Fixture:rayCast'),
            _requireNumber(args, 5, 'Fixture:rayCast'),
            childIndex: args.length >= 7
                ? _requireRoundedInt(args, 6, 'Fixture:rayCast')
                : 1,
          ),
        );
        return hit == null
            ? _physicsNoResults()
            : Value.multi(<Object?>[hit.normalX, hit.normalY, hit.fraction]);
      }),
      functionName: 'rayCast',
    ),
    'testPoint': Value(
      builder.create((args) {
        return _requirePhysicsFixture(args, 0, 'Fixture:testPoint').testPoint(
          _requireNumber(args, 1, 'Fixture:testPoint'),
          _requireNumber(args, 2, 'Fixture:testPoint'),
        );
      }),
      functionName: 'testPoint',
    ),
    'destroy': Value(
      builder.create((args) {
        _physicsFixtureIfPresent(_valueAt(args, 0))?.destroy();
        return null;
      }),
      functionName: 'destroy',
    ),
    'isDestroyed': Value(
      builder.create(
        (args) =>
            (_physicsFixtureIfPresent(_valueAt(args, 0))?.isDestroyed) ?? false,
      ),
      functionName: 'isDestroyed',
    ),
    ..._physicsObjectEntries<LovePhysicsFixture>(
      builder: builder,
      object: fixture,
      typeName: 'Fixture',
      hierarchy: const <String>{'Fixture', 'Object'},
      requireObject: (args, symbol) => _requirePhysicsFixture(args, 0, symbol),
    ),
  });
  _lovePhysicsFixtureWrapperCache[fixture] = table;
  return table;
}

Value _wrapPhysicsShape(LibraryContext context, LovePhysicsShape shape) {
  final cached = _lovePhysicsShapeWrapperCache[shape];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final hierarchy = <String>{shape.objectTypeName, 'Shape', 'Object'};
  final entries = <Object?, Object?>{
    _lovePhysicsShapeObjectKey: shape,
    'getType': Value(
      builder.create(
        (args) => _requirePhysicsShape(args, 0, 'Shape:getType').shapeTypeName,
      ),
      functionName: 'getType',
    ),
    'getRadius': Value(
      builder.create(
        (args) => _requirePhysicsShape(args, 0, 'Shape:getRadius').radius,
      ),
      functionName: 'getRadius',
    ),
    'getChildCount': Value(
      builder.create(
        (args) =>
            _requirePhysicsShape(args, 0, 'Shape:getChildCount').childCount,
      ),
      functionName: 'getChildCount',
    ),
    'testPoint': Value(
      builder.create((args) {
        final shape = _requirePhysicsShape(args, 0, 'Shape:testPoint');
        return _physicsWithLuaErrors(
          () => shape.testPoint(
            _requireNumber(args, 1, 'Shape:testPoint'),
            _requireNumber(args, 2, 'Shape:testPoint'),
            _requireNumber(args, 3, 'Shape:testPoint'),
            _requireNumber(args, 4, 'Shape:testPoint'),
            _requireNumber(args, 5, 'Shape:testPoint'),
          ),
        );
      }),
      functionName: 'testPoint',
    ),
    'rayCast': Value(
      builder.create((args) {
        final hit = _physicsWithLuaErrors(
          () => _requirePhysicsShape(args, 0, 'Shape:rayCast').rayCast(
            _requireNumber(args, 1, 'Shape:rayCast'),
            _requireNumber(args, 2, 'Shape:rayCast'),
            _requireNumber(args, 3, 'Shape:rayCast'),
            _requireNumber(args, 4, 'Shape:rayCast'),
            _requireNumber(args, 5, 'Shape:rayCast'),
            _requireNumber(args, 6, 'Shape:rayCast'),
            _requireNumber(args, 7, 'Shape:rayCast'),
            _requireNumber(args, 8, 'Shape:rayCast'),
            childIndex: args.length >= 10
                ? _requireRoundedInt(args, 9, 'Shape:rayCast')
                : 1,
          ),
        );
        return hit == null
            ? _physicsNoResults()
            : Value.multi(<Object?>[hit.normalX, hit.normalY, hit.fraction]);
      }),
      functionName: 'rayCast',
    ),
    'computeAABB': Value(
      builder.create((args) {
        final result = _physicsWithLuaErrors(
          () => _requirePhysicsShape(args, 0, 'Shape:computeAABB').computeAabb(
            _requireNumber(args, 1, 'Shape:computeAABB'),
            _requireNumber(args, 2, 'Shape:computeAABB'),
            _requireNumber(args, 3, 'Shape:computeAABB'),
            childIndex: args.length >= 5
                ? _requireRoundedInt(args, 4, 'Shape:computeAABB')
                : 1,
          ),
        );
        return Value.multi(<Object?>[
          result.minX,
          result.minY,
          result.maxX,
          result.maxY,
        ]);
      }),
      functionName: 'computeAABB',
    ),
    'computeMass': Value(
      builder.create((args) {
        final result = _requirePhysicsShape(
          args,
          0,
          'Shape:computeMass',
        ).computeMass(_requireNumber(args, 1, 'Shape:computeMass'));
        return Value.multi(<Object?>[
          result.x,
          result.y,
          result.mass,
          result.inertia,
        ]);
      }),
      functionName: 'computeMass',
    ),
    ..._physicsObjectEntries<LovePhysicsShape>(
      builder: builder,
      object: shape,
      typeName: shape.objectTypeName,
      hierarchy: hierarchy,
      requireObject: (args, symbol) => _requirePhysicsShape(args, 0, symbol),
    ),
  };

  switch (shape) {
    case LovePhysicsCircleShape():
      entries.addAll(<Object?, Object?>{
        'getPoint': Value(
          builder.create((args) {
            final point =
                (_requirePhysicsShape(args, 0, 'CircleShape:getPoint')
                        as LovePhysicsCircleShape)
                    .point;
            return Value.multi(<Object?>[point.x, point.y]);
          }),
          functionName: 'getPoint',
        ),
        'setPoint': Value(
          builder.create((args) {
            (_requirePhysicsShape(args, 0, 'CircleShape:setPoint')
                    as LovePhysicsCircleShape)
                .setPoint(
                  _requireNumber(args, 1, 'CircleShape:setPoint'),
                  _requireNumber(args, 2, 'CircleShape:setPoint'),
                );
            return null;
          }),
          functionName: 'setPoint',
        ),
        'setRadius': Value(
          builder.create((args) {
            (_requirePhysicsShape(args, 0, 'CircleShape:setRadius')
                    as LovePhysicsCircleShape)
                .setRadius(_requireNumber(args, 1, 'CircleShape:setRadius'));
            return null;
          }),
          functionName: 'setRadius',
        ),
      });
    case LovePhysicsPolygonShape():
      entries.addAll(<Object?, Object?>{
        'getPoints': Value(
          builder.create((args) {
            final shape =
                _requirePhysicsShape(args, 0, 'PolygonShape:getPoints')
                    as LovePhysicsPolygonShape;
            return _physicsPointMulti(shape.points);
          }),
          functionName: 'getPoints',
        ),
        'validate': Value(
          builder.create(
            (args) =>
                (_requirePhysicsShape(args, 0, 'PolygonShape:validate')
                        as LovePhysicsPolygonShape)
                    .validate(),
          ),
          functionName: 'validate',
        ),
      });
    case LovePhysicsEdgeShape():
      entries.addAll(<Object?, Object?>{
        'getPoints': Value(
          builder.create((args) {
            final shape =
                _requirePhysicsShape(args, 0, 'EdgeShape:getPoints')
                    as LovePhysicsEdgeShape;
            return _physicsPointMulti(shape.points);
          }),
          functionName: 'getPoints',
        ),
        'getNextVertex': Value(
          builder.create((args) {
            final point =
                (_requirePhysicsShape(args, 0, 'EdgeShape:getNextVertex')
                        as LovePhysicsEdgeShape)
                    .nextVertex;
            return point == null
                ? _physicsNoResults()
                : Value.multi(<Object?>[point.x, point.y]);
          }),
          functionName: 'getNextVertex',
        ),
        'getPreviousVertex': Value(
          builder.create((args) {
            final point =
                (_requirePhysicsShape(args, 0, 'EdgeShape:getPreviousVertex')
                        as LovePhysicsEdgeShape)
                    .previousVertex;
            return point == null
                ? _physicsNoResults()
                : Value.multi(<Object?>[point.x, point.y]);
          }),
          functionName: 'getPreviousVertex',
        ),
        'setNextVertex': Value(
          builder.create((args) {
            (_requirePhysicsShape(args, 0, 'EdgeShape:setNextVertex')
                    as LovePhysicsEdgeShape)
                .setNextVertex(
                  args.length >= 3
                      ? _requireNumber(args, 1, 'EdgeShape:setNextVertex')
                      : null,
                  args.length >= 3
                      ? _requireNumber(args, 2, 'EdgeShape:setNextVertex')
                      : null,
                );
            return null;
          }),
          functionName: 'setNextVertex',
        ),
        'setPreviousVertex': Value(
          builder.create((args) {
            (_requirePhysicsShape(args, 0, 'EdgeShape:setPreviousVertex')
                    as LovePhysicsEdgeShape)
                .setPreviousVertex(
                  args.length >= 3
                      ? _requireNumber(args, 1, 'EdgeShape:setPreviousVertex')
                      : null,
                  args.length >= 3
                      ? _requireNumber(args, 2, 'EdgeShape:setPreviousVertex')
                      : null,
                );
            return null;
          }),
          functionName: 'setPreviousVertex',
        ),
      });
    case LovePhysicsChainShape():
      entries.addAll(<Object?, Object?>{
        'getChildEdge': Value(
          builder.create(
            (args) => _physicsWithLuaErrors(() {
              final shape =
                  _requirePhysicsShape(args, 0, 'ChainShape:getChildEdge')
                      as LovePhysicsChainShape;
              return _wrapPhysicsShape(
                context,
                shape.childEdgeAt(
                  _requireRoundedInt(args, 1, 'ChainShape:getChildEdge'),
                ),
              );
            }),
          ),
          functionName: 'getChildEdge',
        ),
        'getVertexCount': Value(
          builder.create(
            (args) =>
                (_requirePhysicsShape(args, 0, 'ChainShape:getVertexCount')
                        as LovePhysicsChainShape)
                    .vertexCount,
          ),
          functionName: 'getVertexCount',
        ),
        'getPoint': Value(
          builder.create(
            (args) => _physicsWithLuaErrors(() {
              final point =
                  (_requirePhysicsShape(args, 0, 'ChainShape:getPoint')
                          as LovePhysicsChainShape)
                      .pointAt(
                        _requireRoundedInt(args, 1, 'ChainShape:getPoint'),
                      );
              return Value.multi(<Object?>[point.x, point.y]);
            }),
          ),
          functionName: 'getPoint',
        ),
        'getPoints': Value(
          builder.create((args) {
            final shape =
                _requirePhysicsShape(args, 0, 'ChainShape:getPoints')
                    as LovePhysicsChainShape;
            return _physicsPointMulti(shape.points);
          }),
          functionName: 'getPoints',
        ),
        'getNextVertex': Value(
          builder.create((args) {
            final point =
                (_requirePhysicsShape(args, 0, 'ChainShape:getNextVertex')
                        as LovePhysicsChainShape)
                    .nextVertex;
            return point == null
                ? _physicsNoResults()
                : Value.multi(<Object?>[point.x, point.y]);
          }),
          functionName: 'getNextVertex',
        ),
        'getPreviousVertex': Value(
          builder.create((args) {
            final point =
                (_requirePhysicsShape(args, 0, 'ChainShape:getPreviousVertex')
                        as LovePhysicsChainShape)
                    .previousVertex;
            return point == null
                ? _physicsNoResults()
                : Value.multi(<Object?>[point.x, point.y]);
          }),
          functionName: 'getPreviousVertex',
        ),
        'setNextVertex': Value(
          builder.create((args) {
            (_requirePhysicsShape(args, 0, 'ChainShape:setNextVertex')
                    as LovePhysicsChainShape)
                .setNextVertex(
                  args.length >= 3
                      ? _requireNumber(args, 1, 'ChainShape:setNextVertex')
                      : null,
                  args.length >= 3
                      ? _requireNumber(args, 2, 'ChainShape:setNextVertex')
                      : null,
                );
            return null;
          }),
          functionName: 'setNextVertex',
        ),
        'setPreviousVertex': Value(
          builder.create((args) {
            (_requirePhysicsShape(args, 0, 'ChainShape:setPreviousVertex')
                    as LovePhysicsChainShape)
                .setPreviousVertex(
                  args.length >= 3
                      ? _requireNumber(args, 1, 'ChainShape:setPreviousVertex')
                      : null,
                  args.length >= 3
                      ? _requireNumber(args, 2, 'ChainShape:setPreviousVertex')
                      : null,
                );
            return null;
          }),
          functionName: 'setPreviousVertex',
        ),
      });
  }

  final table = ValueClass.table(entries);
  _lovePhysicsShapeWrapperCache[shape] = table;
  return table;
}
