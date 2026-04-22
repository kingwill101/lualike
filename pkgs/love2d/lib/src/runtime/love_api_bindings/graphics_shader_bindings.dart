part of '../love_api_bindings.dart';

const String _loveShaderReleasedWrapperKey = '__love2d_shader_released__';
const String _loveGraphicsNewShaderUnsupportedMessage =
    'love.graphics.newShader cannot compile arbitrary runtime shader source '
    'on the Flutter backend yet; only the compatibility-emulated radial '
    'gradient and desaturation tint shader subsets plus registered Flutter '
    'fragment-asset shaders are currently supported';
const String _loveGraphicsValidateShaderUnsupportedMessage =
    'love.graphics.validateShader cannot validate arbitrary runtime shader '
    'source on the Flutter backend yet; only the compatibility-emulated '
    'radial gradient and desaturation tint shader subsets plus registered '
    'Flutter fragment-asset shaders are currently supported';
const String _loveShaderDataUploadUnsupportedMessage =
    'does not support Data object uploads on the Flutter backend yet';

Map<dynamic, dynamic>? _shaderTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final shader = table[_loveShaderObjectKey];
  return shader is LoveShader ? table : null;
}

bool _shaderWrapperReleased(Object? value) {
  final table = _tableIdentityIfPresent(value);
  return table?[_loveShaderReleasedWrapperKey] == true;
}

LoveShader? _shaderIfPresent(Object? value) {
  final table = _shaderTableIfPresent(value);
  if (table == null) {
    return null;
  }

  if (_shaderWrapperReleased(table)) {
    throw LuaError('Cannot use object after it has been released.');
  }

  return table[_loveShaderObjectKey] as LoveShader;
}

LoveShader _requireShader(List<Object?> args, int index, String symbol) {
  final shader = _shaderIfPresent(_valueAt(args, index));
  if (shader != null) {
    return shader;
  }

  throw LuaError('$symbol expected a Shader at argument ${index + 1}');
}

LoveShaderUniformDescriptor? _shaderUniformIfPresent(
  LoveShader shader,
  String name,
) {
  final declared = shader.uniformDeclaration(name);
  if (declared != null) {
    return declared;
  }

  if (_sourceContainsUniformName(shader.pixelCode, name) ||
      _sourceContainsUniformName(shader.vertexCode ?? '', name)) {
    return const LoveShaderUniformDescriptor.unknown();
  }

  return null;
}

LoveShaderUniformDescriptor _requireShaderUniform(
  LoveShader shader,
  String name,
) {
  final uniform = _shaderUniformIfPresent(shader, name);
  if (uniform != null) {
    return uniform;
  }

  throw LuaError(
    "Shader uniform '$name' does not exist.\n"
    'A common error is to define but not use the variable.',
  );
}

Value _wrapShader(LibraryContext context, LoveShader shader) {
  final cached = _loveShaderWrapperCache[shader];
  if (cached != null && !_shaderWrapperReleased(cached)) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _loveShaderObjectKey: shader,
    'release': Value(
      builder.create((args) {
        final table = _shaderTableIfPresent(_valueAt(args, 0));
        if (table == null) {
          throw LuaError('Object:release expected a Shader at argument 1');
        }
        if (_shaderWrapperReleased(table)) {
          return false;
        }
        table[_loveShaderReleasedWrapperKey] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'send': Value(
      builder.create((args) {
        const symbol = 'Shader:send';
        final shader = _requireShader(args, 0, symbol);
        final name = _requireString(args, 1, symbol);
        final uniform = _requireShaderUniform(shader, name);
        final values = _shaderRequireSendArguments(
          args,
          symbol,
        ).toList(growable: false);
        shader.send(name, _shaderSentValueForUniform(values, uniform, symbol));
        return null;
      }),
      functionName: 'send',
    ),
    'sendColor': Value(
      builder.create((args) {
        // Mirrors Shader:send but accepts color values and converts them from
        // gamma space to linear space before uploading.  In this runtime the
        // gamma-correct pipeline is not active (isGammaCorrect returns false)
        // so we clamp values into LOVE's normal color range and store them
        // without additional conversion, matching LOVE when gamma correction
        // is disabled.
        const symbol = 'Shader:sendColor';
        final shader = _requireShader(args, 0, symbol);
        final name = _requireString(args, 1, symbol);
        final uniform = _requireShaderUniform(shader, name);
        if (uniform.typeName != 'unknown' && !uniform.isColorCompatible) {
          throw LuaError(
            'sendColor can only be used on vec3 or vec4 uniforms.',
          );
        }
        final rawValues = _shaderRequireSendArguments(
          args,
          symbol,
        ).toList(growable: false);
        shader.send(name, _shaderSentColorValue(rawValues, uniform, symbol));
        return null;
      }),
      functionName: 'sendColor',
    ),
    'hasUniform': Value(
      builder.create((args) {
        final shader = _requireShader(args, 0, 'Shader:hasUniform');
        final name = _requireString(args, 1, 'Shader:hasUniform');
        return _shaderSourceContainsUniform(shader, name) ||
            shader.uniforms.containsKey(name);
      }),
      functionName: 'hasUniform',
    ),
    'getWarnings': Value(
      // Mirrors upstream by always returning a string. No GLSL compiler is
      // available in this runtime so there are no warnings to report.
      builder.create((args) => ''),
      functionName: 'getWarnings',
    ),
    'type': Value(
      builder.create((args) {
        _requireShader(args, 0, 'Object:type');
        return 'Shader';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        _requireShader(args, 0, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return queried == 'Shader' || queried == 'Object';
      }),
      functionName: 'typeOf',
    ),
  });
  _loveShaderWrapperCache[shader] = table;
  return table;
}

// ---------------------------------------------------------------------------
// Shader uniform introspection helpers
// ---------------------------------------------------------------------------

/// Returns true if [name] appears as an `extern` or `uniform` declaration in
/// either the pixel or vertex source of [shader].  This is a heuristic text
/// scan used by Shader:hasUniform when the uniform has not yet been sent via
/// Shader:send; it does not validate the GLSL type.
bool _shaderSourceContainsUniform(LoveShader shader, String name) {
  return shader.uniformDeclaration(name) != null ||
      _sourceContainsUniformName(shader.pixelCode, name) ||
      _sourceContainsUniformName(shader.vertexCode ?? '', name);
}

bool _sourceContainsUniformName(String source, String name) {
  // Match "extern <type> <name>" or "uniform <type> <name>" with word
  // boundaries.  We use a simple RegExp that handles optional whitespace and
  // the most common forms; it is not a full GLSL parser.
  final pattern = RegExp(
    r'(?:extern|uniform)\s+\w[\w\s]*\s+' + RegExp.escape(name) + r'\b',
  );
  return pattern.hasMatch(source);
}

LoveApiImplementation _bindGraphicsSetShader(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final shader = args.isEmpty || _valueAt(args, 0) == null
        ? null
        : _requireShader(args, 0, 'love.graphics.setShader');
    runtime.graphics.setShader(shader);
    return null;
  };
}

LoveApiImplementation _bindGraphicsGetShader(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final shader = runtime.graphics.currentShader;
    return shader == null ? null : _wrapShader(context, shader);
  };
}

LoveApiImplementation _bindShaderSend(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'Shader:send';
    final shader = _requireShader(args, 0, symbol);
    final name = _requireString(args, 1, symbol);
    final uniform = _requireShaderUniform(shader, name);
    final values = _shaderRequireSendArguments(
      args,
      symbol,
    ).toList(growable: false);
    shader.send(name, _shaderSentValueForUniform(values, uniform, symbol));
    return null;
  };
}

Iterable<Object?> _shaderRequireSendArguments(
  List<Object?> args,
  String symbol,
) {
  if (args.length < 3) {
    throw LuaError('$symbol expected at least 1 value to send');
  }

  return args.skip(2);
}

Object? _shaderSentValueForUniform(
  List<Object?> rawValues,
  LoveShaderUniformDescriptor uniform,
  String symbol,
) {
  _shaderRejectUnsupportedDataUploads(rawValues, symbol);
  final matrixDimension = uniform.squareMatrixDimension;
  if (matrixDimension != null) {
    return _shaderSentMatrixValue(
      rawValues,
      dimension: matrixDimension,
      arrayLength: uniform.arrayLength,
      symbol: symbol,
    );
  }

  return switch (uniform.valueKind) {
    LoveShaderUniformValueKind.float => _shaderSentTypedUniformValue(
      rawValues,
      uniform: uniform,
      symbol: symbol,
      scalarParser: _shaderFloatUniformComponent,
    ),
    LoveShaderUniformValueKind.int => _shaderSentTypedUniformValue(
      rawValues,
      uniform: uniform,
      symbol: symbol,
      scalarParser: _shaderIntUniformComponent,
    ),
    LoveShaderUniformValueKind.uint => _shaderSentTypedUniformValue(
      rawValues,
      uniform: uniform,
      symbol: symbol,
      scalarParser: _shaderUintUniformComponent,
    ),
    LoveShaderUniformValueKind.bool_ => _shaderSentTypedUniformValue(
      rawValues,
      uniform: uniform,
      symbol: symbol,
      scalarParser: _shaderBoolUniformComponent,
    ),
    LoveShaderUniformValueKind.sampler => _shaderSentSamplerUniformValue(
      rawValues,
      uniform: uniform,
      symbol: symbol,
    ),
    LoveShaderUniformValueKind.unknown || LoveShaderUniformValueKind.matrix =>
      _shaderSentUnknownUniformValue(rawValues),
  };
}

void _shaderRejectUnsupportedDataUploads(
  Iterable<Object?> rawValues,
  String symbol,
) {
  for (final value in rawValues) {
    if (_loveDataObjectIfPresent(value) != null ||
        _filesystemFileDataCompatIfPresent(value) != null) {
      throw LuaError('$symbol $_loveShaderDataUploadUnsupportedMessage');
    }
  }
}

Object? _shaderSentTypedUniformValue(
  List<Object?> rawValues, {
  required LoveShaderUniformDescriptor uniform,
  required String symbol,
  required Object? Function(Object? value, String symbol) scalarParser,
}) {
  final components = uniform.componentCount;
  if (components == null) {
    return _shaderSentUnknownUniformValue(rawValues);
  }

  final values =
      _shaderUniformPayloadValues(rawValues, arrayLength: uniform.arrayLength)
          .map(
            (value) => _shaderValidatedUniformPayload(
              value,
              components: components,
              symbol: symbol,
              scalarParser: scalarParser,
            ),
          )
          .toList(growable: false);

  return uniform.arrayLength == null ? values.first : values;
}

Object? _shaderSentSamplerUniformValue(
  List<Object?> rawValues, {
  required LoveShaderUniformDescriptor uniform,
  required String symbol,
}) {
  _shaderRejectUnsupportedDataUploads(rawValues, symbol);
  final values =
      _shaderUniformPayloadValues(rawValues, arrayLength: uniform.arrayLength)
          .map((value) => _shaderRequireSamplerImage(value, symbol))
          .toList(growable: false);
  return uniform.arrayLength == null ? values.first : values;
}

Object? _shaderSentColorValue(
  List<Object?> rawValues,
  LoveShaderUniformDescriptor uniform,
  String symbol,
) {
  _shaderRejectUnsupportedDataUploads(rawValues, symbol);
  if (uniform.typeName == 'unknown') {
    final values = rawValues
        .map(_shaderSendValue)
        .map(_clampShaderColorValue)
        .toList(growable: false);
    return values.length == 1 ? values.first : values;
  }

  final components = uniform.componentCount;
  if (components == null || components < 3 || components > 4) {
    throw LuaError('sendColor can only be used on vec3 or vec4 uniforms.');
  }

  if (uniform.arrayLength == null) {
    return _shaderValidatedColorPayload(
      rawValues,
      components: components,
      symbol: symbol,
    );
  }

  final values =
      _shaderUniformPayloadValues(rawValues, arrayLength: uniform.arrayLength)
          .map((value) {
            final table = _tableIfPresent(value);
            if (table == null) {
              throw LuaError(
                '$symbol expected a table with $components components',
              );
            }
            return _shaderClampedNumericComponents(
              table,
              components: components,
              symbol: symbol,
            );
          })
          .toList(growable: false);
  return values;
}

Object? _shaderSentUnknownUniformValue(List<Object?> rawValues) {
  final values = rawValues.map(_shaderSendValue).toList(growable: false);
  return values.length == 1 ? values.first : values;
}

List<Object?> _shaderUniformPayloadValues(
  List<Object?> rawValues, {
  required int? arrayLength,
}) {
  final count = arrayLength == null
      ? 1
      : math.min(rawValues.length, math.max(arrayLength, 1));
  return rawValues.take(count).toList(growable: false);
}

Object? _shaderValidatedUniformPayload(
  Object? value, {
  required int components,
  required String symbol,
  required Object? Function(Object? value, String symbol) scalarParser,
}) {
  if (components == 1) {
    return scalarParser(value, symbol);
  }

  final table = _tableIfPresent(value);
  if (table == null) {
    throw LuaError('$symbol expected a table with $components components');
  }

  return List<Object?>.unmodifiable(
    List<Object?>.generate(
      components,
      (index) => scalarParser(_tableIndexedEntry(table, index + 1), symbol),
      growable: false,
    ),
  );
}

Object? _shaderValidatedColorPayload(
  List<Object?> rawValues, {
  required int components,
  required String symbol,
}) {
  final firstTable = _tableIfPresent(rawValues.first);
  if (firstTable != null) {
    return _shaderClampedNumericComponents(
      firstTable,
      components: components,
      symbol: symbol,
    );
  }

  if (rawValues.length < components) {
    throw LuaError('$symbol expected $components color components to send');
  }

  return List<Object?>.unmodifiable(
    List<Object?>.generate(
      components,
      (index) => _clampShaderColorValue(
        _shaderFloatUniformComponent(rawValues[index], symbol),
      ),
      growable: false,
    ),
  );
}

List<Object?> _shaderClampedNumericComponents(
  Map<dynamic, dynamic> table, {
  required int components,
  required String symbol,
}) {
  return List<Object?>.unmodifiable(
    List<Object?>.generate(
      components,
      (index) => _clampShaderColorValue(
        _shaderFloatUniformComponent(
          _tableIndexedEntry(table, index + 1),
          symbol,
        ),
      ),
      growable: false,
    ),
  );
}

double _shaderFloatUniformComponent(Object? value, String symbol) {
  final raw = _rawValue(value);
  if (raw is num) {
    return raw.toDouble();
  }

  throw LuaError('$symbol expected a number for shader uniform values');
}

int _shaderIntUniformComponent(Object? value, String symbol) {
  final raw = _rawValue(value);
  if (raw is! num) {
    throw LuaError('$symbol expected an integer for shader uniform values');
  }

  final asDouble = raw.toDouble();
  final rounded = asDouble.roundToDouble();
  if (asDouble != rounded) {
    throw LuaError('$symbol expected an integer for shader uniform values');
  }

  return rounded.toInt();
}

int _shaderUintUniformComponent(Object? value, String symbol) {
  final parsed = _shaderIntUniformComponent(value, symbol);
  if (parsed < 0) {
    throw LuaError(
      '$symbol expected a non-negative integer for unsigned shader uniform values',
    );
  }

  return parsed;
}

bool _shaderBoolUniformComponent(Object? value, String symbol) {
  final raw = _rawValue(value);
  if (raw is bool) {
    return raw;
  }

  throw LuaError('$symbol expected a boolean for shader uniform values');
}

LoveImage _shaderRequireSamplerImage(Object? value, String symbol) {
  final image = _imageIfPresent(value);
  if (image != null) {
    return image;
  }

  final raw = _rawValue(value);
  if (raw is LoveImage) {
    return raw;
  }

  throw LuaError(
    '$symbol expected an Image or Canvas for sampler uniform values',
  );
}

Object? _shaderSentMatrixValue(
  List<Object?> rawValues, {
  required int dimension,
  required int? arrayLength,
  required String symbol,
}) {
  var columnMajor = false;
  var startIndex = 0;

  final layout = rawValues.isEmpty ? null : _stringLike(rawValues.first);
  if (layout != null) {
    columnMajor = _matrixLayout(layout, symbol);
    startIndex = 1;
  }

  if (rawValues.length <= startIndex) {
    throw LuaError('$symbol expected at least 1 value to send');
  }

  final matrices = <Object?>[];
  final count = arrayLength == null
      ? 1
      : math.min(rawValues.length - startIndex, math.max(arrayLength, 1));
  for (final value in rawValues.skip(startIndex).take(count)) {
    final transform = dimension == 4 ? _transformIfPresent(value) : null;
    if (transform != null) {
      matrices.add(
        List<Object?>.unmodifiable(
          _columnMajorSquareMatrixElementsFromFlat(
            transform.getMatrixRowMajor(),
            dimension: 4,
            columnMajorInput: false,
            symbol: symbol,
          ),
        ),
      );
      continue;
    }

    final table = _tableIfPresent(value);
    if (table == null) {
      throw LuaError('$symbol expected a $dimension x $dimension matrix table');
    }

    matrices.add(
      List<Object?>.unmodifiable(
        _shaderSquareMatrixElementsFromTable(
          table,
          dimension: dimension,
          columnMajor: columnMajor,
          symbol: symbol,
        ),
      ),
    );
  }

  return arrayLength == null ? matrices.first : matrices;
}

Object? _shaderSendValue(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return _rawValue(value);
  }

  final sequentialLength = _luaSequentialLength(table);
  if (sequentialLength > 0 &&
      _luaHasOnlySequentialKeys(table, sequentialLength)) {
    return List<Object?>.unmodifiable(
      List<Object?>.generate(
        sequentialLength,
        (index) => _shaderSendValue(_tableIndexedEntry(table, index + 1)),
        growable: false,
      ),
    );
  }

  return Map<Object?, Object?>.unmodifiable(
    table.map((key, item) => MapEntry(_rawValue(key), _shaderSendValue(item))),
  );
}

List<double> _shaderSquareMatrixElementsFromTable(
  Map<dynamic, dynamic> table, {
  required int dimension,
  required bool columnMajor,
  required String symbol,
}) {
  final first = _tableIndexedEntry(table, 1);
  final firstTable = _tableIfPresent(first);
  if (firstTable != null) {
    final elements = List<double>.filled(
      dimension * dimension,
      0.0,
      growable: false,
    );
    if (columnMajor) {
      for (var column = 0; column < dimension; column++) {
        final columnTable = _tableIfPresent(
          _tableIndexedEntry(table, column + 1),
        );
        if (columnTable == null) {
          throw LuaError(
            '$symbol expected a ${dimension}x$dimension matrix table',
          );
        }
        for (var row = 0; row < dimension; row++) {
          elements[(column * dimension) + row] = _tableIndexedNumber(
            columnTable,
            row + 1,
            symbol,
          );
        }
      }
      return elements;
    }

    for (var row = 0; row < dimension; row++) {
      final rowTable = _tableIfPresent(_tableIndexedEntry(table, row + 1));
      if (rowTable == null) {
        throw LuaError(
          '$symbol expected a ${dimension}x$dimension matrix table',
        );
      }
      for (var column = 0; column < dimension; column++) {
        elements[(column * dimension) + row] = _tableIndexedNumber(
          rowTable,
          column + 1,
          symbol,
        );
      }
    }
    return elements;
  }

  return _columnMajorSquareMatrixElementsFromFlat(
    List<double>.generate(
      dimension * dimension,
      (index) => _tableIndexedNumber(table, index + 1, symbol),
      growable: false,
    ),
    dimension: dimension,
    columnMajorInput: columnMajor,
    symbol: symbol,
  );
}

List<double> _columnMajorSquareMatrixElementsFromFlat(
  List<double> elements, {
  required int dimension,
  required bool columnMajorInput,
  required String symbol,
}) {
  final expectedLength = dimension * dimension;
  if (elements.length != expectedLength) {
    throw LuaError('$symbol expected a ${dimension}x$dimension matrix table');
  }

  if (columnMajorInput) {
    return List<double>.unmodifiable(elements);
  }

  final columnMajor = List<double>.filled(expectedLength, 0.0, growable: false);
  for (var row = 0; row < dimension; row++) {
    for (var column = 0; column < dimension; column++) {
      columnMajor[(column * dimension) + row] =
          elements[(row * dimension) + column];
    }
  }
  return columnMajor;
}

Object? _clampShaderColorValue(Object? value) {
  return switch (value) {
    final num number => number.toDouble().clamp(0.0, 1.0),
    final List<Object?> list => List<Object?>.unmodifiable(
      list.map(_clampShaderColorValue),
    ),
    final Map<Object?, Object?> map => Map<Object?, Object?>.unmodifiable(
      map.map(
        (key, item) => MapEntry(_rawValue(key), _clampShaderColorValue(item)),
      ),
    ),
    _ => value,
  };
}

int _luaSequentialLength(Map<dynamic, dynamic> table) {
  var length = 0;
  while (_tableIndexedEntry(table, length + 1) != null) {
    length++;
  }
  return length;
}

bool _luaHasOnlySequentialKeys(Map<dynamic, dynamic> table, int length) {
  for (final entry in table.entries) {
    final rawKey = _rawValue(entry.key);
    if (rawKey is int) {
      if (rawKey < 1 || rawKey > length) {
        return false;
      }
      continue;
    }

    if (rawKey is double) {
      final keyAsInt = rawKey.round();
      if (rawKey != keyAsInt || keyAsInt < 1 || keyAsInt > length) {
        return false;
      }
      continue;
    }

    return false;
  }

  return true;
}
