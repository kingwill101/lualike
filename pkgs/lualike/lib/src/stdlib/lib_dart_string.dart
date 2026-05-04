import 'dart:async';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/value.dart';

import 'lib_dart_bytes.dart';
import 'library.dart';

String _dartStringText(Object? value) => rawLuaSlot(value).toString();

String _dartStringPattern(Object? value) {
  final raw = rawLuaSlot(value);
  return raw is String ? raw : raw.toString();
}

int _requiredDartStringIndex(List<Object?> args, int index) {
  return (rawLuaSlot(args[index]) as num).toInt();
}

int? _optionalDartStringIndex(List<Object?> args, int index) {
  if (args.length <= index) {
    return null;
  }
  final rawIndex = rawLuaSlot(args[index]);
  return rawIndex is num ? rawIndex.toInt() : null;
}

/// Dart String library implementation using the new Library system
class DartStringLibrary extends Library {
  @override
  String get name => "dart";

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final runtime = context.vm;

    // Create string functions for the dart.string namespace
    final stringFunctions = <String, dynamic>{};

    stringFunctions['split'] = DartStringSplit(runtime);
    stringFunctions['trim'] = DartStringTrim(runtime);
    stringFunctions['toUpperCase'] = DartStringToUpper(runtime);
    stringFunctions['toLowerCase'] = DartStringToLower(runtime);
    stringFunctions['contains'] = DartStringContains(runtime);
    stringFunctions['replaceAll'] = DartStringReplaceAll(runtime);
    stringFunctions['substring'] = DartStringSubstring(runtime);
    stringFunctions['trimLeft'] = DartStringTrimLeft(runtime);
    stringFunctions['trimRight'] = DartStringTrimRight(runtime);
    stringFunctions['padLeft'] = DartStringPadLeft(runtime);
    stringFunctions['padRight'] = DartStringPadRight(runtime);
    stringFunctions['startsWith'] = DartStringStartsWith(runtime);
    stringFunctions['endsWith'] = DartStringEndsWith(runtime);
    stringFunctions['indexOf'] = DartStringIndexOf(runtime);
    stringFunctions['lastIndexOf'] = DartStringLastIndexOf(runtime);
    stringFunctions['replaceFirst'] = DartStringReplaceFirst(runtime);
    stringFunctions['isEmpty'] = DartStringIsEmpty(runtime);
    stringFunctions['fromCharCodes'] = DartStringFromCharCodes(runtime);

    // Add bytes sub-library
    stringFunctions['bytes'] = valueFromOptionalLuaSlot(runtime, {
      'toBytes': DartToBytes(runtime),
      'fromBytes': DartFromBytes(runtime),
    });

    // Register the string subtable
    context.define(
      'string',
      valueFromOptionalLuaSlot(runtime, stringFunctions),
    );
  }
}

class DartStringSplit extends BuiltinFunction {
  DartStringSplit([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.split requires 2 arguments: string and pattern',
      );
    }
    final str = _dartStringText(args[0]);
    final pattern = _dartStringPattern(args[1]);
    final parts = str.split(pattern);
    return valueFromOptionalLuaSlot(interpreter, parts);
  }
}

class DartStringTrim extends BuiltinFunction {
  DartStringTrim([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.trim requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = _dartStringText(val);
    final trimmed = str.trim();
    if (identical(trimmed, str)) {
      return val;
    }
    return dartStringValue(trimmed);
  }
}

class DartStringToUpper extends BuiltinFunction {
  DartStringToUpper([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.toUpperCase requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = _dartStringText(val);
    final upper = str.toUpperCase();
    if (identical(upper, str)) {
      return val;
    }
    return dartStringValue(upper);
  }
}

class DartStringToLower extends BuiltinFunction {
  DartStringToLower([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.toLowerCase requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = _dartStringText(val);
    final lower = str.toLowerCase();
    if (identical(lower, str)) {
      return val;
    }
    return dartStringValue(lower);
  }
}

class DartStringContains extends BuiltinFunction {
  DartStringContains([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.contains requires 2 arguments: string and other',
      );
    }
    final str = _dartStringText(args[0]);
    final other = _dartStringPattern(args[1]);
    final startIndex = _optionalDartStringIndex(args, 2);
    if (startIndex != null) {
      return primitiveValue(str.contains(other, startIndex));
    }
    return primitiveValue(str.contains(other));
  }
}

class DartStringReplaceAll extends BuiltinFunction {
  DartStringReplaceAll([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'dart.string.replaceAll requires 3 arguments: string, from, to',
      );
    }
    final str = _dartStringText(args[0]);
    final from = _dartStringPattern(args[1]);
    final to = _dartStringPattern(args[2]);
    return dartStringValue(str.replaceAll(from, to));
  }
}

class DartStringSubstring extends BuiltinFunction {
  DartStringSubstring([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.substring requires at least 2 arguments: string, startIndex, [endIndex]',
      );
    }
    final str = _dartStringText(args[0]);
    final startIndex = _requiredDartStringIndex(args, 1);
    final endIndex = _optionalDartStringIndex(args, 2);
    return dartStringValue(str.substring(startIndex, endIndex));
  }
}

class DartStringTrimLeft extends BuiltinFunction {
  DartStringTrimLeft([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.trimLeft requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = _dartStringText(val);
    final trimmed = str.trimLeft();
    if (identical(trimmed, str)) {
      return val;
    }
    return dartStringValue(trimmed);
  }
}

class DartStringTrimRight extends BuiltinFunction {
  DartStringTrimRight([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.trimRight requires 1 argument: string');
    }
    final val = args[0] as Value;
    final str = _dartStringText(val);
    final trimmed = str.trimRight();
    if (identical(trimmed, str)) {
      return val;
    }
    return dartStringValue(trimmed);
  }
}

class DartStringPadLeft extends BuiltinFunction {
  DartStringPadLeft([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.padLeft requires 2 arguments: string, width, [padding]',
      );
    }
    final val = args[0] as Value;
    final str = _dartStringText(val);
    final width = _requiredDartStringIndex(args, 1);
    if (width <= str.length) {
      return val;
    }
    String? padding;
    if (args.length > 2) {
      padding = _dartStringPattern(args[2]);
    }
    return dartStringValue(str.padLeft(width, padding ?? ' '));
  }
}

class DartStringPadRight extends BuiltinFunction {
  DartStringPadRight([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.padRight requires 2 arguments: string, width, [padding]',
      );
    }
    final val = args[0] as Value;
    final str = _dartStringText(val);
    final width = _requiredDartStringIndex(args, 1);
    if (width <= str.length) {
      return val;
    }
    String? padding;
    if (args.length > 2) {
      padding = _dartStringPattern(args[2]);
    }
    return dartStringValue(str.padRight(width, padding ?? ' '));
  }
}

class DartStringStartsWith extends BuiltinFunction {
  DartStringStartsWith([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.startsWith requires 2 arguments: string, pattern, [index]',
      );
    }
    final str = _dartStringText(args[0]);
    final pattern = _dartStringPattern(args[1]);
    final index = _optionalDartStringIndex(args, 2);
    return primitiveValue(str.startsWith(pattern, index ?? 0));
  }
}

class DartStringEndsWith extends BuiltinFunction {
  DartStringEndsWith([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.endsWith requires 2 arguments: string, other',
      );
    }
    final str = _dartStringText(args[0]);
    final other = _dartStringPattern(args[1]);
    return primitiveValue(str.endsWith(other));
  }
}

class DartStringIndexOf extends BuiltinFunction {
  DartStringIndexOf([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.indexOf requires 2 arguments: string, pattern, [start]',
      );
    }
    final str = _dartStringText(args[0]);
    final pattern = _dartStringPattern(args[1]);
    final start = _optionalDartStringIndex(args, 2);
    return primitiveValue(str.indexOf(pattern, start ?? 0));
  }
}

class DartStringLastIndexOf extends BuiltinFunction {
  DartStringLastIndexOf([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.lastIndexOf requires 2 arguments: string, pattern, [start]',
      );
    }
    final str = _dartStringText(args[0]);
    final pattern = _dartStringPattern(args[1]);
    final start = _optionalDartStringIndex(args, 2);
    return primitiveValue(str.lastIndexOf(pattern, start));
  }
}

class DartStringReplaceFirst extends BuiltinFunction {
  DartStringReplaceFirst([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'dart.string.replaceFirst requires 3 arguments: string, from, to, [startIndex]',
      );
    }
    final str = _dartStringText(args[0]);
    final from = _dartStringPattern(args[1]);
    final to = _dartStringPattern(args[2]);
    final startIndex = _optionalDartStringIndex(args, 3);
    return dartStringValue(str.replaceFirst(from, to, startIndex ?? 0));
  }
}

class DartStringIsEmpty extends BuiltinFunction {
  DartStringIsEmpty([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.isEmpty requires 1 argument: string');
    }
    final str = _dartStringText(args[0]);
    return primitiveValue(str.isEmpty);
  }
}

class DartStringFromCharCodes extends BuiltinFunction {
  DartStringFromCharCodes([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError(
        'dart.string.fromCharCodes requires at least 1 argument: charCodes table',
      );
    }
    final table = rawLuaSlot(args[0]) as Map;
    final charCodes = <int>[];
    for (var i = 1; i <= table.length; i++) {
      final val = table[primitiveValue(i)];
      final raw = rawLuaSlot(val);
      if (raw is num) {
        charCodes.add(raw.toInt());
      }
    }
    return dartStringValue(String.fromCharCodes(charCodes));
  }
}
