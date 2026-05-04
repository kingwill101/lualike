import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/runtime/lua_slot.dart';

class DartToBytes extends BuiltinFunction {
  DartToBytes([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError(
        'dart.string.bytes.toBytes requires at least 1 argument: string',
      );
    }
    final raw = rawLuaSlot(args[0]);

    // For LuaString, use the raw bytes directly (they're already UTF-8)
    if (raw is LuaString) {
      return valueFromOptionalLuaSlot(
        interpreter,
        Uint8List.fromList(raw.bytes),
      );
    } else {
      // For other types, convert to string first then encode as UTF-8
      final str = raw.toString();
      final bytes = utf8.encode(str);
      return valueFromOptionalLuaSlot(interpreter, Uint8List.fromList(bytes));
    }
  }
}

class DartFromBytes extends BuiltinFunction {
  DartFromBytes([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError(
        'dart.string.bytes.fromBytes requires at least 1 argument: bytes',
      );
    }
    final raw = rawLuaSlot(args[0]);
    Uint8List bytes;

    if (raw is Uint8List) {
      bytes = raw;
    } else if (raw is List) {
      try {
        bytes = Uint8List.fromList(raw.cast<int>());
      } catch (e) {
        throw LuaError(
          'dart.string.bytes.fromBytes requires a List of integers',
        );
      }
    } else if (raw is Map) {
      final table = raw;
      final charCodes = <int>[];
      var index = 1;
      while (true) {
        dynamic entry = table[index];
        entry ??= table[primitiveValue(index)];
        if (entry == null) {
          break;
        }
        entry = rawLuaSlot(entry);
        if (entry is num) {
          charCodes.add(entry.toInt());
        } else {
          throw LuaError(
            'Invalid value in bytes table at index $index: expected a number',
          );
        }
        index++;
      }
      bytes = Uint8List.fromList(charCodes);
    } else {
      throw LuaError(
        'dart.string.bytes.fromBytes requires a Uint8List, a List<int>, or a table of integers as the first argument',
      );
    }

    return dartStringValue(utf8.decode(bytes));
  }
}
