import 'dart:math' as math;
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/lualike.dart';

// Base class for math functions to handle common number validation
abstract class _MathFunction implements BuiltinFunction {
  num _getNumber(Value value, String funcName) {
    if (value.raw is! num) {
      throw LuaError.typeError("$funcName requires a number argument");
    }
    return value.raw as num;
  }
}

class _MathAbs extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.abs requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.abs");
    return Value(num.abs());
  }
}

class _MathAcos extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.acos requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.acos");
    return Value(math.acos(num));
  }
}

class _MathAsin extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.asin requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.asin");
    return Value(math.asin(num));
  }
}

class _MathAtan extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.atan requires at least one argument");
    }

    final y = _getNumber(args[0] as Value, "math.atan");

    if (args.length > 1) {
      final x = _getNumber(args[1] as Value, "math.atan");
      return Value(math.atan2(y, x));
    }

    return Value(math.atan(y));
  }
}

class _MathCeil extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.ceil requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.ceil");
    return Value(num.ceil());
  }
}

class _MathCos extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.cos requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.cos");
    return Value(math.cos(num));
  }
}

class _MathDeg extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.deg requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.deg");
    return Value(num * 180 / math.pi);
  }
}

class _MathExp extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.exp requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.exp");
    return Value(math.exp(num));
  }
}

class _MathFloor extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.floor requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.floor");
    return Value(num.floor());
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

    return Value(x % y);
  }
}

class _MathLog extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.log requires at least one argument");
    }

    final x = _getNumber(args[0] as Value, "math.log");

    if (args.length > 1) {
      final base = _getNumber(args[1] as Value, "math.log");
      return Value(math.log(x) / math.log(base));
    }

    return Value(math.log(x));
  }
}

class _MathMax extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.max requires at least one argument");
    }

    num max = _getNumber(args[0] as Value, "math.max");

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

    num min = _getNumber(args[0] as Value, "math.min");

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

    final num = _getNumber(args[0] as Value, "math.modf");
    final intPart = num.truncate();
    final fracPart = num - intPart;

    return Value.multi([Value(intPart), Value(fracPart)]);
  }
}

class _MathRad extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.rad requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.rad");
    return Value(num * math.pi / 180);
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
      final n = _getNumber(args[0] as Value, "math.random").toInt();
      if (n < 1) {
        throw LuaError.typeError("math.random takes 0-2 arguments");
      }
      return Value(_random.nextInt(n) + 1);
    } else if (args.length == 2) {
      // Two arguments: return a random integer between m and n
      final m = _getNumber(args[0] as Value, "math.random").toInt();
      final n = _getNumber(args[1] as Value, "math.random").toInt();
      if (m > n) {
        throw LuaError.typeError("math.random takes 0-2 arguments");
      }
      return Value(m + _random.nextInt(n - m + 1));
    } else {
      throw LuaError.typeError("math.random takes 0-2 arguments");
    }
  }
}

class _MathRandomseed extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.randomseed requires a number argument");
    }

    final seed = _getNumber(args[0] as Value, "math.randomseed").toInt();
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
    final num = _getNumber(args[0] as Value, "math.sin");
    return Value(math.sin(num));
  }
}

class _MathSqrt extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.sqrt requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.sqrt");
    return Value(math.sqrt(num));
  }
}

class _MathTan extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.tan requires a number argument");
    }
    final num = _getNumber(args[0] as Value, "math.tan");
    return Value(math.tan(num));
  }
}

class _MathType extends _MathFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("math.type requires one argument");
    }

    final value = args[0] as Value;
    if (value.raw is int) {
      return Value("integer");
    } else if (value.raw is double) {
      return Value("float");
    } else {
      return Value(null);
    }
  }
}

class MathLib {
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
    "type": _MathType(),
    "huge": Value(double.infinity),
    "maxinteger": Value(double.maxFinite.toInt()),
    "mininteger": Value(-double.maxFinite.toInt()),
  };
}

void defineMathLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  env.define("math", MathLib.functions);
}
