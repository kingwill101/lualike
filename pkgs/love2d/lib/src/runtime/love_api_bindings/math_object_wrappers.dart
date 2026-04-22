part of '../love_api_bindings.dart';

/// Table entry key that stores the backing [LoveBezierCurve] instance.
const String _loveBezierCurveObjectKey = '__love2d_bezier_curve__';

/// Table entry key that stores the backing [LoveRandomGenerator] instance.
const String _loveRandomGeneratorObjectKey = '__love2d_random_generator__';
const String _loveBezierCurveReleasedWrapperKey =
    '__love2d_bezier_curve_released__';
const String _loveRandomGeneratorReleasedWrapperKey =
    '__love2d_random_generator_released__';

/// Reuses Lua wrapper tables so the same curve keeps a stable identity.
final Expando<Value> _loveBezierCurveWrapperCache = Expando<Value>(
  'love2dBezierCurveWrapper',
);

/// Reuses Lua wrapper tables so the same generator keeps a stable identity.
final Expando<Value> _loveRandomGeneratorWrapperCache = Expando<Value>(
  'love2dRandomGeneratorWrapper',
);

/// Whether a BezierCurve has already been released through `Object:release`.
final Expando<bool> _loveBezierCurveReleased = Expando<bool>(
  'love2dBezierCurveReleased',
);

/// Whether a RandomGenerator has already been released through `Object:release`.
final Expando<bool> _loveRandomGeneratorReleased = Expando<bool>(
  'love2dRandomGeneratorReleased',
);

/// Returns the Lua wrapper table for a `BezierCurve`, including released wrappers.
Map<dynamic, dynamic>? _bezierCurveWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final curve = table[_loveBezierCurveObjectKey];
  if (curve is LoveBezierCurve ||
      table[_loveBezierCurveReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

/// Returns the Lua wrapper table for a `RandomGenerator`, including released wrappers.
Map<dynamic, dynamic>? _randomGeneratorWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final generator = table[_loveRandomGeneratorObjectKey];
  if (generator is LoveRandomGenerator ||
      table[_loveRandomGeneratorReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

/// Returns whether [value] is a released `BezierCurve` wrapper.
bool _bezierCurveWrapperReleased(Object? value) {
  final table = _bezierCurveWrapperTableIfPresent(value);
  return table?[_loveBezierCurveReleasedWrapperKey] == true;
}

/// Returns whether [value] is a released `RandomGenerator` wrapper.
bool _randomGeneratorWrapperReleased(Object? value) {
  final table = _randomGeneratorWrapperTableIfPresent(value);
  return table?[_loveRandomGeneratorReleasedWrapperKey] == true;
}

/// Returns wrapped [LoveBezierCurve] data when [value] is a BezierCurve table.
LoveBezierCurve? _bezierCurveIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final curve = table[_loveBezierCurveObjectKey];
  return curve is LoveBezierCurve ? curve : null;
}

/// Returns wrapped [LoveRandomGenerator] when [value] is a generator table.
LoveRandomGenerator? _randomGeneratorIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final generator = table[_loveRandomGeneratorObjectKey];
  return generator is LoveRandomGenerator ? generator : null;
}

/// Returns a required `BezierCurve` receiver.
LoveBezierCurve _requireBezierCurve(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _valueAt(args, index);
  if (_bezierCurveWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final curve = _bezierCurveIfPresent(value);
  if (curve != null) {
    return curve;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'BezierCurve',
    actual: value,
  );
}

/// Returns a required `RandomGenerator` receiver.
LoveRandomGenerator _requireRandomGenerator(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _valueAt(args, index);
  if (_randomGeneratorWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final generator = _randomGeneratorIfPresent(value);
  if (generator != null) {
    return generator;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'RandomGenerator',
    actual: value,
  );
}

/// Wraps a [LoveBezierCurve] as a Lua-facing `BezierCurve` object table.
Value _wrapBezierCurve(
  LibraryRegistrationContext context,
  LoveBezierCurve curve,
) {
  final cached = _loveBezierCurveWrapperCache[curve];
  if (cached != null && _bezierCurveIfPresent(cached) != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'BezierCurve', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveBezierCurveObjectKey: curve,
    'evaluate': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(args, 0, 'BezierCurve:evaluate');
        final point = _mathGuard(
          () => curve.evaluate(_requireNumber(args, 1, 'BezierCurve:evaluate')),
        );
        return Value.multi(<Object?>[point.x, point.y]);
      }),
      functionName: 'evaluate',
    ),
    'getControlPoint': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(
          args,
          0,
          'BezierCurve:getControlPoint',
        );
        final point = _mathGuard(
          () => curve.getControlPoint(
            _bezierControlPointIndex(args, 1, 'BezierCurve:getControlPoint'),
          ),
        );
        return Value.multi(<Object?>[point.x, point.y]);
      }),
      functionName: 'getControlPoint',
    ),
    'getControlPointCount': Value(
      builder.create(
        (args) => _requireBezierCurve(
          args,
          0,
          'BezierCurve:getControlPointCount',
        ).getControlPointCount(),
      ),
      functionName: 'getControlPointCount',
    ),
    'getDegree': Value(
      builder.create(
        (args) =>
            _requireBezierCurve(args, 0, 'BezierCurve:getDegree').getDegree(),
      ),
      functionName: 'getDegree',
    ),
    'getDerivative': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(args, 0, 'BezierCurve:getDerivative');
        return _wrapBezierCurve(context, _mathGuard(curve.getDerivative));
      }),
      functionName: 'getDerivative',
    ),
    'getSegment': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(args, 0, 'BezierCurve:getSegment');
        return _wrapBezierCurve(
          context,
          _mathGuard(
            () => curve.getSegment(
              _requireNumber(args, 1, 'BezierCurve:getSegment'),
              _requireNumber(args, 2, 'BezierCurve:getSegment'),
            ),
          ),
        );
      }),
      functionName: 'getSegment',
    ),
    'insertControlPoint': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(
          args,
          0,
          'BezierCurve:insertControlPoint',
        );
        curve.insertControlPoint(
          (
            x: _requireNumber(args, 1, 'BezierCurve:insertControlPoint'),
            y: _requireNumber(args, 2, 'BezierCurve:insertControlPoint'),
          ),
          args.length >= 4
              ? _bezierControlPointIndex(
                  args,
                  3,
                  'BezierCurve:insertControlPoint',
                )
              : -1,
        );
        return null;
      }),
      functionName: 'insertControlPoint',
    ),
    'removeControlPoint': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(
          args,
          0,
          'BezierCurve:removeControlPoint',
        );
        _mathGuard(
          () => curve.removeControlPoint(
            _bezierControlPointIndex(args, 1, 'BezierCurve:removeControlPoint'),
          ),
        );
        return null;
      }),
      functionName: 'removeControlPoint',
    ),
    'render': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(args, 0, 'BezierCurve:render');
        final accuracy = args.length >= 2
            ? _requireRoundedInt(args, 1, 'BezierCurve:render')
            : 5;
        return Value(
          _pointListToCoordinateTable(_mathGuard(() => curve.render(accuracy))),
        );
      }),
      functionName: 'render',
    ),
    'renderSegment': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(args, 0, 'BezierCurve:renderSegment');
        final accuracy = args.length >= 4
            ? _requireRoundedInt(args, 3, 'BezierCurve:renderSegment')
            : 5;
        return Value(
          _pointListToCoordinateTable(
            _mathGuard(
              () => curve.renderSegment(
                _requireNumber(args, 1, 'BezierCurve:renderSegment'),
                _requireNumber(args, 2, 'BezierCurve:renderSegment'),
                accuracy,
              ),
            ),
          ),
        );
      }),
      functionName: 'renderSegment',
    ),
    'rotate': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(args, 0, 'BezierCurve:rotate');
        curve.rotate(
          _requireNumber(args, 1, 'BezierCurve:rotate'),
          originX: _optionalNumber(
            args,
            2,
            'BezierCurve:rotate',
            defaultValue: 0.0,
          ),
          originY: _optionalNumber(
            args,
            3,
            'BezierCurve:rotate',
            defaultValue: 0.0,
          ),
        );
        return null;
      }),
      functionName: 'rotate',
    ),
    'scale': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(args, 0, 'BezierCurve:scale');
        curve.scale(
          _requireNumber(args, 1, 'BezierCurve:scale'),
          originX: _optionalNumber(
            args,
            2,
            'BezierCurve:scale',
            defaultValue: 0.0,
          ),
          originY: _optionalNumber(
            args,
            3,
            'BezierCurve:scale',
            defaultValue: 0.0,
          ),
        );
        return null;
      }),
      functionName: 'scale',
    ),
    'setControlPoint': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(
          args,
          0,
          'BezierCurve:setControlPoint',
        );
        _mathGuard(
          () => curve.setControlPoint(
            _bezierControlPointIndex(args, 1, 'BezierCurve:setControlPoint'),
            (
              x: _requireNumber(args, 2, 'BezierCurve:setControlPoint'),
              y: _requireNumber(args, 3, 'BezierCurve:setControlPoint'),
            ),
          ),
        );
        return null;
      }),
      functionName: 'setControlPoint',
    ),
    'translate': Value(
      builder.create((args) {
        final curve = _requireBezierCurve(args, 0, 'BezierCurve:translate');
        curve.translate(
          _requireNumber(args, 1, 'BezierCurve:translate'),
          _requireNumber(args, 2, 'BezierCurve:translate'),
        );
        return null;
      }),
      functionName: 'translate',
    ),
    'release': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        final table = _bezierCurveWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'BezierCurve',
            actual: receiver,
          );
        }

        final curve = table[_loveBezierCurveObjectKey];
        if (curve is! LoveBezierCurve) {
          return false;
        }
        if (_loveBezierCurveReleased[curve] == true) {
          return false;
        }

        _loveBezierCurveReleased[curve] = true;
        table[_loveBezierCurveReleasedWrapperKey] = true;
        table[_loveBezierCurveObjectKey] = null;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_bezierCurveWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'BezierCurve',
            actual: receiver,
          );
        }
        return 'BezierCurve';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_bezierCurveWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'BezierCurve',
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveBezierCurveWrapperCache[curve] = table;
  return table;
}

/// Wraps a [LoveRandomGenerator] as a Lua-facing `RandomGenerator` object table.
Value _wrapRandomGenerator(
  LibraryRegistrationContext unusedContext,
  LoveRandomGenerator generator,
) {
  final cached = _loveRandomGeneratorWrapperCache[generator];
  if (cached != null && _randomGeneratorIfPresent(cached) != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(unusedContext);
  const hierarchy = <String>{'RandomGenerator', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveRandomGeneratorObjectKey: generator,
    'getSeed': Value(
      builder.create((args) {
        final generator = _requireRandomGenerator(
          args,
          0,
          'RandomGenerator:getSeed',
        );
        return Value.multi(<Object?>[generator.seedLow, generator.seedHigh]);
      }),
      functionName: 'getSeed',
    ),
    'getState': Value(
      builder.create(
        (args) => _requireRandomGenerator(
          args,
          0,
          'RandomGenerator:getState',
        ).getState(),
      ),
      functionName: 'getState',
    ),
    'random': Value(
      builder.create((args) {
        final generator = _requireRandomGenerator(
          args,
          0,
          'RandomGenerator:random',
        );
        if (args.length == 1) {
          return generator.random();
        }

        if (args.length == 2) {
          return generator.random(
            _requireNumber(args, 1, 'RandomGenerator:random'),
          );
        }

        return generator.random(
          _requireNumber(args, 1, 'RandomGenerator:random'),
          _requireNumber(args, 2, 'RandomGenerator:random'),
        );
      }),
      functionName: 'random',
    ),
    'randomNormal': Value(
      builder.create((args) {
        final generator = _requireRandomGenerator(
          args,
          0,
          'RandomGenerator:randomNormal',
        );
        final stddev = args.length >= 2
            ? _requireNumber(args, 1, 'RandomGenerator:randomNormal')
            : 1.0;
        final mean = args.length >= 3
            ? _requireNumber(args, 2, 'RandomGenerator:randomNormal')
            : 0.0;
        return generator.randomNormal(stddev, mean);
      }),
      functionName: 'randomNormal',
    ),
    'setSeed': Value(
      builder.create((args) {
        final generator = _requireRandomGenerator(
          args,
          0,
          'RandomGenerator:setSeed',
        );
        final parts = _randomSeedParts(args, 1, 'RandomGenerator:setSeed');
        generator.setSeed(low: parts.low, high: parts.high);
        return null;
      }),
      functionName: 'setSeed',
    ),
    'setState': Value(
      builder.create((args) {
        final generator = _requireRandomGenerator(
          args,
          0,
          'RandomGenerator:setState',
        );
        _mathGuard(
          () => generator.setState(
            _requireString(args, 1, 'RandomGenerator:setState'),
          ),
        );
        return null;
      }),
      functionName: 'setState',
    ),
    'release': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        final table = _randomGeneratorWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'RandomGenerator',
            actual: receiver,
          );
        }

        final generator = table[_loveRandomGeneratorObjectKey];
        if (generator is! LoveRandomGenerator) {
          return false;
        }
        if (_loveRandomGeneratorReleased[generator] == true) {
          return false;
        }

        _loveRandomGeneratorReleased[generator] = true;
        table[_loveRandomGeneratorReleasedWrapperKey] = true;
        table[_loveRandomGeneratorObjectKey] = null;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_randomGeneratorWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'RandomGenerator',
            actual: receiver,
          );
        }
        return 'RandomGenerator';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_randomGeneratorWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'RandomGenerator',
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveRandomGeneratorWrapperCache[generator] = table;
  return table;
}

/// Converts a 1-based Lua control point index to the internal representation.
int _bezierControlPointIndex(List<Object?> args, int index, String symbol) {
  final value = _requireRoundedInt(args, index, symbol);
  return value > 0 ? value - 1 : value;
}

/// Flattens point pairs into the coordinate table shape used by Lua math APIs.
Map<Object?, Object?> _pointListToCoordinateTable(List<LoveMathPoint> points) {
  final table = <Object?, Object?>{};
  for (var i = 0; i < points.length; i++) {
    table[i * 2 + 1] = points[i].x;
    table[i * 2 + 2] = points[i].y;
  }
  return table;
}
