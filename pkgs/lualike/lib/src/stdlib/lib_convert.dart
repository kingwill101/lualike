import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/extensions/value_extension.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';

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

class DartConvertLib {
  static final Map<String, BuiltinFunction> functions = {
    'jsonEncode': JsonEncode(),
    'jsonDecode': JsonDecode(),
    'base64Encode': Base64Encode(),
    'base64Decode': Base64Decode(),
    'base64UrlEncode': Base64UrlEncode(),
    'asciiEncode': AsciiEncode(),
    'asciiDecode': AsciiDecode(),
    'latin1Encode': Latin1Encode(),
    'latin1Decode': Latin1Decode(),
  };
}

void defineConvertLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final convertTable = <String, dynamic>{};
  DartConvertLib.functions.forEach((key, value) {
    convertTable[key] = value;
  });
  env.define('convert', Value(convertTable));
}

class JsonEncode implements BuiltinFunction {
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

class JsonDecode implements BuiltinFunction {
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

class Base64Encode implements BuiltinFunction {
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

class Base64Decode implements BuiltinFunction {
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

class Base64UrlEncode implements BuiltinFunction {
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

class AsciiEncode implements BuiltinFunction {
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

class AsciiDecode implements BuiltinFunction {
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

class Latin1Encode implements BuiltinFunction {
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

class Latin1Decode implements BuiltinFunction {
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
