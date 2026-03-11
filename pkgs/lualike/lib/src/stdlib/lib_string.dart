import 'dart:collection';
import 'dart:convert' as convert;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart' show ListEquality;
import 'package:lualike/lualike.dart';
import 'package:lualike/src/binary_type_size.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/intern.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/parsers/pattern.dart' as lpc;
import 'package:lualike/src/stdlib/lib_utf8.dart' show UTF8Lib;
import 'package:lualike/src/upvalue.dart';
import 'package:lualike/src/utils/type.dart' show getLuaType;

import 'library.dart';

const int _luaPatternCacheSize = 128;
final LinkedHashMap<String, lpc.LuaPattern> _luaPatternCache =
    LinkedHashMap<String, lpc.LuaPattern>();

lpc.LuaPattern _compileLuaPatternCached(String pattern) {
  final cached = _luaPatternCache.remove(pattern);
  if (cached != null) {
    _luaPatternCache[pattern] = cached;
    return cached;
  }

  final compiled = switch (() {
    try {
      return lpc.LuaPattern.compile(pattern);
    } on lpc.LuaPatternTooComplex {
      throw LuaError('pattern too complex');
    }
  }()) {
    final lpc.LuaPattern compiled => compiled,
  };
  _luaPatternCache[pattern] = compiled;
  if (_luaPatternCache.length > _luaPatternCacheSize) {
    _luaPatternCache.remove(_luaPatternCache.keys.first);
  }
  return compiled;
}

bool _isAnchoredLazyWholeStringPattern(String pattern) => pattern == r'^.-$';

bool _isAnchoredWhitespaceTrimCapturePattern(String pattern) =>
    pattern == r'^%s*(.-)%s*$';

Match? _matchAnchoredWhitespaceTrimCapture(String input) =>
    RegExp(r'^\s*(.*?)\s*$', dotAll: true).firstMatch(input);

bool _containsNonAscii(String value) =>
    value.codeUnits.any((unit) => unit > 0x7F);

bool _shouldUseBytePatternProcessing(dynamic subject, dynamic pattern) =>
    subject is LuaString ||
    pattern is LuaString ||
    (subject is String && _containsNonAscii(subject)) ||
    (pattern is String && _containsNonAscii(pattern));

String _toPatternProcessingString(dynamic value, {required bool byteLevel}) {
  if (!byteLevel) {
    return value is LuaString ? value.toString() : value.toString();
  }

  final bytes = switch (value) {
    LuaString luaString => luaString.bytes,
    String string => Uint8List.fromList(convert.utf8.encode(string)),
    _ => Uint8List.fromList(convert.utf8.encode(value.toString())),
  };
  return String.fromCharCodes(bytes);
}

String _stringifyPatternReplacement(dynamic value, {required bool byteLevel}) {
  final raw = value is Value ? value.raw : value;
  if (!byteLevel) {
    return raw.toString();
  }
  return _toPatternProcessingString(raw, byteLevel: true);
}

dynamic _collapsePatternReplacementResult(dynamic value) {
  if (value is Value && value.isMulti) {
    final raw = value.raw;
    if (raw is List && raw.isNotEmpty) {
      return raw.first;
    }
    return Value(null);
  }
  if (value is List) {
    return value.isNotEmpty ? value.first : Value(null);
  }
  return value;
}

String _gsubReplacementTypeName(dynamic value) {
  final raw = value is Value ? value.raw : value;
  return switch (raw) {
    Map _ => 'table',
    Function _ => 'function',
    bool _ => 'boolean',
    null => 'nil',
    _ => NumberUtils.typeName(raw),
  };
}

dynamic _validateGsubReplacementValue(dynamic value) {
  final raw = value is Value ? value.raw : value;
  if (raw == null || raw == false) {
    return raw;
  }
  if (raw is String || raw is LuaString || raw is num || raw is BigInt) {
    return raw;
  }
  throw LuaError(
    'invalid replacement value (a ${_gsubReplacementTypeName(raw)})',
  );
}

String _applyGsubReplacementTemplate(String template, lpc.LuaMatch match) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < template.length) {
    final ch = template[index];
    if (ch != '%') {
      buffer.write(ch);
      index++;
      continue;
    }
    if (index + 1 >= template.length) {
      throw LuaError("invalid use of '%'");
    }
    final next = template[index + 1];
    if (next == '%') {
      buffer.write('%');
      index += 2;
      continue;
    }
    final digit = int.tryParse(next);
    if (digit == null) {
      throw LuaError("invalid use of '%'");
    }
    final replacement = switch (digit) {
      0 => match.match,
      1 when match.captures.isEmpty => match.match,
      _ when digit > match.captures.length => throw LuaError(
        'invalid capture index %$digit',
      ),
      _ => match.captures[digit - 1] ?? '',
    };
    buffer.write(replacement);
    index += 2;
  }
  return buffer.toString();
}

Value _valueFromPatternSlice(String value, {required bool byteLevel}) {
  if (!byteLevel) {
    return Value(value);
  }
  return Value(LuaString.fromBytes(Uint8List.fromList(value.codeUnits)));
}

class _RegexBackreferencePattern {
  _RegexBackreferencePattern(this.regex, this.positionCaptureKinds);

  final RegExp regex;
  final Map<int, _PositionCaptureKind> positionCaptureKinds;
}

enum _PositionCaptureKind { start, end }

String? _regexClassForLuaClass(String letter) {
  final lower = letter.toLowerCase();
  final cls = switch (lower) {
    'a' => 'A-Za-z',
    'd' => '0-9',
    'l' => 'a-z',
    'u' => 'A-Z',
    'w' => '0-9A-Za-z_',
    'x' => '0-9A-Fa-f',
    'z' => r'\x00',
    's' => r'\s',
    'p' => r"""!-/:-@\[-`{-~""",
    _ => null,
  };
  if (cls == null) {
    return null;
  }
  if (lower == 's') {
    return letter == lower ? cls : r'\S';
  }
  return letter == lower ? '[$cls]' : '[^$cls]';
}

_RegexBackreferencePattern? _translateLuaBackreferencePattern(String pattern) {
  final regex = StringBuffer();
  final positionCaptureKinds = <int, _PositionCaptureKind>{};
  var captureCount = 0;
  var index = 0;

  while (index < pattern.length) {
    final ch = pattern[index];

    if (ch == '[') {
      final classBuffer = StringBuffer('[');
      index++;
      if (index < pattern.length && pattern[index] == '^') {
        classBuffer.write('^');
        index++;
      }
      if (index < pattern.length && pattern[index] == ']') {
        classBuffer.write(r'\]');
        index++;
      }
      while (index < pattern.length && pattern[index] != ']') {
        if (pattern[index] == '%' && index + 1 < pattern.length) {
          final translated = _regexClassForLuaClass(pattern[index + 1]);
          if (translated != null) {
            final classBody = translated.startsWith('[')
                ? translated.substring(1, translated.length - 1)
                : translated;
            classBuffer.write(classBody);
            index += 2;
            continue;
          }
          classBuffer.write(RegExp.escape(pattern[index + 1]));
          index += 2;
          continue;
        }
        classBuffer.write(pattern[index]);
        index++;
      }
      if (index >= pattern.length) {
        return null;
      }
      classBuffer.write(']');
      regex.write(classBuffer.toString());
      index++;
      continue;
    }

    if (ch == '%') {
      if (index + 1 >= pattern.length) {
        return null;
      }
      final next = pattern[index + 1];
      if (RegExp(r'[1-9]').hasMatch(next)) {
        regex.write(r'\');
        regex.write(next);
        index += 2;
        continue;
      }
      final translated = _regexClassForLuaClass(next);
      if (translated != null) {
        regex.write(translated);
        index += 2;
        continue;
      }
      if (next == 'b' || next == 'f') {
        return null;
      }
      regex.write(RegExp.escape(next));
      index += 2;
      continue;
    }

    if (ch == '(') {
      if (index + 1 < pattern.length && pattern[index + 1] == ')') {
        captureCount++;
        final remaining = pattern.substring(index + 2);
        final atLeadingPosition = regex.isEmpty || regex.toString() == '^';
        final atTrailingPosition = remaining.isEmpty || remaining == r'$';
        if (!atLeadingPosition && !atTrailingPosition) {
          return null;
        }
        positionCaptureKinds[captureCount] = atLeadingPosition
            ? _PositionCaptureKind.start
            : _PositionCaptureKind.end;
        regex.write('()');
        index += 2;
        continue;
      }
      captureCount++;
      regex.write('(');
      index++;
      continue;
    }

    if (ch == ')') {
      regex.write(')');
      index++;
      continue;
    }

    if (ch == '.') {
      regex.write(r'[\s\S]');
      index++;
      continue;
    }

    if (ch == '*') {
      regex.write('*');
      index++;
      continue;
    }

    if (ch == '+') {
      regex.write('+');
      index++;
      continue;
    }

    if (ch == '?') {
      regex.write('?');
      index++;
      continue;
    }

    if (ch == '-') {
      regex.write('*?');
      index++;
      continue;
    }

    if (ch == '^' && index == 0) {
      regex.write('^');
      index++;
      continue;
    }

    if (ch == r'$' && index == pattern.length - 1) {
      regex.write(r'$');
      index++;
      continue;
    }

    regex.write(RegExp.escape(ch));
    index++;
  }

  return _RegexBackreferencePattern(
    RegExp(regex.toString(), dotAll: true),
    positionCaptureKinds,
  );
}

bool _shouldPreferRegexPatternEngine({
  required String subject,
  required String pattern,
  required bool byteLevel,
}) =>
    !byteLevel &&
    subject.length >= 8192 &&
    _translateLuaBackreferencePattern(pattern) != null;

({bool supported, int? start, int? end})? _tryFastAnchoredLiteralTailFind(
  String subject,
  String pattern, {
  required int start,
}) {
  if (start != 0 || !pattern.startsWith('^') || !pattern.endsWith(r'$')) {
    return null;
  }
  if (pattern.length case final len when len != 6 && len != 7) {
    return null;
  }
  final repeatedLiteral = pattern[1];
  final repetition = pattern[2];
  if ((repetition != '*' && repetition != '-') ||
      pattern[3] != '.' ||
      pattern[4] != '?') {
    return null;
  }

  bool allButMaybeLastMatch() {
    if (subject.isEmpty) {
      return true;
    }
    for (var index = 0; index < subject.length - 1; index++) {
      if (subject[index] != repeatedLiteral) {
        return false;
      }
    }
    return true;
  }

  if (pattern.length == 6) {
    return allButMaybeLastMatch()
        ? (supported: true, start: 1, end: subject.length)
        : (supported: true, start: null, end: null);
  }

  final suffixLiteral = pattern[5];
  if (subject.isEmpty || subject[subject.length - 1] != suffixLiteral) {
    return (supported: true, start: null, end: null);
  }
  if (subject.length == 1) {
    return (supported: true, start: 1, end: 1);
  }

  for (var index = 0; index < subject.length - 2; index++) {
    if (subject[index] != repeatedLiteral) {
      return (supported: true, start: null, end: null);
    }
  }
  return (supported: true, start: 1, end: subject.length);
}

List<Value> _capturesFromRegexMatch(
  Match match,
  _RegexBackreferencePattern translation, {
  required bool byteLevel,
}) {
  final captures = <Value>[];
  for (var groupIndex = 1; groupIndex <= match.groupCount; groupIndex++) {
    final positionKind = translation.positionCaptureKinds[groupIndex];
    if (positionKind != null) {
      captures.add(
        Value(switch (positionKind) {
          _PositionCaptureKind.start => match.start + 1,
          _PositionCaptureKind.end => match.end + 1,
        }),
      );
      continue;
    }
    final capture = match.group(groupIndex);
    captures.add(
      capture == null
          ? Value(null)
          : _valueFromPatternSlice(capture, byteLevel: byteLevel),
    );
  }
  return captures;
}

int _requireIntegerRepresentation(dynamic value) {
  final integer = NumberUtils.tryToInteger(value);
  if (integer != null) {
    return integer;
  }
  if (value is num ||
      value is BigInt ||
      value is String ||
      value is LuaString) {
    throw LuaError('number has no integer representation');
  }
  throw LuaError.typeError(
    'number expected, got ${NumberUtils.typeName(value)}',
  );
}

bool _isMethodSyntaxCall(BuiltinFunction builtin) =>
    builtin.interpreter?.callStack.top?.callNode is MethodCall;

Value _requireStringLibrarySubject(
  BuiltinFunction builtin,
  List<Object?> args,
  String functionName,
) {
  return _requireStringLikeArgument(
    builtin,
    args,
    argumentIndex: 0,
    functionName: functionName,
  );
}

Value _requireStringLikeArgument(
  BuiltinFunction builtin,
  List<Object?> args, {
  required int argumentIndex,
  required String functionName,
}) {
  final luaArgumentNumber = argumentIndex + 1;
  if (args.isEmpty) {
    throw LuaError.typeError(
      "bad argument #1 to '$functionName' (string expected, got no value)",
    );
  }

  if (argumentIndex >= args.length) {
    throw LuaError.typeError(
      "bad argument #$luaArgumentNumber to '$functionName' (string expected, got no value)",
    );
  }

  final value = args[argumentIndex] as Value;
  final raw = value.raw;
  if (raw is String || raw is LuaString || raw is num || raw is BigInt) {
    return value;
  }

  final typeName = getLuaType(value);
  if (_isMethodSyntaxCall(builtin)) {
    throw LuaError.typeError(
      "calling '$functionName' on bad self (string expected, got $typeName)",
    );
  }

  throw LuaError.typeError(
    "bad argument #$luaArgumentNumber to '$functionName' (string expected, got $typeName)",
  );
}

int _requireStringIntegerArgument(
  BuiltinFunction builtin,
  Value value, {
  required String functionName,
  required int functionArgNumber,
  required int methodArgNumber,
}) {
  final integer = NumberUtils.tryToInteger(value.raw);
  if (integer != null) {
    return integer;
  }

  final raw = value.raw;
  final argNumber = _isMethodSyntaxCall(builtin)
      ? methodArgNumber
      : functionArgNumber;
  if (raw is num || raw is BigInt) {
    throw LuaError.typeError(
      "bad argument #$argNumber to '$functionName' "
      "(number has no integer representation)",
    );
  }
  if (raw is String || raw is LuaString) {
    try {
      LuaNumberParser.parse(raw.toString());
      throw LuaError.typeError(
        "bad argument #$argNumber to '$functionName' "
        "(number has no integer representation)",
      );
    } on FormatException {
      // Fall through to the type-based "number expected" message below.
    }
  }
  throw LuaError.typeError(
    "bad argument #$argNumber to '$functionName' "
    "(number expected, got ${NumberUtils.typeName(raw)})",
  );
}

/// String library implementation using the new Library system
class StringLibrary extends Library {
  @override
  String get name => "string";

  // Metamethods for string values are handled in metatables.dart
  // This library only provides the string table functions

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Register all string functions directly
    context.define("byte", _StringByte(interpreter));
    context.define("char", _StringChar(interpreter));
    context.define("dump", _StringDump(interpreter));
    context.define("find", _StringFind(interpreter));
    context.define("format", _StringFormat(interpreter));
    context.define("gmatch", _StringGmatch(interpreter));
    context.define("gsub", _StringGsub(interpreter));
    context.define("len", _StringLen(interpreter));
    context.define("lower", _StringLower(interpreter));
    context.define("match", _StringMatch(interpreter));
    context.define("pack", _StringPack(interpreter));
    context.define("packsize", _StringPackSize(interpreter));
    context.define("rep", _StringRep(interpreter));
    context.define("reverse", _StringReverse(interpreter));
    context.define("sub", _StringSub(interpreter));
    context.define("unpack", _StringUnpack(interpreter));
    context.define("upper", _StringUpper(interpreter));
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
}

class _StringByte extends BuiltinFunction {
  _StringByte([super.interpreter]);

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

class _StringChar extends BuiltinFunction {
  _StringChar([super.interpreter]);

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

class _StringDump extends BuiltinFunction {
  _StringDump([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("string.dump requires a function argument");
    }

    final func = args[0] as Value;
    if (!func.isCallable()) {
      throw LuaError.typeError("string.dump requires a function argument");
    }
    final runtime = func.interpreter ?? interpreter;
    if (runtime == null) {
      throw LuaError("No interpreter context available");
    }
    final stripDebugInfo = args.length > 1 && (args[1] as Value).isTruthy();
    return Value(runtime.dumpFunction(func, stripDebugInfo: stripDebugInfo));
  }
}

class _StringFind extends BuiltinFunction {
  _StringFind([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.find requires a string and a pattern");
    }

    final strValue =
        _requireStringLibrarySubject(this, args, 'string.find').raw;
    final patternValue =
        _requireStringLikeArgument(
          this,
          args,
          argumentIndex: 1,
          functionName: 'string.find',
        ).raw;
    final useByteLevel = _shouldUseBytePatternProcessing(
      strValue,
      patternValue,
    );
    final str = _toPatternProcessingString(strValue, byteLevel: useByteLevel);
    final pattern = _toPatternProcessingString(
      patternValue,
      byteLevel: useByteLevel,
    );
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

    if (_isAnchoredLazyWholeStringPattern(pattern)) {
      return Value.multi([Value(start + 1), Value(str.length)]);
    }

    final fastFind = _tryFastAnchoredLiteralTailFind(
      str,
      pattern,
      start: start,
    );
    if (fastFind case final match?) {
      if (match.start == null || match.end == null) {
        return Value(null);
      }
      return Value.multi([Value(match.start!), Value(match.end!)]);
    }

    if (_isAnchoredWhitespaceTrimCapturePattern(pattern) && start == 0) {
      final trimMatch = _matchAnchoredWhitespaceTrimCapture(str);
      if (trimMatch == null) {
        return Value(null);
      }
      return Value.multi([
        Value(1),
        Value(str.length),
        _valueFromPatternSlice(
          trimMatch.group(1) ?? '',
          byteLevel: useByteLevel,
        ),
      ]);
    }

    if (plain) {
      final index = str.indexOf(pattern, start);
      if (index == -1) return Value(null);
      return Value.multi([Value(index + 1), Value(index + pattern.length)]);
    }

    try {
      bool isEscaped(int index) =>
          index > 0 && pattern[index - 1] == '%' && !isEscaped(index - 1);
      final anchoredStart = pattern.startsWith('^') && !isEscaped(0);
      final preferredRegex =
          _shouldPreferRegexPatternEngine(
            subject: str,
            pattern: pattern,
            byteLevel: useByteLevel,
          )
          ? _translateLuaBackreferencePattern(pattern)
          : null;
      if (preferredRegex != null) {
        final regexMatch =
            preferredRegex.regex.matchAsPrefix(str, start) ??
            preferredRegex.regex.firstMatch(str.substring(start));
        if (regexMatch == null) {
          return Value(null);
        }
        final absoluteStart =
            regexMatch.start + (regexMatch.input == str ? 0 : start);
        final absoluteEnd =
            regexMatch.end + (regexMatch.input == str ? 0 : start);
        if (anchoredStart && absoluteStart != start) {
          return Value(null);
        }
        if (regexMatch.groupCount == 0) {
          return Value.multi([Value(absoluteStart + 1), Value(absoluteEnd)]);
        }
        final captures = _capturesFromRegexMatch(
          regexMatch,
          preferredRegex,
          byteLevel: useByteLevel,
        );
        return Value.multi([
          Value(absoluteStart + 1),
          Value(absoluteEnd),
          ...captures,
        ]);
      }
      final lp = _compileLuaPatternCached(pattern);
      final match = lp.firstMatch(str, start);
      if (match == null) {
        final regexBackref = _translateLuaBackreferencePattern(pattern);
        if (regexBackref == null) {
          return Value(null);
        }
        final regexMatch =
            regexBackref.regex.matchAsPrefix(str, start) ??
            regexBackref.regex.firstMatch(str.substring(start));
        if (regexMatch == null) {
          return Value(null);
        }
        final absoluteStart =
            regexMatch.start + (regexMatch.input == str ? 0 : start);
        final absoluteEnd =
            regexMatch.end + (regexMatch.input == str ? 0 : start);
        if (regexMatch.groupCount == 0) {
          return Value.multi([Value(absoluteStart + 1), Value(absoluteEnd)]);
        }
        final captures = _capturesFromRegexMatch(
          regexMatch,
          regexBackref,
          byteLevel: useByteLevel,
        );
        return Value.multi([
          Value(absoluteStart + 1),
          Value(absoluteEnd),
          ...captures,
        ]);
      }
      if (anchoredStart && match.start != start) {
        return Value(null);
      }

      final startPos = match.start + 1;
      final endPos = match.end;
      final results = [Value(startPos), Value(endPos)];
      for (var index = 0; index < match.captures.length; index++) {
        final cap = match.captures[index];
        results.add(
          cap == null
              ? Value(null)
              : match.positionCaptureIndexes.contains(index)
              ? Value(int.parse(cap))
              : _valueFromPatternSlice(cap, byteLevel: useByteLevel),
        );
      }
      if (match.captures.isNotEmpty) {
        return Value.multi(results);
      }
      return Value.multi(results);
    } catch (e) {
      throw LuaError('malformed pattern: $e');
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

Object? _tryFormatBareString(_FormatContext ctx) {
  if (ctx.flags.isNotEmpty ||
      ctx.width.isNotEmpty ||
      ctx.precision.isNotEmpty) {
    return null;
  }

  final value = ctx.value;
  final rawValue = value is Value ? value.raw : value;
  if (value is Value) {
    if (value.hasMetamethod('__tostring')) {
      return null;
    }
    if (rawValue is Map && value.getMetamethod('__name') != null) {
      return null;
    }
  }

  return switch (rawValue) {
    LuaString raw => raw,
    String raw => raw,
    null => 'nil',
    bool raw => raw.toString(),
    Map _ => 'table: ${rawValue.hashCode.toRadixString(16)}',
    Function _ => 'function: ${rawValue.hashCode.toRadixString(16)}',
    _ => rawValue.toString(),
  };
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
    if (value.hasMetamethod("__tostring")) {
      try {
        final awaitedResult = await value.callMetamethodAsync('__tostring', [
          value,
        ]);
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
  dynamic raw = ctx.value is Value ? (ctx.value as Value).raw : ctx.value;

  // Scalars → "(null)"
  if (raw == null || raw is num || raw is bool) {
    return _applyPadding('(null)', ctx);
  }

  int id;

  // Short strings (≤ 40 bytes) must share the same pointer when their
  // contents are equal, no matter if they are different objects.
  if (raw is String && raw.length <= 40) {
    id = raw.hashCode; // content hash is enough
  } else if (raw is LuaString && raw.length <= 40) {
    id = const ListEquality<int>().hash(raw.bytes);
  } else {
    // Other collectable objects: use identity
    id = identityHashCode(raw);
  }

  final ptr = '0x${id.toUnsigned(32).toRadixString(16)}';
  return _applyPadding(ptr, ctx);
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

class _StringFormat extends BuiltinFunction {
  _StringFormat([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("string.format requires a format string");
    }

    final formatString = (args[0] as Value).raw.toString();

    List<FormatPart> formatParts;
    try {
      final parsedParts = FormatStringParser.parseCached(formatString);
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
            formatted = _tryFormatBareString(ctx) ?? await _formatString(ctx);
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

class _StringGmatch extends BuiltinFunction {
  _StringGmatch([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.gmatch requires a string and a pattern");
    }

    final strValue = (args[0] as Value).raw;
    final patternValue = (args[1] as Value).raw;
    var init = args.length > 2 ? NumberUtils.toInt((args[2] as Value).raw) : 1;

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
      int pos = init > 0 ? init - 1 : bytes.length + init;
      if (pos < 0) pos = 0;

      final iterator = Value((List<Object?> _) {
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
      iterator.upvalues = [
        Upvalue(
          valueBox: Box<dynamic>(bytes, isTransient: true),
          interpreter: interpreter,
        ),
      ];
      return iterator;
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
      final lp = _compileLuaPatternCached(pattern);
      bool isEscaped(int index) =>
          index > 0 && pattern[index - 1] == '%' && !isEscaped(index - 1);
      final anchoredStart = pattern.startsWith('^') && !isEscaped(0);
      var currentPosition = init > 0 ? init - 1 : str.length + init;
      if (currentPosition < 0) currentPosition = 0;
      int? lastMatchEnd;

      // Return iterator function that follows Lua's behavior
      final iterator = Value((List<Object?> iterArgs) {
        if (currentPosition > str.length) {
          return Value(null);
        }
        while (true) {
          final match = lp.firstMatch(str, currentPosition);
          if (match != null &&
              match.start == currentPosition &&
              match.end != lastMatchEnd) {
            currentPosition = lastMatchEnd = match.end;
            if (match.captures.isEmpty) {
              if (useByteLevel && match.match.isNotEmpty) {
                final matchBytes = match.match.codeUnits
                    .map((c) => c & 0xFF)
                    .toList();
                return Value(
                  LuaString.fromBytes(Uint8List.fromList(matchBytes)),
                );
              }
              return Value(match.match);
            }

            final captures = <Value>[];
            for (var idx = 0; idx < match.captures.length; idx++) {
              final cap = match.captures[idx];

              if (cap == null) {
                captures.add(Value(null));
                continue;
              }

              if (match.positionCaptureIndexes.contains(idx)) {
                captures.add(Value(int.parse(cap)));
                continue;
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
            }
            return Value.multi(captures);
          }

          if (currentPosition >= str.length) {
            return Value(null);
          }

          currentPosition++;
          if (anchoredStart) {
            return Value(null);
          }
        }
      });
      iterator.upvalues = [
        Upvalue(
          valueBox: Box<dynamic>(str, isTransient: true),
          interpreter: interpreter,
        ),
      ];
      return iterator;
    } catch (e) {
      throw LuaError.typeError("malformed pattern: $e");
    }
  }
}

class _StringGsub extends BuiltinFunction {
  _StringGsub([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError.typeError(
        "string.gsub requires string, pattern, and replacement",
      );
    }
    final strValue = (args[0] as Value).raw;
    final patternValue = (args[1] as Value).raw;
    final useByteLevel = _shouldUseBytePatternProcessing(
      strValue,
      patternValue,
    );
    final str = _toPatternProcessingString(strValue, byteLevel: useByteLevel);
    final pattern = _toPatternProcessingString(
      patternValue,
      byteLevel: useByteLevel,
    );
    final repl = args[2] as Value;
    final n = args.length > 3 ? NumberUtils.toInt((args[3] as Value).raw) : -1;

    try {
      var count = 0;
      var didSubstitute = false;
      if (_isAnchoredWhitespaceTrimCapturePattern(pattern) &&
          (repl.raw is String || repl.raw is LuaString)) {
        final trimMatch = _matchAnchoredWhitespaceTrimCapture(str);
        if (trimMatch == null || n == 0) {
          return Value.multi([
            _valueFromPatternSlice(str, byteLevel: useByteLevel),
            Value(0),
          ]);
        }
        var replacement = _stringifyPatternReplacement(
          repl,
          byteLevel: useByteLevel,
        );
        replacement = replacement.replaceAll('%1', trimMatch.group(1) ?? '');
        if (replacement.contains('%%')) {
          replacement = replacement.replaceAll('%%', '%');
        }
        return Value.multi([
          _valueFromPatternSlice(replacement, byteLevel: useByteLevel),
          Value(1),
        ]);
      }
      final lp = _compileLuaPatternCached(pattern);
      bool isEscaped(int index) =>
          index > 0 && pattern[index - 1] == '%' && !isEscaped(index - 1);
      final anchoredStart = pattern.startsWith('^') && !isEscaped(0);

      lpc.LuaMatch? matchAtCurrentPosition(int srcPos, int? lastMatchEnd) {
        final match = lp.firstMatch(str, srcPos);
        if (match == null ||
            match.start != srcPos ||
            match.end == lastMatchEnd) {
          return null;
        }
        return match;
      }

      String result;
      Future<Object?> resolveTailSignal(Object? value) async {
        final runtime = interpreter;
        if (runtime == null || value is! TailCallSignal) {
          return value;
        }
        final callee = value.functionValue is Value
            ? value.functionValue as Value
            : Value(value.functionValue);
        final normalizedArgs = value.args
            .map((arg) => arg is Value ? arg : Value(arg))
            .toList();
        return runtime.callFunction(callee, normalizedArgs);
      }

      Future<dynamic> invokeCallable(
        Value callable,
        List<Value> captures,
      ) async {
        final runtime = interpreter;
        final previousYieldable = runtime?.isYieldable;
        try {
          if (callable.raw is Function) {
            if (runtime != null) {
              runtime.isYieldable = false;
            }
            final result = (callable.raw as Function)(captures);
            final awaited = result is Future ? await result : result;
            return resolveTailSignal(awaited);
          }
          if (runtime == null) {
            throw LuaError.typeError("Invalid replacement type");
          }
          runtime.isYieldable = false;
          return await runtime.callFunction(callable, captures);
        } on TailCallException catch (t) {
          if (runtime == null) rethrow;
          final callee = t.functionValue is Value
              ? t.functionValue as Value
              : Value(t.functionValue);
          final normalizedArgs = t.args
              .map((a) => a is Value ? a : Value(a))
              .toList();
          runtime.isYieldable = false;
          return await runtime.callFunction(callee, normalizedArgs);
        } finally {
          if (runtime != null) {
            runtime.isYieldable = previousYieldable ?? true;
          }
        }
      }

      if (repl.isCallable()) {
        final buffer = StringBuffer();
        var srcPos = 0;
        int? lastMatchEnd;

        while (n == -1 || count < n) {
          final match = matchAtCurrentPosition(srcPos, lastMatchEnd);
          if (match != null) {
            buffer.write(str.substring(srcPos, match.start));
            count++;

            final captures = <Value>[];
            if (match.captures.isEmpty) {
              captures.add(
                _valueFromPatternSlice(match.match, byteLevel: useByteLevel),
              );
            } else {
              for (var index = 0; index < match.captures.length; index++) {
                final cap = match.captures[index];
                captures.add(
                  cap == null
                      ? Value(null)
                      : match.positionCaptureIndexes.contains(index)
                      ? Value(int.parse(cap))
                      : _valueFromPatternSlice(cap, byteLevel: useByteLevel),
                );
              }
            }

            final replacement = _collapsePatternReplacementResult(
              await invokeCallable(repl, captures),
            );

            if (replacement == null ||
                (replacement is Value &&
                    (replacement.isNil || replacement.raw == false))) {
              buffer.write(match.match);
            } else {
              didSubstitute = true;
              final validatedReplacement = _validateGsubReplacementValue(
                replacement,
              );
              buffer.write(
                _stringifyPatternReplacement(
                  validatedReplacement,
                  byteLevel: useByteLevel,
                ),
              );
            }
            srcPos = lastMatchEnd = match.end;
          } else if (srcPos < str.length) {
            buffer.write(str.substring(srcPos, srcPos + 1));
            srcPos++;
          } else {
            break;
          }
          if (anchoredStart) {
            break;
          }
        }
        if (srcPos < str.length) {
          buffer.write(str.substring(srcPos));
        }
        result = buffer.toString();
      } else if (repl.raw is Map) {
        final buffer = StringBuffer();
        var srcPos = 0;
        int? lastMatchEnd;

        while (n == -1 || count < n) {
          final match = matchAtCurrentPosition(srcPos, lastMatchEnd);
          if (match != null) {
            buffer.write(str.substring(srcPos, match.start));
            count++;

            final key = match.captures.isEmpty
                ? _valueFromPatternSlice(match.match, byteLevel: useByteLevel)
                : (match.positionCaptureIndexes.contains(0)
                      ? Value(int.parse(match.captures.first!))
                      : _valueFromPatternSlice(
                          match.captures.first!,
                          byteLevel: useByteLevel,
                        ));
            var replacement = await repl.getValueAsync(key);

            if (replacement is Value) {
              replacement = replacement.isNil ? null : replacement.raw;
            }

            if (replacement != null && replacement != false) {
              didSubstitute = true;
              final validatedReplacement = _validateGsubReplacementValue(
                replacement,
              );
              buffer.write(
                _stringifyPatternReplacement(
                  validatedReplacement,
                  byteLevel: useByteLevel,
                ),
              );
            } else {
              buffer.write(match.match);
            }
            srcPos = lastMatchEnd = match.end;
          } else if (srcPos < str.length) {
            buffer.write(str.substring(srcPos, srcPos + 1));
            srcPos++;
          } else {
            break;
          }
          if (anchoredStart) {
            break;
          }
        }

        if (srcPos < str.length) {
          buffer.write(str.substring(srcPos));
        }
        result = buffer.toString();
      } else if (repl.raw is String || repl.raw is LuaString) {
        final replStr = _stringifyPatternReplacement(
          repl,
          byteLevel: useByteLevel,
        );
        final buffer = StringBuffer();
        var srcPos = 0;
        int? lastMatchEnd;

        while (n == -1 || count < n) {
          final match = matchAtCurrentPosition(srcPos, lastMatchEnd);
          if (match != null) {
            buffer.write(str.substring(srcPos, match.start));

            final replacement = _applyGsubReplacementTemplate(replStr, match);

            count++;
            didSubstitute = true;

            buffer.write(replacement);
            srcPos = lastMatchEnd = match.end;
          } else if (srcPos < str.length) {
            buffer.write(str.substring(srcPos, srcPos + 1));
            srcPos++;
          } else {
            break;
          }
          if (anchoredStart) {
            break;
          }
        }

        if (srcPos < str.length) {
          buffer.write(str.substring(srcPos));
        }
        result = buffer.toString();
      } else {
        throw LuaError.typeError("Invalid replacement type");
      }

      final resultValue = !didSubstitute
          ? (args[0] as Value)
          : (strValue is LuaString || useByteLevel
                ? Value(
                    LuaString.fromBytes(
                      result.codeUnits.map((c) => c & 0xFF).toList(),
                    ),
                  )
                : Value(result));
      return Value.multi([resultValue, Value(count)]);
    } on CoroutineCloseSignal {
      rethrow;
    } on LuaError {
      rethrow;
    } catch (e) {
      throw LuaError.typeError("Error in string.gsub: $e");
    }
  }
}

class _StringLen extends BuiltinFunction {
  _StringLen([super.interpreter]);

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

class _StringLower extends BuiltinFunction {
  _StringLower([super.interpreter]);

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

class _StringMatch extends BuiltinFunction {
  _StringMatch([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.match requires a string and a pattern");
    }

    final strValue = (args[0] as Value).raw;
    final patternValue = (args[1] as Value).raw;
    final useByteLevel = _shouldUseBytePatternProcessing(
      strValue,
      patternValue,
    );
    final str = _toPatternProcessingString(strValue, byteLevel: useByteLevel);
    final pattern = _toPatternProcessingString(
      patternValue,
      byteLevel: useByteLevel,
    );
    var init = args.length > 2 ? NumberUtils.toInt((args[2] as Value).raw) : 1;

    // Convert to 0-based index and handle negative indices
    init = init > 0 ? init - 1 : str.length + init;
    if (init < 0) init = 0;
    if (init > str.length) {
      return Value(null);
    }

    if (_isAnchoredLazyWholeStringPattern(pattern)) {
      return Value(str.substring(init));
    }

    final fastFind = _tryFastAnchoredLiteralTailFind(str, pattern, start: init);
    if (fastFind case final match?) {
      if (match.start == null || match.end == null) {
        return Value(null);
      }
      return _valueFromPatternSlice(
        str.substring(match.start! - 1, match.end!),
        byteLevel: useByteLevel,
      );
    }

    if (_isAnchoredWhitespaceTrimCapturePattern(pattern) && init == 0) {
      final trimMatch = _matchAnchoredWhitespaceTrimCapture(str);
      if (trimMatch == null) {
        return Value(null);
      }
      return _valueFromPatternSlice(
        trimMatch.group(1) ?? '',
        byteLevel: useByteLevel,
      );
    }

    try {
      bool isEscaped(int index) =>
          index > 0 && pattern[index - 1] == '%' && !isEscaped(index - 1);
      final anchoredStart = pattern.startsWith('^') && !isEscaped(0);
      final preferredRegex =
          _shouldPreferRegexPatternEngine(
            subject: str,
            pattern: pattern,
            byteLevel: useByteLevel,
          )
          ? _translateLuaBackreferencePattern(pattern)
          : null;
      if (preferredRegex != null) {
        final regexMatch =
            preferredRegex.regex.matchAsPrefix(str, init) ??
            preferredRegex.regex.firstMatch(str.substring(init));
        if (regexMatch == null) {
          return Value(null);
        }
        final absoluteStart =
            regexMatch.start + (regexMatch.input == str ? 0 : init);
        if (anchoredStart && absoluteStart != init) {
          return Value(null);
        }
        final captures = _capturesFromRegexMatch(
          regexMatch,
          preferredRegex,
          byteLevel: useByteLevel,
        );
        if (captures.isEmpty) {
          final matched = regexMatch.group(0) ?? '';
          return _valueFromPatternSlice(matched, byteLevel: useByteLevel);
        }
        if (captures.length == 1) {
          return captures.first;
        }
        return Value.multi(captures);
      }
      final lp = _compileLuaPatternCached(pattern);
      final resultMatch = lp.firstMatch(str, init);
      if (resultMatch == null) {
        final regexBackref = _translateLuaBackreferencePattern(pattern);
        if (regexBackref == null) {
          return Value(null);
        }
        final regexMatch =
            regexBackref.regex.matchAsPrefix(str, init) ??
            regexBackref.regex.firstMatch(str.substring(init));
        if (regexMatch == null) {
          return Value(null);
        }
        final captures = _capturesFromRegexMatch(
          regexMatch,
          regexBackref,
          byteLevel: useByteLevel,
        );
        if (captures.isEmpty) {
          final matched = regexMatch.group(0) ?? '';
          return _valueFromPatternSlice(matched, byteLevel: useByteLevel);
        }
        if (captures.length == 1) {
          return captures.first;
        }
        return Value.multi(captures);
      }
      if (anchoredStart && resultMatch.start != init) {
        return Value(null);
      }

      if (resultMatch.captures.isNotEmpty) {
        final captures = resultMatch.captures.indexed.map((entry) {
          final (index, capture) = entry;
          if (capture == null) {
            return Value(null);
          }
          if (resultMatch.positionCaptureIndexes.contains(index)) {
            return Value(int.parse(capture));
          }
          return _valueFromPatternSlice(capture, byteLevel: useByteLevel);
        }).toList();
        if (captures.length == 1) {
          return captures[0];
        }
        return Value.multi(captures);
      }

      return _valueFromPatternSlice(resultMatch.match, byteLevel: useByteLevel);
    } catch (e) {
      throw LuaError.typeError("malformed pattern: $e");
    }
  }
}

class _StringRep extends BuiltinFunction {
  _StringRep([super.interpreter]);

  Value _wrapRepeatedStringBytes(List<int> bytes) {
    final runtime = interpreter;
    if (runtime != null &&
        bytes.length <= StringInterning.shortStringThreshold) {
      return runtime.constantStringValue(bytes);
    }
    return Value(LuaString.fromBytes(bytes));
  }

  Value _wrapRepeatedString(String value) {
    final runtime = interpreter;
    if (runtime != null &&
        value.length <= StringInterning.shortStringThreshold) {
      return runtime.constantStringValue(convert.utf8.encode(value));
    }
    return StringInterning.createStringValue(value);
  }

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("string.rep requires a string and count");
    }

    final value = args[0] as Value;
    final count = _requireIntegerRepresentation((args[1] as Value).raw);
    final separatorValue = args.length > 2 ? (args[2] as Value) : null;

    if (count <= 0) return _wrapRepeatedString('');

    // For large allocations, suppress auto-GC to prevent premature collection
    // of transient objects before collectgarbage("count") can see them
    final isLargeAllocation = count > 1000000;
    if (isLargeAllocation) {
      interpreter?.gc.suppressAutoTrigger();
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
        if (isLargeAllocation) {
          interpreter?.gc.resumeAutoTrigger();
        }
        throw LuaError('too large');
      }

      if (count == 1) {
        if (isLargeAllocation) {
          interpreter?.gc.resumeAutoTrigger();
        }
        return value;
      }

      final resultBytes = <int>[];
      for (var i = 0; i < count; i++) {
        resultBytes.addAll(luaStr.bytes);
        if (separatorBytes.isNotEmpty && i < count - 1) {
          resultBytes.addAll(separatorBytes);
        }
      }

      final result = _wrapRepeatedStringBytes(resultBytes);
      if (isLargeAllocation) {
        interpreter?.gc.resumeAutoTrigger();
      }
      return result;
    } else {
      // Handle regular strings
      final originalStr = value.raw.toString();
      final separatorStr = separatorValue?.raw?.toString() ?? '';

      final totalLength =
          (BigInt.from(originalStr.length) * BigInt.from(count)) +
          (BigInt.from(separatorStr.length) *
              BigInt.from(math.max(0, count - 1)));

      if (totalLength > BigInt.from(1 << 30)) {
        if (isLargeAllocation) {
          interpreter?.gc.resumeAutoTrigger();
        }
        throw LuaError('too large');
      }

      if (count == 1) {
        if (isLargeAllocation) {
          interpreter?.gc.resumeAutoTrigger();
        }
        return value;
      }

      final buffer = StringBuffer();
      for (var i = 0; i < count; i++) {
        buffer.write(originalStr);
        if (separatorStr.isNotEmpty && i < count - 1) {
          buffer.write(separatorStr);
        }
      }

      // Create the result string once and reuse it
      final resultString = buffer.toString();
      final result = _wrapRepeatedString(resultString);

      // Re-enable auto-GC after large allocation completes
      if (isLargeAllocation) {
        interpreter?.gc.resumeAutoTrigger();
      }

      return result;
    }
  }
}

class _StringReverse extends BuiltinFunction {
  _StringReverse([super.interpreter]);

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

class _StringSub extends BuiltinFunction {
  _StringSub([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    final value = _requireStringLibrarySubject(this, args, 'sub');
    // Use toLatin1String for byte-level operations to preserve raw bytes
    final strValue = value.raw;
    final str = strValue is LuaString
        ? strValue.toLatin1String()
        : strValue.toString();

    var start = args.length > 1
        ? _requireStringIntegerArgument(
            this,
            args[1] as Value,
            functionName: 'sub',
            functionArgNumber: 2,
            methodArgNumber: 1,
          )
        : 1;
    var end = args.length > 2
        ? _requireStringIntegerArgument(
            this,
            args[2] as Value,
            functionName: 'sub',
            functionArgNumber: 3,
            methodArgNumber: 2,
          )
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

class _StringPack extends BuiltinFunction {
  _StringPack([super.interpreter]);

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

class _StringPackSize extends BuiltinFunction {
  _StringPackSize([super.interpreter]);

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

class _StringUnpack extends BuiltinFunction {
  _StringUnpack([super.interpreter]);

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

class _StringUpper extends BuiltinFunction {
  _StringUpper([super.interpreter]);

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
