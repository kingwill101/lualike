import 'dart:math' as math;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'library.dart';

import '../number_limits.dart' as limits;
import 'random_native.dart' if (dart.library.js_interop) 'random_web.dart';

/// Math library implementation using the new Library system
class MathLibrary extends Library {
  @override
  String get name => "math";

  @override
  String get description =>
      'Standard mathematical functions including trigonometry, logarithms, and rounding.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final interpreter = context.vm;
    Value primitiveConstant(Object? raw) {
      return cachedPrimitiveOrValue(interpreter, raw);
    }

    final atanFunc = _MathAtan(interpreter);

    // Register all math functions directly
    context.define("abs", _MathAbs(interpreter));
    context.define("acos", _MathAcos(interpreter));
    context.define("asin", _MathAsin(interpreter));
    context.define("atan", atanFunc);
    context.define("atan2", _MathAtan(interpreter, "atan2"));
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
    context.define("pi", primitiveConstant(math.pi));
    context.define("pow", _MathPow(interpreter));
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
    context.define("huge", primitiveConstant(double.infinity));
    context.define(
      "maxinteger",
      primitiveConstant(limits.NumberLimits.maxInteger),
    );
    context.define(
      "mininteger",
      primitiveConstant(limits.NumberLimits.minInteger),
    );
  }
}

// Base class for math functions to handle common number validation.
dynamic _getNumber(Object? value, String funcName, int argNum) {
  return NumberUtils.getNumber(value, funcName, argNum);
}

dynamic _getFastNumber(Object? value, String funcName, int argNum) {
  if (value is int || value is double || value is BigInt) {
    return value;
  }
  if (value is Value && luaResultValues(value) == null) {
    final rawNumber = rawLuaSlot(value);
    if (rawNumber is int || rawNumber is double || rawNumber is BigInt) {
      return rawNumber;
    }
  }
  return _getNumber(value, funcName, argNum);
}

Object? _tryFastMinMaxNumericResult(
  Object? arg0,
  Object? arg1, {
  required bool wantMax,
}) {
  if (arg0 is Value && luaResultValues(arg0) == null) {
    final leftRaw = rawLuaSlot(arg0);
    if (arg1 is Value && luaResultValues(arg1) == null) {
      final rightRaw = rawLuaSlot(arg1);
      if (leftRaw is num && rightRaw is num) {
        if (leftRaw is double && leftRaw.isNaN) return leftRaw;
        if (rightRaw is double && rightRaw.isNaN) return rightRaw;
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

  // The bytecode VM may call these builtins directly without pushing a managed
  // Lua frame. Keep subclasses limited to synchronous numeric work that does
  // not inspect call-stack-only state or call back into Lua.
  @override
  bool get canBytecodeInlineWithoutManagedFrame => true;
}

class _MathAbs extends _MathBuiltin {
  _MathAbs([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the absolute value of a number.',
    params: [DocParam('x', 'number', 'The input value.')],
    returns: 'The absolute value of x.',
    category: 'math',
    example: 'print(math.abs(-5)) --> 5',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'abs' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0], "abs", 1);
    return primitiveValue(NumberUtils.abs(number));
  }
}

class _MathAcos extends _MathBuiltin {
  _MathAcos([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the arc cosine of a number in radians.',
    params: [
      DocParam('x', 'number', 'The cosine value, must be in range [-1, 1].'),
    ],
    returns: 'The arc cosine in radians.',
    category: 'math',
    example: 'print(math.acos(0)) --> 1.5707963267949',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'acos' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0], "acos", 1);
    return primitiveValue(math.acos(NumberUtils.toDouble(number)));
  }
}

class _MathAsin extends _MathBuiltin {
  _MathAsin([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the arc sine of a number in radians.',
    params: [
      DocParam('x', 'number', 'The sine value, must be in range [-1, 1].'),
    ],
    returns: 'The arc sine in radians.',
    category: 'math',
    example: 'print(math.asin(1)) --> 1.5707963267949',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'asin' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0], "asin", 1);
    return primitiveValue(math.asin(NumberUtils.toDouble(number)));
  }
}

class _MathAtan extends _MathBuiltin {
  _MathAtan([super.interpreter, this.functionName = "atan"]);

  final String functionName;

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Returns the arc tangent of a number in radians, or the angle of y/x.',
    params: [
      DocParam('y', 'number', 'The y coordinate.'),
      DocParam('x', 'number', 'The x coordinate (optional).', optional: true),
    ],
    returns: 'The arc tangent in radians.',
    category: 'math',
    example: 'print(math.atan(1)) --> 0.78539816339745',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to '$functionName' (number expected, got no value)",
      );
    }

    final y = _getNumber(args[0], functionName, 1);
    final double yDouble = NumberUtils.toDouble(y);

    if (args.length > 1) {
      final x = _getNumber(args[1], functionName, 2);
      final double xDouble = NumberUtils.toDouble(x);
      return primitiveValue(math.atan2(yDouble, xDouble));
    }

    return primitiveValue(math.atan(yDouble));
  }
}

class _MathCeil extends _MathBuiltin {
  _MathCeil([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the smallest integer greater than or equal to x.',
    params: [DocParam('x', 'number', 'The input value.')],
    returns: 'The ceiling of x as an integer.',
    category: 'math',
    example: 'print(math.ceil(3.14)) --> 4',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'ceil' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0], "ceil", 1);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the cosine of an angle in radians.',
    params: [DocParam('x', 'number', 'The angle in radians.')],
    returns: 'The cosine of x.',
    category: 'math',
    example: 'print(math.cos(0)) --> 1',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'cos' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0], "cos", 1);
    return primitiveValue(math.cos(NumberUtils.toDouble(number)));
  }
}

class _MathDeg extends _MathBuiltin {
  _MathDeg([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Converts a number from radians to degrees.',
    params: [DocParam('x', 'number', 'The angle in radians.')],
    returns: 'The angle in degrees.',
    category: 'math',
    example: 'print(math.deg(math.pi)) --> 180',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'deg' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0], "deg", 1);
    return primitiveValue(NumberUtils.toDouble(number) * 180 / math.pi);
  }
}

class _MathExp extends _MathBuiltin {
  _MathExp([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns e raised to the power of x (the exponential function).',
    params: [DocParam('x', 'number', 'The exponent.')],
    returns: 'e^x.',
    category: 'math',
    example: 'print(math.exp(1)) --> 2.718281828459',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'exp' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0], "exp", 1);
    return primitiveValue(math.exp(NumberUtils.toDouble(number)));
  }
}

class _MathFloor extends _MathBuiltin {
  _MathFloor([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the largest integer less than or equal to x.',
    params: [DocParam('x', 'number', 'The input value.')],
    returns: 'The floor of x as an integer.',
    category: 'math',
    example: 'print(math.floor(3.14)) --> 3',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'floor' (number expected, got no value)",
      );
    }
    final number = _getNumber(args[0], "floor", 1);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the remainder of x divided by y (floating-point modulo).',
    params: [
      DocParam('x', 'number', 'The dividend.'),
      DocParam('y', 'number', 'The divisor.'),
    ],
    returns: 'The remainder of x/y.',
    category: 'math',
    example: 'print(math.fmod(10, 3)) --> 1',
  );

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

    final x = _getNumber(args[0], "fmod", 1);
    final y = _getNumber(args[1], "fmod", 2);

    return primitiveValue(NumberUtils.fmod(x, y));
  }
}

class _MathFrexp extends _MathBuiltin {
  _MathFrexp([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Decomposes a floating-point number into mantissa and exponent.',
    params: [DocParam('x', 'number', 'The input value.')],
    returns: 'The mantissa and exponent as two values.',
    category: 'math',
    example: 'local m, e = math.frexp(8) --> 0.5, 4',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'frexp' (number expected, got no value)",
      );
    }

    final number = _getNumber(args[0], "frexp", 1);
    final (mantissa, exponent) = NumberUtils.frexp(number);
    return LuaResults([mantissa, exponent]);
  }
}

class _MathLdexp extends _MathBuiltin {
  _MathLdexp([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns x * 2^e (the inverse of frexp).',
    params: [
      DocParam('x', 'number', 'The mantissa.'),
      DocParam('e', 'number', 'The exponent.'),
    ],
    returns: 'The computed value x * 2^e.',
    category: 'math',
    example: 'print(math.ldexp(0.5, 4)) --> 8',
  );

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

    final number = _getNumber(args[0], "ldexp", 1);
    final exponentRaw = rawLuaSlot(args[1]);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the logarithm of x in the given base.',
    params: [
      DocParam('x', 'number', 'The input value.'),
      DocParam(
        'base',
        'number',
        'The logarithm base (defaults to e).',
        optional: true,
      ),
    ],
    returns: 'The logarithm of x.',
    category: 'math',
    example: 'print(math.log(100, 10)) --> 2',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'log' (number expected, got no value)",
      );
    }

    final x = _getNumber(args[0], "log", 1);
    final double xDouble = NumberUtils.toDouble(x);

    if (args.length > 1) {
      final base = _getNumber(args[1], "log", 2);
      final double baseDouble = NumberUtils.toDouble(base);
      return primitiveValue(math.log(xDouble) / math.log(baseDouble));
    }

    return primitiveValue(math.log(xDouble));
  }
}

class _MathMax extends _MathBuiltin {
  _MathMax(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the maximum value among its arguments.',
    params: [DocParam('...', 'number', 'One or more numbers.')],
    returns: 'The maximum value.',
    category: 'math',
    example: 'print(math.max(3, 7, 2, 9, 5)) --> 9',
  );

  @override
  Object? fastCall2(Object? arg0, Object? arg1) {
    final fastResult = _tryFastMinMaxNumericResult(arg0, arg1, wantMax: true);
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

    dynamic max = _getNumber(args[0], "max", 1);

    for (int i = 1; i < args.length; i++) {
      final num = _getNumber(args[i], "max", i + 1);
      max = NumberUtils.max(max, num);
    }

    return primitiveValue(max);
  }
}

class _MathMin extends _MathBuiltin {
  _MathMin(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the minimum value among its arguments.',
    params: [DocParam('...', 'number', 'One or more numbers.')],
    returns: 'The minimum value.',
    category: 'math',
    example: 'print(math.min(3, 7, 2, 9, 5)) --> 2',
  );

  @override
  Object? fastCall2(Object? arg0, Object? arg1) {
    final fastResult = _tryFastMinMaxNumericResult(arg0, arg1, wantMax: false);
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

    dynamic min = _getNumber(args[0], "min", 1);

    for (int i = 1; i < args.length; i++) {
      final num = _getNumber(args[i], "min", i + 1);
      min = NumberUtils.min(min, num);
    }

    return primitiveValue(min);
  }
}

class _MathModf extends _MathBuiltin {
  _MathModf(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Decomposes a number into its integer and fractional parts.',
    params: [DocParam('x', 'number', 'The input value.')],
    returns: 'The integer part and the fractional part.',
    category: 'math',
    example: 'local int, frac = math.modf(3.14) --> 3, 0.14',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.modf requires a number argument");
    }

    final number = _getNumber(args[0], "modf", 1);
    final (intPart, fracPart) = NumberUtils.modf(number);
    return LuaResults([intPart, fracPart]);
  }
}

class _MathPow extends _MathBuiltin {
  _MathPow([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns x raised to the power y.',
    params: [
      DocParam('x', 'number', 'The base.'),
      DocParam('y', 'number', 'The exponent.'),
    ],
    returns: 'x^y.',
    category: 'math',
    example: 'print(math.pow(2, 10)) --> 1024',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'pow' (number expected, got no value)",
      );
    }
    if (args.length < 2) {
      throw LuaError.typeError(
        "bad argument #2 to 'pow' (number expected, got no value)",
      );
    }

    final base = _getNumber(args[0], "pow", 1);
    final exponent = _getNumber(args[1], "pow", 2);
    return primitiveValue(NumberUtils.exponentiate(base, exponent));
  }
}

class _MathRad extends _MathBuiltin {
  _MathRad([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Converts a number from degrees to radians.',
    params: [DocParam('x', 'number', 'The angle in degrees.')],
    returns: 'The angle in radians.',
    category: 'math',
    example: 'print(math.rad(180)) --> 3.1415926535898',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.rad requires a number argument");
    }
    final number = _getNumber(args[0], "rad", 1);
    return primitiveValue(NumberUtils.toDouble(number) * math.pi / 180);
  }
}

class _MathRandom extends _MathBuiltin {
  _MathRandom([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Returns a pseudo-random number. With no arguments, returns a float in [0,1). With one argument m, returns an integer in [1, m]. With two arguments m, n, returns an integer in [m, n].',
    params: [
      DocParam(
        'm',
        'number',
        'Upper bound (or lower bound if n is also given).',
        optional: true,
      ),
      DocParam('n', 'number', 'Upper bound.', optional: true),
    ],
    returns: 'A pseudo-random number.',
    category: 'math',
    example: 'local r = math.random(1, 6) -- dice roll',
  );

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
      final n = _getNumber(args[0], "random", 1);
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
      final m = _getNumber(args[0], "random", 1);
      final n = _getNumber(args[1], "random", 2);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Seeds the pseudo-random number generator.',
    params: [DocParam('x', 'number', 'The seed value.')],
    returns: 'Nothing.',
    category: 'math',
    example: 'math.randomseed(os.time())',
  );

  @override
  Object? call(List<Object?> args) {
    int n1;
    int n2;
    if (args.isEmpty) {
      n1 = DateTime.now().microsecondsSinceEpoch;
      n2 = Xoshiro256ss.seeded().nextRaw64();
    } else {
      final number1 = _getNumber(args[0], "randomseed", 1);
      n1 = NumberUtils.toInt(number1);
      if (args.length >= 2) {
        final number2 = _getNumber(args[1], "randomseed", 2);
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

    return LuaResults([n1, n2]);
  }
}

class _MathSin extends _MathBuiltin {
  _MathSin([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the sine of an angle in radians.',
    params: [DocParam('x', 'number', 'The angle in radians.')],
    returns: 'The sine of x.',
    category: 'math',
    example: 'print(math.sin(math.pi/2)) --> 1',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sin requires a number argument");
    }
    final number = _getNumber(args[0], "sin", 1);
    return primitiveValue(math.sin(NumberUtils.toDouble(number)));
  }
}

class _MathSqrt extends _MathBuiltin {
  _MathSqrt([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the square root of x.',
    params: [DocParam('x', 'number', 'The input value.')],
    returns: 'The square root of x.',
    category: 'math',
    example: 'print(math.sqrt(9)) --> 3',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sqrt requires a number argument");
    }
    final number = _getNumber(args[0], "sqrt", 1);
    return primitiveValue(math.sqrt(NumberUtils.toDouble(number)));
  }
}

class _MathTan extends _MathBuiltin {
  _MathTan([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the tangent of an angle in radians.',
    params: [DocParam('x', 'number', 'The angle in radians.')],
    returns: 'The tangent of x.',
    category: 'math',
    example: 'print(math.tan(math.pi/4)) --> 1',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.tan requires a number argument");
    }
    final number = _getNumber(args[0], "tan", 1);
    return primitiveValue(math.tan(NumberUtils.toDouble(number)));
  }
}

class _MathTointeger extends _MathBuiltin {
  _MathTointeger([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the integer part of x, or nil if x is not convertible.',
    params: [DocParam('x', 'number', 'The input value.')],
    returns: 'The integer value, or nil.',
    category: 'math',
    example: 'print(math.tointeger(3.14)) --> 3',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError('math.tointeger requires one argument');
    }

    final value = rawLuaSlot(args[0]);
    final result = NumberUtils.tryToInteger(value);
    return primitiveValue(result);
  }
}

class _MathType extends _MathBuiltin {
  _MathType([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the numeric type of a number: "integer" or "float".',
    params: [DocParam('x', 'number', 'The input value.')],
    returns: '"integer" or "float".',
    category: 'math',
    example: 'print(math.type(3)) --> integer',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.type requires one argument");
    }

    final value = rawLuaSlot(args[0]);
    if (value is int || value is BigInt) {
      return dartStringValue("integer");
    } else if (value is double) {
      return dartStringValue("float");
    } else {
      return primitiveValue(null);
    }
  }
}

class _MathUlt extends _MathBuiltin {
  _MathUlt([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Returns true if m < n when both are compared as unsigned integers.',
    params: [
      DocParam('m', 'number', 'First value.'),
      DocParam('n', 'number', 'Second value.'),
    ],
    returns: 'true if m is less than n in unsigned comparison.',
    category: 'math',
    example: 'print(math.ult(1, 2)) --> true',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError('math.ult requires two integer arguments');
    }

    final m = rawLuaSlot(args[0]);
    final n = rawLuaSlot(args[1]);

    return primitiveValue(NumberUtils.unsignedLessThan(m, n));
  }
}
