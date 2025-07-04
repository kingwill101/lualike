import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/pattern.dart';
import 'package:lualike/src/stdlib/format_parser.dart';
import 'package:petitparser/petitparser.dart';

import '../value_class.dart';
import 'number_utils.dart';
import '../lua_string.dart';

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
      result.add(Value(bytes[i - 1]));
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
    // Return Dart string for better interop - use latin1 to handle all byte values 0-255
    final str = String.fromCharCodes(bytes);
    return Value(str);
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
      final regexp = LuaPattern.toRegExp(pattern);
      final substring = str.substring(start);
      final match = regexp.firstMatch(substring);

      if (match == null) return Value(null);

      // In Lua, string.find returns the 1-based indices of the match
      final startPos = start + match.start + 1;
      final endPos = start + match.end;

      final results = [Value(startPos), Value(endPos)];

      // Add captured groups if any
      for (var i = 1; i <= match.groupCount; i++) {
        final group = match.group(i);
        if (group != null) {
          results.add(Value(group));
        }
      }

      if (match.groupCount > 0) {
        return Value.multi(results);
      }

      return results;
    } catch (e) {
      throw Exception("malformed pattern: $e");
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

String _typeName(dynamic value) {
  if (value == null) return 'nil';
  if (value is bool) return 'boolean';
  if (value is num) return 'number';
  if (value is String) return 'string';
  if (value is List) return 'table';
  if (value is Function) return 'function';
  return value.runtimeType.toString();
}

String _escapeLuaString(String str) {
  // Lua's %q format escapes quotes, backslashes, newlines, and control characters
  final buffer = StringBuffer();
  final bytes = str.codeUnits;
  int i = 0;
  while (i < bytes.length) {
    final code = bytes[i];
    if (code == 92) {
      // backslash
      buffer.write('\\\\');
    } else if (code == 34) {
      // quote
      buffer.write('\\"');
    } else if (code == 10) {
      // newline - special case: backslash + literal newline
      buffer.write('\\\n');
    } else if (code == 0) {
      // null - check if next character is a digit
      if (i + 1 < bytes.length && bytes[i + 1] >= 48 && bytes[i + 1] <= 57) {
        buffer.write('\\000');
      } else {
        buffer.write('\\0');
      }
    } else if (code == 7) {
      // bell
      buffer.write('\\a');
    } else if (code == 8) {
      // backspace
      buffer.write('\\b');
    } else if (code == 12) {
      // form feed
      buffer.write('\\f');
    } else if (code == 13) {
      // carriage return
      buffer.write('\\r');
    } else if (code == 9) {
      // tab
      buffer.write('\\t');
    } else if (code == 11) {
      // vertical tab
      buffer.write('\\v');
    } else if (code < 32 || code == 127) {
      // other control characters - use minimal digits unless next char is digit
      String codeStr = code.toString();
      if (i + 1 < bytes.length && bytes[i + 1] >= 48 && bytes[i + 1] <= 57) {
        codeStr = codeStr.padLeft(3, '0');
      }
      buffer.write('\\$codeStr');
    } else if (code >= 0x80) {
      // Try to decode as UTF-8 sequence
      try {
        final decoded = utf8.decode([code], allowMalformed: true);
        if (decoded == '\uFFFD') {
          buffer.write('\\ufffd');
        } else {
          buffer.write(decoded);
        }
      } catch (_) {
        buffer.write('\\ufffd');
      }
    } else {
      buffer.write(String.fromCharCode(code));
    }
    i++;
  }
  return buffer.toString();
}

String _formatString(_FormatContext ctx) {
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;

  String str;
  if (rawValue == null) {
    str = 'nil';
  } else if (rawValue is bool) {
    str = rawValue.toString(); // true/false are already correct in Dart
  } else if (rawValue is LuaString) {
    // For LuaString, we need to handle it specially to preserve byte-level precision
    final luaStr = rawValue;
    if (ctx.precision.isNotEmpty) {
      final precValue = ctx.precisionValue;
      if (precValue < luaStr.length) {
        // Create a new LuaString with truncated bytes, then convert to string
        final truncatedBytes = luaStr.bytes.sublist(0, precValue);
        final truncatedLuaStr = LuaString(truncatedBytes);
        return _applyPadding(truncatedLuaStr.toString(), ctx);
      }
    }
    str = luaStr.toString();
  } else {
    str = rawValue.toString();
  }

  // Handle precision for regular strings - truncate if needed
  String result = str;
  if (ctx.precision.isNotEmpty) {
    final precValue = ctx.precisionValue;
    if (precValue < str.length) {
      result = str.substring(0, precValue);
    }
  }

  return _applyPadding(result, ctx);
}

String _formatCharacter(_FormatContext ctx) {
  if (ctx.value is! num && ctx.value is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${_typeName(ctx.value)})",
    );
  }

  final charCode = NumberUtils.toInt(ctx.value);
  final char = String.fromCharCode(charCode);

  return _applyPadding(char, ctx);
}

String _formatQuoted(_FormatContext ctx) {
  // Extract the raw value from Value objects
  final rawValue = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;

  if (rawValue == null) {
    return 'nil';
  } else if (rawValue is bool) {
    return rawValue ? 'true' : 'false';
  } else if (rawValue is num) {
    return rawValue.toString();
  } else {
    final str = rawValue.toString();
    final escaped = _escapeLuaString(str);
    return '"$escaped"';
  }
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

String _formatFloat(_FormatContext ctx, bool uppercase) {
  if (ctx.value is! num && ctx.value is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${_typeName(ctx.value)})",
    );
  }

  final doubleValue = NumberUtils.toDouble(ctx.value);

  // Handle special values
  if (doubleValue.isNaN) return uppercase ? 'NAN' : 'nan';
  if (doubleValue.isInfinite) {
    final sign = doubleValue.isNegative ? '-' : (ctx.showSign ? '+' : '');
    return uppercase ? '${sign}INF' : '${sign}inf';
  }

  String result = doubleValue.toStringAsFixed(ctx.precisionValue);

  if (ctx.showSign && !doubleValue.isNegative) {
    result = '+$result';
  } else if (ctx.spacePrefix && !doubleValue.isNegative) {
    result = ' $result';
  }

  return _applyPadding(result, ctx);
}

String _formatScientific(_FormatContext ctx, bool uppercase) {
  if (ctx.value is! num && ctx.value is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${_typeName(ctx.value)})",
    );
  }

  final doubleValue = NumberUtils.toDouble(ctx.value);

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
  if (ctx.value is! num && ctx.value is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${_typeName(ctx.value)})",
    );
  }

  double v = NumberUtils.toDouble(ctx.value);

  if (v.isNaN) return uppercase ? 'NAN' : 'nan';
  if (v.isInfinite) {
    final sign = v.isNegative ? '-' : (ctx.showSign ? '+' : '');
    return uppercase ? '${sign}INF' : '${sign}inf';
  }

  String sign = '';
  if (v.isNegative) {
    sign = '-';
    v = -v;
  } else if (ctx.showSign) {
    sign = '+';
  } else if (ctx.spacePrefix) {
    sign = ' ';
  }

  int exponent = 0;
  if (v != 0.0) {
    exponent = (math.log(v) / math.ln2).floor();
    v /= math.pow(2, exponent);
  }

  int precision = ctx.precision.isNotEmpty ? ctx.precisionValue : 13;
  StringBuffer hex = StringBuffer();
  hex.write(v.floor().toRadixString(16));
  double frac = v - v.floor();
  if (precision > 0 || ctx.alternative) hex.write('.');
  for (int i = 0; i < precision; i++) {
    frac *= 16;
    int digit = frac.floor();
    hex.write(digit.toRadixString(16));
    frac -= digit;
  }

  String result = '0x${hex.toString()}p${exponent >= 0 ? '+' : ''}$exponent';
  if (uppercase) result = result.toUpperCase();
  result = sign + result;

  return _applyPadding(result, ctx);
}

String _formatInteger(_FormatContext ctx, {bool unsigned = false}) {
  if (ctx.value is! num && ctx.value is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${_typeName(ctx.value)})",
    );
  }

  var intValue = NumberUtils.toInt(ctx.value);
  if (unsigned) intValue = intValue.abs();

  String result;
  if (ctx.precision.isNotEmpty) {
    final precValue = ctx.precisionValue;
    result = intValue.toString().padLeft(precValue, '0');
  } else {
    result = intValue.toString();
  }

  if (ctx.showSign && intValue >= 0) {
    result = '+$result';
  } else if (ctx.spacePrefix && intValue >= 0) {
    result = ' $result';
  }

  return _applyPadding(result, ctx);
}

String _formatHex(_FormatContext ctx, bool uppercase) {
  if (ctx.value is! num && ctx.value is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${_typeName(ctx.value)})",
    );
  }

  final intValue = NumberUtils.toInt(ctx.value);
  String result = intValue.toRadixString(16);
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
  int get precisionValue => precision.isEmpty
      ? 6
      : int.parse(
          precision.startsWith('.') ? precision.substring(1) : precision,
        );
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
  if (ctx.value is! num && ctx.value is! BigInt) {
    throw LuaError.typeError(
      "bad argument #${ctx.valueIndex} to 'format' (number expected, got ${_typeName(ctx.value)})",
    );
  }

  final intValue = NumberUtils.toInt(ctx.value);
  String result = intValue.toRadixString(8);

  if (ctx.alternative && intValue != 0) {
    result = '0$result';
  }

  if (ctx.precision.isNotEmpty) {
    final precValue = ctx.precisionValue;
    result = result.padLeft(precValue, '0');
  }

  return _applyPadding(result, ctx);
}

class _StringFormat implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "missing argument #1 to 'format' (string expected)",
      );
    }

    final formatStringValue = args[0] as Value;
    if (formatStringValue.raw is! String &&
        formatStringValue.raw is! LuaString) {
      throw LuaError.typeError(
        "bad argument #1 to 'format' (string expected, got ${_typeName(formatStringValue.raw)}) ",
      );
    }

    final formatString = formatStringValue.raw.toString();
    final buffer = StringBuffer();
    var argIndex = 1;

    try {
      final parser = FormatStringParser.formatStringParser;
      final result = parser.parse(formatString);

      if (result is! Success) {
        throw FormatException(
          "Invalid format string: ${result.message} at ${result.position}",
        );
      }

      final formatParts = result.value;

      for (final part in formatParts) {
        if (part is LiteralPart) {
          buffer.write(part.text);
        } else if (part is SpecifierPart) {
          if (part.specifier == '%') {
            buffer.write('%');
            continue;
          }

          if (argIndex >= args.length) {
            throw LuaError(
              "no value for format specifier '%${part.specifier}'",
            );
          }

          final currentArg = args[argIndex];
          Logger.debug(
            'currentArg type: ${currentArg.runtimeType}, value: $currentArg, specifier: ${part.specifier}',
            category: 'StringLib',
          );
          final ctx = _FormatContext(
            value: (currentArg is Value) ? currentArg.raw : currentArg,
            valueIndex: argIndex + 1,
            flags: part.flags.split('').toSet(),
            width: part.width ?? '',
            precision: part.precision ?? '',
            specifier: part.specifier,
          );

          switch (part.specifier) {
            case 'd':
            case 'i':
            case 'u': // Lua treats 'u' as signed integer format
              buffer.write(
                _formatInteger(ctx, unsigned: part.specifier == 'u'),
              );
              break;
            case 'o':
              buffer.write(_formatOctal(ctx));
              break;
            case 'x':
              buffer.write(_formatHex(ctx, false));
              break;
            case 'X':
              buffer.write(_formatHex(ctx, true));
              break;
            case 'f':
            case 'F':
              buffer.write(_formatFloat(ctx, part.specifier == 'F'));
              break;
            case 'e':
              buffer.write(_formatScientific(ctx, false));
              break;
            case 'E':
              buffer.write(_formatScientific(ctx, true));
              break;
            case 'a':
              buffer.write(_formatHexFloat(ctx, false));
              break;
            case 'A':
              buffer.write(_formatHexFloat(ctx, true));
              break;
            case 'c':
              buffer.write(_formatCharacter(ctx));
              break;
            case 's':
              buffer.write(_formatString(ctx));
              break;
            case 'q':
              buffer.write(_formatQuoted(ctx));
              break;
            case 'p':
              buffer.write(_formatPointer(ctx));
              break;
            default:
              throw LuaError.typeError(
                "Invalid format specifier: %${part.specifier}",
              );
          }
          argIndex++;
        }
      }
    } on FormatException catch (e) {
      throw LuaError("bad argument #1 to 'format' (${e.message})");
    } catch (e) {
      throw LuaError("Error in string.format: $e");
    }

    return Value(buffer.toString());
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
      final regexp = LuaPattern.toRegExp(pattern);
      final matches = regexp.allMatches(str).toList();
      var currentIndex = 0;

      // Return iterator function that follows Lua's behavior
      return Value((List<Object?> iterArgs) {
        if (currentIndex >= matches.length) {
          return Value(null);
        }

        final match = matches[currentIndex++];
        if (match.groupCount == 0) {
          // No captures, return the whole match as a string
          final wholeMatch = match.group(0);
          return Value(wholeMatch);
        }

        // Return all captures as separate values
        final captures = <Value>[];
        for (var i = 1; i <= match.groupCount; i++) {
          final group = match.group(i);
          if (group != null) {
            captures.add(Value(group));
          } else {
            captures.add(Value(null));
          }
        }

        // For Lua compatibility, we need to return multiple values
        // but not as a list - they should be separate return values
        if (captures.length == 1) {
          return captures[0];
        } else {
          // Use Value.multi to return multiple values
          // This will be handled by the VM to bind multiple variables in a for-in loop
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
      final regexp = LuaPattern.toRegExp(pattern);

      String result;
      if (repl.raw is Function) {
        final replFunc = repl.raw as Function;
        final buffer = StringBuffer();
        var lastEnd = 0;
        final matches = regexp.allMatches(str);

        for (final match in matches) {
          if (n != -1 && count >= n) {
            break;
          }
          buffer.write(str.substring(lastEnd, match.start));

          final captures = <Value>[];
          if (match.groupCount == 0) {
            captures.add(Value(match.group(0)));
          } else {
            for (var i = 1; i <= match.groupCount; i++) {
              captures.add(Value(match.group(i)));
            }
          }

          var replacement = replFunc(captures);
          if (replacement is Future) {
            replacement = await replacement;
          }

          if (replacement == null ||
              (replacement is Value &&
                  (replacement.isNil || replacement.raw == false))) {
            buffer.write(match.group(0));
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

        for (final match in regexp.allMatches(str)) {
          if (n != -1 && count >= n) {
            break;
          }
          buffer.write(str.substring(lastEnd, match.start));

          final key = Value(match.group(0)!);
          var replacement = replTable[key];

          if (replacement is Value) {
            replacement = replacement.raw;
          }

          if (replacement != null && replacement != false) {
            buffer.write(replacement.toString());
            count++;
          } else {
            buffer.write(match.group(0)!);
          }
          lastEnd = match.end;
        }

        if (lastEnd < str.length) {
          buffer.write(str.substring(lastEnd));
        }
        result = buffer.toString();
      } else if (repl.raw is String || repl.raw is LuaString) {
        final replStr = repl.raw.toString();
        result = str.replaceAllMapped(regexp, (match) {
          if (n != -1 && count >= n) return match.group(0)!;

          String replacement = replStr;
          bool captureReplaced = false;

          // Handle %0, %1, %2... captures in the replacement string
          for (int i = 0; i <= match.groupCount; i++) {
            final capture = match.group(i);
            // Only replace if the capture exists and the placeholder is found
            final placeholder = '%$i';
            if (replacement.contains(placeholder)) {
              replacement = replacement.replaceAll(placeholder, capture ?? '');
              captureReplaced = true;
            }
          }
          // Handle %% (literal percent) - this was previously handled outside, but now needs to be here
          if (replacement.contains('%%')) {
            replacement = replacement.replaceAll('%%', '%');
            captureReplaced =
                true; // Mark as replaced if literal percent was processed
          }

          // Lua 5.4 behavior: if no captures replaced but it's a string literal replacement, count it
          // If `captureReplaced` is true, we already incremented `count`.
          // If `captureReplaced` is false, it means `replStr` did not contain any %n or %%,
          // so we treat `replStr` as a literal replacement for the whole match.
          if (captureReplaced || replStr.isNotEmpty) {
            // Lua counts replacements even if no captures are used
            count++;
          }

          return replacement;
        });
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

    final substring = str.substring(init);
    try {
      final regexp = LuaPattern.toRegExp(pattern);
      final hasMatch = regexp.hasMatch(substring);

      final match = regexp.firstMatch(substring);
      if (match == null) {
        return Value(null);
      }

      if (match.groupCount > 0) {
        // Return captures
        List<Value> captures = [];
        for (int i = 1; i <= match.groupCount; i++) {
          captures.add(Value(match.group(i)));
        }

        if (captures.length == 1) {
          return captures[0];
        } else {
          return Value(captures);
        }
      } else {
        // Return whole match
        return Value(match.group(0));
      }
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

    Uint8List originalBytes;
    if (value.raw is LuaString) {
      originalBytes = (value.raw as LuaString).bytes;
    } else {
      originalBytes = utf8.encode(value.raw.toString());
    }

    Uint8List separatorBytes = Uint8List(0);
    if (separatorValue != null) {
      if (separatorValue.raw is LuaString) {
        separatorBytes = (separatorValue.raw as LuaString).bytes;
      } else {
        separatorBytes = utf8.encode(separatorValue.raw.toString());
      }
    }

    if (count <= 0) {
      return StringInterning.createStringValue("");
    }

    const maxAllowedLength = 2000000000;
    int expectedTotalLength;

    if (separatorBytes.isEmpty) {
      if (originalBytes.length > maxAllowedLength ~/ count) {
        throw LuaError("resulting string too large");
      }
      expectedTotalLength = originalBytes.length * count;
    } else {
      if (originalBytes.length > maxAllowedLength ~/ count) {
        throw LuaError("resulting string too large");
      }
      final lengthOfRepeatedStrings = originalBytes.length * count;

      final numSeparators = count - 1;
      if (numSeparators > 0 &&
          separatorBytes.length > maxAllowedLength ~/ numSeparators) {
        throw LuaError("resulting string too large");
      }
      final lengthOfSeparators = separatorBytes.length * numSeparators;

      if (lengthOfRepeatedStrings > maxAllowedLength - lengthOfSeparators) {
        throw LuaError("resulting string too large");
      }
      expectedTotalLength = lengthOfRepeatedStrings + lengthOfSeparators;
    }

    if (expectedTotalLength > maxAllowedLength) {
      throw LuaError("resulting string too large");
    }

    final Uint8List resultBytes = Uint8List(expectedTotalLength);
    int currentOffset = 0;
    for (int i = 0; i < count; i++) {
      resultBytes.setRange(
        currentOffset,
        currentOffset + originalBytes.length,
        originalBytes,
      );
      currentOffset += originalBytes.length;
      if (i < count - 1) {
        resultBytes.setRange(
          currentOffset,
          currentOffset + separatorBytes.length,
          separatorBytes,
        );
        currentOffset += separatorBytes.length;
      }
    }

    final resultString = utf8.decode(resultBytes, allowMalformed: true);
    return Value(resultString);
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
