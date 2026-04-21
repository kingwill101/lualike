part of '../love_api_bindings.dart';

Value _wrapSpriteBatch(
  LibraryRegistrationContext context,
  LoveSpriteBatch spriteBatch,
) {
  final cached = _loveSpriteBatchWrapperCache[spriteBatch];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);

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
    'release': Value(builder.create((args) => null), functionName: 'release'),
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
      builder.create((args) => 'SpriteBatch'),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final name = _requireString(args, 1, 'SpriteBatch:typeOf');
        return name == 'SpriteBatch' || name == 'Drawable' || name == 'Object';
      }),
      functionName: 'typeOf',
    ),
  });
  _loveSpriteBatchWrapperCache[spriteBatch] = table;
  return table;
}
