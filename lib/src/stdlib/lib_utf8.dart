import 'dart:convert' as convert;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/builtin_function.dart' show BuiltinFunction;
import 'package:lualike/src/environment.dart' show Environment;
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/value.dart' show Value;
import 'package:lualike/src/lua_string.dart';
import '../../lualike.dart' show Value;
import '../value_class.dart';
import 'package:lualike/src/lua_error.dart';

class UTF8Lib {
  // Pattern that matches exactly one UTF-8 byte sequence
  // This matches Lua 5.4's utf8.charpattern which is "[\0-\x7F\xC2-\xF4][\x80-\xBF]*"
  static const String charpattern = "[\x00-\x7F\xC2-\xF4][\x80-\xBF]*";

  static final ValueClass utf8Class = ValueClass.create({
    "__len": (List<Object?> args) {
      final str = args[0] as Value;
      if (str.raw is! String && str.raw is! LuaString) {
        throw Exception("utf8 operation on non-string value");
      }
      return Value(str.raw.toString().characters.length);
    },
    "__index": (List<Object?> args) {
      final _ = args[0] as Value;
      final key = args[1] as Value;
      return functions[key.raw] ?? Value(null);
    },
  });

  static final Map<String, dynamic> functions = {
    'char': _UTF8Char(),
    'codes': _UTF8Codes(),
    'codepoint': _UTF8CodePoint(),
    'len': _UTF8Len(),
    'offset': _UTF8Offset(),
    'charpattern': Value(charpattern),
  };
}

class _UTF8Helper {
  static Uint8List getBytes(Value value) {
    if (value.raw is LuaString) {
      return (value.raw as LuaString).bytes;
    } else if (value.raw is String) {
      return Uint8List.fromList(convert.utf8.encode(value.raw as String));
    } else {
      throw LuaError("utf8 operation on non-string value");
    }
  }
}

class _UTF8Char implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      return Value(LuaString(Uint8List(0))); // empty string
    }

    final codePoints = <int>[];
    for (final arg in args) {
      final value = (arg as Value).raw;
      if (value is! num) {
        throw LuaError("utf8.char requires at least one argument");
      }
      final codePoint = value.toInt();
      if (codePoint < 0 || codePoint > 0x10FFFF) {
        throw LuaError("bad argument to 'utf8.char' (value out of range)");
      }
      codePoints.add(codePoint);
    }

    try {
      // Create a proper Dart string from the codepoints
      final dartString = String.fromCharCodes(codePoints);
      // Encode it to UTF-8 bytes
      final utf8Bytes = convert.utf8.encode(dartString);
      // Create a LuaString with the UTF-8 bytes
      return Value(LuaString(Uint8List.fromList(utf8Bytes)));
    } catch (e) {
      throw LuaError("invalid UTF-8 code");
    }
  }
}

class _UTF8Codes implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.codes requires a string argument");
    }

    // Work with raw bytes to properly detect invalid UTF-8
    final value = (args[0] as Value).raw;
    final bytes = value is LuaString
        ? value.bytes
        : convert.utf8.encode(value.toString());
    final lax = args.length > 1 ? (args[1] as Value).raw as bool : false;

    var bytePos = 0;

    return Value((List<Object?> iterArgs) {
      if (bytePos >= bytes.length) {
        return Value(null);
      }

      final byte = bytes[bytePos];
      int sequenceLength;

      // Determine UTF-8 sequence length from first byte
      if (byte < 0x80) {
        // ASCII: 0xxxxxxx
        sequenceLength = 1;
      } else if ((byte & 0xE0) == 0xC0) {
        // 2-byte: 110xxxxx 10xxxxxx
        sequenceLength = 2;
      } else if ((byte & 0xF0) == 0xE0) {
        // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
        sequenceLength = 3;
      } else if ((byte & 0xF8) == 0xF0) {
        // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        sequenceLength = 4;
      } else {
        // Invalid start byte
        throw LuaError("invalid UTF-8 code");
      }

      // Check if we have enough bytes for the complete sequence
      if (bytePos + sequenceLength > bytes.length) {
        throw LuaError("invalid UTF-8 code");
      }

      // For multi-byte sequences, check that continuation bytes are valid
      for (int k = 1; k < sequenceLength; k++) {
        if (bytePos + k >= bytes.length ||
            (bytes[bytePos + k] & 0xC0) != 0x80) {
          throw LuaError("invalid UTF-8 code");
        }
      }

      // Decode the code point
      int codePoint = 0;
      if (sequenceLength == 1) {
        codePoint = byte;
      } else if (sequenceLength == 2) {
        codePoint = ((byte & 0x1F) << 6) | (bytes[bytePos + 1] & 0x3F);
        // Check for overlong encoding
        if (!lax && codePoint < 0x80) {
          throw LuaError("invalid UTF-8 code");
        }
      } else if (sequenceLength == 3) {
        codePoint =
            ((byte & 0x0F) << 12) |
            ((bytes[bytePos + 1] & 0x3F) << 6) |
            (bytes[bytePos + 2] & 0x3F);
        // Check for overlong encoding and surrogate pairs
        if (!lax &&
            (codePoint < 0x800 ||
                (codePoint >= 0xD800 && codePoint <= 0xDFFF))) {
          throw LuaError("invalid UTF-8 code");
        }
      } else if (sequenceLength == 4) {
        codePoint =
            ((byte & 0x07) << 18) |
            ((bytes[bytePos + 1] & 0x3F) << 12) |
            ((bytes[bytePos + 2] & 0x3F) << 6) |
            (bytes[bytePos + 3] & 0x3F);
        // Check for overlong encoding and out-of-range code points
        if (!lax && (codePoint < 0x10000 || codePoint > 0x10FFFF)) {
          throw LuaError("invalid UTF-8 code");
        }
      }

      // Calculate the current byte position (1-based for Lua)
      final currentPos = bytePos + 1;

      // Move to next character
      bytePos += sequenceLength;

      return [Value(currentPos), Value(codePoint)];
    });
  }
}

class _UTF8CodePoint implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.codepoint requires a string argument");
    }

    final str = (args[0] as Value).raw.toString();
    var i = args.length > 1 ? (args[1] as Value).raw as int : 1;
    var j = args.length > 2 ? (args[2] as Value).raw as int : i;
    final lax = args.length > 3 ? (args[3] as Value).raw as bool : false;

    // Convert to 0-based indices
    i = i > 0 ? i - 1 : str.characters.length + i;
    j = j > 0 ? j - 1 : str.characters.length + j;

    final chars = str.characters.toList();
    if (i < 0) i = 0;
    if (j >= chars.length) j = chars.length - 1;

    // Return individual values instead of a list to match Lua's behavior
    if (i == j) {
      final codePoint = chars[i].runes.first;
      if (!lax && codePoint > 0x10FFFF) {
        throw LuaError("invalid UTF-8 code");
      }
      return Value(codePoint);
    } else {
      final codePoints = <Value>[];
      for (var pos = i; pos <= j; pos++) {
        final codePoint = chars[pos].runes.first;
        if (!lax && codePoint > 0x10FFFF) {
          throw LuaError("invalid UTF-8 code");
        }
        codePoints.add(Value(codePoint));
      }
      return codePoints;
    }
  }
}

class _UTF8Len implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.len requires a string argument");
    }

    // Work with raw bytes to properly detect invalid UTF-8
    final value = (args[0] as Value).raw;
    final bytes = value is LuaString
        ? value.bytes
        : convert.utf8.encode(value.toString());

    var i = args.length > 1 ? (args[1] as Value).raw as int : 1;
    var j = args.length > 2 ? (args[2] as Value).raw as int : -1;
    final lax = args.length > 3 ? (args[3] as Value).raw as bool : false;

    // Convert to 0-based indices for byte array access
    final startByte = i > 0 ? i - 1 : bytes.length + i;
    final endByte = j > 0 ? j - 1 : bytes.length + j;

    // Clamp indices to valid range
    final start = math.max(0, math.min(startByte, bytes.length));
    final end = math.max(start, math.min(endByte + 1, bytes.length));

    // Validate UTF-8 sequence by sequence in the specified range
    int charCount = 0;
    int pos = start;

    while (pos < end) {
      final byte = bytes[pos];
      int sequenceLength;

      // Determine UTF-8 sequence length from first byte
      if (byte < 0x80) {
        // ASCII: 0xxxxxxx
        sequenceLength = 1;
      } else if ((byte & 0xE0) == 0xC0) {
        // 2-byte: 110xxxxx 10xxxxxx
        sequenceLength = 2;
      } else if ((byte & 0xF0) == 0xE0) {
        // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
        sequenceLength = 3;
      } else if ((byte & 0xF8) == 0xF0) {
        // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        sequenceLength = 4;
      } else {
        // Invalid UTF-8 sequence found - return nil and byte position
        return [Value(null), Value(pos + 1)]; // 1-based position for Lua
      }

      // Check if we have enough bytes for the complete sequence
      if (pos + sequenceLength > end) {
        return [Value(null), Value(pos + 1)];
      }

      // For multi-byte sequences, check that continuation bytes are valid
      for (int k = 1; k < sequenceLength; k++) {
        if (pos + k >= bytes.length || (bytes[pos + k] & 0xC0) != 0x80) {
          return [Value(null), Value(pos + 1)];
        }
      }

      // Decode and validate the code point if not in lax mode
      if (!lax) {
        int codePoint = 0;
        if (sequenceLength == 1) {
          codePoint = byte;
        } else if (sequenceLength == 2) {
          codePoint = ((byte & 0x1F) << 6) | (bytes[pos + 1] & 0x3F);
          // Check for overlong encoding
          if (codePoint < 0x80) {
            return [Value(null), Value(pos + 1)];
          }
        } else if (sequenceLength == 3) {
          codePoint =
              ((byte & 0x0F) << 12) |
              ((bytes[pos + 1] & 0x3F) << 6) |
              (bytes[pos + 2] & 0x3F);
          // Check for overlong encoding and surrogate pairs
          if (codePoint < 0x800 ||
              (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
            return [Value(null), Value(pos + 1)];
          }
        } else if (sequenceLength == 4) {
          codePoint =
              ((byte & 0x07) << 18) |
              ((bytes[pos + 1] & 0x3F) << 12) |
              ((bytes[pos + 2] & 0x3F) << 6) |
              (bytes[pos + 3] & 0x3F);
          // Check for overlong encoding and out-of-range code points
          if (codePoint < 0x10000 || codePoint > 0x10FFFF) {
            return [Value(null), Value(pos + 1)];
          }
        }
      }

      pos += sequenceLength;
      charCount++;
    }

    return Value(charCount);
  }
}

class _UTF8Offset implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("utf8.offset requires string and n arguments");
    }

    final str = (args[0] as Value).raw.toString();
    final n = (args[1] as Value).raw as int;
    final i = args.length > 2 ? (args[2] as Value).raw as int : 1;

    // Lua string positions are 1-based
    if (n == 0) {
      // Return the start of the character that contains byte i
      return Value(i);
    }

    // For simplicity, using Dart's character iterator
    // This is not perfectly accurate for all UTF-8 edge cases
    final chars = str.characters;
    final charList = chars.toList();

    if (n > 0) {
      final targetIndex = i + n - 1;
      if (targetIndex <= charList.length) {
        return Value(targetIndex + 1); // Convert back to 1-based
      }
      return Value(null);
    } else {
      final targetIndex = i + n - 1;
      if (targetIndex >= 0) {
        return Value(targetIndex + 1); // Convert back to 1-based
      }
      return Value(null);
    }
  }
}

void defineUTF8Library({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  env.define(
    "utf8",
    Value(UTF8Lib.functions, metatable: UTF8Lib.utf8Class.metamethods),
  );
}
