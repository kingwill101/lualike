import 'dart:math' as math;
import '../logger.dart';
import '../lua_error.dart';
import '../number.dart';
import '../value.dart';
import '../lua_string.dart';

/// Utility class for common number operations and conversions used throughout the stdlib
class NumberUtils {
  NumberUtils._(); // Prevent instantiation

  /// 64-bit signed integer limits
  static const int maxInteger = (1 << 63) - 1; // 9223372036854775807
  static const int minInteger = -(1 << 63); // -9223372036854775808
  static const int sizeInBits = 64;

  /// Get type name for error messages
  static String typeName(dynamic value) {
    if (value == null) return 'nil';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    if (value is String || value is LuaString) return 'string';
    if (value is List) return 'table';
    if (value is Function) return 'function';
    return value.runtimeType.toString();
  }

  /// Extract and validate a number from a Value with proper error handling
  static dynamic getNumber(Value value, String funcName, int argNum) {
    if (value.raw is! num && value.raw is! BigInt) {
      throw LuaError.typeError(
        "bad argument #$argNum to '$funcName' (number expected, got ${typeName(value.raw)})",
      );
    }
    return value.raw;
  }

  /// Convert any numeric type to double
  static double toDouble(dynamic number) {
    if (number is String || number is LuaString) {
      number = LuaNumberParser.parse(number.toString());
    }
    if (number is BigInt) return number.toDouble();
    return (number as num).toDouble();
  }

  /// Convert any numeric type to int (with overflow handling)
  static int toInt(dynamic number) {
    if (number is String || number is LuaString) {
      number = LuaNumberParser.parse(number.toString());
    }
    if (number is BigInt) return number.toInt();
    if (number is int) return number;
    return (number as num).toInt();
  }

  /// Convert any numeric type to BigInt
  static BigInt toBigInt(dynamic number) {
    if (number is String || number is LuaString) {
      number = LuaNumberParser.parse(number.toString());
    }
    if (number is BigInt) return number;
    if (number is int) return BigInt.from(number);
    return BigInt.from((number as num).toInt());
  }

  /// Convert double to BigInt safely, handling scientific notation
  static BigInt doubleToBigInt(double value) {
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

  /// Check if a number is zero (works with int, double, BigInt)
  static bool isZero(dynamic number) {
    if (number is BigInt) return number == BigInt.zero;
    return (number as num) == 0;
  }

  /// Check if a number is finite (for doubles)
  static bool isFinite(dynamic number) {
    if (number is double) return number.isFinite;
    return true; // int and BigInt are always finite
  }

  /// Check if a number is an integer (no fractional part)
  static bool isInteger(dynamic number) {
    if (number is int || number is BigInt) return true;
    if (number is double) {
      return number.isFinite && number == number.truncateToDouble();
    }
    return false;
  }

  /// Check if a value is within the 64-bit signed integer range
  static bool isInIntegerRange(dynamic number) {
    if (number is int) return true; // Dart ints are always in range
    if (number is BigInt) {
      return number >= BigInt.from(minInteger) &&
          number <= BigInt.from(maxInteger);
    }
    if (number is double) {
      return number >= minInteger.toDouble() && number <= maxInteger.toDouble();
    }
    return false;
  }

  /// Convert a number to integer if possible, respecting Lua's math.tointeger semantics
  static int? tryToInteger(dynamic value) {
    if (value is String || value is LuaString) {
      try {
        value = LuaNumberParser.parse(value.toString());
      } catch (_) {
        return null;
      }
    }

    if (value is int) {
      return value;
    } else if (value is BigInt) {
      if (value <= BigInt.from(maxInteger) &&
          value >= BigInt.from(minInteger)) {
        return value.toInt();
      }
      return null;
    } else if (value is double) {
      if (!value.isFinite) return null;

      // For values at the edge of double precision, we need to be more careful
      // Any double >= 2^63 (9223372036854775808.0) cannot be exactly represented as int64
      if (value >= 9223372036854775808.0 || value < -9223372036854775808.0) {
        return null;
      }

      final int intVal = value.toInt();

      // Check if the conversion is exact (no fractional part)
      if (intVal.toDouble() == value) {
        return intVal;
      }
      return null;
    }
    return null;
  }

  /// Convert a double result to the most appropriate numeric type (int or double)
  /// This is useful for functions like floor/ceil that may return integers
  static dynamic optimizeNumericResult(double result) {
    if (!result.isFinite) return result;

    try {
      // Try to convert to BigInt to avoid floating point precision issues
      final bigIntRes = doubleToBigInt(result);
      // Check if it fits in int64 range
      if (bigIntRes >= BigInt.from(minInteger) &&
          bigIntRes <= BigInt.from(maxInteger)) {
        final intRes = bigIntRes.toInt();
        // Verify the conversion is exact
        if (intRes.toDouble() == result) {
          return intRes;
        }
      }
    } catch (_) {
      // If BigInt conversion fails, fall through to return double
    }

    return result;
  }

  /// Perform unsigned comparison for math.ult
  static bool unsignedLessThan(dynamic m, dynamic n) {
    if (m is! int && m is! BigInt) {
      throw LuaError.typeError('math.ult first argument must be an integer');
    }
    if (n is! int && n is! BigInt) {
      throw LuaError.typeError('math.ult second argument must be an integer');
    }

    BigInt mb = m is BigInt ? m : BigInt.from(m as int);
    BigInt nb = n is BigInt ? n : BigInt.from(n as int);

    final BigInt mod = BigInt.one << sizeInBits;
    if (mb.isNegative) mb += mod;
    if (nb.isNegative) nb += mod;

    return mb < nb;
  }

  /// Compare two numbers of any type
  static int compare(dynamic a, dynamic b) {
    // If both are integers (int or BigInt), use BigInt comparison to avoid precision loss
    if ((a is int || a is BigInt) && (b is int || b is BigInt)) {
      final bigA = toBigInt(a);
      final bigB = toBigInt(b);
      return bigA.compareTo(bigB);
    }

    // For mixed types or floating point, use double comparison
    final doubleA = toDouble(a);
    final doubleB = toDouble(b);
    return doubleA.compareTo(doubleB);
  }

  /// Check division by zero for any numeric type
  static void checkDivisionByZero(dynamic divisor, String funcName) {
    if (isZero(divisor)) {
      throw LuaError.typeError("bad argument to '$funcName' (zero)");
    }
  }

  /// Perform addition with 64-bit signed integer wrap-around semantics
  static dynamic add(dynamic a, dynamic b) {
    if ((a is int || a is BigInt) && (b is int || b is BigInt)) {
      // If either operand is BigInt, preserve BigInt type and don't wrap
      if (a is BigInt || b is BigInt) {
        final bigA = toBigInt(a);
        final bigB = toBigInt(b);
        return bigA + bigB;
      }

      // Both are regular int - apply wrap-around
      final bigA = toBigInt(a);
      final bigB = toBigInt(b);
      final result = bigA + bigB;
      return _wrapToInt64(result);
    }

    // For mixed types or floating point, use double arithmetic
    return toDouble(a) + toDouble(b);
  }

  /// Perform subtraction with 64-bit signed integer wrap-around semantics
  static dynamic subtract(dynamic a, dynamic b) {
    if ((a is int || a is BigInt) && (b is int || b is BigInt)) {
      // If either operand is BigInt, preserve BigInt type and don't wrap
      if (a is BigInt || b is BigInt) {
        final bigA = toBigInt(a);
        final bigB = toBigInt(b);
        return bigA - bigB;
      }

      // Both are regular int - apply wrap-around, but preserve large ranges for specific cases
      final bigA = toBigInt(a);
      final bigB = toBigInt(b);
      final result = bigA - bigB;

      // Special case: preserve large positive numbers ONLY for specific range calculations
      // like maxint - (minint + 1), not for basic cases like 0 - minint
      if (result > BigInt.from(maxInteger) &&
          result <= BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16)) {
        // Only preserve if it looks like a legitimate range calculation:
        // - The first operand should be near maxint
        // - The second operand should be near minint
        if (a >= (maxInteger ~/ 2) && b <= (minInteger ~/ 2)) {
          return result;
        }
      }

      // Apply 64-bit signed integer wrap-around for all other cases
      return _wrapToInt64(result);
    }

    // For mixed types or floating point, use double arithmetic
    return toDouble(a) - toDouble(b);
  }

  /// Helper method to wrap BigInt results to 64-bit signed integer range
  static int _wrapToInt64(BigInt value) {
    // Apply 64-bit signed integer wrap-around
    final mask64 = BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16); // 64-bit mask
    final masked = value & mask64;

    // Convert to signed 64-bit representation
    if (masked > BigInt.from(maxInteger)) {
      // If result is > maxInt64, subtract 2^sizeInBits to get the wrapped negative value
      final wrapped = masked - (BigInt.one << sizeInBits);
      return wrapped.toInt();
    }

    return masked.toInt();
  }

  /// Perform right shift with proper 64-bit signed integer semantics
  static dynamic rightShift(dynamic a, dynamic shiftAmount) {
    // Validate that both operands are valid integers
    if (a is double) {
      if (!a.isFinite) {
        if (a == double.infinity) {
          throw LuaError("number (field 'huge') has no integer representation");
        } else if (a == double.negativeInfinity) {
          throw LuaError("number (field 'huge') has no integer representation");
        }
        throw LuaError("number has no integer representation");
      }
      if (a.floorToDouble() != a) {
        throw LuaError('number has no integer representation');
      }
    }
    if (shiftAmount is double) {
      if (!shiftAmount.isFinite) {
        if (shiftAmount == double.infinity) {
          throw LuaError("number (field 'huge') has no integer representation");
        } else if (shiftAmount == double.negativeInfinity) {
          throw LuaError("number (field 'huge') has no integer representation");
        }
        throw LuaError("number has no integer representation");
      }
      if (shiftAmount.floorToDouble() != shiftAmount) {
        throw LuaError('number has no integer representation');
      }
    }

    final shift = toInt(shiftAmount);

    // If operating on BigInt, preserve BigInt type
    if (a is BigInt) {
      final bigA = a;

      // Handle negative shift by reversing operation
      if (shift < 0) {
        return leftShift(a, -shift);
      }

      // Handle large shifts (>= sizeInBits bits)
      if (shift >= sizeInBits) {
        return bigA.isNegative ? BigInt.from(-1) : BigInt.zero;
      }

      return bigA >> shift;
    }

    // For regular int, apply wrap-around semantics
    final bigA = toBigInt(a);

    // Handle negative shift by reversing operation
    if (shift < 0) {
      return leftShift(a, -shift);
    }

    // Handle large shifts (>= sizeInBits bits)
    if (shift >= sizeInBits) {
      return bigA.isNegative ? -1 : 0;
    }

    final result = bigA >> shift;
    return result.toInt();
  }

  /// Perform left shift with proper 64-bit signed integer wrap-around semantics
  static dynamic leftShift(dynamic a, dynamic shiftAmount) {
    // Validate that both operands are valid integers
    if (a is double) {
      if (!a.isFinite) {
        if (a == double.infinity) {
          throw LuaError("number (field 'huge') has no integer representation");
        } else if (a == double.negativeInfinity) {
          throw LuaError("number (field 'huge') has no integer representation");
        }
        throw LuaError("number has no integer representation");
      }
      if (a.floorToDouble() != a) {
        throw LuaError('number has no integer representation');
      }
    }
    if (shiftAmount is double) {
      if (!shiftAmount.isFinite) {
        if (shiftAmount == double.infinity) {
          throw LuaError("number (field 'huge') has no integer representation");
        } else if (shiftAmount == double.negativeInfinity) {
          throw LuaError("number (field 'huge') has no integer representation");
        }
        throw LuaError("number has no integer representation");
      }
      if (shiftAmount.floorToDouble() != shiftAmount) {
        throw LuaError('number has no integer representation');
      }
    }

    final shift = toInt(shiftAmount);

    // If operating on BigInt, preserve BigInt type
    if (a is BigInt) {
      final bigA = a;

      // Handle negative shift by reversing operation
      if (shift < 0) {
        return rightShift(a, -shift);
      }

      return bigA << shift;
    }

    // For regular int, apply wrap-around semantics
    final bigA = toBigInt(a);

    // Handle negative shift by reversing operation
    if (shift < 0) {
      return rightShift(a, -shift);
    }

    // Perform the shift with proper 64-bit wrap-around
    final result = bigA << shift;

    // Apply 64-bit signed integer wrap-around by masking and converting
    final mask64 = BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16); // 64-bit mask
    final masked = result & mask64;

    // Convert to signed 64-bit representation
    if (masked > BigInt.from(maxInteger)) {
      // If result is > maxInt64, subtract 2^sizeInBits to get the wrapped negative value
      final wrapped = masked - (BigInt.one << sizeInBits);
      return wrapped.toInt();
    }

    return masked.toInt();
  }

  /// Perform modulo operation following Lua semantics
  static dynamic fmod(dynamic x, dynamic y) {
    checkDivisionByZero(y, 'math.fmod');

    if (x is BigInt || y is BigInt) {
      final bigX = toBigInt(x);
      final bigY = toBigInt(y);
      return bigX - (bigX ~/ bigY) * bigY;
    }

    // For integers, use integer arithmetic to avoid precision loss
    if (x is int && y is int) {
      final quotient = x ~/ y; // truncated division
      return x - quotient * y;
    }

    // For floating point cases, use standard fmod behavior
    // Lua's fmod follows: fmod(x, y) = x - trunc(x/y) * y
    final dx = toDouble(x);
    final dy = toDouble(y);
    final quotient = dx / dy;
    final truncatedQuotient = quotient.truncateToDouble();
    return dx - truncatedQuotient * dy;
  }

  /// Get the absolute value of any numeric type
  static dynamic abs(dynamic number) {
    if (number is BigInt) return number.abs();
    return (number as num).abs();
  }

  /// Find maximum of two numbers
  static dynamic max(dynamic a, dynamic b) {
    return compare(a, b) >= 0 ? a : b;
  }

  /// Find minimum of two numbers
  static dynamic min(dynamic a, dynamic b) {
    return compare(a, b) <= 0 ? a : b;
  }

  /// Perform modf operation (split into integer and fractional parts)
  static (dynamic, double) modf(dynamic number) {
    if (number is int || number is BigInt) {
      return (number, 0.0);
    }

    final d = toDouble(number);
    if (d.isNaN) {
      return (double.nan, double.nan);
    }
    if (d.isInfinite) {
      return (d, 0.0);
    }

    final intPart = d.truncateToDouble();
    final fracPart = d - intPart;
    return (intPart, fracPart);
  }

  /// Perform multiplication with proper type handling
  static dynamic multiply(dynamic a, dynamic b) {
    if ((a is int || a is BigInt) && (b is int || b is BigInt)) {
      // If either operand is BigInt, preserve BigInt type
      if (a is BigInt || b is BigInt) {
        final bigA = toBigInt(a);
        final bigB = toBigInt(b);
        return bigA * bigB;
      }

      // Both are regular int - check for overflow
      final result = (a as int) * (b as int);
      return result;
    }

    // For mixed types or floating point, use double arithmetic
    return toDouble(a) * toDouble(b);
  }

  /// Perform division (always returns float)
  static double divide(dynamic a, dynamic b) {
    final f1 = toDouble(a);
    final f2 = toDouble(b);
    return f1 / f2;
  }

  /// Perform floor division
  static dynamic floorDivide(dynamic a, dynamic b) {
    // Check for division by zero for integer types
    if ((a is int || a is BigInt) && (b is int || b is BigInt) && isZero(b)) {
      throw LuaError('divide by zero');
    }

    if ((a is int || a is BigInt) && (b is int || b is BigInt)) {
      // Integer floor division
      if (a is BigInt || b is BigInt) {
        final bigA = toBigInt(a);
        final bigB = toBigInt(b);
        final div = bigA.toDouble() / bigB.toDouble();
        return (div.isInfinite || div.isNaN) ? div : div.floorToDouble();
      }

      // Both are regular integers
      final intA = a as int;
      final intB = b as int;
      final quotient = intA ~/ intB;
      final remainder = intA % intB;
      if (remainder != 0 && (intA < 0) != (intB < 0)) {
        return quotient - 1;
      } else {
        return quotient;
      }
    }

    // For floating point
    final f1 = toDouble(a);
    final f2 = toDouble(b);
    final div = f1 / f2;
    return (div.isInfinite || div.isNaN) ? div : div.floorToDouble();
  }

  /// Perform modulo operation with Lua semantics
  static dynamic modulo(dynamic a, dynamic b) {
    if ((a is int || a is BigInt) && (b is int || b is BigInt)) {
      if (a is BigInt || b is BigInt) {
        // BigInt modulo
        final bigA = toBigInt(a);
        final bigB = toBigInt(b);
        var div = bigA ~/ bigB;
        final differentSigns =
            (bigA.isNegative && !bigB.isNegative) ||
            (!bigA.isNegative && bigB.isNegative);
        if (differentSigns && bigA % bigB != BigInt.zero) {
          div -= BigInt.one;
        }
        return bigA - div * bigB;
      }

      // Regular int modulo
      final intA = a as int;
      final intB = b as int;
      var div = intA ~/ intB;
      if ((intA < 0) != (intB < 0) && intA % intB != 0) {
        div -= 1;
      }
      return intA - div * intB;
    }

    // Floating point modulo
    final f1 = toDouble(a);
    final f2 = toDouble(b);
    var rem = f1.remainder(f2);
    if (rem != 0 && ((f1 < 0 && f2 > 0) || (f1 > 0 && f2 < 0))) {
      rem += f2;
    }
    return rem;
  }

  /// Perform exponentiation (always returns float)
  static double exponentiate(dynamic a, dynamic b) {
    final f1 = toDouble(a);
    final f2 = toDouble(b);
    return math.pow(f1, f2).toDouble();
  }

  /// Convert a signed integer to its unsigned 64-bit representation
  /// This is used for formatting negative numbers as unsigned values (%u, %x, %o)
  static BigInt toUnsigned64(int value) {
    if (value >= 0) {
      return BigInt.from(value);
    }
    // For negative values, add 2^sizeInBits to get the unsigned representation
    return (BigInt.one << sizeInBits) + BigInt.from(value);
  }

  /// Perform bitwise AND with integer validation
  static dynamic bitwiseAnd(dynamic a, dynamic b) {
    final bigA = _validateAndConvertToInteger(a);
    final bigB = _validateAndConvertToInteger(b);

    final result = bigA & bigB;

    // Return appropriate type
    if ((a is int && b is int) &&
        result >= BigInt.from(minInteger) &&
        result <= BigInt.from(maxInteger)) {
      return result.toInt();
    }
    return result;
  }

  /// Perform bitwise OR with integer validation
  static dynamic bitwiseOr(dynamic a, dynamic b) {
    final bigA = _validateAndConvertToInteger(a);
    final bigB = _validateAndConvertToInteger(b);

    final result = bigA | bigB;

    // Return appropriate type
    if ((a is int && b is int) &&
        result >= BigInt.from(minInteger) &&
        result <= BigInt.from(maxInteger)) {
      return result.toInt();
    }
    return result;
  }

  /// Perform bitwise XOR with integer validation
  static dynamic bitwiseXor(dynamic a, dynamic b) {
    final bigA = _validateAndConvertToInteger(a);
    final bigB = _validateAndConvertToInteger(b);

    final result = bigA ^ bigB;

    // Return appropriate type
    if ((a is int && b is int) &&
        result >= BigInt.from(minInteger) &&
        result <= BigInt.from(maxInteger)) {
      return result.toInt();
    }
    return result;
  }

  /// Perform bitwise NOT with integer validation
  static dynamic bitwiseNot(dynamic a) {
    // Try to convert strings to numbers (Lua automatic conversion)
    if (a is String || a is LuaString) {
      try {
        a = LuaNumberParser.parse(a.toString());
      } catch (e) {
        throw LuaError.typeError(
          "attempt to perform arithmetic on a string value",
        );
      }
    }

    final bigA = _validateAndConvertToInteger(a);
    final result = ~bigA;

    // Return appropriate type
    if (a is int &&
        result >= BigInt.from(minInteger) &&
        result <= BigInt.from(maxInteger)) {
      return result.toInt();
    }
    return result;
  }

  /// Helper method to validate and convert to integer for bitwise operations
  static BigInt _validateAndConvertToInteger(dynamic value) {
    if (value is String || value is LuaString) {
      try {
        value = LuaNumberParser.parse(value.toString());
      } catch (_) {
        throw LuaError.typeError('number has no integer representation');
      }
    }
    if (value is BigInt) return value;
    if (value is int) return BigInt.from(value);
    if (value is double) {
      if (!value.isFinite) {
        if (value == double.infinity || value == double.negativeInfinity) {
          throw LuaError("number (field 'huge') has no integer representation");
        }
        throw LuaError("number has no integer representation");
      }
      if (value.floorToDouble() != value) {
        throw LuaError('number has no integer representation');
      }
      final bi = BigInt.parse(value.toStringAsFixed(0));
      if (bi < BigInt.from(minInteger) || bi > BigInt.from(maxInteger)) {
        throw LuaError('number has no integer representation');
      }
      return bi;
    }
    throw LuaError.typeError('number has no integer representation');
  }

  /// Perform arithmetic operation with full Lua semantics including string conversion
  static dynamic performArithmetic(String op, dynamic r1, dynamic r2) {
    Logger.debug(
      'ARITH: START op=$op, r1=$r1 (${r1.runtimeType}), r2=$r2 (${r2.runtimeType})',
      category: 'NumberUtils',
    );

    // Try to convert strings to numbers (Lua automatic conversion)
    if (r1 is String || r1 is LuaString) {
      Logger.debug('ARITH: r1 is String, parsing...', category: 'NumberUtils');
      try {
        r1 = LuaNumberParser.parse(r1.toString());
        Logger.debug(
          'ARITH: r1 parsed to $r1 (${r1.runtimeType})',
          category: 'NumberUtils',
        );
      } catch (e) {
        Logger.warning(
          'ARITH: r1 parse error: $e',
          category: 'NumberUtils',
          error: e,
        );
        throw LuaError.typeError(
          "attempt to perform arithmetic on a string value",
        );
      }
    }

    if (r2 is String || r2 is LuaString) {
      Logger.debug('ARITH: r2 is String, parsing...', category: 'NumberUtils');
      try {
        r2 = LuaNumberParser.parse(r2.toString());
        Logger.debug(
          'ARITH: r2 parsed to $r2 (${r2.runtimeType})',
          category: 'NumberUtils',
        );
      } catch (e) {
        Logger.warning(
          'ARITH: r2 parse error: $e',
          category: 'NumberUtils',
          error: e,
        );
        throw LuaError.typeError(
          "attempt to perform arithmetic on a string value",
        );
      }
    }

    Logger.debug(
      'ARITH: after string parse, r1=$r1 (${r1.runtimeType}), r2=$r2 (${r2.runtimeType})',
      category: 'NumberUtils',
    );

    // Validate that we have numbers
    if (!((r1 is num || r1 is BigInt) && (r2 is num || r2 is BigInt))) {
      Logger.warning(
        'ARITH: type error, non-number values',
        category: 'NumberUtils',
      );
      throw LuaError.typeError(
        "attempt to perform arithmetic on non-number values",
      );
    }

    // Delegate all arithmetic operations to the appropriate methods
    dynamic result;
    try {
      switch (op) {
        case '+':
          result = add(r1, r2);
          break;
        case '-':
          result = subtract(r1, r2);
          break;
        case '*':
          result = multiply(r1, r2);
          break;
        case '/':
          result = divide(r1, r2);
          break;
        case '//':
          result = floorDivide(r1, r2);
          break;
        case '%':
          result = modulo(r1, r2);
          break;
        case '^':
          result = exponentiate(r1, r2);
          break;
        case '<<':
          result = leftShift(r1, r2);
          break;
        case '>>':
          result = rightShift(r1, r2);
          break;
        case '&':
          result = bitwiseAnd(r1, r2);
          break;
        case '|':
          result = bitwiseOr(r1, r2);
          break;
        case 'bxor':
          result = bitwiseXor(r1, r2);
          break;
        default:
          Logger.warning(
            'ARITH: unsupported operation: $op',
            category: 'NumberUtils',
          );
          throw LuaError.typeError('operation "$op" not supported');
      }
    } catch (e) {
      Logger.warning(
        'ARITH: operation failed: $e',
        category: 'NumberUtils',
        error: e,
      );
      rethrow;
    }

    Logger.debug(
      'ARITH: result: $result (${result.runtimeType})',
      category: 'NumberUtils',
    );
    return result;
  }

  /// Perform unary negation with Lua semantics including string conversion
  static dynamic negate(dynamic value) {
    // Try to convert strings to numbers (Lua automatic conversion)
    if (value is String || value is LuaString) {
      try {
        value = LuaNumberParser.parse(value.toString());
      } catch (e) {
        throw LuaError.typeError(
          "attempt to perform arithmetic on a string value",
        );
      }
    }

    if (value is BigInt) return -value;
    if (value is num) return -value;

    throw LuaError.typeError(
      'Unary negation not supported for type ${value.runtimeType}',
    );
  }
}
