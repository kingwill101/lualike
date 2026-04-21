part of '../love_api_bindings.dart';

final Expando<bool> _loveShaderReleased = Expando<bool>('love2dShaderReleased');

LoveShader? _shaderIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final shader = table[_loveShaderObjectKey];
  return shader is LoveShader ? shader : null;
}

LoveShader _requireShader(List<Object?> args, int index, String symbol) {
  final shader = _shaderIfPresent(_valueAt(args, index));
  if (shader != null) {
    return shader;
  }

  throw LuaError('$symbol expected a Shader at argument ${index + 1}');
}

Value _wrapShader(LibraryRegistrationContext context, LoveShader shader) {
  final cached = _loveShaderWrapperCache[shader];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _loveShaderObjectKey: shader,
    'release': Value(
      builder.create((args) {
        final shader = _requireShader(args, 0, 'Object:release');
        if (_loveShaderReleased[shader] == true) {
          return false;
        }
        _loveShaderReleased[shader] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'send': Value(
      builder.create((args) {
        final shader = _requireShader(args, 0, 'Shader:send');
        final name = _requireString(args, 1, 'Shader:send');
        final values = args
            .skip(2)
            .map(_shaderSendValue)
            .toList(growable: false);
        shader.send(
          name,
          values.isEmpty ? null : (values.length == 1 ? values.first : values),
        );
        return null;
      }),
      functionName: 'send',
    ),
    'sendColor': Value(
      builder.create((args) {
        // Mirrors Shader:send but accepts color values and converts them from
        // gamma space to linear space before uploading.  In this runtime the
        // gamma-correct pipeline is not active (isGammaCorrect returns false)
        // so we store the values as-is, matching LOVE's behaviour when gamma
        // correction is disabled.
        final shader = _requireShader(args, 0, 'Shader:sendColor');
        final name = _requireString(args, 1, 'Shader:sendColor');
        final values = args
            .skip(2)
            .map(_shaderSendValue)
            .toList(growable: false);
        shader.send(
          name,
          values.isEmpty ? null : (values.length == 1 ? values.first : values),
        );
        return null;
      }),
      functionName: 'sendColor',
    ),
    'hasUniform': Value(
      builder.create((args) {
        final shader = _requireShader(args, 0, 'Shader:hasUniform');
        final name = _requireString(args, 1, 'Shader:hasUniform');
        // A uniform is considered present if it has been explicitly sent via
        // Shader:send, or if the shader source contains an 'extern' / 'uniform'
        // declaration with that name.  The source scan is a best-effort heuristic
        // since we have no compiled reflection data.
        if (shader.uniforms.containsKey(name)) {
          return true;
        }
        return _shaderSourceContainsUniform(shader, name);
      }),
      functionName: 'hasUniform',
    ),
    'getWarnings': Value(
      // Returns compile warnings from the shader.  No GLSL compiler is
      // available in this runtime so there are no warnings to report.
      builder.create((args) => null),
      functionName: 'getWarnings',
    ),
    'type': Value(builder.create((args) => 'Shader'), functionName: 'type'),
    'typeOf': Value(
      builder.create((args) {
        final queried = _requireString(args, 1, 'Object:typeOf');
        return queried == 'Shader' || queried == 'Object';
      }),
      functionName: 'typeOf',
    ),
  });
  _loveShaderWrapperCache[shader] = table;
  return table;
}

LoveApiImplementation _bindGraphicsNewShader(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.graphics.newShader';
    final first = await _resolveShaderSourceArgument(
      context,
      _valueAt(args, 0),
      symbol: symbol,
      argumentIndex: 1,
    );
    final second = args.length >= 2
        ? await _resolveShaderSourceArgument(
            context,
            _valueAt(args, 1),
            symbol: symbol,
            argumentIndex: 2,
          )
        : null;
    return _wrapShader(
      context,
      LoveShader.fromSource(
        second ?? first,
        vertexCode: second == null ? null : first,
      ),
    );
  };
}

Future<String> _resolveShaderSourceArgument(
  LibraryRegistrationContext context,
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) async {
  final fileData = _filesystemFileDataCompatIfPresent(value);
  if (fileData != null) {
    return utf8.decode(fileData.bytes);
  }

  final source = _stringLike(value);
  if (source != null) {
    final mounted = await _readMountedResourceFileData(
      context,
      source,
      symbol: symbol,
    );
    if (mounted != null) {
      return utf8.decode(mounted.bytes);
    }

    if (_looksLikeShaderFilePath(source)) {
      throw LuaError('Could not open file $source. Does not exist.');
    }

    return source;
  }

  final coerced = await _coerceResourceFileDataViaFilesystem(
    context,
    value,
    symbol,
  );
  if (coerced != null) {
    return utf8.decode(coerced.bytes);
  }

  throw LuaError(
    '$symbol expected shader source, filename, FileData, or File at argument $argumentIndex',
  );
}

// ---------------------------------------------------------------------------
// Shader uniform introspection helpers
// ---------------------------------------------------------------------------

/// Returns true if [name] appears as an `extern` or `uniform` declaration in
/// either the pixel or vertex source of [shader].  This is a heuristic text
/// scan used by Shader:hasUniform when the uniform has not yet been sent via
/// Shader:send; it does not validate the GLSL type.
bool _shaderSourceContainsUniform(LoveShader shader, String name) {
  return _sourceContainsUniformName(shader.pixelCode, name) ||
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

bool _looksLikeShaderFilePath(String source) {
  if (source.isEmpty || source.length >= 64) {
    return false;
  }

  if (source.contains('\n') || source.contains('\r')) {
    return false;
  }

  final dotIndex = source.indexOf('.');
  if (dotIndex < 0) {
    return false;
  }

  final extension = source.substring(dotIndex);
  return !extension.contains(';') && !extension.contains(' ');
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

LoveApiImplementation _bindShaderSend(LibraryRegistrationContext context) {
  return (args) {
    final shader = _requireShader(args, 0, 'Shader:send');
    final name = _requireString(args, 1, 'Shader:send');
    final values = args.skip(2).map(_shaderSendValue).toList(growable: false);
    shader.send(
      name,
      values.isEmpty ? null : (values.length == 1 ? values.first : values),
    );
    return null;
  };
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
