import 'dart:math' as math;
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/lualike.dart';
import 'package:xrandom/xrandom.dart';
import 'number_utils.dart';

// Base class for math functions to handle common number validation
abstract class _MathFunction implements BuiltinFunction {
  dynamic _getNumber(Value value, String funcName, int argNum) {
    return NumberUtils.getNumber(value, funcName, argNum);
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
    return Value(NumberUtils.abs(number));
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
    return Value(math.acos(NumberUtils.toDouble(number)));
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
    return Value(math.asin(NumberUtils.toDouble(number)));
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
    final double yDouble = NumberUtils.toDouble(y);

    if (args.length > 1) {
      final x = _getNumber(args[1] as Value, "atan", 2);
      final double xDouble = NumberUtils.toDouble(x);
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
    if (number is BigInt || number is int) {
      return Value(number);
    }
    final double n = NumberUtils.toDouble(number);
    if (!n.isFinite) return Value(n);

    final doubleRes = n.ceilToDouble();
    return Value(NumberUtils.optimizeNumericResult(doubleRes));
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
    return Value(math.cos(NumberUtils.toDouble(number)));
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
    return Value(NumberUtils.toDouble(number) * 180 / math.pi);
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
    return Value(math.exp(NumberUtils.toDouble(number)));
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
    if (number is BigInt || number is int) {
      return Value(number);
    }
    final double n = NumberUtils.toDouble(number);
    if (!n.isFinite) return Value(n);

    final doubleRes = n.floorToDouble();
    return Value(NumberUtils.optimizeNumericResult(doubleRes));
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

    return Value(NumberUtils.fmod(x, y));
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
    final double xDouble = NumberUtils.toDouble(x);

    if (args.length > 1) {
      final base = _getNumber(args[1] as Value, "log", 2);
      final double baseDouble = NumberUtils.toDouble(base);
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
      max = NumberUtils.max(max, num);
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
      min = NumberUtils.min(min, num);
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
    final (intPart, fracPart) = NumberUtils.modf(number);
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
    return Value(NumberUtils.toDouble(number) * math.pi / 180);
  }
}

class _MathRandom extends _MathFunction {
  Xoshiro256ss _random = Xoshiro256ss.seeded();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      // No arguments: return float between 0 and 1
      return Value(_random.nextDouble());
    } else if (args.length == 1) {
      // Single argument: return integer in [1, n] or full integer if n=0
      final n = _getNumber(args[0] as Value, "random", 1);
      final intN = NumberUtils.toInt(n);
      if (intN == 0) {
        // Return full random 64-bit integer (signed)
        final raw = _random.nextRaw64();
        return Value(raw);
      }
      if (intN < 1) {
        throw LuaError.typeError(
          "bad argument #1 to 'random' (interval is empty)",
        );
      }
      // Use project method for range [1, n]
      final rv = _random.nextRaw64();
      final projected = _project(rv, intN);
      return Value(1 + projected);
    } else if (args.length == 2) {
      // Two arguments: return integer in [low, up]
      final m = _getNumber(args[0] as Value, "random", 1);
      final n = _getNumber(args[1] as Value, "random", 2);
      final intM = NumberUtils.toInt(m);
      final intN = NumberUtils.toInt(n);

      if (intM > intN) {
        throw LuaError.typeError(
          "bad argument #1 to 'random' (interval is empty)",
        );
      }

      // Use BigInt arithmetic to safely calculate range size and avoid overflow
      final bigM = NumberUtils.toBigInt(intM);
      final bigN = NumberUtils.toBigInt(intN);
      final bigRangeSize = bigN - bigM;

      // Check if range size + 1 exceeds what we can handle with int64
      final bigRangePlusOne = bigRangeSize + BigInt.one;

      final rv = _random.nextRaw64();
      final urv = rv.toUnsigned(64);

      // Use BigInt modulo to handle large ranges safely
      final bigResult = BigInt.from(urv) % bigRangePlusOne;

      // Use BigInt addition to avoid overflow in final calculation
      final finalResult = bigM + bigResult;

      // Ensure result fits in int64 range
      if (finalResult < NumberUtils.toBigInt(NumberUtils.minInteger) ||
          finalResult > NumberUtils.toBigInt(NumberUtils.maxInteger)) {
        throw LuaError.typeError("random result overflow");
      }

      return Value(finalResult.toInt());
    } else {
      throw LuaError.typeError("wrong number of arguments to 'random'");
    }
  }

  // Project a 64-bit random value into range [0, n-1]
  // This mimics Lua's project function for handling large ranges
  int _project(int rv, int n) {
    if (n <= 0) return 0;
    // Use unsigned arithmetic like Lua does
    final urv = rv.toUnsigned(64);
    final un = n.toUnsigned(64);
    return (urv % un).toSigned(64);
  }
}

class _MathRandomseed extends _MathFunction {
  final _MathRandom _randomFunc;
  _MathRandomseed(this._randomFunc);

  @override
  Object? call(List<Object?> args) {
    int n1;
    int n2;
    if (args.isEmpty) {
      n1 = DateTime.now().microsecondsSinceEpoch;
      n2 = Xoshiro256ss.seeded().nextRaw64();
    } else {
      final number1 = _getNumber(args[0] as Value, "randomseed", 1);
      n1 = NumberUtils.toInt(number1);
      if (args.length >= 2) {
        final number2 = _getNumber(args[1] as Value, "randomseed", 2);
        n2 = NumberUtils.toInt(number2);
      } else {
        n2 = 0;
      }
    }

    final rng = Xoshiro256ss(n1, 0xff, n2, 0);
    for (var i = 0; i < 16; i++) {
      rng.nextRaw64();
    }
    _randomFunc._random = rng;

    return Value.multi([Value(n1), Value(n2)]);
  }
}

class _MathSin extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sin requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "sin", 1);
    return Value(math.sin(NumberUtils.toDouble(number)));
  }
}

class _MathSqrt extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sqrt requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "sqrt", 1);
    return Value(math.sqrt(NumberUtils.toDouble(number)));
  }
}

class _MathTan extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.tan requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "tan", 1);
    return Value(math.tan(NumberUtils.toDouble(number)));
  }
}

class _MathTointeger extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError('math.tointeger requires one argument');
    }

    dynamic value = args[0] is Value ? (args[0] as Value).raw : args[0];
    final result = NumberUtils.tryToInteger(value);
    return Value(result);
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

    return Value(NumberUtils.unsignedLessThan(m, n));
  }
}

class MathLib {
  // Use constants from NumberUtils
  static int get maxInteger => NumberUtils.maxInteger;
  static int get minInteger => NumberUtils.minInteger;

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
