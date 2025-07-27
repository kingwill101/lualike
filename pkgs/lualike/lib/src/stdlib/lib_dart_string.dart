import 'dart:async';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'lib_dart_bytes.dart';

class DartStringLib {
  static final Map<String, BuiltinFunction> functions = {
    'split': DartStringSplit(),
    'trim': DartStringTrim(),
    'toUpperCase': DartStringToUpper(),
    'toLowerCase': DartStringToLower(),
    'contains': DartStringContains(),
    'replaceAll': DartStringReplaceAll(),
    'substring': DartStringSubstring(),
    'trimLeft': DartStringTrimLeft(),
    'trimRight': DartStringTrimRight(),
    'padLeft': DartStringPadLeft(),
    'padRight': DartStringPadRight(),
    'startsWith': DartStringStartsWith(),
    'endsWith': DartStringEndsWith(),
    'indexOf': DartStringIndexOf(),
    'lastIndexOf': DartStringLastIndexOf(),
    'replaceFirst': DartStringReplaceFirst(),
    'isEmpty': DartStringIsEmpty(),
    'fromCharCodes': DartStringFromCharCodes(),
  };
}

void defineDartStringLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final existing = env.get('dart');
  Map<String, dynamic> dartTable;

  if (existing is Value && existing.raw is Map<String, dynamic>) {
    dartTable = existing.raw as Map<String, dynamic>;
  } else if (existing is Map<String, dynamic>) {
    dartTable = existing;
  } else {
    dartTable = {};
    env.define('dart', Value(dartTable));
  }

  final stringTable = <String, dynamic>{};
  DartStringLib.functions.forEach((key, value) {
    stringTable[key] = value;
  });

  final bytesTable = <String, dynamic>{};
  DartBytesLib.functions.forEach((key, value) {
    bytesTable[key] = value;
  });
  stringTable['bytes'] = bytesTable;

  dartTable['string'] = stringTable;
}

class DartStringSplit implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.split requires 2 arguments: string and pattern',
      );
    }
    final str = (args[0] as Value).raw.toString();
    final patternValue = (args[1] as Value).raw;
    final pattern = patternValue is String
        ? patternValue
        : patternValue.toString();
    final parts = str.split(pattern);
    return Value(parts);
  }
}

class DartStringTrim implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.trim requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = val.raw.toString();
    final trimmed = str.trim();
    if (identical(trimmed, str)) {
      return val;
    }
    return Value(trimmed);
  }
}

class DartStringToUpper implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.toUpperCase requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = val.raw.toString();
    final upper = str.toUpperCase();
    if (identical(upper, str)) {
      return val;
    }
    return Value(upper);
  }
}

class DartStringToLower implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.toLowerCase requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = val.raw.toString();
    final lower = str.toLowerCase();
    if (identical(lower, str)) {
      return val;
    }
    return Value(lower);
  }
}

class DartStringContains implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.contains requires 2 arguments: string and other',
      );
    }
    final str = (args[0] as Value).raw.toString();
    final otherValue = (args[1] as Value).raw;
    final other = otherValue is String ? otherValue : otherValue.toString();
    if (args.length > 2 && args[2] is Value && (args[2] as Value).raw is num) {
      final startIndex = ((args[2] as Value).raw as num).toInt();
      return Value(str.contains(other, startIndex));
    }
    return Value(str.contains(other));
  }
}

class DartStringReplaceAll implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'dart.string.replaceAll requires 3 arguments: string, from, to',
      );
    }
    final str = (args[0] as Value).raw.toString();
    final fromValue = (args[1] as Value).raw;
    final from = fromValue is String ? fromValue : fromValue.toString();
    final toValue = (args[2] as Value).raw;
    final to = toValue is String ? toValue : toValue.toString();
    return Value(str.replaceAll(from, to));
  }
}

class DartStringSubstring implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.substring requires at least 2 arguments: string, startIndex, [endIndex]',
      );
    }
    final str = (args[0] as Value).raw.toString();
    final startIndex = ((args[1] as Value).raw as num).toInt();
    int? endIndex;
    if (args.length > 2 && args[2] is Value && (args[2] as Value).raw is num) {
      endIndex = ((args[2] as Value).raw as num).toInt();
    }
    return Value(str.substring(startIndex, endIndex));
  }
}

class DartStringTrimLeft implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.trimLeft requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = val.raw.toString();
    final trimmed = str.trimLeft();
    if (identical(trimmed, str)) {
      return val;
    }
    return Value(trimmed);
  }
}

class DartStringTrimRight implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.trimRight requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = val.raw.toString();
    final trimmed = str.trimRight();
    if (identical(trimmed, str)) {
      return val;
    }
    return Value(trimmed);
  }
}

class DartStringPadLeft implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.padLeft requires 2 arguments: string, width, [padding]',
      );
    }
    final val = args[0] as Value;
    final str = val.raw.toString();
    final width = ((args[1] as Value).raw as num).toInt();
    if (width <= str.length) {
      return val;
    }
    String? padding;
    if (args.length > 2) {
      final paddingValue = (args[2] as Value).raw;
      padding = paddingValue is String ? paddingValue : paddingValue.toString();
    }
    return Value(str.padLeft(width, padding ?? ' '));
  }
}

class DartStringPadRight implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.padRight requires 2 arguments: string, width, [padding]',
      );
    }
    final val = args[0] as Value;
    final str = val.raw.toString();
    final width = ((args[1] as Value).raw as num).toInt();
    if (width <= str.length) {
      return val;
    }
    String? padding;
    if (args.length > 2) {
      final paddingValue = (args[2] as Value).raw;
      padding = paddingValue is String ? paddingValue : paddingValue.toString();
    }
    return Value(str.padRight(width, padding ?? ' '));
  }
}

class DartStringStartsWith implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.startsWith requires 2 arguments: string, pattern, [index]',
      );
    }
    final str = (args[0] as Value).raw.toString();
    final patternValue = (args[1] as Value).raw;
    final pattern = patternValue is String
        ? patternValue
        : patternValue.toString();
    int? index;
    if (args.length > 2 && args[2] is Value && (args[2] as Value).raw is num) {
      index = ((args[2] as Value).raw as num).toInt();
    }
    return Value(str.startsWith(pattern, index ?? 0));
  }
}

class DartStringEndsWith implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.endsWith requires 2 arguments: string, other',
      );
    }
    final str = (args[0] as Value).raw.toString();
    final otherValue = (args[1] as Value).raw;
    final other = otherValue is String ? otherValue : otherValue.toString();
    return Value(str.endsWith(other));
  }
}

class DartStringIndexOf implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.indexOf requires 2 arguments: string, pattern, [start]',
      );
    }
    final str = (args[0] as Value).raw.toString();
    final patternValue = (args[1] as Value).raw;
    final pattern = patternValue is String
        ? patternValue
        : patternValue.toString();
    int? start;
    if (args.length > 2 && args[2] is Value && (args[2] as Value).raw is num) {
      start = ((args[2] as Value).raw as num).toInt();
    }
    return Value(str.indexOf(pattern, start ?? 0));
  }
}

class DartStringLastIndexOf implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.lastIndexOf requires 2 arguments: string, pattern, [start]',
      );
    }
    final str = (args[0] as Value).raw.toString();
    final patternValue = (args[1] as Value).raw;
    final pattern = patternValue is String
        ? patternValue
        : patternValue.toString();
    int? start;
    if (args.length > 2 && args[2] is Value && (args[2] as Value).raw is num) {
      start = ((args[2] as Value).raw as num).toInt();
    }
    return Value(str.lastIndexOf(pattern, start));
  }
}

class DartStringReplaceFirst implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'dart.string.replaceFirst requires 3 arguments: string, from, to, [startIndex]',
      );
    }
    final str = (args[0] as Value).raw.toString();
    final fromValue = (args[1] as Value).raw;
    final from = fromValue is String ? fromValue : fromValue.toString();
    final toValue = (args[2] as Value).raw;
    final to = toValue is String ? toValue : toValue.toString();
    int? startIndex;
    if (args.length > 3 && args[3] is Value && (args[3] as Value).raw is num) {
      startIndex = ((args[3] as Value).raw as num).toInt();
    }
    return Value(str.replaceFirst(from, to, startIndex ?? 0));
  }
}

class DartStringIsEmpty implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.isEmpty requires 1 argument: string');
    }
    final str = (args[0] as Value).raw.toString();
    return Value(str.isEmpty);
  }
}

class DartStringFromCharCodes implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError(
        'dart.string.fromCharCodes requires at least 1 argument: charCodes table',
      );
    }
    final table = (args[0] as Value).raw as Map;
    final charCodes = <int>[];
    for (var i = 1; i <= table.length; i++) {
      final val = table[Value(i)];
      if (val is Value) {
        charCodes.add((val.raw as num).toInt());
      }
    }
    return Value(String.fromCharCodes(charCodes));
  }
}
