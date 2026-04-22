part of '../love_api_bindings.dart';

/// Table entry key that stores the backing [LoveGlyphData] instance.
const String _loveGlyphDataObjectKey = '__love2d_glyph_data__';

/// Table entry key that stores the backing [LoveRasterizer] instance.
const String _loveRasterizerObjectKey = '__love2d_rasterizer__';

/// Marker stored in released `Rasterizer` wrapper tables.
const String _loveRasterizerReleasedWrapperKey =
    '__love2d_rasterizer_released__';

/// Reuses Lua wrapper tables so the same glyph data keeps a stable identity.
final Expando<Value> _loveGlyphDataWrapperCache = Expando<Value>(
  'love2dGlyphDataWrapper',
);

/// Reuses Lua wrapper tables so the same rasterizer keeps a stable identity.
final Expando<Value> _loveRasterizerWrapperCache = Expando<Value>(
  'love2dRasterizerWrapper',
);

/// Whether a rasterizer has already been released through `Object:release`.
final Expando<bool> _loveRasterizerReleased = Expando<bool>(
  'love2dRasterizerReleased',
);

/// Returns wrapped glyph data when [value] is a `GlyphData` userdata table.
LoveGlyphData? _glyphDataIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveGlyphDataObjectKey];
  return data is LoveGlyphData ? data : null;
}

/// Returns the Lua wrapper table for a `Rasterizer`, including released ones.
Map<dynamic, dynamic>? _rasterizerWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final rasterizer = table[_loveRasterizerObjectKey];
  if (rasterizer is LoveRasterizer ||
      table[_loveRasterizerReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

/// Returns whether [value] is a released `Rasterizer` wrapper.
bool _rasterizerWrapperReleased(Object? value) {
  final table = _rasterizerWrapperTableIfPresent(value);
  return table?[_loveRasterizerReleasedWrapperKey] == true;
}

/// Returns wrapped rasterizer state when [value] is a `Rasterizer` userdata table.
LoveRasterizer? _rasterizerIfPresent(Object? value) {
  final table = _rasterizerWrapperTableIfPresent(value);
  if (table == null) {
    return null;
  }

  final rasterizer = table[_loveRasterizerObjectKey];
  if (rasterizer is! LoveRasterizer ||
      table[_loveRasterizerReleasedWrapperKey] == true) {
    return null;
  }

  return rasterizer;
}

/// Returns a required `GlyphData` receiver.
LoveGlyphData _requireGlyphData(List<Object?> args, int index, String symbol) {
  final value = _valueAt(args, index);
  final data = _glyphDataIfPresent(value);
  if (data != null) {
    if (_loveDataReleased[data] == true) {
      _throwReleasedObjectError();
    }
    return data;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'GlyphData',
    actual: value,
  );
}

/// Returns a required `Rasterizer` receiver.
LoveRasterizer _requireRasterizer(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _valueAt(args, index);
  if (_rasterizerWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final rasterizer = _rasterizerIfPresent(value);
  if (rasterizer != null) {
    return rasterizer;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'Rasterizer',
    actual: value,
  );
}

/// Returns a rasterizer after validating that glyph count queries are supported.
LoveRasterizer _requireGlyphCountQueryableRasterizer(
  List<Object?> args,
  int index,
  String symbol,
) {
  final rasterizer = _requireRasterizer(args, index, symbol);
  _ensureRasterizerSupportsGlyphCount(rasterizer, symbol);
  return rasterizer;
}

/// Throws when glyph counts cannot be queried accurately for [rasterizer].
void _ensureRasterizerSupportsGlyphCount(
  LoveRasterizer rasterizer,
  String symbol,
) {
  if (rasterizer.kind == LoveRasterizerKind.trueType &&
      !rasterizer.supportsGlyphCount) {
    throw LuaError(
      '$symbol true type rasterizer glyph count is not supported yet '
      'without source font data; individual glyph queries use estimated '
      'metrics only',
    );
  }
}

/// Wraps [data] as a Lua-facing `GlyphData` object table.
Value _wrapGlyphData(LibraryRegistrationContext context, LoveGlyphData data) {
  final cached = _loveGlyphDataWrapperCache[data];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'GlyphData', 'Data', 'Object'};
  final table = _wrapLoveDataObject(
    context,
    rawObject: data,
    objectKey: _loveGlyphDataObjectKey,
    typeName: 'GlyphData',
    hierarchy: hierarchy,
    clone: (args) => _wrapGlyphData(
      context,
      _requireGlyphData(args, 0, 'GlyphData:clone').clone(),
    ),
    extraEntries: <Object?, Object?>{
      'getAdvance': Value(
        builder.create(
          (args) => _requireGlyphData(args, 0, 'GlyphData:getAdvance').advance,
        ),
        functionName: 'getAdvance',
      ),
      'getBearing': Value(
        builder.create((args) {
          final glyphData = _requireGlyphData(args, 0, 'GlyphData:getBearing');
          return Value.multi(<Object?>[glyphData.bearingX, glyphData.bearingY]);
        }),
        functionName: 'getBearing',
      ),
      'getBoundingBox': Value(
        builder.create((args) {
          final glyphData = _requireGlyphData(
            args,
            0,
            'GlyphData:getBoundingBox',
          );
          return Value.multi(<Object?>[
            glyphData.minX,
            glyphData.minY,
            glyphData.maxX - glyphData.minX,
            glyphData.maxY - glyphData.minY,
          ]);
        }),
        functionName: 'getBoundingBox',
      ),
      'getDimensions': Value(
        builder.create((args) {
          final glyphData = _requireGlyphData(
            args,
            0,
            'GlyphData:getDimensions',
          );
          return Value.multi(<Object?>[glyphData.width, glyphData.height]);
        }),
        functionName: 'getDimensions',
      ),
      'getFormat': Value(
        builder.create(
          (args) => _requireGlyphData(args, 0, 'GlyphData:getFormat').format,
        ),
        functionName: 'getFormat',
      ),
      'getGlyph': Value(
        builder.create(
          (args) => _requireGlyphData(args, 0, 'GlyphData:getGlyph').glyph,
        ),
        functionName: 'getGlyph',
      ),
      'getGlyphString': Value(
        builder.create((args) {
          final glyphData = _requireGlyphData(
            args,
            0,
            'GlyphData:getGlyphString',
          );
          if (!_isValidGlyphStringCodepoint(glyphData.glyph)) {
            throw LuaError(
              'GlyphData:getGlyphString UTF-8 decoding error: '
              'Invalid code point',
            );
          }
          return glyphData.glyphString;
        }),
        functionName: 'getGlyphString',
      ),
      'getHeight': Value(
        builder.create(
          (args) => _requireGlyphData(args, 0, 'GlyphData:getHeight').height,
        ),
        functionName: 'getHeight',
      ),
      'getWidth': Value(
        builder.create(
          (args) => _requireGlyphData(args, 0, 'GlyphData:getWidth').width,
        ),
        functionName: 'getWidth',
      ),
      'type': Value(
        builder.create((args) {
          final receiver = _valueAt(args, 0);
          if (_glyphDataIfPresent(receiver) == null) {
            _throwLuaStyleTypeError(
              symbol: 'Object:type',
              index: 0,
              expected: 'GlyphData',
              actual: receiver,
            );
          }
          return 'GlyphData';
        }),
        functionName: 'type',
      ),
      'typeOf': Value(
        builder.create((args) {
          final receiver = _valueAt(args, 0);
          if (_glyphDataIfPresent(receiver) == null) {
            _throwLuaStyleTypeError(
              symbol: 'Object:typeOf',
              index: 0,
              expected: 'GlyphData',
              actual: receiver,
            );
          }
          final queried = _requireString(args, 1, 'Object:typeOf');
          return hierarchy.contains(queried);
        }),
        functionName: 'typeOf',
      ),
    },
  );
  _loveGlyphDataWrapperCache[data] = table;
  return table;
}

/// Wraps [rasterizer] as a Lua-facing `Rasterizer` object table.
Value _wrapRasterizer(
  LibraryRegistrationContext context,
  LoveRasterizer rasterizer,
) {
  final cached = _loveRasterizerWrapperCache[rasterizer];
  if (cached != null && !_rasterizerWrapperReleased(cached)) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'Rasterizer', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveRasterizerObjectKey: rasterizer,
    'getAdvance': Value(
      builder.create(
        (args) => _requireRasterizer(args, 0, 'Rasterizer:getAdvance').advance,
      ),
      functionName: 'getAdvance',
    ),
    'getAscent': Value(
      builder.create(
        (args) => _requireRasterizer(args, 0, 'Rasterizer:getAscent').ascent,
      ),
      functionName: 'getAscent',
    ),
    'getDescent': Value(
      builder.create(
        (args) => _requireRasterizer(args, 0, 'Rasterizer:getDescent').descent,
      ),
      functionName: 'getDescent',
    ),
    'getGlyphCount': Value(
      builder.create((args) {
        return _requireGlyphCountQueryableRasterizer(
          args,
          0,
          'Rasterizer:getGlyphCount',
        ).glyphCount;
      }),
      functionName: 'getGlyphCount',
    ),
    'getGlyphData': Value(
      builder.create((args) {
        final rasterizer = _requireRasterizer(
          args,
          0,
          'Rasterizer:getGlyphData',
        );
        return _wrapGlyphData(
          context,
          rasterizer.glyphDataForValue(
            _coerceSingleGlyphLookupArgument(
              args,
              1,
              symbol: 'Rasterizer:getGlyphData',
              allowEmptyString: false,
            ),
          ),
        );
      }),
      functionName: 'getGlyphData',
    ),
    'getHeight': Value(
      builder.create(
        (args) => _requireRasterizer(args, 0, 'Rasterizer:getHeight').height,
      ),
      functionName: 'getHeight',
    ),
    'getLineHeight': Value(
      builder.create((args) {
        return _requireRasterizer(
          args,
          0,
          'Rasterizer:getLineHeight',
        ).lineHeight;
      }),
      functionName: 'getLineHeight',
    ),
    'hasGlyphs': Value(
      builder.create((args) {
        final rasterizer = _requireRasterizer(args, 0, 'Rasterizer:hasGlyphs');
        if (args.length < 2) {
          _requireNumber(args, 1, 'Rasterizer:hasGlyphs');
        }
        final glyphValues = <Object?>[];
        for (var index = 1; index < args.length; index++) {
          glyphValues.add(
            _coerceGlyphLookupArgument(
              args,
              index,
              symbol: 'Rasterizer:hasGlyphs',
            ),
          );
        }
        return rasterizer.hasGlyphValues(glyphValues);
      }),
      functionName: 'hasGlyphs',
    ),
    'release': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        final table = _rasterizerWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'Rasterizer',
            actual: receiver,
          );
        }

        final rasterizer = table[_loveRasterizerObjectKey];
        if (rasterizer is! LoveRasterizer) {
          return false;
        }
        if (_loveRasterizerReleased[rasterizer] == true) {
          return false;
        }

        _loveRasterizerReleased[rasterizer] = true;
        table[_loveRasterizerReleasedWrapperKey] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_rasterizerWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'Rasterizer',
            actual: receiver,
          );
        }
        return 'Rasterizer';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_rasterizerWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'Rasterizer',
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveRasterizerWrapperCache[rasterizer] = table;
  return table;
}

/// Coerces a glyph lookup argument using LÖVE font lookup rules.
Object _coerceGlyphLookupArgument(
  List<Object?> args,
  int index, {
  required String symbol,
  bool allowEmptyString = true,
}) {
  final value = _valueAt(args, index);
  final argumentIndex = index + 1;
  final text = _strictFontStringLike(
    value,
    symbol: symbol,
    argumentIndex: argumentIndex,
  );
  if (text != null) {
    if (!allowEmptyString && text.isEmpty) {
      throw LuaError(
        '$symbol UTF-8 decoding error at argument '
        '$argumentIndex: Not enough space',
      );
    }
    return text;
  }

  return _truncateLoveFontNumericValue(_requireNumber(args, index, symbol));
}

/// Coerces a single-glyph lookup argument.
Object _coerceSingleGlyphLookupArgument(
  List<Object?> args,
  int index, {
  required String symbol,
  bool allowEmptyString = true,
}) {
  final value = _valueAt(args, index);
  final argumentIndex = index + 1;
  final text = _singleGlyphStringLike(
    value,
    symbol: symbol,
    argumentIndex: argumentIndex,
  );
  if (text != null) {
    if (!allowEmptyString && text.isEmpty) {
      throw LuaError(
        '$symbol UTF-8 decoding error at argument '
        '$argumentIndex: Not enough space',
      );
    }
    return text;
  }

  return _truncateLoveFontNumericValue(_requireNumber(args, index, symbol));
}

/// Coerces the two glyph arguments used by kerning queries.
({Object left, Object right}) _coerceKerningGlyphLookupPair(
  List<Object?> args, {
  required String symbol,
  required int leftIndex,
  required int rightIndex,
}) {
  final leftArgumentIndex = leftIndex + 1;
  final rightArgumentIndex = rightIndex + 1;
  final leftValue = _valueAt(args, leftIndex);
  final leftText = _singleGlyphStringLike(
    leftValue,
    symbol: symbol,
    argumentIndex: leftArgumentIndex,
  );
  if (leftText != null) {
    final rightText = _requireKerningStringLike(
      args,
      rightIndex,
      symbol: symbol,
    );

    if (leftText.isEmpty) {
      throw LuaError(
        '$symbol UTF-8 decoding error at argument '
        '$leftArgumentIndex: Not enough space',
      );
    }
    if (rightText.isEmpty) {
      throw LuaError(
        '$symbol UTF-8 decoding error at argument '
        '$rightArgumentIndex: Not enough space',
      );
    }

    return (left: leftText, right: rightText);
  }

  return (
    left: _truncateLoveFontNumericValue(
      _requireNumber(args, leftIndex, symbol),
    ),
    right: _coerceKerningNumericArgument(args, rightIndex, symbol: symbol),
  );
}

/// Returns a required string-like glyph argument for kerning lookups.
String _requireKerningStringLike(
  List<Object?> args,
  int index, {
  required String symbol,
}) {
  final argumentIndex = index + 1;
  final text = _singleGlyphTextSegmentLike(
    _valueAt(args, index),
    symbol: symbol,
    argumentIndex: argumentIndex,
  );
  if (text != null) {
    return text;
  }

  throw LuaError('$symbol expected a string at argument $argumentIndex');
}

/// Coerces a numeric kerning argument, including Lua-style numeric strings.
int _coerceKerningNumericArgument(
  List<Object?> args,
  int index, {
  required String symbol,
}) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw is num) {
    return _truncateLoveFontNumericValue(raw);
  }

  final argumentIndex = index + 1;
  final text = _strictFontStringLike(
    _valueAt(args, index),
    symbol: symbol,
    argumentIndex: argumentIndex,
  );
  if (text != null) {
    try {
      final parsed = LuaNumberParser.parse(text);
      return switch (parsed) {
        final BigInt integerValue => integerValue.toInt(),
        final num numericValue => _truncateLoveFontNumericValue(numericValue),
        _ => throw const FormatException('Invalid numeric glyph'),
      };
    } on FormatException {
      // Match luaL_checknumber-style errors for non-numeric strings below.
    }
  }

  return _truncateLoveFontNumericValue(_requireNumber(args, index, symbol));
}

/// Truncates numeric glyph identifiers using LÖVE's numeric coercion behavior.
int _truncateLoveFontNumericValue(num value) => value.truncate();

/// Returns a single glyph string when [value] can be decoded as one glyph.
String? _singleGlyphStringLike(
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) {
  final raw = switch (value) {
    final Value wrapped => wrapped.raw,
    _ => value,
  };
  return switch (raw) {
    final String stringValue => stringValue,
    final LuaString luaString => _decodeSingleGlyphLuaString(
      luaString,
      symbol: symbol,
      argumentIndex: argumentIndex,
    ),
    _ => null,
  };
}

/// Returns one glyph-like text segment, allowing numeric coercion.
String? _singleGlyphTextSegmentLike(
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) {
  final direct = _singleGlyphStringLike(
    value,
    symbol: symbol,
    argumentIndex: argumentIndex,
  );
  if (direct != null) {
    return direct;
  }

  final raw = switch (value) {
    final Value wrapped => wrapped.raw,
    _ => value,
  };
  return switch (raw) {
    final num numericValue => _loveLuaJitNumberToString(numericValue),
    _ => null,
  };
}

/// Returns strict font text when [value] can be decoded without lossy coercion.
String? _strictFontStringLike(
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) {
  final raw = switch (value) {
    final Value wrapped => wrapped.raw,
    _ => value,
  };
  return switch (raw) {
    final String stringValue => stringValue,
    final LuaString luaString => _decodeStrictFontLuaString(
      luaString,
      symbol: symbol,
      argumentIndex: argumentIndex,
    ),
    _ => null,
  };
}

/// Decodes the first UTF-8 codepoint from [value] for glyph APIs.
String _decodeSingleGlyphLuaString(
  LuaString value, {
  required String symbol,
  required int argumentIndex,
}) {
  try {
    return _decodeLoveUtf8FirstCodepoint(value.bytes);
  } on _LoveUtf8DecodeError catch (error) {
    throw LuaError(
      '$symbol UTF-8 decoding error at argument '
      '$argumentIndex: ${error.message}',
    );
  }
}

/// Decodes all UTF-8 bytes from [value] for strict font text APIs.
String _decodeStrictFontLuaString(
  LuaString value, {
  required String symbol,
  required int argumentIndex,
}) {
  try {
    return _decodeLoveUtf8Strict(value.bytes);
  } on _LoveUtf8DecodeError catch (error) {
    throw LuaError(
      '$symbol UTF-8 decoding error at argument '
      '$argumentIndex: ${error.message}',
    );
  }
}

/// Returns whether [glyph] can be represented as a Unicode scalar value.
bool _isValidGlyphStringCodepoint(int glyph) {
  return glyph >= 0 && glyph <= 0x10ffff && (glyph < 0xd800 || glyph > 0xdfff);
}
