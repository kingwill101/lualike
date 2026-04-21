part of '../love_api_bindings.dart';

const String _loveBezierCurveObjectKey = '__love2d_bezier_curve__';
const String _loveRandomGeneratorObjectKey = '__love2d_random_generator__';

final Expando<Value> _loveBezierCurveWrapperCache = Expando<Value>(
  'love2dBezierCurveWrapper',
);
final Expando<Value> _loveRandomGeneratorWrapperCache = Expando<Value>(
  'love2dRandomGeneratorWrapper',
);

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

LoveBezierCurve _requireBezierCurve(
  List<Object?> args,
  int index,
  String symbol,
) {
  final curve = _bezierCurveIfPresent(_valueAt(args, index));
  if (curve != null) {
    return curve;
  }

  throw LuaError('$symbol expected a BezierCurve at argument ${index + 1}');
}

LoveRandomGenerator _requireRandomGenerator(
  List<Object?> args,
  int index,
  String symbol,
) {
  final generator = _randomGeneratorIfPresent(_valueAt(args, index));
  if (generator != null) {
    return generator;
  }

  throw LuaError('$symbol expected a RandomGenerator at argument ${index + 1}');
}

Value _wrapBezierCurve(
  LibraryRegistrationContext context,
  LoveBezierCurve curve,
) {
  final cached = _loveBezierCurveWrapperCache[curve];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
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
  });
  _loveBezierCurveWrapperCache[curve] = table;
  return table;
}

Value _wrapRandomGenerator(
  LibraryRegistrationContext unusedContext,
  LoveRandomGenerator generator,
) {
  final cached = _loveRandomGeneratorWrapperCache[generator];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(unusedContext);
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
  });
  _loveRandomGeneratorWrapperCache[generator] = table;
  return table;
}

int _bezierControlPointIndex(List<Object?> args, int index, String symbol) {
  final value = _requireRoundedInt(args, index, symbol);
  return value > 0 ? value - 1 : value;
}

Map<Object?, Object?> _pointListToCoordinateTable(List<LoveMathPoint> points) {
  final table = <Object?, Object?>{};
  for (var i = 0; i < points.length; i++) {
    table[i * 2 + 1] = points[i].x;
    table[i * 2 + 2] = points[i].y;
  }
  return table;
}
