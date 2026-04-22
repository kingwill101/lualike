part of '../love_api_bindings.dart';

const String _loveSpriteBatchReleasedWrapperKey =
    '__love2d_sprite_batch_released__';

final Expando<bool> _loveSpriteBatchReleased = Expando<bool>(
  'love2dSpriteBatchReleased',
);

Map<dynamic, dynamic>? _spriteBatchWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final spriteBatch = table[_loveSpriteBatchObjectKey];
  if (spriteBatch is LoveSpriteBatch ||
      table[_loveSpriteBatchReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

bool _spriteBatchWrapperReleased(Object? value) {
  final table = _spriteBatchWrapperTableIfPresent(value);
  return table?[_loveSpriteBatchReleasedWrapperKey] == true;
}

/// Wraps [spriteBatch] in the Lua-facing `SpriteBatch` object table.
///
/// The returned table exposes LOVE 11.5 batch mutation and inspection methods
/// while preserving wrapper identity through the shared sprite-batch cache.
Value _wrapSpriteBatch(
  LibraryRegistrationContext context,
  LoveSpriteBatch spriteBatch,
) {
  final cached = _loveSpriteBatchWrapperCache[spriteBatch];
  if (cached != null && _spriteBatchWrapperTableIfPresent(cached) != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'SpriteBatch', 'Drawable', 'Object'};

  final table = ValueClass.table(<Object?, Object?>{
    _loveSpriteBatchObjectKey: spriteBatch,
    'add': Value(
      builder.create((args) {
        final spriteBatch = _requireSpriteBatch(args, 0, 'SpriteBatch:add');
        final quad = _quadIfPresent(_valueAt(args, 1));
        final startIndex = quad == null ? 1 : 2;
        final index = spriteBatch.add(
          _matrixFromTransformArgumentOrStandardTransform(
            args,
            startIndex,
            'SpriteBatch:add',
          ),
          quad: quad,
        );
        return index + 1;
      }),
      functionName: 'add',
    ),
    'addLayer': Value(
      builder.create((args) {
        const symbol = 'SpriteBatch:addLayer';
        final spriteBatch = _requireSpriteBatch(args, 0, symbol);
        final layerIndex = _requireRoundedInt(args, 1, symbol) - 1;
        final quad = _quadIfPresent(_valueAt(args, 2));
        final startIndex = quad == null ? 2 : 3;
        final index = spriteBatch.addLayer(
          layerIndex,
          _matrixFromTransformArgumentOrStandardTransform(
            args,
            startIndex,
            symbol,
          ),
          quad: quad,
        );
        return index + 1;
      }),
      functionName: 'addLayer',
    ),
    'attachAttribute': Value(
      builder.create((args) {
        const symbol = 'SpriteBatch:attachAttribute';
        final spriteBatch = _requireSpriteBatch(args, 0, symbol);
        final name = _requireString(args, 1, symbol);
        final mesh = _requireMesh(args, 2, symbol);
        spriteBatch.attachAttribute(name, mesh);
        return null;
      }),
      functionName: 'attachAttribute',
    ),
    'clear': Value(
      builder.create((args) {
        _requireSpriteBatch(args, 0, 'SpriteBatch:clear').clear();
        return null;
      }),
      functionName: 'clear',
    ),
    'flush': Value(
      builder.create((args) {
        _requireSpriteBatch(args, 0, 'SpriteBatch:flush').flush();
        return null;
      }),
      functionName: 'flush',
    ),
    'getBufferSize': Value(
      builder.create(
        (args) => _requireSpriteBatch(
          args,
          0,
          'SpriteBatch:getBufferSize',
        ).bufferSize,
      ),
      functionName: 'getBufferSize',
    ),
    'getColor': Value(
      builder.create((args) {
        final color = _requireSpriteBatch(
          args,
          0,
          'SpriteBatch:getColor',
        ).color;
        if (color == null) {
          return null;
        }
        return Value.multi(<Object?>[color.r, color.g, color.b, color.a]);
      }),
      functionName: 'getColor',
    ),
    'getCount': Value(
      builder.create(
        (args) => _requireSpriteBatch(args, 0, 'SpriteBatch:getCount').count,
      ),
      functionName: 'getCount',
    ),
    'getDrawRange': Value(
      builder.create((args) {
        final range = _requireSpriteBatch(
          args,
          0,
          'SpriteBatch:getDrawRange',
        ).drawRange;
        if (range == null) {
          return null;
        }
        return Value.multi(<Object?>[range.start + 1, range.count]);
      }),
      functionName: 'getDrawRange',
    ),
    'getTexture': Value(
      builder.create((args) {
        final texture = _requireSpriteBatch(
          args,
          0,
          'SpriteBatch:getTexture',
        ).texture;
        return texture is LoveCanvas
            ? _wrapCanvas(context, texture)
            : _wrapImage(context, texture);
      }),
      functionName: 'getTexture',
    ),
    'release': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        final table = _spriteBatchWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'SpriteBatch',
            actual: receiver,
          );
        }

        final spriteBatch = table[_loveSpriteBatchObjectKey];
        if (spriteBatch is! LoveSpriteBatch) {
          return false;
        }
        if (_loveSpriteBatchReleased[spriteBatch] == true) {
          return false;
        }

        _loveSpriteBatchReleased[spriteBatch] = true;
        table[_loveSpriteBatchReleasedWrapperKey] = true;
        table[_loveSpriteBatchObjectKey] = null;
        return true;
      }),
      functionName: 'release',
    ),
    'set': Value(
      builder.create((args) {
        final spriteBatch = _requireSpriteBatch(args, 0, 'SpriteBatch:set');
        final spriteIndex = _requireRoundedInt(args, 1, 'SpriteBatch:set') - 1;
        final quad = _quadIfPresent(_valueAt(args, 2));
        final startIndex = quad == null ? 2 : 3;
        spriteBatch.set(
          spriteIndex,
          _matrixFromTransformArgumentOrStandardTransform(
            args,
            startIndex,
            'SpriteBatch:set',
          ),
          quad: quad,
        );
        return null;
      }),
      functionName: 'set',
    ),
    'setColor': Value(
      builder.create((args) {
        final spriteBatch = _requireSpriteBatch(
          args,
          0,
          'SpriteBatch:setColor',
        );
        if (args.length <= 1) {
          spriteBatch.setColor();
          return null;
        }

        spriteBatch.setColor(
          _requireColor(
            args.skip(1).toList(growable: false),
            0,
            'SpriteBatch:setColor',
          ),
        );
        return null;
      }),
      functionName: 'setColor',
    ),
    'setDrawRange': Value(
      builder.create((args) {
        final spriteBatch = _requireSpriteBatch(
          args,
          0,
          'SpriteBatch:setDrawRange',
        );
        if (_valueAt(args, 1) == null) {
          spriteBatch.setDrawRange();
          return null;
        }

        spriteBatch.setDrawRange(
          _requireRoundedInt(args, 1, 'SpriteBatch:setDrawRange') - 1,
          _requireRoundedInt(args, 2, 'SpriteBatch:setDrawRange'),
        );
        return null;
      }),
      functionName: 'setDrawRange',
    ),
    'setLayer': Value(
      builder.create((args) {
        const symbol = 'SpriteBatch:setLayer';
        final spriteBatch = _requireSpriteBatch(args, 0, symbol);
        final spriteIndex = _requireRoundedInt(args, 1, symbol) - 1;
        final layerIndex = _requireRoundedInt(args, 2, symbol) - 1;
        final quad = _quadIfPresent(_valueAt(args, 3));
        final startIndex = quad == null ? 3 : 4;
        spriteBatch.setLayer(
          spriteIndex,
          layerIndex,
          _matrixFromTransformArgumentOrStandardTransform(
            args,
            startIndex,
            symbol,
          ),
          quad: quad,
        );
        return null;
      }),
      functionName: 'setLayer',
    ),
    'setTexture': Value(
      builder.create((args) {
        final spriteBatch = _requireSpriteBatch(
          args,
          0,
          'SpriteBatch:setTexture',
        );
        spriteBatch.setTexture(
          _requireImage(args, 1, 'SpriteBatch:setTexture'),
        );
        return null;
      }),
      functionName: 'setTexture',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_spriteBatchWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'SpriteBatch',
            actual: receiver,
          );
        }
        return 'SpriteBatch';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_spriteBatchWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'SpriteBatch',
            actual: receiver,
          );
        }
        final name = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(name);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveSpriteBatchWrapperCache[spriteBatch] = table;
  return table;
}
