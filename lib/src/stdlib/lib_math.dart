import 'dart:math' as math;
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/lualike.dart';

// Base class for math functions to handle common number validation
abstract class _MathFunction implements BuiltinFunction {
  dynamic _getNumber(Value value, String funcName) {
    if (value.raw is! num && value.raw is! BigInt) {
      throw LuaError.typeError("$funcName requires a number argument");
    }
    return value.raw;
  }
}

class _MathAbs extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.abs requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "math.abs");
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
      throw LuaError.typeError("math.acos requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "math.acos");
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
      throw LuaError.typeError("math.asin requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "math.asin");
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
      throw LuaError.typeError("math.atan requires at least one argument");
    }

    final y = _getNumber(args[0] as Value, "math.atan");
    final double yDouble = y is BigInt ? y.toDouble() : (y as num).toDouble();

    if (args.length > 1) {
      final x = _getNumber(args[1] as Value, "math.atan");
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
      throw LuaError.typeError("math.ceil requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "math.ceil");
    if (number is BigInt) {
      return Value(number);
    }
    if (number is int) {
      return Value(number);
    }
    final num n = number as num;
    if (n is double) {
      if (!n.isFinite) return Value(n);
      final intRes = n.ceil();
      final doubleRes = n.ceilToDouble();
      if (doubleRes == intRes.toDouble() &&
          intRes <= MathLib.maxInteger &&
          intRes >= MathLib.minInteger) {
        return Value(intRes);
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
      throw LuaError.typeError("math.cos requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "math.cos");
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
      throw LuaError.typeError("math.deg requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "math.deg");
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
      throw LuaError.typeError("math.exp requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "math.exp");
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
      throw LuaError.typeError("math.floor requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "math.floor");
    if (number is BigInt) {
      return Value(number);
    }
    if (number is int) {
      return Value(number);
    }
    final num n = number as num;
    if (n is double) {
      if (!n.isFinite) return Value(n);
      final intRes = n.floor();
      final doubleRes = n.floorToDouble();
      if (doubleRes == intRes.toDouble() &&
          intRes <= MathLib.maxInteger &&
          intRes >= MathLib.minInteger) {
        return Value(intRes);
      }
      return Value(doubleRes);
    }
    return Value(n);
  }
}

class _MathFmod extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("math.fmod requires two number arguments");
    }

    final x = _getNumber(args[0] as Value, "math.fmod");
    final y = _getNumber(args[1] as Value, "math.fmod");

    if (x is BigInt || y is BigInt) {
      final bigX = x is BigInt ? x : BigInt.from(x as num);
      final bigY = y is BigInt ? y : BigInt.from(y as num);
      return Value(bigX % bigY);
    }

    return Value((x as num) % (y as num));
  }
}

class _MathLog extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.log requires at least one argument");
    }

    final x = _getNumber(args[0] as Value, "math.log");
    final double xDouble = x is BigInt ? x.toDouble() : (x as num).toDouble();

    if (args.length > 1) {
      final base = _getNumber(args[1] as Value, "math.log");
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
      throw LuaError.typeError("math.max requires at least one argument");
    }

    dynamic max = _getNumber(args[0] as Value, "math.max");

    for (int i = 1; i < args.length; i++) {
      final num = _getNumber(args[i] as Value, "math.max");
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
      throw LuaError.typeError("math.min requires at least one argument");
    }

    dynamic min = _getNumber(args[0] as Value, "math.min");

    for (int i = 1; i < args.length; i++) {
      final num = _getNumber(args[i] as Value, "math.min");
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

    final number = _getNumber(args[0] as Value, "math.modf");
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
    final number = _getNumber(args[0] as Value, "math.rad");
    final double val = number is BigInt
        ? number.toDouble()
        : (number as num).toDouble();
    return Value(val * math.pi / 180);
  }
}

class _MathRandom extends _MathFunction {
  final math.Random _random = math.Random();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      // No arguments: return a random float between 0 and 1
      return Value(_random.nextDouble());
    } else if (args.length == 1) {
      // One argument: return a random integer between 1 and n
      final n = _getNumber(args[0] as Value, "math.random");
      final intN = n is BigInt ? n.toInt() : (n as num).toInt();
      if (intN < 1) {
        throw LuaError.typeError("math.random: range is empty");
      }
      return Value(_random.nextInt(intN) + 1);
    } else if (args.length == 2) {
      // Two arguments: return a random integer between m and n
      final m = _getNumber(args[0] as Value, "math.random");
      final n = _getNumber(args[1] as Value, "math.random");
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
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.randomseed requires a number argument");
    }

    final number = _getNumber(args[0] as Value, "math.randomseed");
    final seed = number is BigInt ? number.toInt() : (number as num).toInt();
    math.Random(
      seed,
    ); // Create a new Random with the seed (affects future calls)

    return Value(null);
  }
}

class _MathSin extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sin requires a number argument");
    }
    final number = _getNumber(args[0] as Value, "math.sin");
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
    final number = _getNumber(args[0] as Value, "math.sqrt");
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
    final number = _getNumber(args[0] as Value, "math.tan");
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
    "random": _MathRandom(),
    "randomseed": _MathRandomseed(),
    "sin": _MathSin(),
    "sqrt": _MathSqrt(),
    "tan": _MathTan(),
    "tointeger": _MathTointeger(),
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
