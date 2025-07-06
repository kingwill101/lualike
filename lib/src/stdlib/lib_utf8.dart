import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/builtin_function.dart' show BuiltinFunction;
import 'package:lualike/src/environment.dart' show Environment;
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/value.dart' show Value;
import 'package:lualike/src/lua_string.dart';
import '../../lualike.dart' show Value;
import '../value_class.dart';

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

class _UTF8Char implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("utf8.char requires at least one argument");
    }

    final codePoints = <int>[];
    for (final arg in args) {
      final cp = (arg as Value).raw as int;
      if (cp < 0 || cp > 0x10FFFF) {
        throw Exception("bad argument to 'utf8.char' (value out of range)");
      }
      codePoints.add(cp);
    }

    try {
      // Create a proper Dart string from the codepoints
      final dartString = String.fromCharCodes(codePoints);
      // Encode it to UTF-8 bytes
      final utf8Bytes = utf8.encode(dartString);
      // Create a LuaString with the UTF-8 bytes
      return Value(LuaString(Uint8List.fromList(utf8Bytes)));
    } catch (e) {
      throw Exception("invalid UTF-8 code");
    }
  }
}

class _UTF8Codes implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("utf8.codes requires a string argument");
    }

    // Work with raw bytes to properly detect invalid UTF-8
    final value = (args[0] as Value).raw;
    final bytes = value is LuaString
        ? value.bytes
        : utf8.encode(value.toString());
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
        throw Exception("invalid UTF-8 code");
      }

      // Check if we have enough bytes for the complete sequence
      if (bytePos + sequenceLength > bytes.length) {
        throw Exception("invalid UTF-8 code");
      }

      // For multi-byte sequences, check that continuation bytes are valid
      for (int k = 1; k < sequenceLength; k++) {
        if (bytePos + k >= bytes.length ||
            (bytes[bytePos + k] & 0xC0) != 0x80) {
          throw Exception("invalid UTF-8 code");
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
          throw Exception("invalid UTF-8 code");
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
          throw Exception("invalid UTF-8 code");
        }
      } else if (sequenceLength == 4) {
        codePoint =
            ((byte & 0x07) << 18) |
            ((bytes[bytePos + 1] & 0x3F) << 12) |
            ((bytes[bytePos + 2] & 0x3F) << 6) |
            (bytes[bytePos + 3] & 0x3F);
        // Check for overlong encoding and out-of-range code points
        if (!lax && (codePoint < 0x10000 || codePoint > 0x10FFFF)) {
          throw Exception("invalid UTF-8 code");
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
      throw Exception("utf8.codepoint requires a string argument");
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
        throw Exception("invalid UTF-8 code");
      }
      return Value(codePoint);
    } else {
      final codePoints = <Value>[];
      for (var pos = i; pos <= j; pos++) {
        final codePoint = chars[pos].runes.first;
        if (!lax && codePoint > 0x10FFFF) {
          throw Exception("invalid UTF-8 code");
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
      throw Exception("utf8.len requires a string argument");
    }

    // Work with raw bytes to properly detect invalid UTF-8
    final value = (args[0] as Value).raw;
    final bytes = value is LuaString
        ? value.bytes
        : utf8.encode(value.toString());

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
        // Invalid start byte
        return [Value(null), Value(pos + 1)]; // Return 1-based position
      }

      // Check if we have enough bytes for the complete sequence
      if (pos + sequenceLength > bytes.length) {
        return [Value(null), Value(pos + 1)]; // Incomplete sequence
      }

      // For multi-byte sequences, check that continuation bytes are valid
      for (int k = 1; k < sequenceLength; k++) {
        if (pos + k >= bytes.length || (bytes[pos + k] & 0xC0) != 0x80) {
          return [
            Value(null),
            Value(pos + 1),
          ]; // Invalid continuation byte at start position
        }
      }

      if (!lax) {
        // Additional validation for overlong sequences and invalid code points
        int codePoint;

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

      // Move to next character
      pos += sequenceLength;
      charCount++;

      // Stop if we've reached the end of our range
      if (pos >= end) break;
    }

    return Value(charCount);
  }
}

class _UTF8Offset implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("utf8.offset requires string and n arguments");
    }

    final str = (args[0] as Value).raw.toString();
    final n = (args[1] as Value).raw as int;
    var i = args.length > 2
        ? (args[2] as Value).raw as int
        : (n >= 0 ? 1 : str.length + 1);

    // For Lua compatibility, we need to work with byte positions
    //FIXME:    final bytes = utf8.encode(str);

    if (n == 0) {
      return Value(i); // For n=0, return current position
    }

    // Map character positions to byte positions
    final charPositions = <int>[];
    int bytePos = 1; // Start at position 1 (Lua is 1-indexed)

    for (final char in str.characters) {
      charPositions.add(bytePos);
      bytePos += utf8.encode(char).length;
    }

    // Add the position after the last character
    charPositions.add(bytePos);

    if (n > 0) {
      // Forward direction
      int charIndex = 0;

      // Find the character at position i
      for (int j = 0; j < charPositions.length - 1; j++) {
        if (charPositions[j] <= i && i < charPositions[j + 1]) {
          charIndex = j;
          break;
        }
      }

      // Move n characters forward
      charIndex += n - 1;

      if (charIndex >= 0 && charIndex < charPositions.length) {
        return Value(charPositions[charIndex]);
      }
    } else {
      // Backward direction
      int charIndex = charPositions.length - 2; // Last character

      // Find the character at position i
      for (int j = charPositions.length - 2; j >= 0; j--) {
        if (charPositions[j] < i && i <= charPositions[j + 1]) {
          charIndex = j;
          break;
        }
      }

      // Move -n characters backward
      charIndex += n + 1;

      if (charIndex >= 0 && charIndex < charPositions.length) {
        return Value(charPositions[charIndex]);
      }
    }

    return Value(null); // Out of range
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
