part of '../love_api_bindings.dart';

LoveApiImplementation _bindMathColorFromBytes(
  LibraryRegistrationContext context,
) {
  return (args) {
    final components = _mathColorComponents(args, 'love.math.colorFromBytes');
    final results = <Object?>[];
    for (final component in components) {
      final rounded = component.isFinite
          ? component.roundToDouble()
          : component;
      results.add(loveClamp01(rounded / 255.0));
    }
    return Value.multi(results);
  };
}

LoveApiImplementation _bindMathColorToBytes(
  LibraryRegistrationContext context,
) {
  return (args) {
    final components = _mathColorComponents(args, 'love.math.colorToBytes');
    final results = <Object?>[];
    for (final component in components) {
      results.add((loveClamp01(component) * 255.0 + 0.5).floor());
    }
    return Value.multi(results);
  };
}

LoveApiImplementation _bindMathGammaToLinear(
  LibraryRegistrationContext context,
) {
  return (args) {
    final components = _mathGammaComponents(args, 'love.math.gammaToLinear');
    final results = <Object?>[];
    for (var i = 0; i < components.length; i++) {
      final clamped = loveClamp01(components[i]);
      results.add(i < 3 ? loveGammaToLinear(clamped) : clamped);
    }
    return _singleOrMulti(results);
  };
}

LoveApiImplementation _bindMathGetRandomSeed(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) =>
      Value.multi(<Object?>[runtime.random.seedLow, runtime.random.seedHigh]);
}

LoveApiImplementation _bindMathGetRandomState(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.random.getState();
}

LoveApiImplementation _bindMathIsConvex(LibraryRegistrationContext context) {
  return (args) =>
      loveIsConvex(_coordinateSequence(args, 'love.math.isConvex'));
}

LoveApiImplementation _bindMathLinearToGamma(
  LibraryRegistrationContext context,
) {
  return (args) {
    final components = _mathGammaComponents(args, 'love.math.linearToGamma');
    final results = <Object?>[];
    for (var i = 0; i < components.length; i++) {
      final clamped = loveClamp01(components[i]);
      results.add(i < 3 ? loveLinearToGamma(clamped) : clamped);
    }
    return _singleOrMulti(results);
  };
}

LoveApiImplementation _bindMathNewBezierCurve(
  LibraryRegistrationContext context,
) {
  return (args) {
    final points = _coordinateSequence(args, 'love.math.newBezierCurve');
    return _wrapBezierCurve(context, LoveBezierCurve(points));
  };
}

LoveApiImplementation _bindMathNewRandomGenerator(
  LibraryRegistrationContext context,
) {
  return (args) {
    final generator = LoveRandomGenerator();
    if (args.isNotEmpty) {
      final parts = _randomSeedParts(args, 0, 'love.math.newRandomGenerator');
      generator.setSeed(low: parts.low, high: parts.high);
    }
    return _wrapRandomGenerator(context, generator);
  };
}

LoveApiImplementation _bindMathNewTransform(
  LibraryRegistrationContext context,
) {
  return (args) {
    if (args.isEmpty) {
      return _wrapTransform(context, LoveTransform.identity());
    }

    final x = _requireNumber(args, 0, 'love.math.newTransform');
    final y = _requireNumber(args, 1, 'love.math.newTransform');
    final angle = _optionalNumber(
      args,
      2,
      'love.math.newTransform',
      defaultValue: 0.0,
    );
    final scaleX = _optionalNumber(
      args,
      3,
      'love.math.newTransform',
      defaultValue: 1.0,
    );
    final scaleY = _optionalNumber(
      args,
      4,
      'love.math.newTransform',
      defaultValue: scaleX,
    );
    final originX = _optionalNumber(
      args,
      5,
      'love.math.newTransform',
      defaultValue: 0.0,
    );
    final originY = _optionalNumber(
      args,
      6,
      'love.math.newTransform',
      defaultValue: 0.0,
    );
    final shearX = _optionalNumber(
      args,
      7,
      'love.math.newTransform',
      defaultValue: 0.0,
    );
    final shearY = _optionalNumber(
      args,
      8,
      'love.math.newTransform',
      defaultValue: 0.0,
    );

    return _wrapTransform(
      context,
      LoveTransform.transformation(
        x: x,
        y: y,
        angle: angle,
        scaleX: scaleX,
        scaleY: scaleY,
        originX: originX,
        originY: originY,
        shearX: shearX,
        shearY: shearY,
      ),
    );
  };
}

LoveApiImplementation _bindMathNoise(LibraryRegistrationContext context) {
  return (args) {
    final coordinateCount = args.length.clamp(1, 4) as int;
    final coordinates = List<double>.generate(
      coordinateCount,
      (index) => _requireNumber(args, index, 'love.math.noise'),
      growable: false,
    );
    return loveNoise(coordinates);
  };
}

LoveApiImplementation _bindMathRandom(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty) {
      return runtime.random.random();
    }

    if (args.length == 1) {
      return runtime.random.random(_requireNumber(args, 0, 'love.math.random'));
    }

    return runtime.random.random(
      _requireNumber(args, 0, 'love.math.random'),
      _requireNumber(args, 1, 'love.math.random'),
    );
  };
}

LoveApiImplementation _bindMathRandomNormal(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final stddev = args.isNotEmpty
        ? _requireNumber(args, 0, 'love.math.randomNormal')
        : 1.0;
    final mean = args.length >= 2
        ? _requireNumber(args, 1, 'love.math.randomNormal')
        : 0.0;
    return runtime.random.randomNormal(stddev, mean);
  };
}

LoveApiImplementation _bindMathSetRandomSeed(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty) {
      throw LuaError('love.math.setRandomSeed expects at least 1 argument');
    }

    final parts = _randomSeedParts(args, 0, 'love.math.setRandomSeed');
    runtime.random.setSeed(low: parts.low, high: parts.high);
    return null;
  };
}

LoveApiImplementation _bindMathSetRandomState(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    _mathGuard(
      () => runtime.random.setState(
        _requireString(args, 0, 'love.math.setRandomState'),
      ),
    );
    return null;
  };
}

LoveApiImplementation _bindMathTriangulate(LibraryRegistrationContext context) {
  return (args) {
    final vertices = _coordinateSequence(args, 'love.math.triangulate');
    if (vertices.length < 3) {
      throw LuaError('Need at least 3 vertices to triangulate');
    }

    final triangles = _mathGuard(() => loveTriangulate(vertices));
    final triangleTable = <Object?, Object?>{};
    for (var i = 0; i < triangles.length; i++) {
      final triangle = triangles[i];
      triangleTable[i + 1] = Value(<Object?, Object?>{
        1: triangle.a.x,
        2: triangle.a.y,
        3: triangle.b.x,
        4: triangle.b.y,
        5: triangle.c.x,
        6: triangle.c.y,
      });
    }
    return Value(triangleTable);
  };
}

List<double> _mathColorComponents(List<Object?> args, String symbol) {
  final table = args.isNotEmpty ? _tableIfPresent(args.first) : null;
  final components = <double>[];

  if (table != null) {
    for (var index = 1; index <= 4; index++) {
      final entry = _tableIndexedEntry(table, index);
      if (entry == null) {
        break;
      }
      components.add(_mathFiniteNumber(entry, symbol));
    }
  } else {
    for (final arg in args.take(4)) {
      components.add(_mathFiniteNumber(arg, symbol));
    }
  }

  if (components.length < 3 || components.length > 4) {
    throw LuaError('$symbol expected 3 or 4 color components');
  }

  return components;
}

List<double> _mathGammaComponents(List<Object?> args, String symbol) {
  final table = args.isNotEmpty ? _tableIfPresent(args.first) : null;
  final components = <double>[];

  if (table != null) {
    for (var index = 1; index <= 4; index++) {
      final entry = _tableIndexedEntry(table, index);
      if (entry == null) {
        break;
      }
      components.add(_mathFiniteNumber(entry, symbol));
    }
  } else {
    for (final arg in args.take(4)) {
      components.add(_mathFiniteNumber(arg, symbol));
    }
  }

  if (components.isEmpty) {
    throw LuaError('$symbol expected a number or color table');
  }

  return components;
}

T _mathGuard<T>(T Function() operation) {
  try {
    return operation();
  } on StateError catch (error) {
    throw LuaError(error.message.toString());
  } on ArgumentError catch (error) {
    throw LuaError(error.message?.toString() ?? error.toString());
  }
}

double _mathFiniteNumber(Object? value, String symbol) {
  final raw = _rawValue(value);
  if (raw is num) {
    final number = raw.toDouble();
    if (number.isFinite) {
      return number;
    }
  }

  throw LuaError('$symbol expected a finite number');
}

({int low, int high}) _randomSeedParts(
  List<Object?> args,
  int startIndex,
  String symbol,
) {
  const mask32 = 0xFFFFFFFF;
  const seedBits = 32;

  if (_valueAt(args, startIndex + 1) != null) {
    final low = _randomSeedInteger(_valueAt(args, startIndex), symbol) & mask32;
    final high =
        _randomSeedInteger(_valueAt(args, startIndex + 1), symbol) & mask32;
    return (low: low, high: high);
  }

  final seed =
      NumberUtils.toBigInt(
        _randomSeedInteger(_valueAt(args, startIndex), symbol),
      ) &
      ((BigInt.one << NumberLimits.sizeInBits) - BigInt.one);
  return (
    low: (seed & BigInt.from(mask32)).toInt(),
    high: ((seed >> seedBits) & BigInt.from(mask32)).toInt(),
  );
}

int _randomSeedInteger(Object? value, String symbol) {
  final raw = _rawValue(value);
  if (raw is int) {
    return raw;
  }

  if (raw is num) {
    final number = raw.toDouble();
    if (number.isFinite) {
      return number.truncate();
    }
  }

  throw LuaError('$symbol invalid random seed');
}

Object? _singleOrMulti(List<Object?> values) {
  if (values.length == 1) {
    return values.single;
  }

  return Value.multi(values);
}
