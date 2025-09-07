import 'dart:convert' as convert;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart' show ListEquality;
import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/parsers/pattern.dart' as lpc;
import 'package:lualike/src/stdlib/binary_type_size.dart';
import 'package:lualike/src/stdlib/lib_utf8.dart' show UTF8Lib;

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
    // TODO(lualike): string.dump is a minimal, test-oriented implementation.
    // - Not a true bytecode dump; we synthesize a textual chunk prefixed with
    //   ESC (0x1B) so loadfile recognizes it as "binary" in mode checks.
    // - Only supports literal-only return functions (no upvalues, no complex body).
    // - The optional 'strip' flag is not handled; debug info stripping is not implemented.
    // - Functions with upvalues should serialize only the upvalue count and, upon
    //   load, receive fresh nil upvalues; we currently do not implement that.
    // - On unsupported functions, Lua raises "unable to dump given function";
    //   we should align error behavior (raise LuaError) instead of returning stubs.
    // Consider reworking this to leverage Dumpable on AST nodes and/or add a
    // proper bytecode path once a VM serialization format is available.

    if (args.isEmpty) {
      throw LuaError.typeError("string.dump requires a function argument");
    }

    final func = args[0] as Value;
    if (func.raw is! Function) {
      throw LuaError.typeError("string.dump requires a function argument");
    }

    // Heuristic dump without executing the function: inspect the captured
    // function body. If it is a simple function with a literal-only return
    // statement, synthesize a chunk "return <literals>". This mirrors the
    // behavior of loading a precompiled function that returns those values
    // when executed.
    List<Object?> retValues = [];
    final fb = func.functionBody;
    if (fb != null) {
      // Find the first ReturnStatement in the body
      ReturnStatement? ret;
      for (final s in fb.body) {
        if (s is ReturnStatement) {
          ret = s;
          break;
        }
      }
      if (ret != null) {
        bool allLiterals = true;
        for (final e in ret.expr) {
          if (e is NumberLiteral) {
            retValues.add(Value(e.value));
          } else if (e is StringLiteral) {
            retValues.add(
              Value(LuaString.fromBytes(Uint8List.fromList(e.bytes))),
            );
          } else if (e is BooleanLiteral) {
            retValues.add(Value(e.value));
          } else if (e is NilValue) {
            retValues.add(Value(null));
          } else {
            allLiterals = false;
            break;
          }
        }
        if (!allLiterals) {
          // Fallback: do not attempt to dump complex functions
          return Value("-- dump unsupported (complex function)");
        }
      } else {
        return Value("-- dump unsupported (no return)");
      }
    } else {
      return Value("-- dump unsupported (no body)");
    }

    String quoteStringFromBytes(Uint8List bytes) {
      final sb = StringBuffer();
      sb.write('"');
      for (final b in bytes) {
        switch (b) {
          case 34: // '"'
            sb.write('\\"');
            break;
          case 92: // '\\'
            sb.write('\\\\');
            break;
          case 10: // '\n'
            sb.write('\\n');
            break;
          case 13: // '\r'
            sb.write('\\r');
            break;
          case 9: // '\t'
            sb.write('\\t');
            break;
          default:
            if (b >= 32 && b <= 126) {
              sb.write(String.fromCharCode(b));
            } else {
              // Use 3-digit decimal escapes \ddd
              final d = b.toString().padLeft(3, '0');
              sb.write('\\$d');
            }
        }
      }
      sb.write('"');
      return sb.toString();
    }

    String toLuaLiteral(Value v) {
      final raw = v.raw;
      if (raw == null) return 'nil';
      if (raw is bool) return raw ? 'true' : 'false';
      if (raw is BigInt) return raw.toString();
      if (raw is num) {
        if (raw.isNaN) return '(0/0)';
        if (raw == double.infinity) return '(1/0)';
        if (raw == double.negativeInfinity) return '(-1/0)';
        return raw.toString();
      }
      if (raw is LuaString) {
        return quoteStringFromBytes(raw.bytes);
      }
      if (raw is String) {
        // Encode to bytes to preserve non-ASCII in decimal escapes
        final bytes = Uint8List.fromList(utf8.encode(raw));
        return quoteStringFromBytes(bytes);
      }
      // Unsupported types in this heuristic
      return 'nil';
    }

    final parts = <String>[];
    for (final val in retValues) {
      final vv = val is Value ? val : Value(val);
      parts.add(toLuaLiteral(vv));
    }
    final body = parts.isEmpty ? '' : parts.join(', ');
    // Produce a chunk that, when executed, returns the captured values.
    final chunk = 'return $body';
    Logger.debug('string.dump synthesized chunk: $chunk', category: 'String');
    // Return as a LuaString so that byte-for-byte write preserves content
    // Prefix with 0x1B to mark as a "binary" chunk for loadfile() mode checks.
    final payload = utf8.encode(chunk);
    final bytes = Uint8List(payload.length + 1);
    bytes[0] = 0x1B; // ESC
    bytes.setRange(1, bytes.length, payload);
    final luaString = LuaString.fromBytes(bytes);
    return Value(luaString);
  }
}

class _StringFind implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.find requires a string and a pattern");
    }

    // Use toLatin1String for pattern processing to preserve raw bytes
    final strValue = (args[0] as Value).raw;
    final str = strValue is LuaString
        ? strValue.toLatin1String()
        : strValue.toString();
    final patternValue = (args[1] as Value).raw;
    final pattern = patternValue is LuaString
        ? patternValue.toLatin1String()
        : patternValue.toString();
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
      return Value.multi([Value(start + 1), Value(start)]);
    }

    if (plain) {
      final index = str.indexOf(pattern, start);
      if (index == -1) return Value(null);
      return Value.multi([Value(index + 1), Value(index + pattern.length)]);
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
      return Value.multi(results);
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
        final str = '${name.raw}: ';
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
    if (intValue == NumberLimits.minInteger) {
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
      bytes = convert.utf8.encode(rawValue.toString());
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

    final strValue = (args[0] as Value).raw;
    final patternValue = (args[1] as Value).raw;

    // Helper function to check if LuaString contains valid UTF-8
    bool isValidUtf8(LuaString luaStr) {
      try {
        utf8.decode(luaStr.bytes, allowMalformed: false);
        return true;
      } catch (e) {
        return false;
      }
    }

    // Only use byte-level processing when explicitly dealing with LuaString objects
    // that contain non-UTF-8 data or when pattern is a LuaString with byte patterns
    final bool useByteLevel =
        (strValue is LuaString && !isValidUtf8(strValue)) ||
        (patternValue is LuaString && !isValidUtf8(patternValue));

    // Special-case utf8.charpattern: implement our own iterator that walks
    // UTF-8 byte sequences using LuaStringParser so we don't rely on the
    // LuaPattern engine (which operates on code-units and caused corruption
    // when multi-byte characters were involved).

    // Detect "utf8.charpattern" regardless of whether the script passes it
    // as a LuaString or as a plain Dart string.  Some call-sites (e.g. code
    // executed via `-e` on the CLI or inside the test-bridge) end up with the
    // constant coerced to a regular Dart `String`, which previously made us
    // miss the fast-path and fall back to the LuaPattern engine (leading to
    // duplicated matches for multi-byte characters).  We now recognise both
    // representations.

    final bool isUtf8CharPattern = (() {
      if (patternValue is LuaString) {
        return const ListEquality().equals(
          patternValue.bytes,
          UTF8Lib.charpattern.bytes,
        );
      }

      if (patternValue is String) {
        // Compare based on raw byte sequence to avoid issues with escape
        // representations or different String instances.
        return const ListEquality<int>().equals(
          patternValue.codeUnits,
          UTF8Lib.charpattern.bytes,
        );
      }

      return false;
    })();

    if (isUtf8CharPattern) {
      // Obtain raw bytes of the subject string.
      final bytes = strValue is LuaString
          ? strValue.bytes
          : convert.utf8.encode(strValue.toString());

      // Iterator state.
      int pos = 0;

      return Value((List<Object?> _) {
        if (pos >= bytes.length) return Value(null);

        // Decode next UTF-8 character (lax allows 5/6-byte sequences etc.)
        final res = LuaStringParser.decodeUtf8Character(bytes, pos, lax: true);
        int seqLen;
        Uint8List slice;
        if (res == null) {
          // Invalid byte → treat as single-byte char.
          seqLen = 1;
          slice = Uint8List.fromList([bytes[pos]]);
        } else {
          seqLen = res.sequenceLength;
          slice = Uint8List.sublistView(bytes, pos, pos + seqLen);
        }
        pos += seqLen;
        return Value(LuaString(slice));
      });
    }

    final String str;
    final String pattern;

    if (useByteLevel) {
      // Only use byte-level processing when dealing with invalid UTF-8 data
      final strBytes = strValue is LuaString
          ? strValue.bytes
          : Uint8List.fromList(utf8.encode(strValue.toString()));
      final patternBytes = patternValue is LuaString
          ? patternValue.bytes
          : Uint8List.fromList(utf8.encode(patternValue.toString()));

      str = String.fromCharCodes(strBytes);
      pattern = String.fromCharCodes(patternBytes);
    } else {
      // For valid UTF-8 or normal Dart strings, work directly with UTF-8 strings
      // This preserves proper UTF-8 character encoding
      str = strValue.toString();
      pattern = patternValue.toString();
    }

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
          // Return the match preserving the original encoding
          if (useByteLevel && match.match.isNotEmpty) {
            // Convert back to bytes and create LuaString for byte-level matches
            final matchBytes = match.match.codeUnits
                .map((c) => c & 0xFF)
                .toList();
            return Value(LuaString.fromBytes(Uint8List.fromList(matchBytes)));
          } else {
            return Value(match.match);
          }
        }

        final captures = <Value>[];
        for (var idx = 0; idx < match.captures.length; idx++) {
          final cap = match.captures[idx];

          if (cap == null) {
            captures.add(Value(null));
            continue;
          }

          // Only treat the very first capture (position capture produced by
          // plain '()' in patterns like "()pattern") as a numeric value. All
          // subsequent captures must **always** be returned as strings, even
          // when they happen to consist solely of digits (e.g. the character
          // "4"). This mimics Lua's semantics and prevents accidental type
          // conversion that breaks code relying on string values.
          if (idx == 0) {
            final numericPosition = int.tryParse(cap);
            if (numericPosition != null) {
              captures.add(Value(numericPosition));
              continue;
            }
          }

          if (useByteLevel && cap.isNotEmpty) {
            final captureBytes = cap.codeUnits
                .map((code) => code & 0xFF)
                .toList();
            captures.add(
              Value(LuaString.fromBytes(Uint8List.fromList(captureBytes))),
            );
          } else {
            captures.add(Value(cap));
          }
        }

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
    // Use toLatin1String for pattern processing to preserve raw bytes
    final strValue = (args[0] as Value).raw;
    final str = strValue is LuaString
        ? strValue.toLatin1String()
        : strValue.toString();
    final patternValue = (args[1] as Value).raw;
    final pattern = patternValue is LuaString
        ? patternValue.toLatin1String()
        : patternValue.toString();
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

          dynamic replacement;
          try {
            replacement = replFunc(captures);
            if (replacement is Future) {
              replacement = await replacement;
            }
          } on TailCallException catch (t) {
            final vm = Environment.current?.interpreter;
            if (vm == null) rethrow;
            final callee = t.functionValue is Value
                ? t.functionValue as Value
                : Value(t.functionValue);
            final normalizedArgs = t.args
                .map((a) => a is Value ? a : Value(a))
                .toList();
            replacement = await vm.callFunction(callee, normalizedArgs);
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

      // Preserve byte representation for LuaString inputs, use regular String for String inputs
      final resultValue = strValue is LuaString
          ? Value(
              LuaString.fromBytes(
                result.codeUnits.map((c) => c & 0xFF).toList(),
              ),
            )
          : Value(result);
      return [resultValue, Value(count)];
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

    // Handle LuaString specially to preserve byte representation
    if (value.raw is LuaString) {
      final luaStr = value.raw as LuaString;
      final bytes = luaStr.bytes;
      final resultBytes = <int>[];

      // Apply lowercase transformation byte by byte
      for (final byte in bytes) {
        if (byte >= 65 && byte <= 90) {
          // 'A' to 'Z'
          resultBytes.add(byte + 32); // Convert to lowercase
        } else {
          resultBytes.add(byte); // Keep unchanged
        }
      }

      // For better interop, return regular strings when they only contain ASCII
      final isAsciiOnly = resultBytes.every((b) => b <= 127);
      if (isAsciiOnly) {
        final resultString = String.fromCharCodes(resultBytes);
        return Value(resultString);
      } else {
        return Value(LuaString.fromBytes(Uint8List.fromList(resultBytes)));
      }
    } else {
      // For normal string operations, use Dart's string methods for better interop
      final str = value.raw.toString();
      return Value(str.toLowerCase());
    }
  }
}

class _StringMatch implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.match requires a string and a pattern");
    }

    // Use toLatin1String for pattern processing to preserve raw bytes
    final strValue = (args[0] as Value).raw;
    final str = strValue is LuaString
        ? strValue.toLatin1String()
        : strValue.toString();
    final patternValue = (args[1] as Value).raw;
    final pattern = patternValue is LuaString
        ? patternValue.toLatin1String()
        : patternValue.toString();
    var init = args.length > 2 ? NumberUtils.toInt((args[2] as Value).raw) : 1;

    // Convert to 0-based index and handle negative indices
    init = init > 0 ? init - 1 : str.length + init;
    if (init < 0) init = 0;
    if (init > str.length) {
      return Value(null);
    }

    try {
      bool isEscaped(int index) =>
          index > 0 && pattern[index - 1] == '%' && !isEscaped(index - 1);
      final anchoredStart = pattern.startsWith('^') && !isEscaped(0);
      final lp = lpc.LuaPattern.compile(pattern);
      final resultMatch = lp.firstMatch(str, init);
      if (resultMatch == null) {
        return Value(null);
      }
      if (anchoredStart && resultMatch.start != init) {
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

    if (count <= 0) {
      return StringInterning.createStringValue('');
    }

    // Handle LuaString specially to preserve byte representation
    if (value.raw is LuaString) {
      final luaStr = value.raw as LuaString;
      final separatorBytes = separatorValue?.raw is LuaString
          ? (separatorValue!.raw as LuaString).bytes
          : (separatorValue?.raw?.toString() ?? '').codeUnits
                .map((c) => c & 0xFF)
                .toList();

      final totalLength =
          (BigInt.from(luaStr.length) * BigInt.from(count)) +
          (BigInt.from(separatorBytes.length) *
              BigInt.from(math.max(0, count - 1)));

      if (totalLength > BigInt.from(1 << 30)) {
        throw LuaError('too large');
      }

      if (count == 1) {
        return value;
      }

      final resultBytes = <int>[];
      for (var i = 0; i < count; i++) {
        resultBytes.addAll(luaStr.bytes);
        if (separatorBytes.isNotEmpty && i < count - 1) {
          resultBytes.addAll(separatorBytes);
        }
      }

      // For LuaString results, we need to handle interning carefully
      // Check if the result contains only ASCII characters (safe for interning)
      final isAsciiOnly = resultBytes.every((b) => b <= 127);

      if (isAsciiOnly) {
        // Safe to convert to regular string and intern
        final resultString = String.fromCharCodes(resultBytes);
        return StringInterning.createStringValue(resultString);
      } else {
        // Contains high bytes, preserve as LuaString
        final resultLuaString = LuaString.fromBytes(resultBytes);

        // For high-byte content, we cannot use StringInterning because it would
        // UTF-8 encode the Latin-1 string, corrupting the bytes
        // Instead, return the LuaString directly
        return Value(resultLuaString);
      }
    } else {
      // Handle regular strings
      final originalStr = value.raw.toString();
      final separatorStr = separatorValue?.raw?.toString() ?? '';

      final totalLength =
          (BigInt.from(originalStr.length) * BigInt.from(count)) +
          (BigInt.from(separatorStr.length) *
              BigInt.from(math.max(0, count - 1)));

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
}

class _StringReverse implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.reverse requires a string argument");
    }

    final value = args[0] as Value;

    if (value.raw is LuaString) {
      final bytes = List<int>.from((value.raw as LuaString).bytes.reversed);
      return Value(LuaString.fromBytes(bytes));
    }

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
    // Use toLatin1String for byte-level operations to preserve raw bytes
    final strValue = value.raw;
    final str = strValue is LuaString
        ? strValue.toLatin1String()
        : strValue.toString();

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

    // For better interop, return regular strings when they only contain ASCII
    // Only use LuaString when we have non-ASCII bytes that need preservation
    if (result.codeUnits.every((c) => c <= 127)) {
      return Value(result); // Regular Dart string for ASCII content
    } else {
      // Return as LuaString to preserve byte sequence integrity for non-ASCII
      final bytes = result.codeUnits.map((c) => c & 0xFF).toList();
      return Value(LuaString.fromBytes(Uint8List.fromList(bytes)));
    }
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
    Endian endianness = Endian.host;
    int maxAlign = 1;
    final maxAllowed = (BinaryTypeSize.j <= BinaryTypeSize.T)
        ? BigInt.from(NumberLimits.maxInteger)
        : (BigInt.one << (BinaryTypeSize.T * 8));

    BigInt alignTo(BigInt offset, int align) {
      if (align <= 1) return BigInt.zero;
      if ((align & (align - 1)) != 0) {
        throw LuaError("format asks for alignment not power of 2");
      }
      final mod = offset % BigInt.from(align);
      return mod == BigInt.zero ? BigInt.zero : BigInt.from(align) - mod;
    }

    final options = BinaryFormatParser.parse(format);
    BigInt offset = BigInt.zero;
    for (final opt in options) {
      Value getArg([String kind = 'number']) {
        if (i < values.length) return values[i] as Value;
        return kind == 'string' ? Value('') : Value(0);
      }

      switch (opt.type) {
        case '<':
          endianness = Endian.little;
          continue;
        case '>':
          endianness = Endian.big;
          continue;
        case '=':
          endianness = Endian.host;
          continue;
        case '!':
          if (opt.align == null) {
            maxAlign = BinaryTypeSize.j; // reset to default alignment
          } else {
            maxAlign = opt.align!;
            if ((maxAlign & (maxAlign - 1)) != 0) {
              throw LuaError("format asks for alignment not power of 2");
            }
          }
          continue;
        case 'c': // char array of size N (never needs alignment)
          final size = opt.size;
          if (size == null) {
            throw LuaError("missing size for format option 'c'");
          }
          final rawVal = getArg('string').raw;
          final encoded = rawVal is LuaString
              ? rawVal.bytes
              : utf8.encode(rawVal.toString());
          if (offset + BigInt.from(size) > maxAllowed) {
            throw LuaError('too long');
          }
          if (encoded.length > size) {
            throw LuaError('longer than');
          }
          bytes.addAll(encoded);
          bytes.addAll(List.filled(size - encoded.length, 0));
          i++;
          offset += BigInt.from(size);
          break;
        case 'b':
        case 'B':
        case 'h':
        case 'H':
        case 'l':
        case 'L':
        case 'j':
        case 'J':
        case 'T':
        case 'f':
        case 'd':
        case 'n':
        case 'i':
        case 'I':
          {
            int size;
            switch (opt.type) {
              case 'b':
                size = BinaryTypeSize.b;
                break;
              case 'B':
                size = BinaryTypeSize.B;
                break;
              case 'h':
                size = BinaryTypeSize.h;
                break;
              case 'H':
                size = BinaryTypeSize.H;
                break;
              case 'l':
                size = BinaryTypeSize.l;
                break;
              case 'L':
                size = BinaryTypeSize.L;
                break;
              case 'j':
                size = BinaryTypeSize.j;
                break;
              case 'J':
                size = BinaryTypeSize.J;
                break;
              case 'T':
                size = BinaryTypeSize.T;
                break;
              case 'f':
                size = BinaryTypeSize.f;
                break;
              case 'd':
                size = BinaryTypeSize.d;
                break;
              case 'n':
                size = BinaryTypeSize.n;
                break;
              case 'i':
                size = opt.size ?? BinaryTypeSize.i;
                break;
              case 'I':
                size = opt.size ?? BinaryTypeSize.I;
                break;
              default:
                size = 1;
                break;
            }
            final align = size > maxAlign ? maxAlign : size;
            final pad = alignTo(offset, align).toInt();
            if (offset + BigInt.from(pad) + BigInt.from(size) > maxAllowed) {
              throw LuaError('too long');
            }
            bytes.addAll(List.filled(pad, 0));
            offset += BigInt.from(pad);

            // Handle float types differently from integer types
            if (opt.type == 'f') {
              final value = NumberUtils.toDouble(getArg().raw);
              bytes.addAll(NumberUtils.packFloat32(value, endianness));
            } else if (opt.type == 'd' || opt.type == 'n') {
              final value = NumberUtils.toDouble(getArg().raw);
              bytes.addAll(NumberUtils.packFloat64(value, endianness));
            } else {
              // Integer types with overflow detection
              final v = NumberUtils.toBigInt(getArg().raw);
              final isUnsigned =
                  opt.type == 'B' ||
                  opt.type == 'H' ||
                  opt.type == 'L' ||
                  opt.type == 'I' ||
                  opt.type == 'J' ||
                  opt.type == 'T';
              final signed = !isUnsigned;
              BigInt n = v;
              if (isUnsigned && v.isNegative) {
                if (size < BinaryTypeSize.j) {
                  throw LuaError('overflow');
                }
                final mask = (BigInt.one << (size * 8)) - BigInt.one;
                n = v & mask;
              } else {
                final minVal = signed
                    ? -(BigInt.one << (size * 8 - 1))
                    : BigInt.zero;
                final maxVal = signed
                    ? (BigInt.one << (size * 8 - 1)) - BigInt.one
                    : (BigInt.one << (size * 8)) - BigInt.one;
                if (n < minVal || n > maxVal) {
                  throw LuaError('overflow');
                }
              }
              final packed = _packInt(n, size, endianness);
              bytes.addAll(packed);
            }
            i++;
            offset += BigInt.from(size);
            if (offset > maxAllowed) {
              throw LuaError('too long');
            }
            break;
          }
        case 's': // size-prefixed string with native integer size
          {
            final rawVal = getArg('string').raw;
            final encoded = rawVal is LuaString
                ? rawVal.bytes
                : utf8.encode(rawVal.toString());
            final size =
                opt.size ?? BinaryTypeSize.j; // Use lua_Integer size as default

            if (opt.size != null && (size < 1 || size > 16)) {
              throw LuaError('out of limits');
            }
            final maxVal = (BigInt.one << (size * 8)) - BigInt.one;
            if (BigInt.from(encoded.length) > maxVal) {
              throw LuaError('does not fit');
            }

            // Pack the length as an integer of the specified size
            final lengthBytes = _packInt(
              BigInt.from(encoded.length),
              size,
              endianness,
            );
            bytes.addAll(lengthBytes);
            bytes.addAll(encoded);

            i++;
            offset += BigInt.from(size + encoded.length);
            if (offset > maxAllowed) {
              throw LuaError('too long');
            }
            break;
          }
        case 'X':
          {
            int size;
            if (opt.size != null) {
              size = opt.size!;
            } else {
              if (i + 1 >= options.length) {
                throw LuaError('invalid next option');
              }
              final nextOpt = options[i + 1];
              switch (nextOpt.type) {
                case 'b':
                  size = BinaryTypeSize.b;
                  break;
                case 'B':
                  size = BinaryTypeSize.B;
                  break;
                case 'h':
                  size = BinaryTypeSize.h;
                  break;
                case 'H':
                  size = BinaryTypeSize.H;
                  break;
                case 'l':
                  size = BinaryTypeSize.l;
                  break;
                case 'L':
                  size = BinaryTypeSize.L;
                  break;
                case 'j':
                  size = BinaryTypeSize.j;
                  break;
                case 'J':
                  size = BinaryTypeSize.J;
                  break;
                case 'T':
                  size = BinaryTypeSize.T;
                  break;
                case 'f':
                  size = BinaryTypeSize.f;
                  break;
                case 'd':
                  size = BinaryTypeSize.d;
                  break;
                case 'n':
                  size = BinaryTypeSize.n;
                  break;
                case 'i':
                  size = nextOpt.size ?? BinaryTypeSize.i;
                  break;
                case 'I':
                  size = nextOpt.size ?? BinaryTypeSize.I;
                  break;
                default:
                  throw LuaError('invalid next option');
              }
            }
            final align = size > maxAlign ? maxAlign : size;
            final pad = alignTo(offset, align).toInt();
            if (offset + BigInt.from(pad) > maxAllowed) {
              throw LuaError('too long');
            }
            bytes.addAll(List.filled(pad, 0));
            offset += BigInt.from(pad);
            continue;
          }
        case 'x':
          if (offset + BigInt.one > maxAllowed) {
            throw LuaError('too long');
          }
          bytes.add(0);
          offset += BigInt.one;
          continue;
        case 'z':
          {
            final rawVal = getArg('string').raw;
            final encoded = rawVal is LuaString
                ? rawVal.bytes
                : utf8.encode(rawVal.toString());
            if (encoded.contains(0)) {
              throw LuaError('contains zeros');
            }
            bytes.addAll(encoded);
            bytes.add(0); // zero terminator
            i++;
            offset += BigInt.from(encoded.length + 1);
            if (offset > maxAllowed) {
              throw LuaError('too long');
            }
            break;
          }

        default:
          throw LuaError(
            "string.pack: option ' [${opt.type}] ' not implemented",
          );
      }
    }

    final result = LuaString.fromBytes(bytes);
    return Value(result);
  }
}

List<int> _packInt(BigInt value, int size, Endian endianness) {
  final mask = (BigInt.one << (size * 8)) - BigInt.one;
  var v = value & mask;
  final bytes = List<int>.filled(size, 0);
  if (endianness == Endian.little) {
    for (var b = 0; b < size; b++) {
      bytes[b] = ((v >> (8 * b)) & BigInt.from(0xFF)).toInt();
    }
  } else {
    for (var b = 0; b < size; b++) {
      bytes[size - b - 1] = ((v >> (8 * b)) & BigInt.from(0xFF)).toInt();
    }
  }
  return bytes;
}

class _StringPackSize implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.packsize requires format string");
    }
    final format = (args[0] as Value).raw.toString();

    // Use the new parser instead of character-by-character parsing
    try {
      final options = BinaryFormatParser.parse(format);
      BigInt offset = BigInt.zero;
      int maxAlign = 1;
      final maxAllowed = (BinaryTypeSize.j <= BinaryTypeSize.T)
          ? BigInt.from(NumberLimits.maxInteger)
          : (BigInt.one << (BinaryTypeSize.T * 8));

      BigInt alignTo(BigInt offset, int align) {
        if (align <= 1) return BigInt.zero;
        if ((align & (align - 1)) != 0) {
          throw LuaError("format asks for alignment not power of 2");
        }
        final mod = offset % BigInt.from(align);
        return mod == BigInt.zero ? BigInt.zero : BigInt.from(align) - mod;
      }

      void addSized(int size) {
        final align = size > maxAlign ? maxAlign : size;
        offset += alignTo(offset, align);
        offset += BigInt.from(size);
        if (offset > maxAllowed) {
          throw LuaError('too large');
        }
      }

      for (final opt in options) {
        switch (opt.type) {
          case '<':
          case '>':
          case '=':
            continue; // Endianness doesn't affect size
          case '!':
            if (opt.align == null) {
              maxAlign = BinaryTypeSize.j; // reset to default alignment
            } else {
              maxAlign = opt.align!;
            }
            continue;
          case 'c':
            if (opt.size == null) {
              throw LuaError("missing size for format option 'c'");
            }
            offset += BigInt.from(opt.size!);
            if (offset > maxAllowed) {
              throw LuaError('too large');
            }
            break;
          case 'b':
          case 'B':
            addSized(BinaryTypeSize.b);
            break;
          case 'h':
          case 'H':
            addSized(BinaryTypeSize.h);
            break;
          case 'l':
          case 'L':
            addSized(BinaryTypeSize.l);
            break;
          case 'j':
          case 'J':
            addSized(BinaryTypeSize.j);
            break;
          case 'T':
            addSized(BinaryTypeSize.T);
            break;
          case 'f':
            addSized(BinaryTypeSize.f);
            break;
          case 'd':
          case 'n':
            addSized(BinaryTypeSize.d);
            break;
          case 'i':
            addSized(opt.size ?? BinaryTypeSize.i);
            break;
          case 'I':
            addSized(opt.size ?? BinaryTypeSize.I);
            break;
          case 's':
          case 'z':
            throw LuaError('variable-length format');
          case 'x':
            offset += BigInt.one;
            if (offset > maxAllowed) {
              throw LuaError('too large');
            }
            break;
          case 'X':
            {
              int size;
              if (opt.size != null) {
                size = opt.size!;
              } else {
                final idx = options.indexOf(opt);
                if (idx + 1 >= options.length) {
                  throw LuaError('invalid next option');
                }
                final nextOpt = options[idx + 1];
                switch (nextOpt.type) {
                  case 'b':
                    size = BinaryTypeSize.b;
                    break;
                  case 'B':
                    size = BinaryTypeSize.B;
                    break;
                  case 'h':
                    size = BinaryTypeSize.h;
                    break;
                  case 'H':
                    size = BinaryTypeSize.H;
                    break;
                  case 'l':
                    size = BinaryTypeSize.l;
                    break;
                  case 'L':
                    size = BinaryTypeSize.L;
                    break;
                  case 'j':
                    size = BinaryTypeSize.j;
                    break;
                  case 'J':
                    size = BinaryTypeSize.J;
                    break;
                  case 'T':
                    size = BinaryTypeSize.T;
                    break;
                  case 'f':
                    size = BinaryTypeSize.f;
                    break;
                  case 'd':
                    size = BinaryTypeSize.d;
                    break;
                  case 'n':
                    size = BinaryTypeSize.n;
                    break;
                  case 'i':
                    size = nextOpt.size ?? BinaryTypeSize.i;
                    break;
                  case 'I':
                    size = nextOpt.size ?? BinaryTypeSize.I;
                    break;
                  default:
                    throw LuaError('invalid next option');
                }
              }
              final align = size > maxAlign ? maxAlign : size;
              final pad = alignTo(offset, align);
              offset += pad;
              continue;
            }
          default:
            throw LuaError.typeError("Invalid format option '${opt.type}'");
        }
      }
      return Value(offset.toInt());
    } catch (e) {
      if (e is LuaError) rethrow;
      throw LuaError('invalid format');
    }
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
    final binaryValue = args[1] as Value;
    final pos = args.length > 2 ? NumberUtils.toInt((args[2] as Value).raw) : 1;

    final results = <Value>[];
    final bytes = binaryValue.raw is LuaString
        ? (binaryValue.raw as LuaString).bytes
        : LuaString.fromDartString(binaryValue.raw.toString()).bytes;
    var startPos = pos;
    if (startPos < 0) {
      startPos = bytes.length + startPos + 1;
    }
    var offset = startPos - 1;
    Endian endianness = Endian.host;
    int maxAlign = 1;

    int alignTo(int offset, int align) {
      if (align <= 1) return 0;
      if ((align & (align - 1)) != 0) {
        throw LuaError("format asks for alignment not power of 2");
      }
      final mod = offset % align;
      return mod == 0 ? 0 : align - mod;
    }

    final options = BinaryFormatParser.parse(format);
    var i = 0;
    for (final opt in options) {
      switch (opt.type) {
        case '<':
          endianness = Endian.little;
          continue;
        case '>':
          endianness = Endian.big;
          continue;
        case '=':
          endianness = Endian.host;
          continue;
        case '!':
          if (opt.align == null) {
            maxAlign = BinaryTypeSize.j; // reset to default alignment
          } else {
            maxAlign = opt.align!;
            if ((maxAlign & (maxAlign - 1)) != 0) {
              throw LuaError("format asks for alignment not power of 2");
            }
          }
          continue;
        case 'c': // char array of size N (never needs alignment)
          final size = opt.size;
          if (size == null) {
            throw LuaError("missing size for format option 'c'");
          }
          if (offset > bytes.length) {
            throw LuaError.typeError('out of string');
          }
          if (offset + size - 1 >= bytes.length) {
            throw LuaError.typeError('too short');
          }
          final strBytes = bytes.sublist(offset, offset + size);
          try {
            final str = utf8.decode(strBytes);
            results.add(Value(str));
          } catch (_) {
            final luaStr = LuaString.fromBytes(Uint8List.fromList(strBytes));
            results.add(Value(luaStr));
          }
          offset += size;
          break;
        case 'b':
        case 'B':
        case 'h':
        case 'H':
        case 'l':
        case 'L':
        case 'j':
        case 'J':
        case 'T':
        case 'f':
        case 'd':
        case 'n':
        case 'i':
        case 'I':
          {
            int size;
            switch (opt.type) {
              case 'b':
                size = BinaryTypeSize.b;
                break;
              case 'B':
                size = BinaryTypeSize.B;
                break;
              case 'h':
                size = BinaryTypeSize.h;
                break;
              case 'H':
                size = BinaryTypeSize.H;
                break;
              case 'l':
                size = BinaryTypeSize.l;
                break;
              case 'L':
                size = BinaryTypeSize.L;
                break;
              case 'j':
                size = BinaryTypeSize.j;
                break;
              case 'J':
                size = BinaryTypeSize.J;
                break;
              case 'T':
                size = BinaryTypeSize.T;
                break;
              case 'f':
                size = BinaryTypeSize.f;
                break;
              case 'd':
                size = BinaryTypeSize.d;
                break;
              case 'n':
                size = BinaryTypeSize.n;
                break;
              case 'i':
                size = opt.size ?? BinaryTypeSize.i;
                break;
              case 'I':
                size = opt.size ?? BinaryTypeSize.I;
                break;
              default:
                size = 1;
                break;
            }
            final align = size > maxAlign ? maxAlign : size;
            final pad = alignTo(offset, align);
            offset += pad;
            if (offset + size - 1 >= bytes.length) {
              throw LuaError.typeError('too short');
            }

            // Handle float types differently from integer types
            if (opt.type == 'f') {
              final value = NumberUtils.unpackFloat32(
                bytes,
                offset,
                endianness,
              );
              results.add(Value(value));
            } else if (opt.type == 'd' || opt.type == 'n') {
              final value = NumberUtils.unpackFloat64(
                bytes,
                offset,
                endianness,
              );
              results.add(Value(value));
            } else {
              // Integer types
              int value;
              if (size > BinaryTypeSize.j) {
                var big = _unpackBigInt(bytes, offset, size, endianness);
                final isSigned =
                    opt.type == 'b' ||
                    opt.type == 'h' ||
                    opt.type == 'l' ||
                    opt.type == 'j' ||
                    opt.type == 'i';
                if (isSigned) {
                  big = big.toSigned(size * 8);
                }
                if (big.bitLength > 64) {
                  throw LuaError(
                    '$size-byte integer does not fit into Lua Integer',
                  );
                }
                final signed = big.toSigned(64);
                value = signed.toInt();
              } else {
                value = _unpackInt(bytes, offset, size, endianness);
                if ((opt.type == 'b' ||
                        opt.type == 'h' ||
                        opt.type == 'l' ||
                        opt.type == 'j' ||
                        opt.type == 'i') &&
                    size > 0) {
                  final signBit = 1 << ((size * 8) - 1);
                  final mask = (1 << (size * 8)) - 1;
                  if ((value & signBit) != 0) {
                    value = value - (mask + 1);
                  }
                }
              }
              // For unsigned types, no additional processing needed
              // Lua integers are always signed, so unsigned formats just affect packing, not unpacking
              results.add(Value(value));
            }
            offset += size;
            break;
          }
        case 's': // size-prefixed string with native integer size
          {
            final size =
                opt.size ?? BinaryTypeSize.j; // Use lua_Integer size as default

            if (offset + size - 1 >= bytes.length) {
              throw LuaError.typeError('too short');
            }

            // Read the length as an integer
            final length = _unpackInt(bytes, offset, size, endianness);
            offset += size;

            if (offset + length - 1 >= bytes.length) {
              throw LuaError.typeError('too short');
            }

            final segment = bytes.sublist(offset, offset + length);
            try {
              final str = utf8.decode(segment);
              results.add(Value(str));
            } catch (_) {
              final luaStr = LuaString.fromBytes(Uint8List.fromList(segment));
              results.add(Value(luaStr));
            }
            offset += length;
            break;
          }
        case 'X':
          {
            int size;
            if (opt.size != null) {
              size = opt.size!;
            } else {
              if (i + 1 >= options.length) {
                throw LuaError('invalid next option');
              }
              final nextOpt = options[i + 1];
              switch (nextOpt.type) {
                case 'b':
                  size = BinaryTypeSize.b;
                  break;
                case 'B':
                  size = BinaryTypeSize.B;
                  break;
                case 'h':
                  size = BinaryTypeSize.h;
                  break;
                case 'H':
                  size = BinaryTypeSize.H;
                  break;
                case 'l':
                  size = BinaryTypeSize.l;
                  break;
                case 'L':
                  size = BinaryTypeSize.L;
                  break;
                case 'j':
                  size = BinaryTypeSize.j;
                  break;
                case 'J':
                  size = BinaryTypeSize.J;
                  break;
                case 'T':
                  size = BinaryTypeSize.T;
                  break;
                case 'f':
                  size = BinaryTypeSize.f;
                  break;
                case 'd':
                  size = BinaryTypeSize.d;
                  break;
                case 'n':
                  size = BinaryTypeSize.n;
                  break;
                case 'i':
                  size = nextOpt.size ?? BinaryTypeSize.i;
                  break;
                case 'I':
                  size = nextOpt.size ?? BinaryTypeSize.I;
                  break;
                default:
                  throw LuaError('invalid next option');
              }
            }
            final align = size > maxAlign ? maxAlign : size;
            final pad = alignTo(offset, align);
            offset += pad;
            continue;
          }
        case 'x':
          if (offset >= bytes.length) {
            throw LuaError.typeError('too short');
          }
          offset += 1;
          continue;
        case 'z':
          {
            var end = bytes.indexOf(0, offset);
            if (end == -1) {
              throw LuaError.typeError(
                "unpack: unfinished string for format 'z'",
              );
            }
            var strBytes = bytes.sublist(offset, end);
            try {
              final str = utf8.decode(strBytes);
              results.add(Value(str));
            } catch (_) {
              final luaStr = LuaString.fromBytes(Uint8List.fromList(strBytes));
              results.add(Value(luaStr));
            }
            offset = end + 1;
            break;
          }

        default:
          // TODO: Implement all options
          throw LuaError(
            "string.unpack: option ' [${opt.type}] ' not implemented",
          );
      }
      i++;
    }
    results.add(Value(offset + 1)); // Next position after unpacking
    return results;
  }
}

int _unpackInt(List<int> bytes, int offset, int size, Endian endianness) {
  int value = 0;
  if (endianness == Endian.little) {
    for (var b = 0; b < size; b++) {
      value |= (bytes[offset + b] << (8 * b));
    }
  } else {
    for (var b = 0; b < size; b++) {
      value |= (bytes[offset + b] << (8 * (size - b - 1)));
    }
  }
  return value;
}

BigInt _unpackBigInt(List<int> bytes, int offset, int size, Endian endianness) {
  var value = BigInt.zero;
  if (endianness == Endian.little) {
    for (var b = size - 1; b >= 0; b--) {
      value = (value << 8) | BigInt.from(bytes[offset + b]);
    }
  } else {
    for (var b = 0; b < size; b++) {
      value = (value << 8) | BigInt.from(bytes[offset + b]);
    }
  }
  return value;
}

class _StringUpper implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.upper requires a string argument");
    }

    final value = args[0] as Value;

    // Handle LuaString specially to preserve byte representation
    if (value.raw is LuaString) {
      final luaStr = value.raw as LuaString;
      final bytes = luaStr.bytes;
      final resultBytes = <int>[];

      // Apply uppercase transformation byte by byte
      for (final byte in bytes) {
        if (byte >= 97 && byte <= 122) {
          // 'a' to 'z'
          resultBytes.add(byte - 32); // Convert to uppercase
        } else {
          resultBytes.add(byte); // Keep unchanged
        }
      }

      // For better interop, return regular strings when they only contain ASCII
      final isAsciiOnly = resultBytes.every((b) => b <= 127);
      if (isAsciiOnly) {
        final resultString = String.fromCharCodes(resultBytes);
        return Value(resultString);
      } else {
        return Value(LuaString.fromBytes(Uint8List.fromList(resultBytes)));
      }
    } else {
      // For normal string operations, use Dart's string methods for better interop
      final str = value.raw.toString();
      return Value(str.toUpperCase());
    }
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
