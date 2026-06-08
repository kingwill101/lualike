import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/extensions/value_extension.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/interpreter/interpreter.dart';

import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/stdlib/doc.dart';
import 'package:lualike/src/value.dart';
import 'library.dart';

/// Convert library implementation using the new Library system
class ConvertLibrary extends Library {
  @override
  String get name => "convert";

  @override
  String get description => 'Data conversion utilities between common formats.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Register all convert functions directly
    context.define('jsonEncode', JsonEncode(interpreter!));
    context.define('jsonDecode', JsonDecode(interpreter!));
    context.define('base64Encode', Base64Encode(interpreter!));
    context.define('base64Decode', Base64Decode(interpreter!));
    context.define('base64UrlEncode', Base64UrlEncode(interpreter!));
    context.define('asciiEncode', AsciiEncode(interpreter!));
    context.define('asciiDecode', AsciiDecode(interpreter!));
    context.define('latin1Encode', Latin1Encode(interpreter!));
    context.define('latin1Decode', Latin1Decode(interpreter!));
  }
}

List<int> _toListInt(Value value) {
  final raw = rawLuaSlot(value);
  if (raw is Uint8List) {
    return raw;
  }
  final unwrapped = fromLuaValue(value);
  if (unwrapped is List) {
    return unwrapped.cast<int>();
  }
  throw LuaError('Expected Uint8List, List<int>, or a table of integers');
}

void defineConvertLibrary({required Environment env, LuaRuntime? vm}) {
  final runtime = vm ?? Interpreter();
  final convertTable = {
    'jsonEncode': JsonEncode(runtime),
    'jsonDecode': JsonDecode(runtime),
    'base64Encode': Base64Encode(runtime),
    'base64Decode': Base64Decode(runtime),
    'base64UrlEncode': Base64UrlEncode(runtime),
    'asciiEncode': AsciiEncode(runtime),
    'asciiDecode': AsciiDecode(runtime),
    'latin1Encode': Latin1Encode(runtime),
    'latin1Decode': Latin1Decode(runtime),
  };
  env.define('convert', Value(convertTable, interpreter: runtime));
}

class JsonEncode extends BuiltinFunction {
  JsonEncode(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Encodes a Lua value into a JSON string.',
    params: [DocParam('value', 'any', 'The value to encode.')],
    returns: 'A JSON string.',
    category: 'convert',
    example: 'convert.jsonEncode({a=1, b=2})',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.jsonEncode requires 1 argument');
    }
    final object = args[0];
    if (object is! Value) {
      throw LuaError('dart.convert.jsonEncode requires a Value argument');
    }
    try {
      final encodable = fromLuaValue(object);
      return dartStringValue(json.encode(encodable));
    } catch (e) {
      throw LuaError('Failed to encode to JSON: $e');
    }
  }
}

class JsonDecode extends BuiltinFunction {
  JsonDecode(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Decodes a JSON string into a Lua value.',
    params: [DocParam('json', 'string', 'The JSON string to decode.')],
    returns: 'The decoded Lua value.',
    category: 'convert',
    example: 'local t = convert.jsonDecode(\'{"a":1}\')',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.jsonDecode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.jsonDecode requires a Value argument');
    }
    final str = rawLuaSlot(arg).toString();
    try {
      return toLuaValue(json.decode(str));
    } catch (e) {
      throw LuaError('Failed to decode from JSON: $e');
    }
  }
}

class Base64Encode extends BuiltinFunction {
  Base64Encode(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Encodes a string to Base64.',
    params: [DocParam('input', 'string', 'The input string.')],
    returns: 'The Base64-encoded string.',
    category: 'convert',
    example: 'convert.base64Encode("hello")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.base64Encode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.base64Encode requires a Value argument');
    }
    final bytes = _toListInt(arg);
    return dartStringValue(base64.encode(bytes));
  }
}

class Base64Decode extends BuiltinFunction {
  Base64Decode(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Decodes a Base64 string back to its original value.',
    params: [DocParam('input', 'string', 'The Base64 string.')],
    returns: 'The decoded string.',
    category: 'convert',
    example: 'convert.base64Decode("aGVsbG8=")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.base64Decode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.base64Decode requires a Value argument');
    }
    final str = rawLuaSlot(arg).toString();
    try {
      return valueFromOptionalLuaSlot(interpreter, base64.decode(str));
    } catch (e) {
      throw LuaError('Failed to decode from Base64: $e');
    }
  }
}

class Base64UrlEncode extends BuiltinFunction {
  Base64UrlEncode(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Encodes a string to URL-safe Base64.',
    params: [DocParam('input', 'string', 'The input string.')],
    returns: 'The URL-safe Base64-encoded string.',
    category: 'convert',
    example: 'convert.base64UrlEncode("hello")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.base64UrlEncode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.base64UrlEncode requires a Value argument');
    }
    final bytes = _toListInt(arg);
    return dartStringValue(base64Url.encode(bytes));
  }
}

class AsciiEncode extends BuiltinFunction {
  AsciiEncode(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Encodes a Lua string to ASCII bytes.',
    params: [DocParam('input', 'string', 'The input string.')],
    returns: 'The ASCII-encoded string.',
    category: 'convert',
    example: 'convert.asciiEncode("hello")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.asciiEncode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.asciiEncode requires a Value argument');
    }
    final str = rawLuaSlot(arg).toString();
    try {
      return valueFromOptionalLuaSlot(interpreter, ascii.encode(str));
    } catch (e) {
      throw LuaError('Failed to encode to ASCII: $e');
    }
  }
}

class AsciiDecode extends BuiltinFunction {
  AsciiDecode(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Decodes ASCII bytes back to a Lua string.',
    params: [DocParam('input', 'string', 'The ASCII byte string.')],
    returns: 'The decoded string.',
    category: 'convert',
    example: 'convert.asciiDecode("hello")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.asciiDecode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.asciiDecode requires a Value argument');
    }
    final bytes = _toListInt(arg);
    return dartStringValue(ascii.decode(bytes));
  }
}

class Latin1Encode extends BuiltinFunction {
  Latin1Encode(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Encodes a Lua string to Latin-1 (ISO 8859-1) bytes.',
    params: [DocParam('input', 'string', 'The input string.')],
    returns: 'The Latin-1 encoded string.',
    category: 'convert',
    example: 'convert.latin1Encode("héllo")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.latin1Encode requires 1 argument');
    }
    final value = args[0];
    if (value is! Value) {
      throw LuaError('dart.convert.latin1Encode requires a Value argument');
    }
    try {
      final raw = rawLuaSlot(value);
      // For LuaString, use the raw bytes directly
      if (raw is LuaString) {
        final luaString = raw;
        // Latin-1 encoding is just the raw bytes (0-255)
        // Check that all bytes are valid Latin-1 (0-255)
        for (final byte in luaString.bytes) {
          if (byte < 0 || byte > 255) {
            throw ArgumentError(
              'Byte value $byte is outside Latin-1 range (0-255)',
            );
          }
        }
        return valueFromOptionalLuaSlot(
          interpreter,
          Uint8List.fromList(luaString.bytes),
        );
      } else {
        // For other types, convert to string first
        final str = raw.toString();
        return valueFromOptionalLuaSlot(interpreter, latin1.encode(str));
      }
    } catch (e) {
      throw LuaError('Failed to encode to Latin-1: $e');
    }
  }
}

class Latin1Decode extends BuiltinFunction {
  Latin1Decode(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Decodes Latin-1 (ISO 8859-1) bytes back to a Lua string.',
    params: [DocParam('input', 'string', 'The Latin-1 byte string.')],
    returns: 'The decoded string.',
    category: 'convert',
    example: 'convert.latin1Decode("héllo")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.latin1Decode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.latin1Decode requires a Value argument');
    }
    final bytes = _toListInt(arg);
    // For Lua compatibility, return a LuaString with the raw bytes
    // instead of converting to UTF-8 string
    return valueFromOptionalLuaSlot(
      interpreter,
      LuaString(Uint8List.fromList(bytes)),
    );
  }
}
