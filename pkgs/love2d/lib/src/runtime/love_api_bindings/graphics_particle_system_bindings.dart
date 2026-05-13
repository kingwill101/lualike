part of '../love_api_bindings.dart';

/// Returns the wrapped [LoveParticleSystem] stored in [value], if any.
LoveParticleSystem? _particleSystemIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final particleSystem = table[_loveParticleSystemObjectKey];
  return particleSystem is LoveParticleSystem ? particleSystem : null;
}

/// Returns the particle system argument at [index] or throws a [LuaError].
LoveParticleSystem _requireParticleSystem(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _valueAt(args, index);
  if (_particleSystemWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final particleSystem = _particleSystemIfPresent(value);
  if (particleSystem != null) {
    return particleSystem;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'ParticleSystem',
    actual: value,
  );
}

/// Binds `love.graphics.newParticleSystem`.
LoveApiImplementation _bindGraphicsNewParticleSystem(
  LibraryRegistrationContext context,
) {
  return (args) {
    const symbol = 'love.graphics.newParticleSystem';
    final texture = _requireImage(args, 0, symbol);
    final bufferSize = _requireRoundedInt(args, 1, symbol);
    if (bufferSize <= 0) {
      throw LuaError('$symbol buffer must be > 0');
    }

    return _wrapParticleSystem(
      context,
      LoveParticleSystem(texture: texture, bufferSize: bufferSize),
    );
  };
}
