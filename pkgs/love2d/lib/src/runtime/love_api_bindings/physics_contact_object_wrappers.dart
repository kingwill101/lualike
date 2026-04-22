part of '../love_api_bindings.dart';

/// Returns the wrapped physics contact stored in [value], if any.
LovePhysicsContact? _physicsContactIfPresent(Object? value) {
  final table = _physicsWrapperTable(value);
  final contact = table?[_lovePhysicsContactObjectKey];
  return contact is LovePhysicsContact ? contact : null;
}

/// Returns the live physics contact at [index].
///
/// Throws a [LuaError] when the argument is not a contact wrapper or when the
/// wrapped contact has already been destroyed.
LovePhysicsContact _requirePhysicsContact(
  List<Object?> args,
  int index,
  String symbol,
) {
  return _requirePhysicsTypedObject<LovePhysicsContact>(
    args: args,
    index: index,
    symbol: symbol,
    typeName: 'Contact',
    ifPresent: _physicsContactIfPresent,
    isDestroyed: (contact) => contact.isDestroyed,
    destroyedMessage: 'Attempt to use destroyed contact.',
  );
}

/// Wraps a physics contact in the Lua-facing contact API table.
///
/// Wrapper tables are cached per contact so repeated crossings between Dart and
/// Lua preserve object identity while the contact remains alive.
Value _wrapPhysicsContact(LibraryContext context, LovePhysicsContact contact) {
  final cached = _lovePhysicsContactWrapperCache[contact];
  if (cached != null && !_physicsWrapperReleasedAs(cached, 'Contact')) {
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
    'getTangentSpeed': Value(
      builder.create(
        (args) => _requirePhysicsContact(
          args,
          0,
          'Contact:getTangentSpeed',
        ).tangentSpeed,
      ),
      functionName: 'getTangentSpeed',
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
    'setTangentSpeed': Value(
      builder.create((args) {
        _requirePhysicsContact(
          args,
          0,
          'Contact:setTangentSpeed',
        ).setTangentSpeed(_requireNumber(args, 1, 'Contact:setTangentSpeed'));
        return null;
      }),
      functionName: 'setTangentSpeed',
    ),
    'isDestroyed': Value(
      builder.create((args) {
        final table = _requirePhysicsReceiverTable(
          args,
          0,
          'Contact:isDestroyed',
          'Contact',
        );
        final contact =
            table[_lovePhysicsContactObjectKey] as LovePhysicsContact?;
        return contact?.isDestroyed ?? false;
      }),
      functionName: 'isDestroyed',
    ),
    ..._physicsObjectEntries<LovePhysicsContact>(
      builder: builder,
      object: contact,
      objectKey: _lovePhysicsContactObjectKey,
      typeName: 'Contact',
      hierarchy: const <String>{'Contact', 'Object'},
      requireObject: (args, symbol) => _requirePhysicsContact(args, 0, symbol),
    ),
  });
  _lovePhysicsContactWrapperCache[contact] = table;
  return table;
}
