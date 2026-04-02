import 'dart:math' as math;

import 'package:lualike/lualike.dart';
import 'library.dart';

import '../number_limits.dart' as limits;
import 'random_native.dart' if (dart.library.js_interop) 'random_web.dart';

/// Math library implementation using the new Library system
class MathLibrary extends Library {
  @override
  String get name => "math";

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final interpreter = context.vm;

    // Register all math functions directly
    context.define("abs", _MathAbs(interpreter));
    context.define("acos", _MathAcos(interpreter));
    context.define("asin", _MathAsin(interpreter));
    context.define("atan", _MathAtan(interpreter));
    context.define("ceil", _MathCeil(interpreter));
    context.define("cos", _MathCos(interpreter));
    context.define("deg", _MathDeg(interpreter));
    context.define("exp", _MathExp(interpreter));
    context.define("floor", _MathFloor(interpreter));
    context.define("fmod", _MathFmod(interpreter));
    context.define("frexp", _MathFrexp(interpreter));
    context.define("ldexp", _MathLdexp(interpreter));
    context.define("log", _MathLog(interpreter));
    context.define("max", _MathMax(interpreter));
    context.define("min", _MathMin(interpreter));
    context.define("modf", _MathModf(interpreter));
    context.define("pi", Value(math.pi));
    context.define("rad", _MathRad(interpreter));
    final randomFunc = _MathRandom(interpreter);
    context.define("random", randomFunc);
    context.define("randomseed", _MathRandomseed(randomFunc));
    context.define("sin", _MathSin(interpreter));
    context.define("sqrt", _MathSqrt(interpreter));
    context.define("tan", _MathTan(interpreter));
    context.define("tointeger", _MathTointeger(interpreter));
    context.define("ult", _MathUlt(interpreter));
    context.define("type", _MathType(interpreter));
    context.define("huge", Value(double.infinity));
    context.define("maxinteger", Value(limits.NumberLimits.maxInteger));
    context.define("mininteger", Value(limits.NumberLimits.minInteger));
  }
}

// Base class for math functions to handle common number validation
dynamic _getNumber(Value value, String funcName, int argNum) {
  return NumberUtils.getNumber(value, funcName, argNum);
}

dynamic _getFastNumber(Object? value, String funcName, int argNum) {
  if (value case Value(isMulti: false, raw: final rawNumber)
      when rawNumber is int || rawNumber is double || rawNumber is BigInt) {
    return rawNumber;
  }
  return _getNumber(value as Value, funcName, argNum);
}

Object? _tryFastMinMaxNumericResult(
  Object? arg0,
  Object? arg1, {
  required bool wantMax,
}) {
  if (arg0 case Value(isMulti: false, raw: final leftRaw)) {
    if (arg1 case Value(isMulti: false, raw: final rightRaw)) {
      if (leftRaw is num && rightRaw is num) {
        return wantMax
            ? (leftRaw >= rightRaw ? leftRaw : rightRaw)
            : (leftRaw <= rightRaw ? leftRaw : rightRaw);
      }
      if (leftRaw is BigInt && rightRaw is BigInt) {
        return wantMax
            ? (leftRaw >= rightRaw ? leftRaw : rightRaw)
            : (leftRaw <= rightRaw ? leftRaw : rightRaw);
      }
    }
  }
  return null;
}

abstract class _MathBuiltin extends BuiltinFunction {
  _MathBuiltin([super.interpreter]);

  @override
  bool get canBytecodeInlineWithoutManagedFrame => true;
}

class _MathAbs extends _MathBuiltin {
  _MathAbs([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'abs' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "abs", 1);
    return primitiveValue(NumberUtils.abs(number));
  }
}

class _MathAcos extends _MathBuiltin {
  _MathAcos([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'acos' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "acos", 1);
    return primitiveValue(math.acos(NumberUtils.toDouble(number)));
  }
}

class _MathAsin extends _MathBuiltin {
  _MathAsin([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'asin' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "asin", 1);
    return primitiveValue(math.asin(NumberUtils.toDouble(number)));
  }
}

class _MathAtan extends _MathBuiltin {
  _MathAtan([super.interpreter]);

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
      return primitiveValue(math.atan2(yDouble, xDouble));
    }

    return primitiveValue(math.atan(yDouble));
  }
}

class _MathCeil extends _MathBuiltin {
  _MathCeil([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'ceil' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "ceil", 1);
    if (number is BigInt || number is int) {
      return primitiveValue(number);
    }
    final double n = NumberUtils.toDouble(number);
    if (!n.isFinite) return primitiveValue(n);

    final doubleRes = n.ceilToDouble();
    return primitiveValue(NumberUtils.optimizeNumericResult(doubleRes));
  }
}

class _MathCos extends _MathBuiltin {
  _MathCos([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'cos' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "cos", 1);
    return primitiveValue(math.cos(NumberUtils.toDouble(number)));
  }
}

class _MathDeg extends _MathBuiltin {
  _MathDeg([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'deg' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "deg", 1);
    return primitiveValue(NumberUtils.toDouble(number) * 180 / math.pi);
  }
}

class _MathExp extends _MathBuiltin {
  _MathExp([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'exp' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "exp", 1);
    return primitiveValue(math.exp(NumberUtils.toDouble(number)));
  }
}

class _MathFloor extends _MathBuiltin {
  _MathFloor([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'floor' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0] as Value, "floor", 1);
    if (number is BigInt || number is int) {
      return primitiveValue(number);
    }
    final double n = NumberUtils.toDouble(number);
    if (!n.isFinite) return primitiveValue(n);

    final doubleRes = n.floorToDouble();
    return primitiveValue(NumberUtils.optimizeNumericResult(doubleRes));
  }
}

class _MathFmod extends _MathBuiltin {
  _MathFmod([super.interpreter]);

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

    return primitiveValue(NumberUtils.fmod(x, y));
  }
}

class _MathFrexp extends _MathBuiltin {
  _MathFrexp([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'frexp' (number expected, got no value)",
      );
    }

    final number = _getNumber(args[0] as Value, "frexp", 1);
    final (mantissa, exponent) = NumberUtils.frexp(number);
    return Value.multi([primitiveValue(mantissa), primitiveValue(exponent)]);
  }
}

class _MathLdexp extends _MathBuiltin {
  _MathLdexp([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'ldexp' (number expected, got no value)",
      );
    }
    if (args.length < 2) {
      throw LuaError.typeError(
        "bad argument #2 to 'ldexp' (number expected, got no value)",
      );
    }

    final number = _getNumber(args[0] as Value, "ldexp", 1);
    final exponentValue = args[1] as Value;
    final exponentRaw = exponentValue.raw;
    if (exponentRaw is! num && exponentRaw is! BigInt) {
      throw LuaError.typeError(
        "bad argument #2 to 'ldexp' "
        "(number expected, got ${NumberUtils.typeName(exponentRaw)})",
      );
    }

    final exponent = NumberUtils.tryToInteger(exponentRaw);
    if (exponent == null) {
      throw LuaError.typeError(
        "bad argument #2 to 'ldexp' (number has no integer representation)",
      );
    }

    return primitiveValue(NumberUtils.ldexp(number, exponent));
  }
}

class _MathLog extends _MathBuiltin {
  _MathLog([super.interpreter]);

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
      return primitiveValue(math.log(xDouble) / math.log(baseDouble));
    }

    return primitiveValue(math.log(xDouble));
  }
}

class _MathMax extends _MathBuiltin {
  _MathMax(super.interpreter);

  @override
  Object? fastCall2(Object? arg0, Object? arg1) {
    final fastResult = _tryFastMinMaxNumericResult(
      arg0,
      arg1,
      wantMax: true,
    );
    if (fastResult != null) {
      return fastResult;
    }
    return NumberUtils.max(
      _getFastNumber(arg0, "max", 1),
      _getFastNumber(arg1, "max", 2),
    );
  }

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

    return primitiveValue(max);
  }
}

class _MathMin extends _MathBuiltin {
  _MathMin(super.interpreter);

  @override
  Object? fastCall2(Object? arg0, Object? arg1) {
    final fastResult = _tryFastMinMaxNumericResult(
      arg0,
      arg1,
      wantMax: false,
    );
    if (fastResult != null) {
      return fastResult;
    }
    return NumberUtils.min(
      _getFastNumber(arg0, "min", 1),
      _getFastNumber(arg1, "min", 2),
    );
  }

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

    return primitiveValue(min);
  }
}

class _MathModf extends _MathBuiltin {
  _MathModf(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.modf requires a number argument");
    }

    final number = _getNumber(args[0] as Value, "modf", 1);
    final (intPart, fracPart) = NumberUtils.modf(number);
    return Value.multi([primitiveValue(intPart), primitiveValue(fracPart)]);
  }
}

class _MathRad extends _MathBuiltin {
  _MathRad([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.rad requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "rad", 1);
    return primitiveValue(NumberUtils.toDouble(number) * math.pi / 180);
  }
}

class _MathRandom extends _MathBuiltin {
  _MathRandom([super.interpreter]);

  Xoshiro256ss _random = Xoshiro256ss.seeded();

  @override
  Object? fastCall0() {
    return _random.nextDouble();
  }

  @override
  Object? fastCall1(Object? arg0) {
    final n = _getFastNumber(arg0, "random", 1);
    final intN = NumberUtils.toInt(n);
    if (intN == 0) {
      return _random.nextRaw64();
    }
    if (intN < 1) {
      throw LuaError.typeError(
        "bad argument #1 to 'random' (interval is empty)",
      );
    }
    final rv = _random.nextRaw64();
    final projected = _project(rv, intN);
    return 1 + projected;
  }

  @override
  Object? fastCall2(Object? arg0, Object? arg1) {
    final m = _getFastNumber(arg0, "random", 1);
    final n = _getFastNumber(arg1, "random", 2);
    final intM = NumberUtils.toInt(m);
    final intN = NumberUtils.toInt(n);

    if (intM > intN) {
      throw LuaError.typeError(
        "bad argument #1 to 'random' (interval is empty)",
      );
    }

    final rangePlusOne = intN - intM + 1;
    final bigM = NumberUtils.toBigInt(intM);
    final rv = _random.nextRaw64();
    if (rangePlusOne > 0 && rangePlusOne <= limits.NumberLimits.maxInteger) {
      final projected = _project(rv, rangePlusOne);
      return intM + projected;
    }

    final urv = rv.toUnsigned(64);
    final bigN = NumberUtils.toBigInt(intN);
    final bigRangePlusOne = (bigN - bigM) + BigInt.one;
    final bigResult = BigInt.from(urv) % bigRangePlusOne;
    final finalResult = bigM + bigResult;

    if (finalResult < NumberUtils.toBigInt(limits.NumberLimits.minInteger) ||
        finalResult > NumberUtils.toBigInt(limits.NumberLimits.maxInteger)) {
      throw LuaError.typeError("random result overflow");
    }

    return finalResult.toInt();
  }

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      // No arguments: return float between 0 and 1
      return primitiveValue(_random.nextDouble());
    } else if (args.length == 1) {
      // Single argument: return integer in [1, n] or full integer if n=0
      final n = _getNumber(args[0] as Value, "random", 1);
      final intN = NumberUtils.toInt(n);
      if (intN == 0) {
        // Return full random 64-bit integer (signed)
        final raw = _random.nextRaw64();
        return primitiveValue(raw);
      }
      if (intN < 1) {
        throw LuaError.typeError(
          "bad argument #1 to 'random' (interval is empty)",
        );
      }
      // Use project method for range [1, n]
      final rv = _random.nextRaw64();
      final projected = _project(rv, intN);
      return primitiveValue(1 + projected);
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

      final rangePlusOne = intN - intM + 1;
      final rv = _random.nextRaw64();
      if (rangePlusOne > 0 && rangePlusOne <= limits.NumberLimits.maxInteger) {
        final projected = _project(rv, rangePlusOne);
        return primitiveValue(intM + projected);
      }

      // Use BigInt arithmetic to safely calculate range size and avoid overflow
      final bigM = NumberUtils.toBigInt(intM);
      final bigN = NumberUtils.toBigInt(intN);
      final bigRangeSize = bigN - bigM;

      // Check if range size + 1 exceeds what we can handle with int64
      final bigRangePlusOne = bigRangeSize + BigInt.one;
      final urv = rv.toUnsigned(64);

      // Use BigInt modulo to handle large ranges safely
      final bigResult = BigInt.from(urv) % bigRangePlusOne;

      // Use BigInt addition to avoid overflow in final calculation
      final finalResult = bigM + bigResult;

      // Ensure result fits in int64 range
      if (finalResult < NumberUtils.toBigInt(limits.NumberLimits.minInteger) ||
          finalResult > NumberUtils.toBigInt(limits.NumberLimits.maxInteger)) {
        throw LuaError.typeError("random result overflow");
      }

      return primitiveValue(finalResult.toInt());
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

class _MathRandomseed extends _MathBuiltin {
  final _MathRandom _randomFunc;
  _MathRandomseed(this._randomFunc) : super(_randomFunc.interpreter);

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

    return Value.multi([primitiveValue(n1), primitiveValue(n2)]);
  }
}

class _MathSin extends _MathBuiltin {
  _MathSin([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sin requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "sin", 1);
    return primitiveValue(math.sin(NumberUtils.toDouble(number)));
  }
}

class _MathSqrt extends _MathBuiltin {
  _MathSqrt([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sqrt requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "sqrt", 1);
    return primitiveValue(math.sqrt(NumberUtils.toDouble(number)));
  }
}

class _MathTan extends _MathBuiltin {
  _MathTan([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.tan requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "tan", 1);
    return primitiveValue(math.tan(NumberUtils.toDouble(number)));
  }
}

class _MathTointeger extends _MathBuiltin {
  _MathTointeger([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError('math.tointeger requires one argument');
    }

    dynamic value = args[0] is Value ? (args[0] as Value).raw : args[0];
    final result = NumberUtils.tryToInteger(value);
    return primitiveValue(result);
  }
}

class _MathType extends _MathBuiltin {
  _MathType([super.interpreter]);

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
      return primitiveValue(null);
    }
  }
}

class _MathUlt extends _MathBuiltin {
  _MathUlt([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError('math.ult requires two integer arguments');
    }

    dynamic m = args[0] is Value ? (args[0] as Value).raw : args[0];
    dynamic n = args[1] is Value ? (args[1] as Value).raw : args[1];

    return primitiveValue(NumberUtils.unsignedLessThan(m, n));
  }
}
