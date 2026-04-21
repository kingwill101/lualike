part of '../love_api_bindings.dart';

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

LoveParticleSystem _requireParticleSystem(
  List<Object?> args,
  int index,
  String symbol,
) {
  final particleSystem = _particleSystemIfPresent(_valueAt(args, index));
  if (particleSystem != null) {
    return particleSystem;
  }

  throw LuaError('$symbol expected a ParticleSystem at argument ${index + 1}');
}

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
