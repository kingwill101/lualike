import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/stdlib/format_parser.dart';
import 'package:lualike/src/lua_pattern_compiler.dart' as lpc;

/// String interning cache for short strings (Lua-like behavior)
/// In Lua, short strings are typically internalized while long strings are not
class StringInterning {
  static const int shortStringThreshold = 40; // Lua 5.4 uses 40 characters
  static final Map<String, LuaString> _internCache = <String, LuaString>{};

  /// Creates or retrieves an interned LuaString
  static LuaString intern(String content) {
    // Only intern short strings
    if (content.length <= shortStringThreshold) {
      return _internCache.putIfAbsent(
        content,
        () => LuaString.fromDartString(content),
      );
    } else {
      // Long strings are not interned - always create new instances
      return LuaString.fromDartString(content);
    }
  }

  /// Creates a Value with proper string interning
  static Value createStringValue(String content) {
    return Value(intern(content));
  }
}

class StringLib {
  static final ValueClass stringClass = ValueClass.create({
    "__len": (List<Object?> args) {
      final str = args[0] as Value;
      return Value(str.raw.toString().length);
    },
    "__concat": (List<Object?> args) {
      final a = args[0] as Value;
      final b = args[1] as Value;
      return Value(a.raw.toString() + b.raw.toString());
    },
  });

  static final Map<String, dynamic> functions = {
    "byte": Value(_StringByte()),
    "char": Value(_StringChar()),
    "dump": Value(_StringDump()),
    "find": Value(_StringFind()),
    "format": Value(_StringFormat()),
    "gmatch": Value(_StringGmatch()),
    "gsub": Value(_StringGsub()),
    "len": Value(_StringLen()),
    "lower": Value(_StringLower()),
    "match": Value(_StringMatch()),
    "pack": Value(_StringPack()),
    "packsize": Value(_StringPackSize()),
    "rep": Value(_StringRep()),
    "reverse": Value(_StringReverse()),
    "sub": Value(_StringSub()),
    "unpack": Value(_StringUnpack()),
    "upper": Value(_StringUpper()),
  };
}

class _StringByte implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.byte requires a string argument");
    }

    final value = args[0] as Value;
    final bytes = value.raw is LuaString
        ? (value.raw as LuaString).bytes
        : LuaString.fromDartString(value.raw.toString()).bytes;

    var start = args.length > 1 ? NumberUtils.toInt((args[1] as Value).raw) : 1;
    var end = args.length > 2
        ? NumberUtils.toInt((args[2] as Value).raw)
        : start;

    start = start < 0 ? bytes.length + start + 1 : start;
    end = end < 0 ? bytes.length + end + 1 : end;

    if (start < 1) start = 1;
    if (end > bytes.length) end = bytes.length;

    final result = <Value>[];
    for (var i = start; i <= end; i++) {
      final byteValue = bytes[i - 1];
      result.add(Value(byteValue));
    }

    if (result.isEmpty) {
      return Value(null);
    } else if (result.length == 1) {
      return result[0];
    } else {
      return Value.multi(result);
    }
  }
}

class _StringChar implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    final bytes = <int>[];
    for (var arg in args.where(
      (arg) => arg is Value && (arg.raw is num || arg.raw is BigInt),
    )) {
      final code = NumberUtils.toInt((arg as Value).raw);
      if (code < 0 || code > 255) {
        throw LuaError('out of range $code');
      }
      bytes.add(code);
    }
    // Instead of creating a Dart String and potentially losing byte integrity,
    // create a LuaString directly from the bytes.
    final luaString = LuaString.fromBytes(Uint8List.fromList(bytes));
    return Value(luaString);
  }
}

class _StringDump implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.dump requires a function argument");
    }

    final func = args[0] as Value;
    if (func.raw is! Function) {
      throw LuaError.typeError("string.dump requires a function argument");
    }

    // In a real implementation, this would serialize the function
    // For now, we'll just return a placeholder
    return Value("function bytecode");
  }
}

class _StringFind implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.find requires a string and a pattern");
    }

    final str = (args[0] as Value).raw.toString();
    final pattern = (args[1] as Value).raw.toString();
    var init = args.length > 2 ? NumberUtils.toInt((args[2] as Value).raw) : 1;
    var start = init < 0 ? str.length + init + 1 : init;
    if (start < 1) start = 1;
    start -= 1;
    bool plain = false;
    if (args.length > 3) {
      final rawPlain = (args[3] as Value).raw;
      plain = rawPlain != false && rawPlain != null;
    }

    // Handle bounds
    if (start > str.length) return Value(null);

    if (pattern.isEmpty) {
      return [Value(start + 1), Value(start)];
    }

    if (plain) {
      final index = str.indexOf(pattern, start);
      if (index == -1) return Value(null);
      return [Value(index + 1), Value(index + pattern.length)];
    }

    try {
      final lp = lpc.LuaPattern.compile(pattern);
      final match = lp.firstMatch(str, start);
      if (match == null) return Value(null);

      final startPos = match.start + 1;
      final endPos = match.end;
      final results = [Value(startPos), Value(endPos)];
      for (final cap in match.captures) {
        results.add(cap == null ? Value(null) : Value(cap));
      }
      if (match.captures.isNotEmpty) {
        return Value.multi(results);
      }
      return results;
    } catch (e) {
      throw Exception('malformed pattern: $e');
    }
  }
}

String _applyPadding(String text, _FormatContext ctx) {
  if (ctx.widthValue > 0) {
    if (ctx.leftAlign) {
      return text.padRight(ctx.widthValue, ' ');
    } else if (ctx.zeroPad) {
      final signChar =
          (text.startsWith('+') || text.startsWith('-') || text.startsWith(' '))
          ? text[0]
          : '';
      final numPart = signChar.isNotEmpty ? text.substring(1) : text;
      return signChar + numPart.padLeft(ctx.widthValue - signChar.length, '0');
    } else {
      return text.padLeft(ctx.widthValue, ' ');
    }
  }
  return text;
}

Future<Object> _formatString(_FormatContext ctx) async {
  final value = ctx.value;

  // Check for null bytes in string when width is specified (Lua requirement)
  if (ctx.widthValue > 0) {
    final rawValue = value is Value ? value.raw : value;
    if (rawValue is String && rawValue.contains('\u0000')) {
      throw LuaError(
        "bad argument #${ctx.valueIndex} to 'format' (string contains zeros)",
      );
    } else if (rawValue is LuaString && rawValue.bytes.contains(0)) {
      throw LuaError(
        "bad argument #${ctx.valueIndex} to 'format' (string contains zeros)",
      );
    }
  }

  // If it's a Value object, check for __tostring metamethod first
  if (value is Value) {
    final tostring = value.getMetamethod("__tostring");
    if (tostring != null) {
      try {
        final result = value.callMetamethod('__tostring', [value]);
        // Await the result if it's a Future
        final awaitedResult = result is Future ? await result : result;
        final str = awaitedResult is Value
            ? awaitedResult.raw.toString()
            : awaitedResult.toString();
        if (ctx.precision.isNotEmpty) {
          final precValue = ctx.precisionValue;
          if (precValue < str.length) {
            return _applyPadding(str.substring(0, precValue), ctx);
          }
        }
        return _applyPadding(str, ctx);
      } catch (e) {
        // If metamethod call fails, fall back to default behavior
      }
    }

    // Check for __name metamethod as fallback for tables
    if (value.raw is Map) {
      final name = value.getMetamethod("__name");
      if (name != null &&
          name is Value &&
          (name.raw is String || name.raw is LuaString)) {
        final str = '${name.raw}: ${value.raw.hashCode.toRadixString(16)}';
        if (ctx.precision.isNotEmpty) {
          final precValue = ctx.precisionValue;
          if (precValue < str.length) {
            return _applyPadding(str.substring(0, precValue), ctx);
          }
        }
        return _applyPadding(str, ctx);
      }
    }
  }

  final rawValue = value is Value ? value.raw : value;

  if (rawValue is LuaString) {
    // For %s format, preserve the original bytes but handle precision and padding
    var bytes = rawValue.bytes;
    if (ctx.precision.isNotEmpty) {
      final precValue = ctx.precisionValue;
      if (precValue < bytes.length) {
        bytes = Uint8List.fromList(bytes.sublist(0, precValue));
      }
    }

    // Apply padding at byte level to preserve Latin-1 characters
    final width = ctx.widthValue;
    if (width > 0 && bytes.length < width) {
      final padding = List.filled(width - bytes.length, 32); // space
      if (ctx.leftAlign) {
        bytes = Uint8List.fromList([...bytes, ...padding]);
      } else {
        bytes = Uint8List.fromList([...padding, ...bytes]);
      }
    }

    return LuaString(bytes);
  }

  String str;
  if (rawValue == null) {
    str = 'nil';
  } else if (rawValue is bool) {
    str = rawValue.toString();
  } else if (rawValue is Map) {
    str = 'table: ${rawValue.hashCode.toRadixString(16)}';
  } else if (rawValue is Function) {
    str = 'function: ${rawValue.hashCode.toRadixString(16)}';
  } else {
    str = rawValue.toString();
  }

  if (ctx.precision.isNotEmpty) {
    final precValue = ctx.precisionValue;
    if (precValue < str.length) {
      str = str.substring(0, precValue);
    }
  }

  return _applyPadding(str, ctx);
}

LuaString _formatCharacter(_FormatContext ctx) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;
  if (rawValue is! num && rawValue is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${NumberUtils.typeName(rawValue)})",
    );
  }

  final charCode = NumberUtils.toInt(rawValue);

  // For %c format, we need to return the raw byte, not a UTF-8 encoded character
  // Create a LuaString with the single byte
  final luaString = LuaString.fromBytes([charCode]);

  // For padding, we need to work at the byte level
  if (ctx.widthValue > 0 && luaString.length < ctx.widthValue) {
    final padding = List.filled(ctx.widthValue - luaString.length, 32); // space
    if (ctx.leftAlign) {
      return LuaString.fromBytes([...luaString.bytes, ...padding]);
    } else {
      return LuaString.fromBytes([...padding, ...luaString.bytes]);
    }
  }

  return luaString;
}

String _formatPointer(_FormatContext ctx) {
  String ptr;
  final v = ctx.value;

  // Extract raw value if it's a Value object
  final rawValue = v is Value ? v.raw : v;

  if (rawValue == null || rawValue is num || rawValue is bool) {
    ptr = '(null)';
  } else if (rawValue is LuaString) {
    // For LuaString objects, use the identity of the LuaString itself
    // This enables proper pointer equality for interned strings
    ptr = identityHashCode(rawValue).toRadixString(16);
  } else {
    // For other objects, use identityHashCode of the Value object itself for unique identification
    ptr = identityHashCode(v).toRadixString(16);
  }

  ptr = _applyPadding(ptr, ctx);
  return ptr;
}

// Helper function to format large numbers with high precision using NumberUtils approach
String _formatLargeNumber(double value, int precision) {
  // For very large numbers in scientific notation, we need to manually expand them
  final str = value.toString();

  if (str.contains('e+') || str.contains('E+')) {
    // Parse scientific notation manually: e.g., "1e+308" or "-1.23e+10"
    final parts = str.toLowerCase().split('e+');
    if (parts.length == 2) {
      final mantissa = double.parse(parts[0]);
      final exponent = int.parse(parts[1]);

      // For positive exponents, we need to create a number with 'exponent' digits
      // e.g., 1e+308 should become 1 followed by 308 zeros
      final mantissaStr = mantissa.abs().toString();
      final dotIndex = mantissaStr.indexOf('.');

      if (dotIndex == -1) {
        // Integer mantissa (e.g., "1e+308")
        final integerPart = mantissaStr + ('0' * exponent);
        final fractionalPart = '0' * precision;
        return '${mantissa.isNegative ? '-' : ''}$integerPart.$fractionalPart';
      } else {
        // Decimal mantissa (e.g., "1.23e+10")
        final beforeDot = mantissaStr.substring(0, dotIndex);
        final afterDot = mantissaStr.substring(dotIndex + 1);

        if (exponent >= afterDot.length) {
          // Move decimal point to the right, pad with zeros
          final integerPart =
              beforeDot + afterDot + ('0' * (exponent - afterDot.length));
          final fractionalPart = '0' * precision;
          return '${mantissa.isNegative ? '-' : ''}$integerPart.$fractionalPart';
        } else {
          // Move decimal point within the existing digits
          final newIntegerPart = beforeDot + afterDot.substring(0, exponent);
          final newFractionalPart = afterDot
              .substring(exponent)
              .padRight(precision, '0');
          return '${mantissa.isNegative ? '-' : ''}$newIntegerPart.${newFractionalPart.substring(0, precision)}';
        }
      }
    }
  }

  if (str.contains('e-') || str.contains('E-')) {
    // Negative exponent - very small number
    final parts = str.toLowerCase().split('e-');
    if (parts.length == 2) {
      final mantissa = double.parse(parts[0]);
      final exponent = int.parse(parts[1]);

      // For negative exponents, we need leading zeros
      final mantissaStr = mantissa.abs().toString().replaceAll('.', '');
      final zeros = '0' * (exponent - 1);
      final result = '0.$zeros$mantissaStr';
      final dotIndex = result.indexOf('.');
      final paddedResult = result.padRight(dotIndex + 1 + precision, '0');
      return mantissa.isNegative ? '-$paddedResult' : paddedResult;
    }
  }

  // Not in scientific notation or couldn't parse, handle normally
  if (value.abs() < 1e15) {
    final intPart = value.truncate();
    final fracPart = (value - intPart).abs();
    final fracStr = fracPart.toStringAsFixed(20);
    final fracDigits = fracStr.substring(2);
    final paddedFracDigits = fracDigits.padRight(precision, '0');

    if (value.isNegative && intPart == 0) {
      return '-$intPart.${paddedFracDigits.substring(0, precision)}';
    } else {
      return '$intPart.${paddedFracDigits.substring(0, precision)}';
    }
  } else {
    // Very large number but not in recognizable scientific notation
    // Fall back to padding approach
    return value.toStringAsFixed(20).padRight(precision + 10, '0');
  }
}

String _formatFloat(_FormatContext ctx, bool uppercase) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;
  if (rawValue is! num && rawValue is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${NumberUtils.typeName(rawValue)})",
    );
  }

  final doubleValue = NumberUtils.toDouble(rawValue);

  // Handle special values
  if (doubleValue.isNaN) return uppercase ? 'NAN' : 'nan';
  if (doubleValue.isInfinite) {
    final sign = doubleValue.isNegative ? '-' : (ctx.showSign ? '+' : '');
    return uppercase ? '${sign}INF' : '${sign}inf';
  }

  String result;
  final precision = ctx.precisionValue;

  // Dart's toStringAsFixed only supports 0-20 fraction digits
  if (precision <= 20) {
    result = doubleValue.toStringAsFixed(precision);
  } else {
    // For larger precision values, use NumberUtils approach
    result = _formatLargeNumber(doubleValue, precision);
  }

  // Handle alternative flag: force decimal point even with precision 0
  if (ctx.alternative && precision == 0 && !result.contains('.')) {
    result += '.';
  }

  if (ctx.showSign && !doubleValue.isNegative) {
    result = '+$result';
  } else if (ctx.spacePrefix && !doubleValue.isNegative) {
    result = ' $result';
  }

  return _applyPadding(result, ctx);
}

String _formatScientific(_FormatContext ctx, bool uppercase) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;
  if (rawValue is! num && rawValue is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${NumberUtils.typeName(rawValue)})",
    );
  }

  final doubleValue = NumberUtils.toDouble(rawValue);

  // Handle special values
  if (doubleValue.isNaN) return uppercase ? 'NAN' : 'nan';
  if (doubleValue.isInfinite) {
    final sign = doubleValue.isNegative ? '-' : (ctx.showSign ? '+' : '');
    return uppercase ? '${sign}INF' : '${sign}inf';
  }

  String result;
  if (doubleValue == 0.0) {
    result =
        '0${ctx.precisionValue > 0 ? '.${'0' * ctx.precisionValue}' : ''}${uppercase ? 'E+00' : 'e+00'}';
  } else {
    final absValue = doubleValue.abs();
    final exponent = (math.log(absValue) / math.ln10).floor();
    final mantissa = absValue / math.pow(10, exponent);
    String mantissaStr = mantissa.toStringAsFixed(ctx.precisionValue);
    String expStr = exponent.abs().toString().padLeft(2, '0');

    result =
        mantissaStr +
        (uppercase ? 'E' : 'e') +
        (exponent >= 0 ? '+' : '-') +
        expStr;
  }

  if (ctx.showSign && !doubleValue.isNegative) {
    result = '+$result';
  } else if (ctx.spacePrefix && !doubleValue.isNegative) {
    result = ' $result';
  }

  return _applyPadding(result, ctx);
}

String _formatHexFloat(_FormatContext ctx, bool uppercase) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;
  if (rawValue is! num && rawValue is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${NumberUtils.typeName(rawValue)})",
    );
  }

  double v = NumberUtils.toDouble(rawValue);

  if (v.isNaN) return uppercase ? 'NAN' : 'nan';
  if (v.isInfinite) {
    final sign = v.isNegative ? '-' : (ctx.showSign ? '+' : '');
    return uppercase ? '${sign}INF' : '${sign}inf';
  }

  String sign = '';
  if (v.isNegative) {
    sign = '-';
    v = NumberUtils.abs(v);
  } else if (ctx.showSign) {
    sign = '+';
  } else if (ctx.spacePrefix) {
    sign = ' ';
  }

  int exponent = 0;
  if (v == 0.0) {
    exponent = 0;
  } else {
    // Use math library functions from NumberUtils context
    // Calculate exponent: floor(log2(v))
    final logValue = math.log(v) / math.ln2;
    exponent = logValue.floor();
    v = v / NumberUtils.exponentiate(2.0, exponent);
  }

  final hex = StringBuffer();
  hex.write(uppercase ? '0X' : '0x');

  // Get the integer part
  final integerPart = v.floor();
  hex.write(integerPart.toInt().toRadixString(16));

  // Get fractional part
  double fractionalPart = v - integerPart;

  // For hex float format, use explicit precision if provided, otherwise use 13 for round-trip accuracy
  // This differs from other formats where the default precision is 6
  final precision = ctx.precision.isNotEmpty ? ctx.precisionValue : 13;

  if (fractionalPart > 0 || precision > 0) {
    hex.write('.');

    // Convert fractional part to hex with sufficient precision
    for (int i = 0; i < precision; i++) {
      fractionalPart *= 16;
      final digit = fractionalPart.floor().toInt();
      hex.write(digit.toRadixString(16));
      fractionalPart -= digit;
      if (fractionalPart == 0 && ctx.precision.isEmpty) break;
    }
  }

  hex.write(uppercase ? 'P' : 'p');
  hex.write(exponent >= 0 ? '+' : '');
  hex.write(exponent);

  String result = sign + hex.toString();
  if (uppercase) {
    result = result.toUpperCase().replaceAll('0X', '0X');
  }

  return _applyPadding(result, ctx);
}

String _formatInteger(_FormatContext ctx, {bool unsigned = false}) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;
  if (rawValue is! num && rawValue is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${NumberUtils.typeName(rawValue)})",
    );
  }

  var intValue = NumberUtils.toInt(rawValue);

  // Special case: precision 0 with value 0 produces empty string
  if (ctx.precision.isNotEmpty && ctx.precisionValue == 0 && intValue == 0) {
    return _applyPadding('', ctx);
  }

  String result;
  if (unsigned && intValue < 0) {
    // For unsigned format with negative numbers, treat as unsigned 64-bit integer
    final unsignedValue = NumberUtils.toUnsigned64(intValue);
    result = unsignedValue.toString();
  } else {
    // Handle precision padding correctly for negative numbers
    if (ctx.precision.isNotEmpty && intValue < 0) {
      // For negative numbers, separate the sign and pad the absolute value
      final precValue = ctx.precisionValue;
      final absValue = intValue.abs().toString();
      result = '-${absValue.padLeft(precValue, '0')}';
    } else {
      result = intValue.toString();
      // Apply precision padding for non-negative numbers
      if (ctx.precision.isNotEmpty) {
        final precValue = ctx.precisionValue;
        result = result.padLeft(precValue, '0');
      }
    }
  }

  if (!unsigned && ctx.showSign && intValue >= 0) {
    result = '+$result';
  } else if (!unsigned && ctx.spacePrefix && intValue >= 0) {
    result = ' $result';
  }

  return _applyPadding(result, ctx);
}

String _formatHex(_FormatContext ctx, bool uppercase) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;
  if (rawValue is! num && rawValue is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${NumberUtils.typeName(rawValue)})",
    );
  }

  final intValue = NumberUtils.toInt(rawValue);

  // For negative numbers, treat as unsigned 64-bit integer (two's complement)
  String result;
  if (intValue < 0) {
    // Convert to unsigned 64-bit representation
    final unsignedValue = NumberUtils.toUnsigned64(intValue);
    result = unsignedValue.toRadixString(16);
  } else {
    result = intValue.toRadixString(16);
  }

  if (uppercase) result = result.toUpperCase();

  if (ctx.alternative && intValue != 0) {
    result = (uppercase ? '0X' : '0x') + result;
  }

  if (ctx.precision.isNotEmpty) {
    final precValue = ctx.precisionValue;
    final prefix = result.startsWith('0x') || result.startsWith('0X')
        ? result.substring(0, 2)
        : '';
    final numPart = prefix.isNotEmpty ? result.substring(2) : result;
    result = prefix + numPart.padLeft(precValue, '0');
  }

  return _applyPadding(result, ctx);
}

class _FormatContext {
  final Object? value;
  final int valueIndex;
  final Set<String> flags;
  final String width;
  final String precision;
  final String specifier;

  int get widthValue => width.isEmpty ? 0 : int.parse(width);
  int get precisionValue {
    if (precision.isEmpty) {
      return 6; // Default precision
    }
    final precisionStr = precision.startsWith('.')
        ? precision.substring(1)
        : precision;
    if (precisionStr.isEmpty) {
      return 0; // "." means precision 0
    }
    return int.parse(precisionStr);
  }

  bool get leftAlign => flags.contains('-');
  bool get showSign => flags.contains('+');
  bool get spacePrefix => flags.contains(' ');
  bool get zeroPad => flags.contains('0');
  bool get alternative => flags.contains('#');

  _FormatContext({
    required this.value,
    required this.valueIndex,
    required this.flags,
    required this.width,
    required this.precision,
    required this.specifier,
  });
}

String _formatOctal(_FormatContext ctx) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;
  if (rawValue is! num && rawValue is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${NumberUtils.typeName(rawValue)})",
    );
  }

  final intValue = NumberUtils.toInt(rawValue);

  // For negative numbers, treat as unsigned 64-bit integer (two's complement)
  String result;
  if (intValue < 0) {
    // Convert to unsigned 64-bit representation
    final unsignedValue = NumberUtils.toUnsigned64(intValue);
    result = unsignedValue.toRadixString(8);
  } else {
    result = intValue.toRadixString(8);
  }

  if (ctx.alternative && intValue != 0) {
    result = '0$result';
  }

  if (ctx.precision.isNotEmpty) {
    final precValue = ctx.precisionValue;
    result = result.padLeft(precValue, '0');
  }

  return _applyPadding(result, ctx);
}

LuaString _formatQuoted(_FormatContext ctx) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;

  // Handle different types according to Lua %q specification
  if (rawValue == null) {
    // nil -> nil (unquoted)
    return LuaString.fromDartString('nil');
  } else if (rawValue is bool) {
    // boolean -> true/false (unquoted)
    return LuaString.fromDartString(rawValue.toString());
  } else if (rawValue is num || rawValue is BigInt) {
    // Numbers should be returned as unquoted literals
    if (rawValue is double) {
      if (rawValue.isNaN) {
        return LuaString.fromDartString('(0/0)');
      } else if (rawValue.isInfinite) {
        return LuaString.fromDartString(
          rawValue.isNegative ? '-1e9999' : '1e9999',
        );
      }
    }

    // Special case for minimum 64-bit integer (must be hex to round-trip correctly)
    final intValue = rawValue is BigInt
        ? rawValue
        : (rawValue is int ? rawValue : rawValue.toInt());
    if (intValue == NumberUtils.minInteger) {
      return LuaString.fromDartString('0x8000000000000000');
    }

    // Regular numbers
    return LuaString.fromDartString(rawValue.toString());
  } else if (rawValue is Map || rawValue is Function) {
    // Tables, functions, etc. have no literal form
    throw LuaError(
      "bad argument #${ctx.valueIndex} to 'format' (value has no literal form)",
    );
  } else {
    // Strings and other types need to be quoted and escaped
    final Uint8List bytes;
    if (rawValue is LuaString) {
      bytes = rawValue.bytes;
    } else {
      bytes = utf8.encode(rawValue.toString());
    }
    final escaped = FormatStringParser.escape(bytes);

    // Convert the escaped string back to bytes preserving Latin-1 characters
    final escapedBytes = <int>[];
    escapedBytes.add(34); // opening quote "
    for (int i = 0; i < escaped.length; i++) {
      escapedBytes.add(escaped.codeUnitAt(i));
    }
    escapedBytes.add(34); // closing quote "

    return LuaString(Uint8List.fromList(escapedBytes));
  }
}

class _StringFormat implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("string.format requires a format string");
    }

    final formatString = (args[0] as Value).raw.toString();

    List<FormatPart> formatParts;
    try {
      final parsedParts = FormatStringParser.parse(formatString);
      formatParts = parsedParts;
    } catch (e) {
      if (e is FormatException) {
        // Convert FormatException to appropriate LuaError
        if (e.message.contains('end of input expected')) {
          // This happens when there's an invalid specifier
          throw LuaError(
            "invalid conversion '${formatString.substring(formatString.lastIndexOf('%'))}' to 'format'",
          );
        }
        throw LuaError("invalid format string");
      }
      rethrow;
    }

    final buffer = <Object>[];
    int argIndex = 1;

    for (final part in formatParts) {
      if (part is LiteralPart) {
        buffer.add(part.text);
      } else if (part is SpecifierPart) {
        // Validate the format specifier
        _validateFormatSpecifier(part);

        if (argIndex >= args.length) {
          throw LuaError(
            'bad argument #${argIndex + 1} to \'format\' (no value)',
          );
        }

        final currentArg = args[argIndex];
        final ctx = _FormatContext(
          value: currentArg is Value ? currentArg : Value(currentArg),
          valueIndex: argIndex + 1,
          flags: part.flags.split('').toSet(),
          width: part.width ?? '',
          precision: part.precision ?? '',
          specifier: part.specifier,
        );

        Object formatted;
        switch (part.specifier) {
          case 'd':
          case 'i':
          case 'u':
            formatted = _formatInteger(ctx, unsigned: part.specifier == 'u');
            break;
          case 'o':
            formatted = _formatOctal(ctx);
            break;
          case 'x':
            formatted = _formatHex(ctx, false);
            break;
          case 'X':
            formatted = _formatHex(ctx, true);
            break;
          case 'f':
          case 'F':
            formatted = _formatFloat(ctx, part.specifier == 'F');
            break;
          case 'e':
            formatted = _formatScientific(ctx, false);
            break;
          case 'E':
            formatted = _formatScientific(ctx, true);
            break;
          case 'a':
            formatted = _formatHexFloat(ctx, false);
            break;
          case 'A':
            formatted = _formatHexFloat(ctx, true);
            break;
          case 'g':
            formatted = _formatGeneral(ctx, false);
            break;
          case 'G':
            formatted = _formatGeneral(ctx, true);
            break;
          case 'c':
            formatted = _formatCharacter(ctx);
            break;
          case 's':
            formatted = await _formatString(ctx);
            break;
          case 'q':
            formatted = _formatQuoted(ctx);
            break;
          case 'p':
            formatted = _formatPointer(ctx);
            break;
          case '%':
            formatted = '%';
            // Don't increment argIndex for %% - it doesn't consume an argument
            buffer.add(formatted);
            continue;
          default:
            throw LuaError(
              "invalid conversion '%${part.specifier}' to 'format'",
            );
        }
        buffer.add(formatted);
        argIndex++;
      }
    }

    final bytesBuilder = BytesBuilder(copy: false);
    for (final item in buffer) {
      if (item is LuaString) {
        bytesBuilder.add(item.bytes);
      } else {
        bytesBuilder.add(utf8.encode(item.toString()));
      }
    }
    return Value(LuaString(bytesBuilder.takeBytes()));
  }

  void _validateFormatSpecifier(SpecifierPart part) {
    // Check if the format specifier is too long
    if (part.full.length > 100) {
      throw LuaError("invalid format (too long)");
    }

    // Check for modifiers that aren't allowed with certain specifiers
    final hasModifiers =
        part.flags.isNotEmpty || part.width != null || part.precision != null;

    switch (part.specifier) {
      case 'q':
        if (hasModifiers) {
          throw LuaError("specifier '%q' cannot have modifiers");
        }
        break;
      case 'c':
        if (part.precision != null) {
          throw LuaError("invalid conversion '%${part.full}' to 'format'");
        }
        if (part.flags.contains('0') && part.width != null) {
          throw LuaError("invalid conversion '%${part.full}' to 'format'");
        }
        break;
      case 's':
        if (part.flags.contains('0')) {
          throw LuaError("invalid conversion '%${part.full}' to 'format'");
        }
        break;
      case 'p':
        if (part.precision != null) {
          throw LuaError("invalid conversion '%${part.full}' to 'format'");
        }
        break;
      case 'i':
        if (part.flags.contains('#')) {
          throw LuaError("invalid conversion '%${part.full}' to 'format'");
        }
        break;
    }

    // Check for precision on integer formats that don't allow large precision
    if (['d', 'i', 'u', 'o', 'x', 'X'].contains(part.specifier)) {
      if (part.precision != null) {
        final precisionStr = part.precision!.substring(1);
        final precisionValue = precisionStr.isEmpty
            ? 0
            : int.tryParse(precisionStr);
        if (precisionValue != null && precisionValue >= 100) {
          throw LuaError("invalid conversion '%${part.full}' to 'format'");
        }
      }
    }

    // Check for width that's too large
    if (part.width != null) {
      final widthValue = int.tryParse(part.width!);
      if (widthValue != null && widthValue >= 100) {
        throw LuaError("invalid conversion '%${part.full}' to 'format'");
      }
    }
  }
}

class _StringGmatch implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.gmatch requires a string and a pattern");
    }

    final str = (args[0] as Value).raw.toString();
    final pattern = (args[1] as Value).raw.toString();

    try {
      final lp = lpc.LuaPattern.compile(pattern);
      final matches = lp.allMatches(str).toList();
      var currentIndex = 0;

      // Return iterator function that follows Lua's behavior
      return Value((List<Object?> iterArgs) {
        if (currentIndex >= matches.length) {
          return Value(null);
        }

        final match = matches[currentIndex++];
        if (match.captures.isEmpty) {
          return Value(match.match);
        }

        final captures = match.captures
            .map((c) => c == null ? Value(null) : Value(c))
            .toList();

        if (captures.length == 1) {
          return captures[0];
        } else {
          return Value.multi(captures);
        }
      });
    } catch (e) {
      throw LuaError.typeError("malformed pattern: $e");
    }
  }
}

class _StringGsub implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError.typeError(
        "string.gsub requires string, pattern, and replacement",
      );
    }
    final str = (args[0] as Value).raw.toString();
    final pattern = (args[1] as Value).raw.toString();
    final repl = args[2] as Value;
    final n = args.length > 3 ? NumberUtils.toInt((args[3] as Value).raw) : -1;

    try {
      var count = 0;
      final lp = lpc.LuaPattern.compile(pattern);

      String result;
      if (repl.raw is Function) {
        final replFunc = repl.raw as Function;
        final buffer = StringBuffer();
        var lastEnd = 0;
        final matches = lp.allMatches(str);

        for (final match in matches) {
          if (n != -1 && count >= n) {
            break;
          }
          buffer.write(str.substring(lastEnd, match.start));

          final captures = <Value>[];
          if (match.captures.isEmpty) {
            captures.add(Value(match.match));
          } else {
            for (final cap in match.captures) {
              captures.add(cap == null ? Value(null) : Value(cap));
            }
          }

          var replacement = replFunc(captures);
          if (replacement is Future) {
            replacement = await replacement;
          }

          if (replacement == null ||
              (replacement is Value &&
                  (replacement.isNil || replacement.raw == false))) {
            buffer.write(match.match);
          } else {
            buffer.write(replacement is Value ? replacement.raw : replacement);
            count++;
          }
          lastEnd = match.end;
        }

        if (lastEnd < str.length) {
          buffer.write(str.substring(lastEnd));
        }
        result = buffer.toString();
      } else if (repl.raw is Map) {
        final replTable = repl.raw as Map;
        final buffer = StringBuffer();
        var lastEnd = 0;

        for (final match in lp.allMatches(str)) {
          if (n != -1 && count >= n) {
            break;
          }
          buffer.write(str.substring(lastEnd, match.start));

          final key = Value(match.match);
          var replacement = replTable[key];

          if (replacement is Value) {
            replacement = replacement.raw;
          }

          if (replacement != null && replacement != false) {
            buffer.write(replacement.toString());
            count++;
          } else {
            buffer.write(match.match);
          }
          lastEnd = match.end;
        }

        if (lastEnd < str.length) {
          buffer.write(str.substring(lastEnd));
        }
        result = buffer.toString();
      } else if (repl.raw is String || repl.raw is LuaString) {
        final replStr = repl.raw.toString();
        final buffer = StringBuffer();
        var lastEnd = 0;

        for (final match in lp.allMatches(str)) {
          if (n != -1 && count >= n) break;

          buffer.write(str.substring(lastEnd, match.start));

          String replacement = replStr;
          bool captureReplaced = false;

          for (int i = 0; i <= match.captures.length; i++) {
            final capture = i == 0 ? match.match : match.captures[i - 1];
            final placeholder = '%$i';
            if (replacement.contains(placeholder)) {
              replacement = replacement.replaceAll(placeholder, capture ?? '');
              captureReplaced = true;
            }
          }

          if (replacement.contains('%%')) {
            replacement = replacement.replaceAll('%%', '%');
            captureReplaced = true;
          }

          if (captureReplaced || replStr.isNotEmpty) {
            count++;
          }

          buffer.write(replacement);
          lastEnd = match.end;
        }

        if (lastEnd < str.length) {
          buffer.write(str.substring(lastEnd));
        }
        result = buffer.toString();
      } else {
        throw LuaError.typeError("Invalid replacement type");
      }

      return [Value(result), Value(count)];
    } catch (e) {
      throw LuaError.typeError("Error in string.gsub: $e");
    }
  }
}

class _StringLen implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.len requires a string argument");
    }
    final value = args[0] as Value;
    int len;
    if (value.raw is LuaString) {
      len = (value.raw as LuaString).bytes.length;
    } else {
      len = utf8.encode(value.raw.toString()).length;
    }
    return Value(len);
  }
}

class _StringLower implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.lower requires a string argument");
    }

    final value = args[0] as Value;
    // For normal string operations, use Dart's string methods for better interop
    final str = value.raw.toString();
    return Value(str.toLowerCase());
  }
}

class _StringMatch implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.match requires a string and a pattern");
    }

    final str = (args[0] as Value).raw.toString();
    final pattern = (args[1] as Value).raw.toString();
    var init = args.length > 2 ? NumberUtils.toInt((args[2] as Value).raw) : 1;

    // Convert to 0-based index and handle negative indices
    init = init > 0 ? init - 1 : str.length + init;
    if (init < 0) init = 0;
    if (init > str.length) {
      return Value(null);
    }

    try {
      final lp = lpc.LuaPattern.compile(pattern);
      final resultMatch = lp.firstMatch(str, init);
      if (resultMatch == null) {
        return Value(null);
      }

      if (resultMatch.captures.isNotEmpty) {
        final captures = resultMatch.captures
            .map((c) => c == null ? Value(null) : Value(c))
            .toList();
        if (captures.length == 1) {
          return captures[0];
        }
        return Value.multi(captures);
      }

      return Value(resultMatch.match);
    } catch (e) {
      throw LuaError.typeError("malformed pattern: $e");
    }
  }
}

class _StringRep implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.rep requires a string and count");
    }

    final value = args[0] as Value;
    final count = NumberUtils.toInt((args[1] as Value).raw);
    final separatorValue = args.length > 2 ? (args[2] as Value) : null;

    final originalStr = value.raw.toString();
    final separatorStr = separatorValue?.raw?.toString() ?? '';

    if (count <= 0) {
      return StringInterning.createStringValue('');
    }

    final totalLength =
        (BigInt.from(originalStr.length) * BigInt.from(count)) +
        (BigInt.from(separatorStr.length) *
            BigInt.from(math.max(0, count - 1)));

    // Dart strings can be huge, but creating multi-gigabyte strings is risky.
    // Let's cap it at something sane to prevent OOM errors, similar to Lua.
    // (e.g., 2^30 bytes, ~1GB). Lua's limit is related to size_t.
    if (totalLength > BigInt.from(1 << 30)) {
      throw LuaError('too large');
    }

    if (count == 1) {
      return StringInterning.createStringValue(originalStr);
    }

    final buffer = StringBuffer();
    for (var i = 0; i < count; i++) {
      buffer.write(originalStr);
      if (separatorStr.isNotEmpty && i < count - 1) {
        buffer.write(separatorStr);
      }
    }

    return StringInterning.createStringValue(buffer.toString());
  }
}

class _StringReverse implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.reverse requires a string argument");
    }

    final value = args[0] as Value;
    final str = value.raw.toString();

    return Value(str.split('').reversed.join(''));
  }
}

class _StringSub implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.sub requires a string argument");
    }

    final value = args[0] as Value;
    final str = value.raw.toString();

    var start = args.length > 1 ? NumberUtils.toInt((args[1] as Value).raw) : 1;
    var end = args.length > 2
        ? NumberUtils.toInt((args[2] as Value).raw)
        : str.length;

    // Handle negative indices
    if (start < 0) start = str.length + start + 1;
    if (end < 0) end = str.length + end + 1;

    // Clamp to valid range
    if (start < 1) start = 1;
    if (end > str.length) end = str.length;

    // Handle empty substring
    if (start > end || start > str.length) {
      return Value("");
    }

    // Extract substring (1-based to 0-based conversion)
    final result = str.substring(start - 1, end);
    return Value(result);
  }
}

class _StringPack implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.pack requires format string");
    }
    final format = (args[0] as Value).raw.toString();
    final values = args.sublist(1);

    final bytes = <int>[];
    var i = 0;

    for (var c in format.split('')) {
      if (i >= values.length) break;

      switch (c) {
        case 'b': // signed byte
          final value = NumberUtils.toInt((values[i] as Value).raw);
          bytes.add(value & 0xFF);
          i++;
          break;
        case 'B': // unsigned byte
          final value = NumberUtils.toInt((values[i] as Value).raw);
          bytes.add(value & 0xFF);
          i++;
          break;
        case 'h': // signed short
          var n = NumberUtils.toInt((values[i] as Value).raw);
          // Little endian
          bytes.add(n & 0xFF);
          bytes.add((n >> 8) & 0xFF);
          i++;
          break;
        case 'H': // unsigned short
          var n = NumberUtils.toInt((values[i] as Value).raw);
          // Little endian
          bytes.add(n & 0xFF);
          bytes.add((n >> 8) & 0xFF);
          i++;
          break;
        case 'i': // signed int
          var n = NumberUtils.toInt((values[i] as Value).raw);
          // Little endian
          bytes.add(n & 0xFF);
          bytes.add((n >> 8) & 0xFF);
          bytes.add((n >> 16) & 0xFF);
          bytes.add((n >> 24) & 0xFF);
          i++;
          break;
        case 's': // string
          var s = (values[i] as Value).raw.toString();
          bytes.addAll(utf8.encode(s));
          bytes.add(0); // null terminator
          i++;
          break;
      }
    }

    final result = String.fromCharCodes(bytes);
    return Value(result);
  }
}

class _StringPackSize implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.packsize requires format string");
    }
    final format = (args[0] as Value).raw.toString();

    var size = 0;
    for (var c in format.split('')) {
      switch (c) {
        case 'b':
        case 'B':
          size += 1;
          break;
        case 'h':
        case 'H':
          size += 2;
          break;
        case 'i':
        case 'I':
          size += 4;
          break;
        case 'l':
        case 'L':
          size += 8;
          break;
        default:
          throw LuaError.typeError("Invalid format option '$c'");
      }
    }
    return Value(size);
  }
}

class _StringUnpack implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError(
        "string.unpack requires format string and binary string",
      );
    }
    final format = (args[0] as Value).raw.toString();
    final binary = (args[1] as Value).raw.toString();
    final pos = args.length > 2 ? NumberUtils.toInt((args[2] as Value).raw) : 1;

    final results = <Value>[];
    var offset = pos - 1;
    final bytes = binary.codeUnits;

    for (var c in format.split('')) {
      switch (c) {
        case 'b': // signed byte
          if (offset >= bytes.length) {
            throw LuaError.typeError("unpack: out of bounds");
          }
          var value = bytes[offset];
          // Handle sign extension for signed byte
          if (value & 0x80 != 0) {
            value = value - 256;
          }
          results.add(Value(value));
          offset++;
          break;
        case 'h': // signed short
          if (offset + 1 >= bytes.length) {
            throw LuaError.typeError("unpack: out of bounds");
          }
          // Little endian
          var value = bytes[offset] | (bytes[offset + 1] << 8);
          // Handle sign extension for signed short
          if (value & 0x8000 != 0) {
            value = value - 65536;
          }
          results.add(Value(value));
          offset += 2;
          break;
        case 'i': // signed int
          if (offset + 3 >= bytes.length) {
            throw LuaError.typeError("unpack: out of bounds");
          }
          // Little endian
          var value =
              bytes[offset] |
              (bytes[offset + 1] << 8) |
              (bytes[offset + 2] << 16) |
              (bytes[offset + 3] << 24);
          // Convert to signed 32-bit integer
          if (value >= 0x80000000) {
            value = value - 0x100000000;
          }
          results.add(Value(value));
          offset += 4;
          break;
        case 's': // null-terminated string
          var end = bytes.indexOf(0, offset);
          if (end == -1) end = bytes.length;
          var str = String.fromCharCodes(bytes.sublist(offset, end));
          results.add(Value(str));
          offset = end + 1;
          break;
      }
    }

    results.add(Value(offset + 1)); // Next position after unpacking
    return results;
  }
}

class _StringUpper implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.upper requires a string argument");
    }

    final value = args[0] as Value;
    // For normal string operations, use Dart's string methods for better interop
    final str = value.raw.toString();
    return Value(str.toUpperCase());
  }
}

String _formatGeneral(_FormatContext ctx, bool uppercase) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;
  if (rawValue is! num && rawValue is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${NumberUtils.typeName(rawValue)})",
    );
  }

  final doubleValue = NumberUtils.toDouble(rawValue);

  // Handle special values
  if (doubleValue.isNaN) return uppercase ? 'NAN' : 'nan';
  if (doubleValue.isInfinite) {
    final sign = doubleValue.isNegative ? '-' : (ctx.showSign ? '+' : '');
    return uppercase ? '${sign}INF' : '${sign}inf';
  }

  // For %g/%G, precision means significant digits, not decimal places
  // Default precision is 6 if not specified
  final precision = ctx.precision.isNotEmpty ? ctx.precisionValue : 6;

  // Determine the exponent
  final absValue = doubleValue.abs();
  int exponent = 0;
  if (absValue != 0.0) {
    exponent = (math.log(absValue) / math.ln10).floor();
  }

  // Choose between %f and %e format based on the exponent
  // Use %e if exponent < -4 or exponent >= precision
  final useScientific = exponent < -4 || exponent >= precision;

  String result;
  if (useScientific) {
    // Use scientific notation (like %e)
    if (doubleValue == 0.0) {
      result = '0${uppercase ? 'E+00' : 'e+00'}';
    } else {
      final mantissa = absValue / NumberUtils.exponentiate(10.0, exponent);
      final mantissaStr = mantissa.toStringAsFixed(precision - 1);
      final expStr = exponent.abs().toString().padLeft(2, '0');
      result =
          mantissaStr +
          (uppercase ? 'E' : 'e') +
          (exponent >= 0 ? '+' : '-') +
          expStr;
    }
  } else {
    // Use fixed-point notation (like %f)
    final decimalPlaces = precision - 1 - exponent;
    result = absValue.toStringAsFixed(math.max(0, decimalPlaces));
  }

  // Remove trailing zeros and decimal point if not needed (specific to %g/%G)
  if (result.contains('.')) {
    result = result.replaceAll(RegExp(r'0+$'), '');
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
  }

  // Apply sign
  if (doubleValue.isNegative) {
    result = '-$result';
  } else if (ctx.showSign) {
    result = '+$result';
  } else if (ctx.spacePrefix) {
    result = ' $result';
  }

  return _applyPadding(result, ctx);
}

void defineStringLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final stringTable = <String, dynamic>{};
  StringLib.functions.forEach((key, value) {
    stringTable[key] = value;
  });

  env.define(
    "string",
    Value(StringLib.functions, metatable: StringLib.stringClass.metamethods),
  );
}
