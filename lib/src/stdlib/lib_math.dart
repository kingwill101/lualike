import 'dart:math' as math;
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/lualike.dart';

// Base class for math functions to handle common number validation
abstract class _MathFunction implements BuiltinFunction {
  String _typeName(dynamic value) {
    if (value == null) return 'nil';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    if (value is String) return 'string';
    if (value is List) return 'table';
    if (value is Function) return 'function';
    return value.runtimeType.toString();
  }

  dynamic _getNumber(Value value, String funcName, int argNum) {
    if (value.raw is! num && value.raw is! BigInt) {
      throw LuaError.typeError(
        "bad argument #$argNum to '$funcName' (number expected, got ${_typeName(value.raw)})",
      );
    }
    return value.raw;
  }

  BigInt _doubleToBigInt(double value) {
    final str = value.toStringAsFixed(0);
    if (str.contains('e') || str.contains('E')) {
      // Use LuaNumberParser for scientific notation
      final parsed = LuaNumberParser.parse(str);
      if (parsed is double) {
        throw FormatException('Cannot convert to BigInt');
      }
      return parsed is BigInt ? parsed : BigInt.from(parsed);
    }
    return BigInt.parse(str);
  }
}

class _MathAbs extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'abs' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "abs", 1);
    if (number is BigInt) {
      return Value(number.abs());
    }
    return Value((number as num).abs());
  }
}

class _MathAcos extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'acos' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "acos", 1);
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(math.acos(val));
  }
}

class _MathAsin extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'asin' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "asin", 1);
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(math.asin(val));
  }
}

class _MathAtan extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'atan' (number expected, got no value)",
      );
    }

    final y = _getNumber(args[0] as Value, "atan", 1);
    final double yDouble = y is BigInt ? y.toDouble() : (y as num).toDouble();

    if (args.length > 1) {
      final x = _getNumber(args[1] as Value, "atan", 2);
      final double xDouble = x is BigInt ? x.toDouble() : (x as num).toDouble();
      return Value(math.atan2(yDouble, xDouble));
    }

    return Value(math.atan(yDouble));
  }
}

class _MathCeil extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'ceil' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "ceil", 1);
    if (number is BigInt) {
      return Value(number);
    }
    if (number is int) {
      return Value(number);
    }
    final num n = number as num;
    if (n is double) {
      if (!n.isFinite) return Value(n);
      final doubleRes = n.ceilToDouble();
      if (doubleRes.isFinite) {
        try {
          // Try to convert to BigInt to avoid floating point precision issues
          final bigIntRes = _doubleToBigInt(doubleRes);
          // Check if it fits in int64 range
          if (bigIntRes >= BigInt.from(MathLib.minInteger) &&
              bigIntRes <= BigInt.from(MathLib.maxInteger)) {
            final intRes = bigIntRes.toInt();
            // Verify the conversion is exact
            if (intRes.toDouble() == doubleRes) {
              return Value(intRes);
            }
          }
        } catch (_) {
          // If BigInt conversion fails, fall through to return double
        }
      }
      return Value(doubleRes);
    }
    return Value(n);
  }
}

class _MathCos extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'cos' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "cos", 1);
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(math.cos(val));
  }
}

class _MathDeg extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'deg' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "deg", 1);
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(val * 180 / math.pi);
  }
}

class _MathExp extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'exp' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "exp", 1);
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(math.exp(val));
  }
}

class _MathFloor extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'floor' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "floor", 1);
    if (number is BigInt) {
      return Value(number);
    }
    if (number is int) {
      return Value(number);
    }
    final num n = number as num;
    if (n is double) {
      if (!n.isFinite) return Value(n);
      final doubleRes = n.floorToDouble();
      if (doubleRes.isFinite) {
        try {
          // Try to convert to BigInt to avoid floating point precision issues
          final bigIntRes = _doubleToBigInt(doubleRes);
          // Check if it fits in int64 range
          if (bigIntRes >= BigInt.from(MathLib.minInteger) &&
              bigIntRes <= BigInt.from(MathLib.maxInteger)) {
            final intRes = bigIntRes.toInt();
            // Verify the conversion is exact
            if (intRes.toDouble() == doubleRes) {
              return Value(intRes);
            }
          }
        } catch (_) {
          // If BigInt conversion fails, fall through to return double
        }
      }
      return Value(doubleRes);
    }
    return Value(n);
  }
}

class _MathFmod extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'fmod' (number expected, got no value)",
      );
    }
    if (args.length < 2) {
      throw LuaError.typeError(
        "bad argument #2 to 'fmod' (number expected, got no value)",
      );
    }

    final x = _getNumber(args[0] as Value, "fmod", 1);
    final y = _getNumber(args[1] as Value, "fmod", 2);

    // Check for division by zero
    if ((y is num && y == 0) || (y is BigInt && y == BigInt.zero)) {
      throw LuaError.typeError("bad argument #2 to 'math.fmod' (zero)");
    }

    if (x is BigInt || y is BigInt) {
      final bigX = x is BigInt ? x : BigInt.from(x as num);
      final bigY = y is BigInt ? y : BigInt.from(y as num);
      final result = bigX - (bigX ~/ bigY) * bigY;
      return Value(result);
    }

    // For integers, use integer arithmetic to avoid precision loss
    if (x is int && y is int) {
      // Use integer division to avoid floating point precision issues
      final quotient = x ~/ y; // truncated division
      final result = x - quotient * y;
      return Value(result);
    }

    // For floating point cases, use standard fmod behavior
    // Lua's fmod follows: fmod(x, y) = x - trunc(x/y) * y
    final dx = (x as num).toDouble();
    final dy = (y as num).toDouble();
    final quotient = dx / dy;
    final truncatedQuotient = quotient.truncateToDouble();
    final result = dx - truncatedQuotient * dy;

    return Value(result);
  }
}

class _MathLog extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'log' (number expected, got no value)",
      );
    }

    final x = _getNumber(args[0] as Value, "log", 1);
    final double xDouble = x is BigInt ? x.toDouble() : (x as num).toDouble();

    if (args.length > 1) {
      final base = _getNumber(args[1] as Value, "log", 2);
      final double baseDouble = base is BigInt
          ? base.toDouble()
          : (base as num).toDouble();
      return Value(math.log(xDouble) / math.log(baseDouble));
    }

    return Value(math.log(xDouble));
  }
}

class _MathMax extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("bad argument #1 to 'max' (value expected)");
    }

    dynamic max = _getNumber(args[0] as Value, "max", 1);

    for (int i = 1; i < args.length; i++) {
      final num = _getNumber(args[i] as Value, "max", i + 1);
      if (num > max) {
        max = num;
      }
    }

    return Value(max);
  }
}

class _MathMin extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("bad argument #1 to 'min' (value expected)");
    }

    dynamic min = _getNumber(args[0] as Value, "min", 1);

    for (int i = 1; i < args.length; i++) {
      final num = _getNumber(args[i] as Value, "min", i + 1);
      if (num < min) {
        min = num;
      }
    }

    return Value(min);
  }
}

class _MathModf extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.modf requires a number argument");
    }

    final number = _getNumber(args[0] as Value, "modf", 1);
    if (number is int || number is BigInt) {
      return Value.multi([Value(number), Value(0.0)]);
    }
    final d = number as double;
    if (d.isNaN) {
      return Value.multi([Value(double.nan), Value(double.nan)]);
    }
    if (d.isInfinite) {
      return Value.multi([Value(d), Value(0.0)]);
    }
    final intPart = d.truncateToDouble();
    final fracPart = d - intPart;
    return Value.multi([Value(intPart), Value(fracPart)]);
  }
}

class _MathRad extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.rad requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "rad", 1);
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(val * math.pi / 180);
  }
}

class _MathRandom extends _MathFunction {
  math.Random _random = math.Random();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      // No arguments: return a random float between 0 and 1
      return Value(_random.nextDouble());
    } else if (args.length == 1) {
      // One argument: return a random integer between 1 and n
      final n = _getNumber(args[0] as Value, "random", 1);
      final intN = n is BigInt ? n.toInt() : (n as num).toInt();
      if (intN == 0) {
        final high = _random.nextInt(0x100000000);
        final low = _random.nextInt(0x100000000);
        final result = (BigInt.from(high) << 32) | BigInt.from(low);
        return Value(result);
      }
      if (intN < 1) {
        throw LuaError.typeError("math.random: range is empty");
      }
      return Value(_random.nextInt(intN) + 1);
    } else if (args.length == 2) {
      // Two arguments: return a random integer between m and n
      final m = _getNumber(args[0] as Value, "random", 1);
      final n = _getNumber(args[1] as Value, "random", 2);
      final intM = m is BigInt ? m.toInt() : (m as num).toInt();
      final intN = n is BigInt ? n.toInt() : (n as num).toInt();

      if (intM > intN) {
        throw LuaError.typeError("math.random: range is empty");
      }
      return Value(intM + _random.nextInt(intN - intM + 1));
    } else {
      throw LuaError.typeError("wrong number of arguments to 'random'");
    }
  }
}

class _MathRandomseed extends _MathFunction {
  final _MathRandom _randomFunc;
  _MathRandomseed(this._randomFunc);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.randomseed requires a number argument");
    }

    final number = _getNumber(args[0] as Value, "randomseed", 1);
    final seed = number is BigInt ? number.toInt() : (number as num).toInt();
    _randomFunc._random = math.Random(seed);

    return Value(null);
  }
}

class _MathSin extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sin requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "sin", 1);
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(math.sin(val));
  }
}

class _MathSqrt extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sqrt requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "sqrt", 1);
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(math.sqrt(val));
  }
}

class _MathTan extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.tan requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "tan", 1);
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(math.tan(val));
  }
}

class _MathTointeger extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError('math.tointeger requires one argument');
    }

    dynamic value = args[0] is Value ? (args[0] as Value).raw : args[0];

    if (value is String) {
      try {
        value = LuaNumberParser.parse(value);
      } catch (_) {
        return Value(null);
      }
    }

    if (value is int) {
      return Value(value);
    } else if (value is BigInt) {
      if (value <= BigInt.from(MathLib.maxInteger) &&
          value >= BigInt.from(MathLib.minInteger)) {
        return Value(value.toInt());
      }
      return Value(null);
    } else if (value is double) {
      if (!value.isFinite) return Value(null);
      final int intVal = value.toInt();
      if (intVal.toDouble() == value &&
          intVal <= MathLib.maxInteger &&
          intVal >= MathLib.minInteger) {
        return Value(intVal);
      }
      return Value(null);
    }
    return Value(null);
  }
}

class _MathType extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.type requires one argument");
    }

    final value = args[0] as Value;
    if (value.raw is int || value.raw is BigInt) {
      return Value("integer");
    } else if (value.raw is double) {
      return Value("float");
    } else {
      return Value(null);
    }
  }
}

class _MathUlt extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError('math.ult requires two integer arguments');
    }

    dynamic m = args[0] is Value ? (args[0] as Value).raw : args[0];
    dynamic n = args[1] is Value ? (args[1] as Value).raw : args[1];

    if (m is! int && m is! BigInt) {
      throw LuaError.typeError('math.ult first argument must be an integer');
    }
    if (n is! int && n is! BigInt) {
      throw LuaError.typeError('math.ult second argument must be an integer');
    }

    BigInt mb = m is BigInt ? m : BigInt.from(m as int);
    BigInt nb = n is BigInt ? n : BigInt.from(n as int);

    final BigInt mod = BigInt.one << MathLib._sizeInBits;
    if (mb.isNegative) mb += mod;
    if (nb.isNegative) nb += mod;

    return Value(mb < nb);
  }
}

class MathLib {
  // Use 64-bit signed integer limits for maxInteger and minInteger
  static const int _sizeInBits = 64;
  static final int maxInteger = (1 << (_sizeInBits - 1)) - 1;
  static final int minInteger = -(1 << (_sizeInBits - 1));
  static void logIntegerLimits() {
    print(
      'MathLib: Dart platform maxInteger=\x1b[32m$maxInteger\x1b[0m, minInteger=\x1b[31m$minInteger\x1b[0m',
    );
  }

  static final _MathRandom _randomFunc = _MathRandom();
  static final Map<String, dynamic> functions = {
    "abs": _MathAbs(),
    "acos": _MathAcos(),
    "asin": _MathAsin(),
    "atan": _MathAtan(),
    "ceil": _MathCeil(),
    "cos": _MathCos(),
    "deg": _MathDeg(),
    "exp": _MathExp(),
    "floor": _MathFloor(),
    "fmod": _MathFmod(),
    "log": _MathLog(),
    "max": _MathMax(),
    "min": _MathMin(),
    "modf": _MathModf(),
    "pi": Value(math.pi),
    "rad": _MathRad(),
    "random": _randomFunc,
    "randomseed": _MathRandomseed(_randomFunc),
    "sin": _MathSin(),
    "sqrt": _MathSqrt(),
    "tan": _MathTan(),
    "tointeger": _MathTointeger(),
    "ult": _MathUlt(),
    "type": _MathType(),
    "huge": Value(double.infinity),
    "maxinteger": Value(maxInteger),
    "mininteger": Value(minInteger),
  };
}

void defineMathLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  env.define("math", MathLib.functions);
}
