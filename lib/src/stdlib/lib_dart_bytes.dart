import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';

class DartBytesLib {
  static final Map<String, BuiltinFunction> functions = {
    'toBytes': DartToBytes(),
    'fromBytes': DartFromBytes(),
  };
}

class DartToBytes implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError(
        'dart.string.bytes.toBytes requires at least 1 argument: string',
      );
    }
    final value = args[0] as Value;

    // For LuaString, use the raw bytes directly (they're already UTF-8)
    if (value.raw is LuaString) {
      final luaString = value.raw as LuaString;
      return Value(Uint8List.fromList(luaString.bytes));
    } else {
      // For other types, convert to string first then encode as UTF-8
      final str = value.raw.toString();
      final bytes = utf8.encode(str);
      return Value(Uint8List.fromList(bytes));
    }
  }
}

class DartFromBytes implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError(
        'dart.string.bytes.fromBytes requires at least 1 argument: bytes',
      );
    }
    final value = args[0] as Value;
    Uint8List bytes;

    if (value.raw is Uint8List) {
      bytes = value.raw as Uint8List;
    } else if (value.raw is List) {
      try {
        bytes = Uint8List.fromList((value.raw as List).cast<int>());
      } catch (e) {
        throw LuaError(
          'dart.string.bytes.fromBytes requires a List of integers',
        );
      }
    } else if (value.raw is Map) {
      final table = value.raw as Map;
      final charCodes = <int>[];
      for (var i = 1; i <= table.length; i++) {
        final val = table[Value(i)];
        if (val is Value && val.raw is num) {
          charCodes.add((val.raw as num).toInt());
        } else {
          throw LuaError(
            'Invalid value in bytes table at index $i: expected a number',
          );
        }
      }
      bytes = Uint8List.fromList(charCodes);
    } else {
      throw LuaError(
        'dart.string.bytes.fromBytes requires a Uint8List, a List<int>, or a table of integers as the first argument',
      );
    }

    return Value(utf8.decode(bytes));
  }
}
