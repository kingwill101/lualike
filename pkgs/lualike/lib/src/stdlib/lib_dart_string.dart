import 'dart:async';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/stdlib/doc.dart';

import 'lib_dart_bytes.dart';
import 'library.dart';

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
  String get description =>
      'Dart native string utilities bridging Lua and Dart string operations.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final runtime = context.vm;

    // Create string functions for the dart.string namespace
    final stringFunctions = <String, dynamic>{};

    stringFunctions['split'] = DartStringSplit(runtime);
    context.describe('string.split', DartStringSplit(runtime).doc!);
    stringFunctions['trim'] = DartStringTrim(runtime);
    context.describe('string.trim', DartStringTrim(runtime).doc!);
    stringFunctions['toUpperCase'] = DartStringToUpper(runtime);
    context.describe('string.toUpperCase', DartStringToUpper(runtime).doc!);
    stringFunctions['toLowerCase'] = DartStringToLower(runtime);
    context.describe('string.toLowerCase', DartStringToLower(runtime).doc!);
    stringFunctions['contains'] = DartStringContains(runtime);
    context.describe('string.contains', DartStringContains(runtime).doc!);
    stringFunctions['replaceAll'] = DartStringReplaceAll(runtime);
    context.describe('string.replaceAll', DartStringReplaceAll(runtime).doc!);
    stringFunctions['substring'] = DartStringSubstring(runtime);
    context.describe('string.substring', DartStringSubstring(runtime).doc!);
    stringFunctions['trimLeft'] = DartStringTrimLeft(runtime);
    context.describe('string.trimLeft', DartStringTrimLeft(runtime).doc!);
    stringFunctions['trimRight'] = DartStringTrimRight(runtime);
    context.describe('string.trimRight', DartStringTrimRight(runtime).doc!);
    stringFunctions['padLeft'] = DartStringPadLeft(runtime);
    context.describe('string.padLeft', DartStringPadLeft(runtime).doc!);
    stringFunctions['padRight'] = DartStringPadRight(runtime);
    context.describe('string.padRight', DartStringPadRight(runtime).doc!);
    stringFunctions['startsWith'] = DartStringStartsWith(runtime);
    context.describe('string.startsWith', DartStringStartsWith(runtime).doc!);
    stringFunctions['endsWith'] = DartStringEndsWith(runtime);
    context.describe('string.endsWith', DartStringEndsWith(runtime).doc!);
    stringFunctions['indexOf'] = DartStringIndexOf(runtime);
    context.describe('string.indexOf', DartStringIndexOf(runtime).doc!);
    stringFunctions['lastIndexOf'] = DartStringLastIndexOf(runtime);
    context.describe('string.lastIndexOf', DartStringLastIndexOf(runtime).doc!);
    stringFunctions['replaceFirst'] = DartStringReplaceFirst(runtime);
    context.describe(
      'string.replaceFirst',
      DartStringReplaceFirst(runtime).doc!,
    );
    stringFunctions['isEmpty'] = DartStringIsEmpty(runtime);
    context.describe('string.isEmpty', DartStringIsEmpty(runtime).doc!);
    stringFunctions['fromCharCodes'] = DartStringFromCharCodes(runtime);
    context.describe(
      'string.fromCharCodes',
      DartStringFromCharCodes(runtime).doc!,
    );

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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Splits a string by a pattern into a table of substrings.',
    params: [
      DocParam('input', 'string', 'The string to split.'),
      DocParam('pattern', 'string', 'The delimiter pattern.'),
    ],
    returns: 'A table of substrings.',
    category: 'dart',
    example: 'dart.string.split("a,b,c", ",")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.split requires 2 arguments: string and pattern',
      );
    }
    final str = rawLuaSlotString(args[0]);
    final pattern = _dartStringPattern(args[1]);
    final parts = str.split(pattern);
    return valueFromOptionalLuaSlot(interpreter, parts);
  }
}

class DartStringTrim extends BuiltinFunction {
  DartStringTrim([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Removes leading and trailing whitespace from a string.',
    params: [DocParam('input', 'string', 'The string to trim.')],
    returns: 'The trimmed string.',
    category: 'dart',
    example: 'dart.string.trim("  hello  ")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.trim requires 1 argument: string');
    }
    final val = args[0];
    final str = rawLuaSlotString(val);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Converts all characters in a string to uppercase.',
    params: [DocParam('input', 'string', 'The input string.')],
    returns: 'The uppercase string.',
    category: 'dart',
    example: 'dart.string.toUpper("hello")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.toUpperCase requires 1 argument: string');
    }
    final val = args[0];
    final str = rawLuaSlotString(val);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Converts all characters in a string to lowercase.',
    params: [DocParam('input', 'string', 'The input string.')],
    returns: 'The lowercase string.',
    category: 'dart',
    example: 'dart.string.toLower("HELLO")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.toLowerCase requires 1 argument: string');
    }
    final val = args[0];
    final str = rawLuaSlotString(val);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Checks whether a string contains a given substring.',
    params: [
      DocParam('input', 'string', 'The string to search in.'),
      DocParam('substring', 'string', 'The substring to look for.'),
    ],
    returns: 'true if found, false otherwise.',
    category: 'dart',
    example: 'dart.string.contains("hello", "ell")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.contains requires 2 arguments: string and other',
      );
    }
    final str = rawLuaSlotString(args[0]);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Replaces all occurrences of a pattern in a string.',
    params: [
      DocParam('input', 'string', 'The input string.'),
      DocParam('pattern', 'string', 'The substring to replace.'),
      DocParam('replacement', 'string', 'The replacement string.'),
    ],
    returns: 'The resulting string.',
    category: 'dart',
    example: 'dart.string.replaceAll("abc", "b", "x")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'dart.string.replaceAll requires 3 arguments: string, from, to',
      );
    }
    final str = rawLuaSlotString(args[0]);
    final from = _dartStringPattern(args[1]);
    final to = _dartStringPattern(args[2]);
    return dartStringValue(str.replaceAll(from, to));
  }
}

class DartStringSubstring extends BuiltinFunction {
  DartStringSubstring([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Extracts a substring given start and optional end index.',
    params: [
      DocParam('input', 'string', 'The input string.'),
      DocParam('start', 'number', 'Start index (0-based).'),
      DocParam(
        'end',
        'number',
        'End index (exclusive, defaults to end).',
        optional: true,
      ),
    ],
    returns: 'The extracted substring.',
    category: 'dart',
    example: 'dart.string.substring("hello", 1, 4)',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.substring requires at least 2 arguments: string, startIndex, [endIndex]',
      );
    }
    final str = rawLuaSlotString(args[0]);
    final startIndex = _requiredDartStringIndex(args, 1);
    final endIndex = _optionalDartStringIndex(args, 2);
    return dartStringValue(str.substring(startIndex, endIndex));
  }
}

class DartStringTrimLeft extends BuiltinFunction {
  DartStringTrimLeft([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Removes leading whitespace from a string.',
    params: [DocParam('input', 'string', 'The string to trim.')],
    returns: 'The trimmed string.',
    category: 'dart',
    example: 'dart.string.trimLeft("  hello")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.trimLeft requires 1 argument: string');
    }
    final val = args[0];
    final str = rawLuaSlotString(val);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Removes trailing whitespace from a string.',
    params: [DocParam('input', 'string', 'The string to trim.')],
    returns: 'The trimmed string.',
    category: 'dart',
    example: 'dart.string.trimRight("hello  ")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.trimRight requires 1 argument: string');
    }
    final val = args[0];
    final str = rawLuaSlotString(val);
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
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Pads the left side of a string to a minimum width with a fill character.',
    params: [
      DocParam('input', 'string', 'The input string.'),
      DocParam('width', 'number', 'Minimum total width.'),
      DocParam(
        'fill',
        'string',
        'Fill character (defaults to space).',
        optional: true,
      ),
    ],
    returns: 'The padded string.',
    category: 'dart',
    example: 'dart.string.padLeft("42", 5, "0")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.padLeft requires 2 arguments: string, width, [padding]',
      );
    }
    final val = args[0];
    final str = rawLuaSlotString(val);
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
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Pads the right side of a string to a minimum width with a fill character.',
    params: [
      DocParam('input', 'string', 'The input string.'),
      DocParam('width', 'number', 'Minimum total width.'),
      DocParam(
        'fill',
        'string',
        'Fill character (defaults to space).',
        optional: true,
      ),
    ],
    returns: 'The padded string.',
    category: 'dart',
    example: 'dart.string.padRight("42", 5, "0")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.padRight requires 2 arguments: string, width, [padding]',
      );
    }
    final val = args[0];
    final str = rawLuaSlotString(val);
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
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Checks if a string starts with a given prefix.',
    params: [
      DocParam('input', 'string', 'The input string.'),
      DocParam('prefix', 'string', 'The prefix to check.'),
    ],
    returns: 'true if the string starts with the prefix.',
    category: 'dart',
    example: 'dart.string.startsWith("hello", "he")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.startsWith requires 2 arguments: string, pattern, [index]',
      );
    }
    final str = rawLuaSlotString(args[0]);
    final pattern = _dartStringPattern(args[1]);
    final index = _optionalDartStringIndex(args, 2);
    return primitiveValue(str.startsWith(pattern, index ?? 0));
  }
}

class DartStringEndsWith extends BuiltinFunction {
  DartStringEndsWith([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Checks if a string ends with a given suffix.',
    params: [
      DocParam('input', 'string', 'The input string.'),
      DocParam('suffix', 'string', 'The suffix to check.'),
    ],
    returns: 'true if the string ends with the suffix.',
    category: 'dart',
    example: 'dart.string.endsWith("hello", "lo")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.endsWith requires 2 arguments: string, other',
      );
    }
    final str = rawLuaSlotString(args[0]);
    final other = _dartStringPattern(args[1]);
    return primitiveValue(str.endsWith(other));
  }
}

class DartStringIndexOf extends BuiltinFunction {
  DartStringIndexOf([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the first index of a substring, or -1 if not found.',
    params: [
      DocParam('input', 'string', 'The string to search in.'),
      DocParam('substring', 'string', 'The substring to find.'),
      DocParam(
        'start',
        'number',
        'Starting index (0-based, optional).',
        optional: true,
      ),
    ],
    returns: 'The index or -1.',
    category: 'dart',
    example: 'dart.string.indexOf("hello", "l")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.indexOf requires 2 arguments: string, pattern, [start]',
      );
    }
    final str = rawLuaSlotString(args[0]);
    final pattern = _dartStringPattern(args[1]);
    final start = _optionalDartStringIndex(args, 2);
    return primitiveValue(str.indexOf(pattern, start ?? 0));
  }
}

class DartStringLastIndexOf extends BuiltinFunction {
  DartStringLastIndexOf([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the last index of a substring, or -1 if not found.',
    params: [
      DocParam('input', 'string', 'The string to search in.'),
      DocParam('substring', 'string', 'The substring to find.'),
      DocParam(
        'start',
        'number',
        'Starting index (0-based, optional).',
        optional: true,
      ),
    ],
    returns: 'The index or -1.',
    category: 'dart',
    example: 'dart.string.lastIndexOf("hello", "l")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError(
        'dart.string.lastIndexOf requires 2 arguments: string, pattern, [start]',
      );
    }
    final str = rawLuaSlotString(args[0]);
    final pattern = _dartStringPattern(args[1]);
    final start = _optionalDartStringIndex(args, 2);
    return primitiveValue(str.lastIndexOf(pattern, start));
  }
}

class DartStringReplaceFirst extends BuiltinFunction {
  DartStringReplaceFirst([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Replaces the first occurrence of a pattern in a string.',
    params: [
      DocParam('input', 'string', 'The input string.'),
      DocParam('pattern', 'string', 'The substring to replace.'),
      DocParam('replacement', 'string', 'The replacement string.'),
    ],
    returns: 'The resulting string.',
    category: 'dart',
    example: 'dart.string.replaceFirst("abc", "b", "x")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'dart.string.replaceFirst requires 3 arguments: string, from, to, [startIndex]',
      );
    }
    final str = rawLuaSlotString(args[0]);
    final from = _dartStringPattern(args[1]);
    final to = _dartStringPattern(args[2]);
    final startIndex = _optionalDartStringIndex(args, 3);
    return dartStringValue(str.replaceFirst(from, to, startIndex ?? 0));
  }
}

class DartStringIsEmpty extends BuiltinFunction {
  DartStringIsEmpty([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Checks if a string is empty.',
    params: [DocParam('input', 'string', 'The input string.')],
    returns: 'true if the string is empty.',
    category: 'dart',
    example: 'dart.string.isEmpty("")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.string.isEmpty requires 1 argument: string');
    }
    final str = rawLuaSlotString(args[0]);
    return primitiveValue(str.isEmpty);
  }
}

class DartStringFromCharCodes extends BuiltinFunction {
  DartStringFromCharCodes([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Creates a string from a table of character code points.',
    params: [DocParam('codes', 'table', 'A table of Unicode code points.')],
    returns: 'The constructed string.',
    category: 'dart',
    example: 'dart.string.fromCharCodes({65, 66, 67})',
  );

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
