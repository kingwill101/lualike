part of '../love_api_bindings.dart';

/// Returns the wrapped [LoveSpriteBatch] stored in [value], if any.
LoveSpriteBatch? _spriteBatchIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final spriteBatch = table[_loveSpriteBatchObjectKey];
  return spriteBatch is LoveSpriteBatch ? spriteBatch : null;
}

/// Returns the sprite batch argument at [index] or throws a [LuaError].
LoveSpriteBatch _requireSpriteBatch(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _valueAt(args, index);
  if (_spriteBatchWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final spriteBatch = _spriteBatchIfPresent(value);
  if (spriteBatch != null) {
    return spriteBatch;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'SpriteBatch',
    actual: value,
  );
}

/// Binds `love.graphics.newSpriteBatch`.
LoveApiImplementation _bindGraphicsNewSpriteBatch(
  LibraryRegistrationContext context,
) {
  return (args) {
    const symbol = 'love.graphics.newSpriteBatch';
    final texture = _requireImage(args, 0, symbol);
    final bufferSize = args.length >= 2
        ? _requireRoundedInt(args, 1, symbol)
        : 1000;
    if (bufferSize <= 0) {
      throw LuaError('$symbol maxsprites must be > 0');
    }

    final usage = _spriteBatchUsage(_valueAt(args, 2), symbol);
    return _wrapSpriteBatch(
      context,
      LoveSpriteBatch(texture: texture, bufferSize: bufferSize, usage: usage),
    );
  };
}

/// Returns the validated sprite-batch usage hint for [value].
///
/// Missing values default to LOVE's `dynamic` usage.
LoveSpriteBatchUsage _spriteBatchUsage(Object? value, String symbol) {
  final raw = _stringLike(value);
  if (raw == null) {
    return LoveSpriteBatchUsage.dynamicUsage;
  }

  return switch (raw) {
    'dynamic' => LoveSpriteBatchUsage.dynamicUsage,
    'static' => LoveSpriteBatchUsage.staticUsage,
    'stream' => LoveSpriteBatchUsage.stream,
    _ => throw LuaError('$symbol invalid usage hint "$raw"'),
  };
}
