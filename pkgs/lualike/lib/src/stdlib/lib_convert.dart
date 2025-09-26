import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/extensions/value_extension.dart';
import 'package:lualike/src/interpreter/interpreter.dart';

import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';
import 'library.dart';

/// Convert library implementation using the new Library system
class ConvertLibrary extends Library {
  @override
  String get name => "convert";

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
  if (value.raw is Uint8List) {
    return value.raw as Uint8List;
  }
  final unwrapped = fromLuaValue(value);
  if (unwrapped is List) {
    return unwrapped.cast<int>();
  }
  throw LuaError('Expected Uint8List, List<int>, or a table of integers');
}

void defineConvertLibrary({required Environment env, Interpreter? astVm}) {
  final vm = astVm ?? Interpreter();
  final convertTable = {
    'jsonEncode': JsonEncode(vm),
    'jsonDecode': JsonDecode(vm),
    'base64Encode': Base64Encode(vm),
    'base64Decode': Base64Decode(vm),
    'base64UrlEncode': Base64UrlEncode(vm),
    'asciiEncode': AsciiEncode(vm),
    'asciiDecode': AsciiDecode(vm),
    'latin1Encode': Latin1Encode(vm),
    'latin1Decode': Latin1Decode(vm),
  };
  env.define('convert', Value(convertTable));
}

class JsonEncode extends BuiltinFunction {
  JsonEncode(super.interpreter);
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
      return Value(json.encode(encodable));
    } catch (e) {
      throw LuaError('Failed to encode to JSON: $e');
    }
  }
}

class JsonDecode extends BuiltinFunction {
  JsonDecode(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.jsonDecode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.jsonDecode requires a Value argument');
    }
    final str = arg.raw.toString();
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
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.base64Encode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.base64Encode requires a Value argument');
    }
    final bytes = _toListInt(arg);
    return Value(base64.encode(bytes));
  }
}

class Base64Decode extends BuiltinFunction {
  Base64Decode(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.base64Decode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.base64Decode requires a Value argument');
    }
    final str = arg.raw.toString();
    try {
      return Value(base64.decode(str));
    } catch (e) {
      throw LuaError('Failed to decode from Base64: $e');
    }
  }
}

class Base64UrlEncode extends BuiltinFunction {
  Base64UrlEncode(super.interpreter);

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
    return Value(base64Url.encode(bytes));
  }
}

class AsciiEncode extends BuiltinFunction {
  AsciiEncode(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('dart.convert.asciiEncode requires 1 argument');
    }
    final arg = args[0];
    if (arg is! Value) {
      throw LuaError('dart.convert.asciiEncode requires a Value argument');
    }
    final str = arg.raw.toString();
    try {
      return Value(ascii.encode(str));
    } catch (e) {
      throw LuaError('Failed to encode to ASCII: $e');
    }
  }
}

class AsciiDecode extends BuiltinFunction {
  AsciiDecode(super.interpreter);

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
    return Value(ascii.decode(bytes));
  }
}

class Latin1Encode extends BuiltinFunction {
  Latin1Encode(super.interpreter);

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
      // For LuaString, use the raw bytes directly
      if (value.raw is LuaString) {
        final luaString = value.raw as LuaString;
        // Latin-1 encoding is just the raw bytes (0-255)
        // Check that all bytes are valid Latin-1 (0-255)
        for (final byte in luaString.bytes) {
          if (byte < 0 || byte > 255) {
            throw ArgumentError(
              'Byte value $byte is outside Latin-1 range (0-255)',
            );
          }
        }
        return Value(Uint8List.fromList(luaString.bytes));
      } else {
        // For other types, convert to string first
        final str = value.raw.toString();
        return Value(latin1.encode(str));
      }
    } catch (e) {
      throw LuaError('Failed to encode to Latin-1: $e');
    }
  }
}

class Latin1Decode extends BuiltinFunction {
  Latin1Decode(super.interpreter);

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
    return Value(LuaString(Uint8List.fromList(bytes)));
  }
}
