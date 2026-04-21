part of '../love_api_bindings.dart';

LovePhysicsContact? _physicsContactIfPresent(Object? value) {
  final table = _physicsWrapperTable(value);
  final contact = table?[_lovePhysicsContactObjectKey];
  return contact is LovePhysicsContact ? contact : null;
}

LovePhysicsContact _requirePhysicsContact(
  List<Object?> args,
  int index,
  String symbol,
) {
  final contact = _physicsContactIfPresent(_valueAt(args, index));
  if (contact == null) {
    throw LuaError('$symbol expected a Contact at argument ${index + 1}');
  }
  if (contact.isDestroyed) {
    throw LuaError('Attempt to use destroyed contact.');
  }
  return contact;
}

Value _wrapPhysicsContact(LibraryContext context, LovePhysicsContact contact) {
  final cached = _lovePhysicsContactWrapperCache[contact];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _lovePhysicsContactObjectKey: contact,
    'getChildren': Value(
      builder.create((args) {
        final children = _requirePhysicsContact(
          args,
          0,
          'Contact:getChildren',
        ).children;
        return Value.multi(<Object?>[children.indexA, children.indexB]);
      }),
      functionName: 'getChildren',
    ),
    'getFixtures': Value(
      builder.create(
        (args) => _physicsWithLuaErrors(() {
          final fixtures = _requirePhysicsContact(
            args,
            0,
            'Contact:getFixtures',
          ).fixtures;
          return Value.multi(<Object?>[
            _wrapPhysicsFixture(context, fixtures.fixtureA),
            _wrapPhysicsFixture(context, fixtures.fixtureB),
          ]);
        }),
      ),
      functionName: 'getFixtures',
    ),
    'getFriction': Value(
      builder.create(
        (args) =>
            _requirePhysicsContact(args, 0, 'Contact:getFriction').friction,
      ),
      functionName: 'getFriction',
    ),
    'getNormal': Value(
      builder.create((args) {
        final normal = _requirePhysicsContact(
          args,
          0,
          'Contact:getNormal',
        ).normal;
        return Value.multi(<Object?>[normal.x, normal.y]);
      }),
      functionName: 'getNormal',
    ),
    'getPositions': Value(
      builder.create((args) {
        final positions = _requirePhysicsContact(
          args,
          0,
          'Contact:getPositions',
        ).positions;
        return positions.isEmpty
            ? _physicsNoResults()
            : _physicsPointMulti(positions);
      }),
      functionName: 'getPositions',
    ),
    'getRestitution': Value(
      builder.create(
        (args) => _requirePhysicsContact(
          args,
          0,
          'Contact:getRestitution',
        ).restitution,
      ),
      functionName: 'getRestitution',
    ),
    'isEnabled': Value(
      builder.create(
        (args) =>
            _requirePhysicsContact(args, 0, 'Contact:isEnabled').isEnabled,
      ),
      functionName: 'isEnabled',
    ),
    'isTouching': Value(
      builder.create(
        (args) =>
            _requirePhysicsContact(args, 0, 'Contact:isTouching').isTouching,
      ),
      functionName: 'isTouching',
    ),
    'resetFriction': Value(
      builder.create((args) {
        _requirePhysicsContact(
          args,
          0,
          'Contact:resetFriction',
        ).resetFriction();
        return null;
      }),
      functionName: 'resetFriction',
    ),
    'resetRestitution': Value(
      builder.create((args) {
        _requirePhysicsContact(
          args,
          0,
          'Contact:resetRestitution',
        ).resetRestitution();
        return null;
      }),
      functionName: 'resetRestitution',
    ),
    'setEnabled': Value(
      builder.create((args) {
        _requirePhysicsContact(
          args,
          0,
          'Contact:setEnabled',
        ).setEnabled(_requireBoolean(args, 1, 'Contact:setEnabled'));
        return null;
      }),
      functionName: 'setEnabled',
    ),
    'setFriction': Value(
      builder.create((args) {
        _requirePhysicsContact(
          args,
          0,
          'Contact:setFriction',
        ).setFriction(_requireNumber(args, 1, 'Contact:setFriction'));
        return null;
      }),
      functionName: 'setFriction',
    ),
    'setRestitution': Value(
      builder.create((args) {
        _requirePhysicsContact(
          args,
          0,
          'Contact:setRestitution',
        ).setRestitution(_requireNumber(args, 1, 'Contact:setRestitution'));
        return null;
      }),
      functionName: 'setRestitution',
    ),
    'isDestroyed': Value(
      builder.create(
        (args) =>
            (_physicsContactIfPresent(_valueAt(args, 0))?.isDestroyed) ?? false,
      ),
      functionName: 'isDestroyed',
    ),
    ..._physicsObjectEntries<LovePhysicsContact>(
      builder: builder,
      object: contact,
      typeName: 'Contact',
      hierarchy: const <String>{'Contact', 'Object'},
      requireObject: (args, symbol) => _requirePhysicsContact(args, 0, symbol),
    ),
  });
  _lovePhysicsContactWrapperCache[contact] = table;
  return table;
}
